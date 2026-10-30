import AppKit
import ApplicationServices
import AVFoundation
import CryptoKit
import Foundation
import RuntimeE2ECore

@main
struct LipVisualCases {
    @MainActor static func main() async {
        if CommandLine.arguments.dropFirst() == ["--link-check"] {
            print("PASS native lip dictation helper loaded")
            return
        }
        let early = Array(CommandLine.arguments.dropFirst())
        if early.count == 5, early[0] == "--screen-capture-check", early[1] == "--json-output", early[3] == "--consent-result" {
            exit(RuntimeScreenCaptureCheck.capture(
                reportURL: URL(fileURLWithPath: early[2]), consentResultURL: URL(fileURLWithPath: early[4])
            ) ? 0 : 1)
        }
        if early.count == 4, early[0] == "--screen-consent-driver", early[2] == "--output" {
            exit(RuntimeScreenCaptureCheck.approveConsent(
                configurationURL: URL(fileURLWithPath: early[1]), reportURL: URL(fileURLWithPath: early[3])
            ) ? 0 : 1)
        }
        var report: [String: Any] = ["passed": false]
        var output: URL?
        var session: RuntimeVoiceInkSession?
        var outputSession: RuntimeSystemOutputSession?
        var target: RuntimePreparedTarget?
        var playback: RuntimeAudioPlayback?
        var modifierHeld = false
        do {
            let arguments = CommandLine.arguments
            guard arguments.count % 2 == 1 else { throw ProofError.invalidArguments }
            var values: [String: String] = [:]
            for index in stride(from: 1, to: arguments.count, by: 2) { values[arguments[index]] = arguments[index + 1] }
            guard let configPath = values["--config"], let outputPath = values["--output"],
                  let scenario = values["--scenario"], let appLog = values["--app-log"] else { throw ProofError.invalidArguments }
            output = URL(fileURLWithPath: outputPath)
            let configuration = try JSONDecoder().decode(RuntimeHarnessConfiguration.self, from: Data(contentsOf: URL(fileURLWithPath: configPath)))
            let preflight = RuntimePreflight.run(configuration: configuration)
            report["preflight"] = try json(preflight)
            guard preflight.passed, let audioDevice = preflight.requestedAudioDevice else { throw ProofError.preflight }
            let startOffset = (try? Data(contentsOf: URL(fileURLWithPath: appLog)).count) ?? 0
            outputSession = try RuntimeSystemOutputSession.start(targetDevice: audioDevice)
            session = try RuntimeVoiceInkSession.start(configuration: configuration, audioDeviceUID: audioDevice.uid)
            report["app"] = try json(session!.info)
            report["scenario"] = scenario
            let application = try runningApp(configuration.voiceInkBundleIdentifier)
            if scenario == "setup" {
                try openSettings(application, appPath: session!.info.selectedAppPath)
                if let setup = find(application, label: "Set Up", roles: [kAXButtonRole]) {
                    try press(setup)
                    report["actualSetupButtonPressed"] = true
                } else {
                    report["actualSetupButtonPressed"] = false
                }
                let deadline = Date().addingTimeInterval(1200)
                var ready = false
                while Date() < deadline {
                    if let toggle = find(application, label: "Read Lips While Dictating", roles: [kAXCheckBoxRole, "AXSwitch"]), enabled(toggle) {
                        ready = true
                        break
                    }
                    if find(application, label: "Couldn't set up", roles: [kAXStaticTextRole]) != nil { break }
                    wait(0.5)
                }
                guard ready else { throw ProofError.setup }
                screenshot(output!.deletingLastPathComponent().appendingPathComponent("setup.png"))
                try setToggle(application, label: "Read Lips While Dictating", value: 1)
                screenshot(output!.deletingLastPathComponent().appendingPathComponent("settings-combined.png"))
                try setToggle(application, label: "Lips Only", value: 1)
                screenshot(output!.deletingLastPathComponent().appendingPathComponent("settings-lips-only.png"))
                try setToggle(application, label: "Read Lips While Dictating", value: 0)
                screenshot(output!.deletingLastPathComponent().appendingPathComponent("settings-off.png"))
                report["actualSetupUIReady"] = true
                report["actualModeControlsChanged"] = true
                report["passed"] = true
            } else {
                guard let websocket = values["--obs-config"], let still = values["--still"],
                      let video = values["--video"], let audio = values["--audio"] else { throw ProofError.invalidArguments }
                let obs = try OBSClient(configurationURL: URL(fileURLWithPath: websocket))
                try await obs.connect()
                defer { obs.close() }
                try await obs.media(path: still, looping: true)
                var disableControl: AXUIElement?
                if scenario == "disable" {
                    try openSettings(application, appPath: session!.info.selectedAppPath)
                    disableControl = find(application, label: "Read Lips While Dictating", roles: [kAXCheckBoxRole, "AXSwitch"])
                    guard let disableControl, toggleValue(disableControl) == 1 else { throw ProofError.settingControl }
                }
                let prepared = try RuntimeTargetController.prepare(
                    target: configuration.targets[0], textScenario: .existingText,
                    runID: "lip-\(scenario)-textedit-existingText-r1-\(UUID().uuidString.prefix(6))",
                    settleSeconds: 1, availabilityPolicy: .launchIfNeeded
                )
                target = prepared
                report["target"] = try json(prepared.info)
                let down = try RuntimeShortcutInjector.postLeftShiftDown()
                modifierHeld = true
                report["shortcutDown"] = try json(down)
                guard waitForLog(appLog, after: startOffset, containing: "event=engine.state.recording", timeout: 45) else { throw ProofError.recordingStart }
                guard prepared.refreshRenderedBaseline() == nil else { throw ProofError.renderedBaseline }
                try await obs.media(path: video, looping: false)
                let audioURL = URL(fileURLWithPath: audio)
                let file = try AVAudioFile(forReading: audioURL)
                let duration = Double(file.length) / file.processingFormat.sampleRate
                let playing = RuntimeAudioPlayback(fixtureURL: audioURL, device: audioDevice, expectedDurationSeconds: duration)
                playback = playing
                _ = try playing.start()
                let negative = ["cancel", "disable", "quit"].contains(scenario)
                if scenario == "disable" {
                    wait(0.5)
                    try press(disableControl!)
                    guard waitForLog(appLog, after: startOffset, containing: "canceled=true", timeout: 45) else { throw ProofError.cancellation }
                } else if scenario == "quit" {
                    wait(0.5)
                    guard application.terminate() else { throw ProofError.quit }
                    let deadline = Date().addingTimeInterval(45)
                    while !application.isTerminated, Date() < deadline { wait(0.1) }
                    guard application.isTerminated else { throw ProofError.quit }
                } else {
                    report["audioPlayback"] = try json(playing.waitUntilFinished())
                    wait(0.3)
                }
                let up = try RuntimeShortcutInjector.postLeftShiftUp()
                modifierHeld = false
                report["shortcutUp"] = try json(up)
                if scenario == "cancel" {
                    guard waitForLog(appLog, after: startOffset, containing: "recognition.start", timeout: 45) else { throw ProofError.inferenceStart }
                    guard RuntimeAX.postKey(keyCode: 53, flags: []) else { throw ProofError.cancellation }
                    wait(0.1)
                    guard RuntimeAX.postKey(keyCode: 53, flags: []) else { throw ProofError.cancellation }
                }
                let visible = prepared.waitForVisibleText(keyUpAtSystemUptime: up.postedAtSystemUptime, timeoutSeconds: negative ? 15 : 120)
                report["visibleText"] = try json(visible)
                screenshot(output!.deletingLastPathComponent().appendingPathComponent(scenario + ".png"))
                if scenario != "quit" {
                    guard waitForLog(appLog, after: startOffset, containing: "recording.drained id=", timeout: 45) else { throw ProofError.notDrained }
                }
                let messages = logSlice(appLog, after: startOffset)
                report["appMessages"] = messages
                let starts = messages.split(separator: "\n").filter { $0.contains("capture.start id=") }
                let recordingStarts = messages.split(separator: "\n").filter { $0.contains("event=engine.state.recording") }
                let captureID = starts.first.flatMap { line -> String? in
                    guard let start = line.range(of: "capture.start id=") else { return nil }
                    return line[start.upperBound...].split(separator: " ").first.map(String.init)
                }
                let closed = captureID.map { messages.contains("capture.closed id=\($0)") } ?? false
                let micClosed = messages.contains("recording=false pre_roll=false audio_unit=false")
                let micStarted = messages.contains("startRecording called") || messages.contains("Starting pre-roll buffering")
                let noFinishDeadline = !messages.contains("capture.finish_deadline")
                report["cameraStartCount"] = starts.count
                report["recordingStartCount"] = recordingStarts.count
                report["captureID"] = captureID
                report["cameraClosedObserved"] = closed
                report["microphoneClosedDiagnostic"] = micClosed
                report["microphoneStartObserved"] = micStarted
                report["nativeWriterDeadlineObserved"] = !noFinishDeadline
                guard starts.count == 1, recordingStarts.count == 1,
                      starts.allSatisfy({ $0.contains("audio_inputs=0") }) else { throw ProofError.captureEvidence }
                if negative {
                    guard visible.text == nil || visible.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true else { throw ProofError.unexpectedInsertion }
                    guard closed, noFinishDeadline, messages.contains("canceled=true") else { throw ProofError.cancellation }
                } else {
                    let expected = "its eleven oclock"
                    guard normalized(visible.text ?? "") == expected, visible.keyUpToVisibleMilliseconds != nil else { throw ProofError.dictation }
                    guard starts.count == 1, closed, noFinishDeadline, messages.contains("recognition.start"), messages.contains("canceled=false") else { throw ProofError.captureEvidence }
                    guard let captureID else { throw ProofError.captureEvidence }
                    let selectedSource = scenario == "combined" ? "voice" : "lips"
                    let selected = "recognition.selected id=\(captureID) source=\(selectedSource)"
                    guard messages.contains(selected) else { throw ProofError.captureEvidence }
                    report["selectedSource"] = selectedSource
                    if scenario == "lips" || scenario == "combined-silent" {
                        report["visualFallbackRequired"] = scenario == "combined-silent"
                    }
                    if scenario == "lips" {
                        guard micClosed, !micStarted else { throw ProofError.microphone }
                    }
                }
                report["passed"] = true
            }
        } catch {
            report["error"] = String(describing: error)
            if let app = try? runningApp("com.negentropi.RomaJustTalk") {
                report["appAccessibilitySnapshot"] = accessibilitySnapshot(app)
            }
        }
        if modifierHeld { _ = try? RuntimeShortcutInjector.postLeftShiftUp() }
        try? playback?.stop()
        if let target {
            let cleanup = target.cleanup()
            report["targetCleanup"] = try? json(cleanup)
            if !cleanup.passed { report["passed"] = false }
        }
        do {
            try session?.restore()
            try outputSession?.restore()
            report["restored"] = true
        } catch {
            report["restored"] = false
            report["restoreError"] = String(describing: error)
            report["passed"] = false
        }
        if let output, let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: output, options: .atomic)
        }
        exit(report["passed"] as? Bool == true ? 0 : 1)
    }

    static func json<T: Encodable>(_ value: T) throws -> Any {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
    }
    static func normalized(_ text: String) -> String {
        let words = text.lowercased().replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "’", with: "").split { !$0.isLetter && !$0.isNumber }
        return words.map { $0 == "11" ? "eleven" : String($0) }.joined(separator: " ")
    }
    static func wait(_ seconds: TimeInterval) { RunLoop.current.run(until: Date().addingTimeInterval(seconds)) }
    static func logSlice(_ path: String, after offset: Int) -> String {
        guard let file = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else { return "" }
        defer { try? file.close() }
        do {
            try file.seek(toOffset: UInt64(offset))
            return String(decoding: try file.readToEnd() ?? Data(), as: UTF8.self)
        } catch { return "" }
    }
    static func waitForLog(_ path: String, after offset: Int, containing marker: String, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if logSlice(path, after: offset).contains(marker) { return true }
            wait(0.05)
        }
        return false
    }
    static func runningApp(_ identifier: String) throws -> NSRunningApplication {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: identifier).first else { throw ProofError.appMissing }
        return app
    }
    static func enabled(_ element: AXUIElement) -> Bool {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, kAXEnabledAttribute as CFString, &value) == .success && (value as? NSNumber)?.boolValue == true
    }
    static func toggleValue(_ element: AXUIElement) -> Int? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success else { return nil }
        return (value as? NSNumber)?.intValue
    }
    static func press(_ element: AXUIElement) throws {
        guard AXUIElementPerformAction(element, kAXPressAction as CFString) == .success else { throw ProofError.settingControl }
    }
    static func setToggle(_ app: NSRunningApplication, label: String, value: Int) throws {
        guard let toggle = find(app, label: label, roles: [kAXCheckBoxRole, "AXSwitch"]), enabled(toggle) else { throw ProofError.settingControl }
        if toggleValue(toggle) != value { try press(toggle) }
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if let current = find(app, label: label, roles: [kAXCheckBoxRole, "AXSwitch"]), toggleValue(current) == value { return }
            wait(0.1)
        }
        throw ProofError.settingControl
    }
    static func find(_ application: NSRunningApplication, label: String, roles: Set<String>) -> AXUIElement? {
        let root = AXUIElementCreateApplication(application.processIdentifier)
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        var visited: [AXUIElement] = []
        let deadline = Date().addingTimeInterval(3)
        while !queue.isEmpty, visited.count < 2000, Date() < deadline {
            let (element, depth) = queue.removeFirst()
            guard depth <= 24, !visited.contains(where: { CFEqual($0, element) }) else { continue }
            visited.append(element)
            AXUIElementSetMessagingTimeout(element, 0.15)
            let role = RuntimeAX.stringAttribute(kAXRoleAttribute, from: element) ?? ""
            let title = [kAXTitleAttribute, kAXDescriptionAttribute].compactMap { RuntimeAX.stringAttribute($0, from: element) }.joined(separator: " ")
            let value = role == kAXStaticTextRole ? RuntimeAX.stringAttribute(kAXValueAttribute, from: element) ?? "" : ""
            if roles.contains(role), title.contains(label) || value.contains(label) { return element }
            var children: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
               let children = children as? [AXUIElement] { queue.append(contentsOf: children.map { ($0, depth + 1) }) }
        }
        return nil
    }
    static func accessibilitySnapshot(_ application: NSRunningApplication) -> [[String: Any]] {
        var queue: [(AXUIElement, Int)] = [(AXUIElementCreateApplication(application.processIdentifier), 0)]
        var visited: [AXUIElement] = []
        var result: [[String: Any]] = []
        let deadline = Date().addingTimeInterval(4)
        while !queue.isEmpty, result.count < 500, Date() < deadline {
            let (element, depth) = queue.removeFirst()
            guard depth <= 24, !visited.contains(where: { CFEqual($0, element) }) else { continue }
            visited.append(element)
            AXUIElementSetMessagingTimeout(element, 0.1)
            let role = RuntimeAX.stringAttribute(kAXRoleAttribute, from: element) ?? ""
            var node: [String: Any] = ["role": role, "title": RuntimeAX.stringAttribute(kAXTitleAttribute, from: element) ?? "", "description": RuntimeAX.stringAttribute(kAXDescriptionAttribute, from: element) ?? "", "enabled": enabled(element)]
            if role == kAXStaticTextRole { node["staticText"] = RuntimeAX.stringAttribute(kAXValueAttribute, from: element) }
            if [kAXCheckBoxRole, "AXSwitch"].contains(role) { node["toggleValue"] = toggleValue(element) }
            result.append(node)
            var children: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
               let children = children as? [AXUIElement] { queue.append(contentsOf: children.map { ($0, depth + 1) }) }
        }
        return result
    }
    static func openSettings(_ app: NSRunningApplication, appPath: String) throws {
        let reopen = Process()
        reopen.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        reopen.arguments = [appPath]
        try reopen.run()
        reopen.waitUntilExit()
        app.activate(options: [.activateIgnoringOtherApps])
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if let settings = find(app, label: "Settings", roles: [kAXButtonRole, kAXRowRole, "AXLink"]) {
                if AXUIElementPerformAction(settings, kAXPressAction as CFString) != .success {
                    _ = AXUIElementSetAttributeValue(settings, kAXSelectedAttribute as CFString, kCFBooleanTrue)
                }
                wait(0.5)
                if find(app, label: "Read Lips While Dictating", roles: [kAXCheckBoxRole, "AXSwitch"]) != nil { return }
            }
            wait(0.2)
        }
        throw ProofError.settingControl
    }
    static func screenshot(_ url: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", url.path]
        do { try process.run(); process.waitUntilExit() }
        catch { }
    }
    enum ProofError: Error {
        case invalidArguments, preflight, appMissing, setup, settingControl, recordingStart, renderedBaseline
        case inferenceStart, notDrained, dictation, captureEvidence, unexpectedInsertion, microphone, cancellation, quit
    }
}

private final class OBSClient {
    private let session = URLSession(configuration: .ephemeral)
    private let socket: URLSessionWebSocketTask
    private let password: String
    private var requestCounter = 0
    init(configurationURL: URL) throws {
        let configuration = try JSONSerialization.jsonObject(with: Data(contentsOf: configurationURL)) as? [String: Any]
        guard let configuration, let password = configuration["server_password"] as? String,
              let port = configuration["server_port"] as? Int, port == 4455 else { throw OBSError.configuration }
        self.password = password
        socket = session.webSocketTask(with: URL(string: "ws://127.0.0.1:\(port)")!)
    }
    func close() { socket.cancel(with: .normalClosure, reason: nil); session.invalidateAndCancel() }
    func connect() async throws {
        socket.resume()
        let hello = try await receive()
        guard hello["op"] as? Int == 0, let data = hello["d"] as? [String: Any] else { throw OBSError.protocolFailure }
        var identify: [String: Any] = ["rpcVersion": 1, "eventSubscriptions": 0]
        if let authentication = data["authentication"] as? [String: String], let salt = authentication["salt"], let challenge = authentication["challenge"] {
            let secret = Data(SHA256.hash(data: Data((password + salt).utf8))).base64EncodedString()
            identify["authentication"] = Data(SHA256.hash(data: Data((secret + challenge).utf8))).base64EncodedString()
        }
        try await send(["op": 1, "d": identify])
        guard try await receive()["op"] as? Int == 2 else { throw OBSError.protocolFailure }
    }
    func media(path: String, looping: Bool) async throws {
        try await request("SetInputSettings", ["inputName": "PublicSilentVideo", "inputSettings": ["is_local_file": true, "local_file": path, "looping": looping, "restart_on_activate": true, "clear_on_media_end": false], "overlay": true])
        try await request("SetInputMute", ["inputName": "PublicSilentVideo", "inputMuted": true])
        try await request("TriggerMediaInputAction", ["inputName": "PublicSilentVideo", "mediaAction": "OBS_WEBSOCKET_MEDIA_INPUT_ACTION_RESTART"])
    }
    private func request(_ type: String, _ data: [String: Any]) async throws {
        requestCounter += 1
        let id = String(requestCounter)
        try await send(["op": 6, "d": ["requestType": type, "requestId": id, "requestData": data]])
        for _ in 0..<20 {
            let message = try await receive()
            guard message["op"] as? Int == 7, let details = message["d"] as? [String: Any], details["requestId"] as? String == id else { continue }
            guard let status = details["requestStatus"] as? [String: Any], status["result"] as? Bool == true else { throw OBSError.requestFailed(type) }
            return
        }
        throw OBSError.protocolFailure
    }
    private func send(_ object: [String: Any]) async throws {
        let data = try JSONSerialization.data(withJSONObject: object)
        try await socket.send(.string(String(decoding: data, as: UTF8.self)))
    }
    private func receive() async throws -> [String: Any] {
        let message = try await socket.receive()
        let data: Data
        switch message {
        case .string(let text): data = Data(text.utf8)
        case .data(let value): data = value
        @unknown default: throw OBSError.protocolFailure
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw OBSError.protocolFailure }
        return object
    }
    enum OBSError: Error { case configuration, protocolFailure, requestFailed(String) }
}
