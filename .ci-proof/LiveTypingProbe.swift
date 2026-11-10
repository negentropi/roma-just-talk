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
    let target: String
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
            fputs("usage: LiveTypingProbe --config PATH --fixture WAV --mode on|off --output JSON --targets DIR [--target textedit|chrome] [--cases N]\n", stderr)
            exit(2)
        }
        let caseCount = Int(arguments["--cases"] ?? "2") ?? 2
        let target = arguments["--target"] ?? "textedit"
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
                    .appendingPathComponent("rjt-live-\(mode)-\(role)-\(UUID().uuidString.prefix(8)).\(target == "chrome" ? "html" : "txt")")
                let result = runCase(role: role, target: target, file: file, fixtureURL: fixtureURL, duration: duration, device: device)
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
        target: String,
        file: URL,
        fixtureURL: URL,
        duration: TimeInterval,
        device: RuntimeAudioDevice
    ) -> LiveTypingCase {
        var result = LiveTypingCase(role: role, target: target, targetFile: file.path)
        var shiftHeld = false
        do {
            let (application, window, field) = try target == "chrome" ? openChrome(file) : openTarget(file)
            guard (RuntimeAX.text(from: field) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ProbeError("Target field is not empty before recording")
            }
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

    static let chromeBundleID = "com.google.Chrome"

    /// A plain contenteditable editor in Chrome: a web editor, like chat composers, where Roma cannot
    /// edit text through Accessibility and must use keystrokes.
    static func openChrome(_ file: URL) throws -> (NSRunningApplication, AXUIElement, AXUIElement) {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let token = file.deletingPathExtension().lastPathComponent
        let label = "Roma live target \(token)"
        // A chat app at everyday size, so recordings show how live text feels in normal use.
        let html = """
        <!doctype html><meta charset="utf-8"><title>Team chat</title>
        <style>
        *{box-sizing:border-box}body{margin:0;font:15px -apple-system,sans-serif;color:#1d1c1d;display:flex;height:100vh}
        nav{width:220px;background:#3f0e40;color:#e8dbe8;padding:16px 12px;font-size:14px}nav b{color:#fff;display:block;margin-bottom:14px;font-size:16px}
        nav div{padding:5px 8px;border-radius:5px}nav .on{background:#1164a3;color:#fff}
        main{flex:1;display:flex;flex-direction:column}header{padding:12px 20px;border-bottom:1px solid #ddd;font-weight:700}
        #log{flex:1;padding:16px 20px;overflow:auto}.m{display:flex;gap:10px;margin-bottom:14px}.a{width:34px;height:34px;border-radius:6px;background:#e0b04c;flex:none}
        .m p{margin:2px 0 0}.n{font-weight:700}.t{color:#777;font-size:12px;font-weight:400;margin-left:6px}
        #box{margin:0 20px 20px;border:1px solid #bbb;border-radius:8px;padding:10px 12px;min-height:70px}
        #e{outline:none;white-space:pre-wrap;min-height:44px;line-height:1.45}
        </style>
        <nav><b>Roma team</b><div># general</div><div class="on"># design</div><div># random</div><div>Maya</div><div>Jon</div></nav>
        <main><header># design</header><div id="log">
        <div class="m"><div class="a"></div><div><span class="n">Maya</span><span class="t">10:02</span><p>Did the new onboarding copy land in the build?</p></div></div>
        <div class="m"><div class="a" style="background:#6bb38e"></div><div><span class="n">Jon</span><span class="t">10:04</span><p>Not yet, waiting on the review. Felix, any thoughts on the stream text idea?</p></div></div>
        </div><div id="box"><div id="e" contenteditable="true" role="textbox" aria-multiline="true" aria-label="\(label)" spellcheck="false"></div></div></main>
        <script>addEventListener('load',()=>document.getElementById('e').focus())</script>
        """
        try Data(html.utf8).write(to: file, options: .atomic)
        let profile = file.deletingLastPathComponent().appendingPathComponent("chrome-profile").path
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")
        process.arguments = ["--force-renderer-accessibility", "--user-data-dir=\(profile)", "--no-first-run",
                             "--no-default-browser-check", "--disable-features=Translate", "--window-size=1300,800",
                             "--new-window", file.absoluteString]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        let deadline = now() + 40
        while now() < deadline {
            if let application = NSRunningApplication.runningApplications(withBundleIdentifier: chromeBundleID).first {
                application.activate()
                let appElement = AXUIElementCreateApplication(application.processIdentifier)
                AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)
                if let field = RuntimeAX.editableElement(in: appElement, identifying: label),
                   let window = RuntimeAX.window(for: field),
                   RuntimeAX.focus(application: application, windowElement: window, textElement: field) {
                    return (application, window, field)
                }
            }
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.3))
        }
        throw ProbeError("Chrome editor for \(token) did not become a focused editable field")
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
