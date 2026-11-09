import AppKit
import ApplicationServices
import AVFoundation
import Foundation
import RuntimeE2ECore

// Drives one Roma recording mode with the runtime harness pieces (BlackHole playback, real
// left-Shift events, Roma session setup, AX text reads, LatencyTrace parsing), but samples the
// target field during the hold, which the harness observer only starts at key-up.

struct TextSample: Codable {
    let uptime: Double
    let text: String?
    let frontmostBundleID: String?
}

struct HistoryRow: Codable {
    let Z_PK: Int
    let ZTEXT: String?
}

struct LiveTypingCase: Codable {
    let role: String
    let targetFile: String
    var audioStartUptime: Double?
    var audioFinishedUptime: Double?
    var keyDownUptime: Double?
    var keyUpUptime: Double?
    var sampleReads = 0
    var samples: [TextSample] = []
    var latencyTrace: RuntimeLatencyTrace?
    var historyRows: [HistoryRow] = []
    var error: String?
}

struct LiveTypingReport: Codable {
    let mode: String
    let startedAt: Date
    var accessibilityTrusted: Bool
    var prewarm = "not-checked"
    var voiceInkSession: RuntimeVoiceInkSessionInfo?
    var cases: [LiveTypingCase] = []
    var restoredOriginalState = false
    var fatalError: String?
}

struct ProbeError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

@main
enum LiveTypingProbe {
    static let textEditBundleID = "com.apple.TextEdit"
    static let historyStore = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/com.negentropi.RomaJustTalk/default.store").path

    static func main() {
        let arguments = Dictionary(
            uniqueKeysWithValues: stride(from: 1, to: CommandLine.arguments.count - 1, by: 2).map {
                (CommandLine.arguments[$0], CommandLine.arguments[$0 + 1])
            }
        )
        guard let configPath = arguments["--config"], let fixturePath = arguments["--fixture"],
              let mode = arguments["--mode"], let outputPath = arguments["--output"],
              let targetDirectory = arguments["--targets"] else {
            fputs("usage: LiveTypingProbe --config PATH --fixture WAV --mode on|off --output JSON --targets DIR [--cases N]\n", stderr)
            exit(2)
        }
        let caseCount = Int(arguments["--cases"] ?? "2") ?? 2
        let outputURL = URL(fileURLWithPath: outputPath)
        var report = LiveTypingReport(mode: mode, startedAt: Date(), accessibilityTrusted: AXIsProcessTrusted())
        defer { write(report, to: outputURL) }

        var outputSession: RuntimeSystemOutputSession?
        var voiceInkSession: RuntimeVoiceInkSession?
        do {
            guard report.accessibilityTrusted else { throw ProbeError("Accessibility is not granted to the probe") }
            let configuration = try JSONDecoder().decode(
                RuntimeHarnessConfiguration.self,
                from: Data(contentsOf: URL(fileURLWithPath: configPath))
            )
            let fixtureURL = URL(fileURLWithPath: fixturePath)
            let audioFile = try AVAudioFile(forReading: fixtureURL)
            let duration = Double(audioFile.length) / audioFile.fileFormat.sampleRate
            guard let device = try RuntimeAudioDeviceCatalog.devices().first(where: { $0.name == configuration.audioDeviceName }) else {
                throw ProbeError("Audio device missing: \(configuration.audioDeviceName)")
            }

            outputSession = try RuntimeSystemOutputSession.start(targetDevice: device)
            let launchedAt = Date().addingTimeInterval(-2)
            let session = try RuntimeVoiceInkSession.start(configuration: configuration, audioDeviceUID: device.uid)
            voiceInkSession = session
            report.voiceInkSession = session.info
            report.prewarm = waitForPrewarm(since: launchedAt, timeoutSeconds: 600)
            log("prewarm: \(report.prewarm)")
            Thread.sleep(forTimeInterval: configuration.preRollWarmupSeconds)

            // The first dictation after launch pays a cold first inference (about 12 s on hosted
            // runners), so only the last case is asserted; earlier ones are warmups.
            for index in 0..<caseCount {
                let role = index == caseCount - 1 ? "measured" : "warmup\(index + 1)"
                let file = URL(fileURLWithPath: targetDirectory)
                    .appendingPathComponent("rjt-live-\(mode)-\(role)-\(UUID().uuidString.prefix(8)).txt")
                let result = runCase(role: role, file: file, fixtureURL: fixtureURL, duration: duration, device: device)
                report.cases.append(result)
                write(report, to: outputURL)
                log("\(role): error=\(result.error ?? "none") final=\(result.samples.last?.text ?? "<nil>")")
            }
        } catch {
            report.fatalError = String(describing: error)
            log("fatal: \(error)")
        }
        do {
            try voiceInkSession?.restore()
            try outputSession?.restore()
            report.restoredOriginalState = true
        } catch {
            report.fatalError = (report.fatalError.map { $0 + "; " } ?? "") + "restore: \(error)"
        }
    }

    static func runCase(
        role: String,
        file: URL,
        fixtureURL: URL,
        duration: TimeInterval,
        device: RuntimeAudioDevice
    ) -> LiveTypingCase {
        var result = LiveTypingCase(role: role, targetFile: file.path)
        var shiftHeld = false
        do {
            let (application, window, field) = try openTarget(file)
            guard RuntimeAX.text(from: field) == "" else { throw ProbeError("Target field is not empty before recording") }
            let seenTraceIDs = Set(try RuntimeLatencyLogReader.recent().traces.map(\.traceID))
            let historyBefore = try historyRows(after: -1).last?.Z_PK ?? 0
            guard RuntimeAX.focus(application: application, windowElement: window, textElement: field) else {
                throw ProbeError("Could not focus the target field")
            }
            sample(field, into: &result, until: now() + 0.3)

            let down = try RuntimeShortcutInjector.postLeftShiftDown()
            shiftHeld = true
            result.keyDownUptime = down.postedAtSystemUptime
            sample(field, into: &result, until: down.postedAtSystemUptime + 1.0)

            let playback = RuntimeAudioPlayback(fixtureURL: fixtureURL, device: device, expectedDurationSeconds: duration)
            let audioStart = try playback.start()
            result.audioStartUptime = audioStart
            sample(field, into: &result, until: audioStart + duration)
            let played = try playback.waitUntilFinished()
            result.audioFinishedUptime = played.finishedAtSystemUptime
            sample(field, into: &result, until: played.finishedAtSystemUptime + 0.5)

            let up = try RuntimeShortcutInjector.postLeftShiftUp()
            shiftHeld = false
            result.keyUpUptime = up.postedAtSystemUptime

            // Dense sampling until the field holds stable text, then coarser while the trace settles.
            let textDeadline = up.postedAtSystemUptime + 90
            var stableSince: Double?
            while now() < textDeadline {
                let before = result.samples.count
                sample(field, into: &result, until: now() + 0.1)
                let text = result.samples.last?.text ?? ""
                if result.samples.count != before || text.isEmpty { stableSince = nil }
                if !text.isEmpty {
                    stableSince = stableSince ?? now()
                    if now() - stableSince! >= 3 { break }
                }
            }
            let traceDeadline = now() + 90
            while now() < traceDeadline {
                if let trace = try RuntimeLatencyLogReader.recent().traces
                    .last(where: { !seenTraceIDs.contains($0.traceID) && $0.triggerObserved }) {
                    result.latencyTrace = trace
                    if trace.keyUpToInteractionSettledMilliseconds != nil { break }
                }
                sample(field, into: &result, until: now() + 0.5)
            }
            sample(field, into: &result, until: now() + 1.5)

            let historyDeadline = now() + 15
            repeat {
                result.historyRows = try historyRows(after: historyBefore)
                if !result.historyRows.isEmpty { break }
                Thread.sleep(forTimeInterval: 0.5)
            } while now() < historyDeadline
        } catch {
            result.error = String(describing: error)
        }
        if shiftHeld {
            result.keyUpUptime = (try? RuntimeShortcutInjector.postLeftShiftUp())?.postedAtSystemUptime
        }
        return result
    }

    static func openTarget(_ file: URL) throws -> (NSRunningApplication, AXUIElement, AXUIElement) {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: file)
        try run("/usr/bin/open", ["-a", "TextEdit", file.path])
        let token = file.deletingPathExtension().lastPathComponent
        let deadline = now() + 20
        while now() < deadline {
            if let application = NSRunningApplication.runningApplications(withBundleIdentifier: textEditBundleID).first {
                let appElement = AXUIElementCreateApplication(application.processIdentifier)
                if let window = RuntimeAX.window(containing: token, in: appElement),
                   let field = RuntimeAX.firstEditableElement(in: window),
                   RuntimeAX.focus(application: application, windowElement: window, textElement: field) {
                    return (application, window, field)
                }
            }
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.2))
        }
        throw ProbeError("TextEdit window for \(token) did not become a focused editable field")
    }

    static func sample(_ field: AXUIElement, into result: inout LiveTypingCase, until end: Double) {
        repeat {
            let text = RuntimeAX.text(from: field)
            let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            result.sampleReads += 1
            if result.samples.last.map({ $0.text != text || $0.frontmostBundleID != frontmost }) ?? true {
                result.samples.append(TextSample(uptime: now(), text: text, frontmostBundleID: frontmost))
            }
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))
        } while now() < end
    }

    static func waitForPrewarm(since start: Date, timeoutSeconds: TimeInterval) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            let output = (try? run("/usr/bin/log", [
                "show", "--start", formatter.string(from: start), "--style", "compact",
                "--predicate", "subsystem == \"com.negentropi.RomaJustTalk\" && eventMessage CONTAINS \"Prewarm \"",
            ])) ?? ""
            if let line = output.split(separator: "\n").first(where: { $0.contains("Prewarm completed") || $0.contains("Prewarm failed") }) {
                return String(line)
            }
            Thread.sleep(forTimeInterval: 3)
        }
        return "timeout after \(Int(timeoutSeconds))s"
    }

    static func historyRows(after primaryKey: Int) throws -> [HistoryRow] {
        guard FileManager.default.fileExists(atPath: historyStore) else { return [] }
        let output = try run("/usr/bin/sqlite3", [
            "-readonly", "-json", historyStore,
            "SELECT Z_PK, ZTEXT FROM ZTRANSCRIPTION WHERE Z_PK > \(primaryKey) ORDER BY Z_PK",
        ])
        guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return try JSONDecoder().decode([HistoryRow].self, from: Data(output.utf8))
    }

    @discardableResult
    static func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.standardError
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ProbeError("\(executable) \(arguments.first ?? "") exited \(process.terminationStatus)")
        }
        return String(decoding: data, as: UTF8.self)
    }

    static func now() -> Double { ProcessInfo.processInfo.systemUptime }

    static func log(_ message: String) {
        print("[live-typing-probe] \(message)")
        fflush(stdout)
    }

    static func write(_ report: LiveTypingReport, to url: URL) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(report).write(to: url, options: .atomic)
    }
}
