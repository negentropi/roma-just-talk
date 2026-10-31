import AppKit
import ApplicationServices
import AVFoundation
import CryptoKit
import Darwin
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
            let priorSetupRun = values["--prior-setup-run"].flatMap(Int.init)
            let priorSetupSourceHead = values["--prior-setup-source-head"]
            if values["--prior-setup-run"] != nil {
                guard scenario == "setup", let priorSetupRun, priorSetupRun > 0 else { throw ProofError.invalidArguments }
            }
            if let priorSetupSourceHead {
                guard priorSetupRun != nil, priorSetupSourceHead.range(of: "^[0-9a-f]{40}$", options: .regularExpression) != nil else { throw ProofError.invalidArguments }
            }
            output = URL(fileURLWithPath: outputPath)
            let configuration = try JSONDecoder().decode(RuntimeHarnessConfiguration.self, from: Data(contentsOf: URL(fileURLWithPath: configPath)))
            if scenario == "negative-controls" {
                report["scenario"] = scenario
                try runNegativeControls(configuration: configuration, report: &report, directory: output!.deletingLastPathComponent())
                let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                try data.write(to: output!, options: .atomic)
                return
            }
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
                let cachedSetup = priorSetupRun != nil
                report["setupProfile"] = priorSetupSourceHead != nil ? "verifiedCachedModelWithPriorSetupSources" : (cachedSetup ? "verifiedCachedModelWithPriorSetup" : "freshPublisherDownload")
                report["freshDownloadAssessed"] = !cachedSetup
                report["actualSetupButtonPressed"] = false
                if let priorSetupRun { report["priorSetupRun"] = priorSetupRun }
                if let priorSetupSourceHead {
                    report["priorSetupSourceHead"] = priorSetupSourceHead
                    report["priorSetupSameExecutable"] = false
                }
                try openSettings(application, appPath: session!.info.selectedAppPath, report: &report)
                if !cachedSetup {
                    guard let setup = find(application, label: "Set Up", roles: [kAXButtonRole]), enabled(setup.element) else { throw ProofError.setup }
                    report["setupControl"] = setup.evidence
                    try press(setup.element)
                    report["actualSetupButtonPressed"] = true
                }
                let deadline = Date().addingTimeInterval(cachedSetup ? 30 : 1200)
                var ready = false
                while Date() < deadline {
                    if let toggle = find(application, label: "Read Lips While Dictating", roles: [kAXCheckBoxRole, "AXSwitch"]), enabled(toggle.element) {
                        let status = find(application, label: "Ready", roles: [kAXStaticTextRole])
                        if !cachedSetup || status != nil {
                            report["readyControl"] = toggle.evidence
                            report["readyStatusControl"] = status?.evidence
                            report["initialMasterOffObserved"] = toggleValue(toggle.element) == 0
                            guard toggleValue(toggle.element) == 0 else { throw ProofError.setup }
                            ready = true
                            break
                        }
                    }
                    if find(application, label: "Couldn't set up", roles: [kAXStaticTextRole]) != nil { break }
                    wait(0.5)
                }
                guard ready else { throw ProofError.setup }
                screenshot(output!.deletingLastPathComponent().appendingPathComponent("setup.png"))
                try setToggle(application, label: "Read Lips While Dictating", value: 1, report: &report)
                guard let lipsOnly = find(application, label: "Lips Only", roles: [kAXCheckBoxRole, "AXSwitch"]),
                      enabled(lipsOnly.element), toggleValue(lipsOnly.element) == 0 else { throw ProofError.setup }
                report["initialLipsOnlyOffObserved"] = true
                report["initialLipsOnlyControl"] = lipsOnly.evidence
                screenshot(output!.deletingLastPathComponent().appendingPathComponent("settings-combined.png"))
                try setToggle(application, label: "Lips Only", value: 1, report: &report)
                screenshot(output!.deletingLastPathComponent().appendingPathComponent("settings-lips-only.png"))
                try setToggle(application, label: "Lips Only", value: 0, report: &report)
                guard let finalLipsOnly = find(application, label: "Lips Only", roles: [kAXCheckBoxRole, "AXSwitch"]),
                      toggleValue(finalLipsOnly.element) == 0 else { throw ProofError.setup }
                report["finalLipsOnlyOffObserved"] = true
                report["finalLipsOnlyControl"] = finalLipsOnly.evidence
                try setToggle(application, label: "Read Lips While Dictating", value: 0, report: &report)
                guard let finalMaster = find(application, label: "Read Lips While Dictating", roles: [kAXCheckBoxRole, "AXSwitch"]),
                      toggleValue(finalMaster.element) == 0 else { throw ProofError.setup }
                report["finalMasterOffObserved"] = true
                screenshot(output!.deletingLastPathComponent().appendingPathComponent("settings-off.png"))
                report["actualSetupUIReady"] = true
                report["actualModeControlsChanged"] = true
                report["passed"] = true
            } else {
                let negative = ["cancel", "disable", "quit"].contains(scenario)
                guard let websocket = values["--obs-config"], let video = values["--video"],
                      let audio = values["--audio"] else { throw ProofError.invalidArguments }
                let obs = try OBSClient(configurationURL: URL(fileURLWithPath: websocket))
                try await obs.connect()
                defer { report["obsMedia"] = obs.mediaEvidence; obs.close() }
                try await obs.preparePausedMotion(path: video)
                var disableControl: AXUIElement?
                if scenario == "disable" {
                    try openSettings(application, appPath: session!.info.selectedAppPath, report: &report)
                    let matched = find(application, label: "Read Lips While Dictating", roles: [kAXCheckBoxRole, "AXSwitch"])
                    disableControl = matched?.element
                    report["disableControl"] = matched?.evidence
                    guard let disableControl, toggleValue(disableControl) == 1 else { throw ProofError.settingControl }
                }
                let prepared = try RuntimeTargetController.prepare(
                    target: configuration.targets[0], textScenario: .existingText,
                    runID: "lip-\(scenario)-textedit-existingText-r1-\(UUID().uuidString.prefix(6))",
                    settleSeconds: 1, availabilityPolicy: .launchIfNeeded
                )
                target = prepared
                report["target"] = try json(prepared.info)
                let seededFullText = negative ? prepared.readFullText() : nil
                if negative {
                    guard let seededFullText else { throw ProofError.targetUnreadable }
                    guard seededFullText == RuntimeTextScenario.existingText.initialText else { throw ProofError.unexpectedInsertion }
                    report["negativeSeededFullText"] = seededFullText
                }
                try await obs.verifyPausedBeforeShortcut()
                let recorderLogOffset = (try? Data(contentsOf: URL(fileURLWithPath: appLog)).count) ?? startOffset
                let down = try RuntimeShortcutInjector.postLeftShiftDown()
                modifierHeld = true
                report["shortcutDown"] = try json(down)
                guard waitForLog(appLog, after: startOffset, containing: "event=engine.state.recording", timeout: 45) else { throw ProofError.recordingStart }
                guard let captureID = captureIdentifier(logSlice(appLog, after: startOffset)) else { throw ProofError.captureEvidence }
                report["captureID"] = captureID
                guard prepared.refreshRenderedBaseline() == nil else { throw ProofError.renderedBaseline }
                let audioURL = URL(fileURLWithPath: audio)
                let file = try AVAudioFile(forReading: audioURL)
                let duration = Double(file.length) / file.processingFormat.sampleRate
                let playing = RuntimeAudioPlayback(fixtureURL: audioURL, device: audioDevice, expectedDurationSeconds: duration)
                playback = playing
                try await obs.playPreparedMotion()
                report["audioPlaybackStartedAtSystemUptime"] = try playing.start()
                try await obs.observePlayingMotion()
                if scenario == "disable" {
                    wait(0.5)
                    try press(disableControl!)
                } else if scenario == "quit" {
                    wait(0.5)
                    guard application.terminate() else { throw ProofError.quit }
                    let deadline = Date().addingTimeInterval(45)
                    while !processExited(application), Date() < deadline { wait(0.1) }
                    guard processExited(application) else { throw ProofError.quit }
                } else {
                    report["audioPlayback"] = try json(playing.waitUntilFinished())
                    try await obs.waitForMotionEnd()
                    report["sourceMotionEndedBeforeShortcutUp"] = true
                    wait(0.3)
                }
                let up = try RuntimeShortcutInjector.postLeftShiftUp()
                modifierHeld = false
                report["shortcutUp"] = try json(up)
                if scenario == "cancel" {
                    let miniShown = waitForLog(appLog, after: recorderLogOffset, containing: "Showing mini recorder", timeout: 5,
                                              processIdentifier: application.processIdentifier)
                    report["miniRecorderShown"] = miniShown
                    report["miniRecorderShownLines"] = logSlice(appLog, after: recorderLogOffset, processIdentifier: application.processIdentifier)
                        .split(separator: "\n").filter { $0.contains("Showing mini recorder") }.map(String.init)
                    guard miniShown else { throw ProofError.cancellation }
                    guard waitForLog(appLog, after: startOffset, containing: "recognition.start", timeout: 45,
                                     processIdentifier: application.processIdentifier) else { throw ProofError.inferenceStart }
                    let escapeLogOffset = (try? Data(contentsOf: URL(fileURLWithPath: appLog)).count) ?? startOffset
                    var injections: [[String: Any]] = []
                    let firstAt = ProcessInfo.processInfo.systemUptime
                    let firstPosted = RuntimeAX.postKey(keyCode: 53, flags: [])
                    injections.append(["postedAtSystemUptime": firstAt, "posted": firstPosted])
                    report["escapeInjections"] = injections
                    guard firstPosted else { throw ProofError.cancellation }
                    wait(0.1)
                    let secondAt = ProcessInfo.processInfo.systemUptime
                    let secondPosted = RuntimeAX.postKey(keyCode: 53, flags: [])
                    injections.append(["postedAtSystemUptime": secondAt, "posted": secondPosted])
                    report["escapeInjections"] = injections
                    guard secondPosted else { throw ProofError.cancellation }
                    let dispatchObserved = waitForLog(appLog, after: escapeLogOffset, containing: "dispatchKeyDown: action=miniRecorderEscape",
                                                      timeout: 5, processIdentifier: application.processIdentifier, minimumCount: 2)
                    let cancelCalled = waitForLog(appLog, after: escapeLogOffset, containing: "cancelRecording called",
                                                  timeout: 5, processIdentifier: application.processIdentifier)
                    let routedLines = logSlice(appLog, after: escapeLogOffset, processIdentifier: application.processIdentifier).split(separator: "\n")
                    let dispatches = routedLines.filter { $0.contains("dispatchKeyDown: action=miniRecorderEscape") }.map(String.init)
                    report["escapeDispatchLines"] = dispatches
                    report["escapeDispatchCount"] = dispatches.count
                    report["cancelRecordingCalled"] = cancelCalled
                    report["cancelRecordingCallLines"] = routedLines.filter { $0.contains("cancelRecording called") }.map(String.init)
                    guard dispatchObserved, dispatches.count == 2, cancelCalled else { throw ProofError.cancellation }
                }
                var visible: RuntimeVisibleTextResult?
                if negative {
                    if scenario == "quit" {
                        guard processExited(application) else { throw ProofError.quit }
                        report["negativeCompletionBoundary"] = "ownedAppProcessTerminated"
                        report["terminatedAppPID"] = application.processIdentifier
                    } else {
                        let terminal = "recording.drained id=\(captureID) canceled=true"
                        guard waitForLog(appLog, after: startOffset, containing: terminal, timeout: 45) else { throw ProofError.notDrained }
                        report["negativeCompletionBoundary"] = terminal
                    }
                    if scenario == "disable" || scenario == "quit" { await obs.recordStats(phase: "afterPartialCaptureStop") }
                    let finalFullText = prepared.readFullText()
                    let observation = RuntimeNegativeTextObservation.classify(baseline: seededFullText, finalText: finalFullText)
                    report["negativeTextObservation"] = observation.rawValue
                    report["negativeFinalFullText"] = finalFullText.map { $0 as Any } ?? NSNull()
                    guard observation != .unreadable else { throw ProofError.targetUnreadable }
                    guard observation == .readableUnchanged else { throw ProofError.unexpectedInsertion }
                } else {
                    let terminal = "recording.drained id=\(captureID) canceled=false"
                    report["positiveDrainDeadlineSeconds"] = 120
                    guard waitForLog(appLog, after: startOffset, containing: terminal, timeout: 120) else { throw ProofError.notDrained }
                    report["positiveCompletionBoundary"] = terminal
                    report["observationOrder"] = "ownedRecordingDrainThenAXAndRenderedPixels"
                    report["observationLatencyBoundary"] = "After-drain functional observation; no product latency claim."
                    report["positiveObservationStartedAtSystemUptime"] = ProcessInfo.processInfo.systemUptime
                    let observed = prepared.waitForVisibleText(keyUpAtSystemUptime: up.postedAtSystemUptime, timeoutSeconds: 120)
                    visible = observed
                    report["visibleText"] = try json(observed)
                }
                screenshot(output!.deletingLastPathComponent().appendingPathComponent(scenario + ".png"))
                let messages = logSlice(appLog, after: startOffset)
                report["appMessages"] = messages
                let starts = messages.split(separator: "\n").filter { $0.contains("capture.start id=") }
                let recordingStarts = messages.split(separator: "\n").filter { $0.contains("event=engine.state.recording") }
                let closed = messages.contains("capture.closed id=\(captureID)")
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
                    guard closed, noFinishDeadline else { throw ProofError.cancellation }
                } else {
                    guard let visible else { throw ProofError.dictation }
                    let expected = "its eleven oclock"
                    guard normalized(visible.text ?? "") == expected, visible.keyUpToVisibleMilliseconds != nil else { throw ProofError.dictation }
                    guard starts.count == 1, closed, noFinishDeadline, messages.contains("recognition.start"), messages.contains("canceled=false") else { throw ProofError.captureEvidence }
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
            if let output {
                report["failureScreenshot"] = screenshot(output.deletingPathExtension().appendingPathExtension("failure.png"))
            }
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
    static func runNegativeControls(configuration: RuntimeHarnessConfiguration, report: inout [String: Any], directory: URL) throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["GITHUB_ACTIONS"] == "true", environment["RUNNER_ENVIRONMENT"] == "github-hosted",
              getuid() != 0, let target = configuration.targets.first,
              target.bundleIdentifier == "com.apple.TextEdit" else { throw ProofError.invalidArguments }
        let prepared = try RuntimeTargetController.prepare(
            target: target, textScenario: .existingText,
            runID: "negative-controls-\(UUID().uuidString)", settleSeconds: configuration.targetSettleSeconds,
            availabilityPolicy: .launchIfNeeded
        )
        var cleanedUp = false
        defer {
            if !cleanedUp { report["targetCleanup"] = try? json(prepared.cleanup()) }
        }
        report["target"] = try json(prepared.info)
        guard let baseline = prepared.readFullText(), baseline == RuntimeTextScenario.existingText.initialText,
              let unchangedText = prepared.readFullText() else { throw ProofError.targetUnreadable }
        let unchanged = RuntimeNegativeTextObservation.classify(baseline: baseline, finalText: unchangedText)
        report["unchangedObservation"] = unchanged.rawValue
        report["unchangedFullText"] = unchangedText
        guard unchanged == .readableUnchanged else { throw ProofError.negativeControl }
        report["unchangedScreenshot"] = screenshot(directory.appendingPathComponent("negative-controls-unchanged.png"))
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == prepared.info.processIdentifier,
              RuntimeAX.postKey(keyCode: 0, flags: .maskCommand, processIdentifier: prepared.info.processIdentifier),
              RuntimeAX.postKey(keyCode: 51, flags: [], processIdentifier: prepared.info.processIdentifier) else { throw ProofError.negativeControl }
        wait(0.2)
        guard let changedText = prepared.readFullText() else { throw ProofError.targetUnreadable }
        let changed = RuntimeNegativeTextObservation.classify(baseline: baseline, finalText: changedText)
        report["changedObservation"] = changed.rawValue
        report["changedFullText"] = changedText
        report["changedScreenshot"] = screenshot(directory.appendingPathComponent("negative-controls-changed.png"))
        guard changed == .changed else { throw ProofError.negativeControl }
        let cleanup = prepared.cleanup()
        cleanedUp = true
        report["targetCleanup"] = try json(cleanup)
        guard cleanup.passed else { throw ProofError.negativeControl }
        let closedText = prepared.readFullText()
        let closed = RuntimeNegativeTextObservation.classify(baseline: baseline, finalText: closedText)
        report["closedObservation"] = closed.rawValue
        report["closedTargetReadable"] = closedText != nil
        guard closedText == nil, closed == .unreadable else { throw ProofError.negativeControl }
        report["acceptedStates"] = [unchanged.rawValue]
        report["rejectedStates"] = [changed.rawValue, closed.rawValue]
        report["passed"] = true
    }
    static func normalized(_ text: String) -> String {
        let words = text.lowercased().replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "’", with: "").split { !$0.isLetter && !$0.isNumber }
        return words.map { $0 == "11" ? "eleven" : String($0) }.joined(separator: " ")
    }
    static func wait(_ seconds: TimeInterval) { RunLoop.current.run(until: Date().addingTimeInterval(seconds)) }
    static func processExited(_ application: NSRunningApplication) -> Bool {
        application.isTerminated && kill(application.processIdentifier, 0) == -1 && errno == ESRCH
    }
    static func logSlice(_ path: String, after offset: Int, processIdentifier: pid_t? = nil) -> String {
        guard let file = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else { return "" }
        defer { try? file.close() }
        do {
            try file.seek(toOffset: UInt64(offset))
            let text = String(decoding: try file.readToEnd() ?? Data(), as: UTF8.self)
            guard let processIdentifier else { return text }
            return text.split(separator: "\n").filter { $0.contains("[\(processIdentifier):") }.joined(separator: "\n")
        } catch { return "" }
    }
    static func captureIdentifier(_ messages: String) -> String? {
        let starts = messages.split(separator: "\n").filter { $0.contains("capture.start id=") }
        guard starts.count == 1, let marker = starts[0].range(of: "capture.start id="),
              let value = starts[0][marker.upperBound...].split(separator: " ").first,
              UUID(uuidString: String(value)) != nil else { return nil }
        return String(value)
    }
    static func waitForLog(_ path: String, after offset: Int, containing marker: String, timeout: TimeInterval,
                           processIdentifier: pid_t? = nil, minimumCount: Int = 1) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if logSlice(path, after: offset, processIdentifier: processIdentifier).split(separator: "\n")
                .filter({ $0.contains(marker) }).count >= minimumCount { return true }
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
    static func setToggle(_ app: NSRunningApplication, label: String, value: Int, report: inout [String: Any]) throws {
        guard let toggle = find(app, label: label, roles: [kAXCheckBoxRole, "AXSwitch"]), enabled(toggle.element) else { throw ProofError.settingControl }
        var actions = report["toggleActions"] as? [[String: Any]] ?? []
        defer { report["toggleActions"] = actions }
        actions.append(toggle.evidence.merging(["requestedValue": value]) { _, new in new })
        guard revealControl(toggle.element, in: app, actions: &actions) else { throw ProofError.settingControl }
        if toggleValue(toggle.element) != value { try press(toggle.element) }
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if let current = find(app, label: label, roles: [kAXCheckBoxRole, "AXSwitch"]), enabled(current.element), toggleValue(current.element) == value {
                actions.append(current.evidence.merging(["verifiedValue": value]) { _, new in new })
                return
            }
            wait(0.1)
        }
        throw ProofError.settingControl
    }
    struct AXControlMatch {
        let element: AXUIElement
        let evidence: [String: Any]
    }
    static func uiLabel(_ value: String) -> String {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.hasSuffix("…") { result.removeLast() }
        else if result.hasSuffix("...") { result.removeLast(3) }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func hasLabel(_ element: AXUIElement, label: String) -> Bool {
        var attributes = [kAXTitleAttribute, kAXDescriptionAttribute, kAXLabelValueAttribute]
        if RuntimeAX.stringAttribute(kAXRoleAttribute, from: element) == kAXStaticTextRole { attributes.append(kAXValueAttribute) }
        return attributes.compactMap { RuntimeAX.stringAttribute($0, from: element) }.contains { uiLabel($0) == uiLabel(label) }
    }
    static func axElements(_ element: AXUIElement, attribute: String) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success, let value else { return [] }
        if CFGetTypeID(value) == AXUIElementGetTypeID() { return [value as! AXUIElement] }
        return value as? [AXUIElement] ?? []
    }
    static func sameOwnedWindow(_ lhs: AXUIElement, _ rhs: AXUIElement, app: NSRunningApplication) -> Bool {
        var leftPID: pid_t = 0
        var rightPID: pid_t = 0
        return AXUIElementGetPid(lhs, &leftPID) == .success && AXUIElementGetPid(rhs, &rightPID) == .success
            && leftPID == app.processIdentifier && rightPID == leftPID
            && RuntimeAX.window(for: lhs).flatMap { left in RuntimeAX.window(for: rhs).map { CFEqual(left, $0) } } == true
    }
    static func controlMatch(_ element: AXUIElement, label: String, relation: String, labelElement: AXUIElement?) -> AXControlMatch {
        var evidence: [String: Any] = ["label": label, "relation": relation,
            "role": RuntimeAX.stringAttribute(kAXRoleAttribute, from: element) ?? "", "enabled": enabled(element)]
        if let value = toggleValue(element) { evidence["value"] = value }
        if let frame = RuntimeAX.frame(of: element), finiteFrame(frame) { evidence["frame"] = frameReceipt(frame) }
        if let labelElement {
            evidence["labelRole"] = RuntimeAX.stringAttribute(kAXRoleAttribute, from: labelElement) ?? ""
            if let frame = RuntimeAX.frame(of: labelElement), finiteFrame(frame) { evidence["labelFrame"] = frameReceipt(frame) }
        }
        if let parent = axElements(element, attribute: kAXParentAttribute).first {
            evidence["parentRole"] = RuntimeAX.stringAttribute(kAXRoleAttribute, from: parent) ?? ""
            evidence["childRoles"] = axElements(parent, attribute: kAXChildrenAttribute).prefix(8).map { RuntimeAX.stringAttribute(kAXRoleAttribute, from: $0) ?? "" }
            if let frame = RuntimeAX.frame(of: parent), finiteFrame(frame) { evidence["parentFrame"] = frameReceipt(frame) }
        }
        return AXControlMatch(element: element, evidence: evidence)
    }
    static func find(_ application: NSRunningApplication, label: String, roles: Set<String>) -> AXControlMatch? {
        let root = AXUIElementCreateApplication(application.processIdentifier)
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        var visited: [AXUIElement] = []
        var controls: [AXUIElement] = []
        var labels: [AXUIElement] = []
        let deadline = Date().addingTimeInterval(3)
        while !queue.isEmpty, visited.count < 2000, Date() < deadline {
            let (element, depth) = queue.removeFirst()
            guard depth <= 24, !visited.contains(where: { CFEqual($0, element) }) else { continue }
            visited.append(element)
            AXUIElementSetMessagingTimeout(element, 0.15)
            let role = RuntimeAX.stringAttribute(kAXRoleAttribute, from: element) ?? ""
            if roles.contains(role) { controls.append(element) }
            if role == kAXStaticTextRole, hasLabel(element, label: label) { labels.append(element) }
            var children: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
               let children = children as? [AXUIElement] { queue.append(contentsOf: children.map { ($0, depth + 1) }) }
        }
        guard queue.isEmpty else { return nil }
        var matches: [AXControlMatch] = []
        func add(_ match: AXControlMatch) {
            if !matches.contains(where: { CFEqual($0.element, match.element) }) { matches.append(match) }
        }
        for control in controls {
            guard Date() < deadline else { return nil }
            if hasLabel(control, label: label) {
                add(controlMatch(control, label: label, relation: "directLabel", labelElement: nil))
            }
            for attribute in [kAXTitleUIElementAttribute, kAXLabelUIElementsAttribute, kAXLinkedUIElementsAttribute] {
                for linked in axElements(control, attribute: attribute) where sameOwnedWindow(control, linked, app: application) && hasLabel(linked, label: label) {
                    add(controlMatch(control, label: label, relation: attribute, labelElement: linked))
                }
            }
        }
        for labelElement in labels {
            for control in axElements(labelElement, attribute: kAXServesAsTitleForUIElementsAttribute)
                where controls.contains(where: { CFEqual($0, control) }) && sameOwnedWindow(control, labelElement, app: application) {
                add(controlMatch(control, label: label, relation: kAXServesAsTitleForUIElementsAttribute, labelElement: labelElement))
            }
        }
        if matches.count == 1 { return matches[0] }
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
            if [kAXCheckBoxRole, "AXSwitch", kAXButtonRole].contains(role)
                || (role == kAXStaticTextRole && ["Read Lips While Dictating", "Lips Only"].contains(node["staticText"] as? String ?? "")) {
                if let frame = RuntimeAX.frame(of: element), finiteFrame(frame) { node["frame"] = frameReceipt(frame) }
                if let parent = axElements(element, attribute: kAXParentAttribute).first {
                    node["parentRole"] = RuntimeAX.stringAttribute(kAXRoleAttribute, from: parent) ?? ""
                    node["parentChildRoles"] = axElements(parent, attribute: kAXChildrenAttribute).prefix(8).map { RuntimeAX.stringAttribute(kAXRoleAttribute, from: $0) ?? "" }
                    if let frame = RuntimeAX.frame(of: parent), finiteFrame(frame) { node["parentFrame"] = frameReceipt(frame) }
                }
                var relations: [String: Any] = [:]
                for attribute in [kAXTitleUIElementAttribute, kAXLabelUIElementsAttribute, kAXLinkedUIElementsAttribute, kAXServesAsTitleForUIElementsAttribute] {
                    let linked = axElements(element, attribute: attribute)
                    if !linked.isEmpty {
                        relations[attribute] = linked.prefix(4).map { item -> [String: Any] in
                            var entry = ["role": RuntimeAX.stringAttribute(kAXRoleAttribute, from: item) ?? "",
                                         "title": RuntimeAX.stringAttribute(kAXTitleAttribute, from: item) ?? "",
                                         "description": RuntimeAX.stringAttribute(kAXDescriptionAttribute, from: item) ?? ""]
                            if entry["role"] == kAXStaticTextRole { entry["staticText"] = RuntimeAX.stringAttribute(kAXValueAttribute, from: item) ?? "" }
                            return entry
                        }
                    }
                }
                node["labelRelations"] = relations
            }
            result.append(node)
            var children: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
               let children = children as? [AXUIElement] { queue.append(contentsOf: children.map { ($0, depth + 1) }) }
        }
        return result
    }
    static func openSettings(_ app: NSRunningApplication, appPath: String, report: inout [String: Any]) throws {
        var actions: [[String: Any]] = []
        defer { report["settingsNavigation"] = actions }
        let reopen = Process()
        reopen.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        reopen.arguments = [appPath]
        try reopen.run()
        reopen.waitUntilExit()
        actions.append(activationState(app, phase: "afterOpen").merging(["openExitCode": reopen.terminationStatus]) { _, value in value })
        let deadline = Date().addingTimeInterval(15)
        var activationAttempts = 0
        var pressed = false
        var clicked = false
        while Date() < deadline {
            guard !app.isTerminated else { throw ProofError.appMissing }
            if NSWorkspace.shared.frontmostApplication?.processIdentifier != app.processIdentifier || !app.isActive {
                if activationAttempts < 3 {
                    activationAttempts += 1
                    var attempt = activationState(app, phase: "activationRequest")
                    attempt["attempt"] = activationAttempts
                    attempt["unhideAllowed"] = app.unhide()
                    attempt["activateAllowed"] = app.activate(options: [.activateAllWindows])
                    if let settings = exactSettingsElement(app), let window = RuntimeAX.window(for: settings) {
                        attempt["raiseResult"] = AXUIElementPerformAction(window, kAXRaiseAction as CFString).rawValue
                        if let frame = RuntimeAX.frame(of: window), finiteFrame(frame) { attempt["windowFrame"] = frameReceipt(frame) }
                    } else { attempt["raiseRejected"] = "uniqueSettingsWindowUnavailable" }
                    actions.append(attempt)
                    wait(0.3)
                    actions.append(activationState(app, phase: "afterActivationRequest"))
                    continue
                }
                wait(0.2)
                continue
            }
            actions.append(activationState(app, phase: "activeNavigation"))
            if let control = find(app, label: "Read Lips While Dictating", roles: [kAXCheckBoxRole, "AXSwitch"]) {
                actions.append(control.evidence.merging(["phase": "lipControlAssociation"]) { _, new in new })
                let visible = revealControl(control.element, in: app, actions: &actions)
                actions.append(["lipControlsObserved": true, "lipControlsVisible": visible])
                guard visible else { throw ProofError.settingControl }
                return
            }
            if let settings = exactSettingsElement(app) {
                if !pressed {
                    pressed = true
                    var names: CFArray?
                    let supported = AXUIElementCopyActionNames(settings, &names) == .success
                        && (names as? [String] ?? []).contains(kAXPressAction)
                    let result = supported ? AXUIElementPerformAction(settings, kAXPressAction as CFString) : .actionUnsupported
                    actions.append(["method": "AXPress", "supported": supported, "result": result.rawValue,
                                    "role": RuntimeAX.stringAttribute(kAXRoleAttribute, from: settings) ?? "",
                                    "label": "Settings"])
                    wait(0.5)
                    continue
                }
                let checked = verifiedFrame(settings, in: app)
                if !clicked, let frame = checked.frame, CGPreflightPostEventAccess() {
                    clicked = true
                    let point = CGPoint(x: frame.midX, y: frame.midY)
                    for type in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
                        guard let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else { throw ProofError.settingControl }
                        event.setIntegerValueField(.mouseEventClickState, value: 1)
                        event.post(tap: .cghidEventTap)
                        wait(0.05)
                    }
                    actions.append(["method": "ordinaryPointerClick", "label": "Settings", "frame": frameReceipt(frame)])
                } else if !clicked {
                    actions.append(activationState(app, phase: "settingsClickRejected").merging([
                        "reason": checked.rejection ?? "postEventPermissionUnavailable"
                    ]) { _, value in value })
                }
            }
            wait(0.2)
        }
        throw ProofError.settingControl
    }
    static func activationState(_ app: NSRunningApplication, phase: String) -> [String: Any] {
        let frontmost = NSWorkspace.shared.frontmostApplication
        return ["phase": phase, "expectedPID": app.processIdentifier,
                "expectedBundleID": app.bundleIdentifier.map { $0 as Any } ?? NSNull(),
                "frontmostPID": frontmost.map { $0.processIdentifier as Any } ?? NSNull(),
                "frontmostBundleID": frontmost?.bundleIdentifier.map { $0 as Any } ?? NSNull(),
                "appActive": app.isActive, "activationPolicy": app.activationPolicy.rawValue]
    }
    static func exactSettingsElement(_ app: NSRunningApplication) -> AXUIElement? {
        let root = AXUIElementCreateApplication(app.processIdentifier)
        guard let windows = RuntimeAX.readWindows(in: root) else { return nil }
        var queue = windows.map { ($0, 0) }
        var visited: [AXUIElement] = []
        var matches: [AXUIElement] = []
        let deadline = Date().addingTimeInterval(1)
        while !queue.isEmpty, visited.count < 1000, Date() < deadline {
            let (element, depth) = queue.removeFirst()
            guard depth <= 24, !visited.contains(where: { CFEqual($0, element) }) else { continue }
            visited.append(element)
            AXUIElementSetMessagingTimeout(element, 0.1)
            let role = RuntimeAX.stringAttribute(kAXRoleAttribute, from: element) ?? ""
            let labels = [kAXTitleAttribute, kAXDescriptionAttribute].compactMap { RuntimeAX.stringAttribute($0, from: element) }
            if [kAXButtonRole, kAXRowRole, "AXLink", "AXUnknown"].contains(role), labels.contains("Settings"), enabled(element) {
                matches.append(element)
            }
            var children: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
               let children = children as? [AXUIElement] { queue.append(contentsOf: children.map { ($0, depth + 1) }) }
        }
        return queue.isEmpty && matches.count == 1 ? matches[0] : nil
    }
    static func verifiedFrame(_ element: AXUIElement, in app: NSRunningApplication) -> (frame: CGRect?, rejection: String?) {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, pid == app.processIdentifier else { return (nil, "elementOwnerMismatch") }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid, app.isActive else { return (nil, "targetNotActiveFrontmost") }
        guard let window = RuntimeAX.window(for: element), let windowFrame = RuntimeAX.frame(of: window), finiteFrame(windowFrame) else { return (nil, "ownedWindowFrameUnavailable") }
        guard let frame = RuntimeAX.frame(of: element), finiteFrame(frame) else { return (nil, "elementFrameUnavailable") }
        guard windowFrame.contains(frame) else { return (nil, "elementOutsideOwnedWindow") }
        guard CGDisplayBounds(CGMainDisplayID()).contains(frame) else { return (nil, "elementOffscreen") }
        return (frame, nil)
    }
    static func finiteFrame(_ frame: CGRect) -> Bool {
        frame.width > 0 && frame.height > 0 && [frame.minX, frame.minY, frame.maxX, frame.maxY].allSatisfy(\.isFinite)
    }
    static func frameReceipt(_ frame: CGRect) -> [String: Double] {
        ["x": frame.minX, "y": frame.minY, "width": frame.width, "height": frame.height]
    }
    static func revealControl(_ control: AXUIElement, in app: NSRunningApplication, actions: inout [[String: Any]]) -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + 5
        if verifiedFrame(control, in: app).frame != nil { return true }
        let result = AXUIElementPerformAction(control, "AXScrollToVisible" as CFString)
        actions.append(["method": "AXScrollToVisible", "result": result.rawValue])
        wait(0.2)
        if verifiedFrame(control, in: app).frame != nil { return true }
        var ancestor = control
        for _ in 0..<24 {
            if RuntimeAX.stringAttribute(kAXRoleAttribute, from: ancestor) == kAXScrollAreaRole,
               verifiedFrame(ancestor, in: app).frame != nil, CGPreflightPostEventAccess() {
                func observation() -> (frame: CGRect?, visibleFrame: CGRect?, bar: Double?, receipt: [String: Any]) {
                    let checked = verifiedFrame(control, in: app)
                    var result: [String: Any] = ["controlFrameRejection": checked.rejection ?? "none"]
                    let controlFrame = (checked.frame ?? RuntimeAX.frame(of: control)).flatMap { finiteFrame($0) ? $0 : nil }
                    if let controlFrame { result["controlFrame"] = frameReceipt(controlFrame) }
                    var barValue: Double?
                    if let bar = axElements(ancestor, attribute: kAXVerticalScrollBarAttribute).first,
                       sameOwnedWindow(ancestor, bar, app: app), RuntimeAX.stringAttribute(kAXRoleAttribute, from: bar) == kAXScrollBarRole {
                        var values: [String: Any] = ["enabled": enabled(bar)]
                        for attribute in [kAXValueAttribute, kAXMinValueAttribute, kAXMaxValueAttribute] {
                            var value: CFTypeRef?
                            if AXUIElementCopyAttributeValue(bar, attribute as CFString, &value) == .success,
                               let number = value as? NSNumber, number.doubleValue.isFinite {
                                values[attribute] = number
                                if attribute == kAXValueAttribute { barValue = number.doubleValue }
                            }
                        }
                        result["verticalScrollBar"] = values
                    } else { result["verticalScrollBarUnavailable"] = true }
                    return (controlFrame, checked.frame, barValue, result)
                }
                for attempt in 1...4 {
                    guard ProcessInfo.processInfo.systemUptime < deadline,
                          let frame = verifiedFrame(ancestor, in: app).frame,
                          sameOwnedWindow(ancestor, control, app: app),
                          let controlFrame = RuntimeAX.frame(of: control), finiteFrame(controlFrame) else { return false }
                    let delta: Int32 = controlFrame.midY > frame.midY ? -400 : 400
                    let point = CGPoint(x: frame.midX, y: frame.midY)
                    guard let move = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left),
                          let scroll = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: delta, wheel2: 0, wheel3: 0) else { return false }
                    let before = observation()
                    guard before.frame != nil else { return false }
                    var action: [String: Any] = ["method": "ownedScroll", "attempt": attempt, "frame": frameReceipt(frame),
                        "delta": delta, "before": before.receipt, "createdFlags": scroll.flags.rawValue]
                    let createdLocation = scroll.location
                    if createdLocation.x.isFinite, createdLocation.y.isFinite {
                        action["createdLocation"] = ["x": createdLocation.x, "y": createdLocation.y]
                    }
                    // The wheel carries its own location; an earlier posted move does not set it.
                    scroll.location = point
                    scroll.flags = []
                    move.flags = []
                    action["postedLocation"] = ["x": scroll.location.x, "y": scroll.location.y]
                    action["postedFlags"] = scroll.flags.rawValue
                    action["postedDeltaAxis1"] = scroll.getIntegerValueField(.scrollWheelEventDeltaAxis1)
                    action["postedPointDeltaAxis1"] = scroll.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
                    if let event = NSEvent(cgEvent: scroll) {
                        action["postedScrollingDeltaY"] = event.scrollingDeltaY
                        action["postedDirectionInvertedFromDevice"] = event.isDirectionInvertedFromDevice
                    }
                    move.post(tap: .cghidEventTap)
                    scroll.post(tap: .cghidEventTap)
                    let postedAt = ProcessInfo.processInfo.systemUptime
                    action["postedAtSystemUptime"] = postedAt
                    var last = before
                    var lastChangedAt = postedAt
                    var progress = false
                    var settled = false
                    var changes: [[String: Any]] = []
                    var outcome = "noMovementBeforeDeadline"
                    while ProcessInfo.processInfo.systemUptime < deadline {
                        wait(0.05)
                        guard let viewport = verifiedFrame(ancestor, in: app).frame,
                              sameOwnedWindow(ancestor, control, app: app) else { outcome = "ownedScrollAreaUnavailable"; break }
                        let current = observation()
                        let observedAt = ProcessInfo.processInfo.systemUptime
                        guard current.frame != nil else { outcome = "controlFrameUnavailable"; break }
                        if current.frame != last.frame || current.bar != last.bar {
                            changes.append(current.receipt.merging(["observedAtSystemUptime": observedAt]) { _, value in value })
                            let moved = current.frame != before.frame
                            if moved, !progress { action["progressObservedAtSystemUptime"] = observedAt }
                            progress = progress || moved
                            lastChangedAt = observedAt
                            if progress { outcome = "movementUnsettledAtDeadline" }
                        }
                        last = current
                        // Observe a response and stable position before sending another wheel.
                        if progress, observedAt < deadline, observedAt - lastChangedAt >= 0.2 {
                            settled = true
                            action["settledObservedAtSystemUptime"] = observedAt
                            action["stableSeconds"] = observedAt - lastChangedAt
                            outcome = current.visibleFrame.map { viewport.contains($0) } == true ? "settledVisible" : "settledOutside"
                            break
                        }
                    }
                    action["changes"] = changes
                    action["after"] = last.receipt
                    action["outcome"] = outcome
                    actions.append(action)
                    if outcome == "settledVisible" { return true }
                    guard settled else { return false }
                }
                return false
            }
            var parent: CFTypeRef?
            guard AXUIElementCopyAttributeValue(ancestor, kAXParentAttribute as CFString, &parent) == .success,
                  let parent, CFGetTypeID(parent) == AXUIElementGetTypeID() else { return false }
            ancestor = parent as! AXUIElement
        }
        return false
    }
    @discardableResult static func screenshot(_ url: URL) -> [String: Any] {
        var receipt: [String: Any] = ["file": url.lastPathComponent, "captured": false]
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-m", url.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do {
            try process.run()
            if finished.wait(timeout: .now() + 5) == .timedOut {
                process.terminate()
                if finished.wait(timeout: .now() + 1) == .timedOut { kill(process.processIdentifier, SIGKILL) }
                receipt["error"] = "five-second capture deadline"
            } else {
                receipt["exitCode"] = process.terminationStatus
                receipt["captured"] = process.terminationStatus == 0 && FileManager.default.fileExists(atPath: url.path)
            }
        } catch { receipt["error"] = String(describing: error) }
        return receipt
    }
    enum ProofError: Error {
        case invalidArguments, preflight, appMissing, setup, settingControl, recordingStart, renderedBaseline
        case inferenceStart, notDrained, dictation, captureEvidence, unexpectedInsertion, targetUnreadable, negativeControl, microphone, cancellation, quit
    }
}

private final class OBSClient {
    private let session = URLSession(configuration: .ephemeral)
    private let socket: URLSessionWebSocketTask
    private let password: String
    private var requestCounter = 0
    private var expectedMotionDurationMilliseconds: Double?
    private var firstFrameDurationMilliseconds: Double?
    private var preparedFirstFrameCursorMilliseconds: Double?
    private(set) var mediaEvidence: [String: Any] = ["inputName": "PublicSilentVideo"]
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
    func preparePausedMotion(path: String) async throws {
        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        let assetDuration = try await asset.load(.duration)
        let expectedDuration = CMTimeGetSeconds(assetDuration) * 1000
        guard expectedDuration.isFinite, expectedDuration > 1000 else { throw OBSError.mediaPreparation("invalidMotionAssetDuration") }
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard tracks.count == 1 else { throw OBSError.mediaPreparation("expectedOneMotionVideoTrack") }
        let minFrameDuration = try await tracks[0].load(.minFrameDuration)
        let frameMilliseconds = CMTimeGetSeconds(minFrameDuration) * 1000
        guard frameMilliseconds.isFinite, frameMilliseconds > 0, frameMilliseconds <= 1000 else {
            throw OBSError.mediaPreparation("invalidMotionFrameDuration")
        }
        expectedMotionDurationMilliseconds = expectedDuration
        firstFrameDurationMilliseconds = frameMilliseconds
        preparedFirstFrameCursorMilliseconds = nil
        mediaEvidence["expectedMediaDurationMilliseconds"] = expectedDuration
        mediaEvidence["videoMinFrameDurationMilliseconds"] = frameMilliseconds
        mediaEvidence["mediaDurationToleranceMilliseconds"] = 1
        mediaEvidence["durationSource"] = "localAVURLAsset"
        do {
            let video = try await request("GetVideoSettings", [:])
            mediaEvidence["videoSettings"] = Dictionary(uniqueKeysWithValues:
                ["baseWidth", "baseHeight", "outputWidth", "outputHeight", "fpsNumerator", "fpsDenominator"]
                    .map { ($0, video[$0] ?? NSNull()) })
        } catch { mediaEvidence["videoSettingsUnavailable"] = String(describing: error) }
        let settings: [String: Any] = ["is_local_file": true, "local_file": path, "looping": false,
                                      "restart_on_activate": false, "clear_on_media_end": false]
        mediaEvidence["requestedInputSettings"] = settings
        mediaEvidence["loadRequestedAtSystemUptime"] = ProcessInfo.processInfo.systemUptime
        try await request("SetInputSettings", ["inputName": "PublicSilentVideo", "inputSettings": settings, "overlay": true])
        try await request("SetInputMute", ["inputName": "PublicSilentVideo", "inputMuted": true])
        mediaEvidence["restartBeforeCaptureAtSystemUptime"] = ProcessInfo.processInfo.systemUptime
        try await request("TriggerMediaInputAction", ["inputName": "PublicSilentVideo", "mediaAction": "OBS_WEBSOCKET_MEDIA_INPUT_ACTION_RESTART"])
        try await waitForMedia(phase: "loaded", pausedAtFirstFrame: false)
        mediaEvidence["pauseRequestedAtSystemUptime"] = ProcessInfo.processInfo.systemUptime
        try await request("TriggerMediaInputAction", ["inputName": "PublicSilentVideo", "mediaAction": "OBS_WEBSOCKET_MEDIA_INPUT_ACTION_PAUSE"])
        try await waitForMedia(phase: "paused", pausedAtFirstFrame: false, requirePaused: true)
        mediaEvidence["seekFirstFrameBeforeCaptureAtSystemUptime"] = ProcessInfo.processInfo.systemUptime
        mediaEvidence["requestedMediaCursorMilliseconds"] = 0
        try await request("SetMediaInputCursor", ["inputName": "PublicSilentVideo", "mediaCursor": 0])
        try await waitForMedia(phase: "pausedFirstFrame", pausedAtFirstFrame: true, requirePaused: true)
        let response = try await request("GetInputSettings", ["inputName": "PublicSilentVideo"])
        guard let actual = response["inputSettings"] as? [String: Any],
              actual["local_file"] as? String == path, actual["is_local_file"] as? Bool == true,
              actual["looping"] as? Bool == false, actual["restart_on_activate"] as? Bool == false,
              actual["clear_on_media_end"] as? Bool == false else { throw OBSError.mediaPreparation("inputSettingsMismatch") }
        // Only public fixture settings enter receipts; authentication configuration never does.
        mediaEvidence["inputKind"] = response["inputKind"]
        mediaEvidence["inputSettings"] = actual.filter { settings[$0.key] != nil }
        let mute = try await request("GetInputMute", ["inputName": "PublicSilentVideo"])
        guard mute["inputMuted"] as? Bool == true else { throw OBSError.mediaPreparation("inputNotMuted") }
        mediaEvidence["inputMuted"] = true
        mediaEvidence["preparedAtSystemUptime"] = ProcessInfo.processInfo.systemUptime
    }
    func verifyPausedBeforeShortcut() async throws {
        guard usableStatus(try await mediaStatus(phase: "beforeShortcut"), requirePaused: true, requireFirstFrame: true) else {
            throw OBSError.mediaPreparation("motionNotPausedAtFirstFrameBeforeShortcut")
        }
    }
    func playPreparedMotion() async throws {
        await recordStats(phase: "beforePlay")
        guard usableStatus(try await mediaStatus(phase: "beforePlay"), requirePaused: true, requireFirstFrame: true) else {
            throw OBSError.mediaPreparation("motionChangedBeforePlay")
        }
        mediaEvidence["playRequestedAtSystemUptime"] = ProcessInfo.processInfo.systemUptime
        try await request("TriggerMediaInputAction", ["inputName": "PublicSilentVideo", "mediaAction": "OBS_WEBSOCKET_MEDIA_INPUT_ACTION_PLAY"])
        mediaEvidence["playAcknowledgedAtSystemUptime"] = ProcessInfo.processInfo.systemUptime
    }
    func observePlayingMotion() async throws {
        guard let preparedFirstFrameCursorMilliseconds else { throw OBSError.mediaPreparation("preparedCursorUnavailable") }
        let deadline = ProcessInfo.processInfo.systemUptime + 5
        while ProcessInfo.processInfo.systemUptime < deadline {
            let status = try await mediaStatus(phase: "afterPlay")
            if usableStatus(status, requirePaused: false, requireFirstFrame: false),
               status["mediaState"] as? String == "OBS_MEDIA_STATE_PLAYING",
               let cursor = status["mediaCursor"] as? NSNumber, cursor.doubleValue > preparedFirstFrameCursorMilliseconds {
                mediaEvidence["effectivePlayObservedAtSystemUptime"] = ProcessInfo.processInfo.systemUptime
                mediaEvidence["effectivePlayCursorMilliseconds"] = cursor
                return
            }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        throw OBSError.mediaPreparation("motionNotPlayingAfterPlay")
    }
    func waitForMotionEnd() async throws {
        guard let expectedMotionDurationMilliseconds else { throw OBSError.mediaPreparation("motionDurationUnavailable") }
        let timeout = expectedMotionDurationMilliseconds / 1000 + 5
        let started = ProcessInfo.processInfo.systemUptime
        mediaEvidence["motionEndWaitStartedAtSystemUptime"] = started
        mediaEvidence["motionEndDeadlineSeconds"] = timeout
        while ProcessInfo.processInfo.systemUptime < started + timeout {
            let status = try await mediaStatus(phase: "afterAudioAwaitingEnd")
            // OBS reports null cursor/duration after ENDED; prior readiness binds this input.
            if status["mediaState"] as? String == "OBS_MEDIA_STATE_ENDED" {
                mediaEvidence["motionEndedObservedAtSystemUptime"] = ProcessInfo.processInfo.systemUptime
                await recordStats(phase: "afterSourceEnd")
                return
            }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        throw OBSError.mediaPreparation("motionDidNotReachEnded")
    }
    func recordStats(phase: String) async {
        var sample: [String: Any] = ["phase": phase]
        do {
            let stats = try await request("GetStats", [:])
            for key in ["activeFps", "averageFrameRenderTime", "renderSkippedFrames", "renderTotalFrames",
                        "outputSkippedFrames", "outputTotalFrames", "cpuUsage"] { sample[key] = stats[key] ?? NSNull() }
            sample["available"] = true
        } catch {
            sample["available"] = false
            sample["error"] = String(describing: error)
        }
        sample["receivedAtSystemUptime"] = ProcessInfo.processInfo.systemUptime
        var samples = mediaEvidence["statsSamples"] as? [[String: Any]] ?? []
        samples.append(sample)
        mediaEvidence["statsSamples"] = samples
    }
    private func waitForMedia(phase: String, pausedAtFirstFrame: Bool, requirePaused: Bool = false) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 5
        var stableSince: TimeInterval?
        var stableCursor: Double?
        while ProcessInfo.processInfo.systemUptime < deadline {
            let status = try await mediaStatus(phase: phase)
            if usableStatus(status, requirePaused: requirePaused, requireFirstFrame: pausedAtFirstFrame) {
                if !pausedAtFirstFrame { return }
                let cursor = (status["mediaCursor"] as! NSNumber).doubleValue
                if stableCursor != cursor {
                    stableCursor = cursor
                    stableSince = ProcessInfo.processInfo.systemUptime
                }
                if ProcessInfo.processInfo.systemUptime - stableSince! >= 0.5 {
                    preparedFirstFrameCursorMilliseconds = cursor
                    mediaEvidence["pausedFirstFrameCursorMilliseconds"] = cursor
                    mediaEvidence["pausedFirstFrameStableSeconds"] = ProcessInfo.processInfo.systemUptime - stableSince!
                    return
                }
            } else { stableSince = nil; stableCursor = nil }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        throw OBSError.mediaPreparation("deadline:\(phase)")
    }
    private func usableStatus(_ status: [String: Any], requirePaused: Bool, requireFirstFrame: Bool) -> Bool {
        guard let state = status["mediaState"] as? String,
              (requirePaused ? state == "OBS_MEDIA_STATE_PAUSED" : ["OBS_MEDIA_STATE_PLAYING", "OBS_MEDIA_STATE_PAUSED"].contains(state)),
              let duration = status["mediaDuration"] as? NSNumber, duration.doubleValue > 1000,
              let expectedMotionDurationMilliseconds,
              // OBS returns integer milliseconds; allow only millisecond rounding.
              abs(duration.doubleValue - expectedMotionDurationMilliseconds) <= 1,
              let cursor = status["mediaCursor"] as? NSNumber, cursor.doubleValue >= 0 else { return false }
        guard requireFirstFrame else { return true }
        guard let firstFrameDurationMilliseconds, cursor.doubleValue <= firstFrameDurationMilliseconds else { return false }
        return preparedFirstFrameCursorMilliseconds.map { $0 == cursor.doubleValue } ?? true
    }
    private func mediaStatus(phase: String) async throws -> [String: Any] {
        let response = try await request("GetMediaInputStatus", ["inputName": "PublicSilentVideo"])
        var sample: [String: Any] = ["phase": phase, "receivedAtSystemUptime": ProcessInfo.processInfo.systemUptime]
        for key in ["mediaState", "mediaCursor", "mediaDuration"] { sample[key] = response[key] ?? NSNull() }
        var samples = mediaEvidence["statusSamples"] as? [[String: Any]] ?? []
        samples.append(sample)
        mediaEvidence["statusSamples"] = samples
        return response
    }
    @discardableResult private func request(_ type: String, _ data: [String: Any]) async throws -> [String: Any] {
        requestCounter += 1
        let id = String(requestCounter)
        try await send(["op": 6, "d": ["requestType": type, "requestId": id, "requestData": data]])
        for _ in 0..<20 {
            let message = try await receive()
            guard message["op"] as? Int == 7, let details = message["d"] as? [String: Any], details["requestId"] as? String == id else { continue }
            guard let status = details["requestStatus"] as? [String: Any], status["result"] as? Bool == true else { throw OBSError.requestFailed(type) }
            return details["responseData"] as? [String: Any] ?? [:]
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
    enum OBSError: Error { case configuration, protocolFailure, requestFailed(String), mediaPreparation(String) }
}
