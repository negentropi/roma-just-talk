import AppKit
import ApplicationServices
import AVFoundation
import CoreMedia
import CoreMediaIO
import CoreVideo
import CryptoKit
import Darwin
import Foundation
import IOSurface
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
        var cameraSource: CMIOFixtureSource?
        var ownedApplication: NSRunningApplication?
        var ownedApplicationPID: pid_t?
        var modifierHeld = false
        do {
            let arguments = CommandLine.arguments
            guard arguments.count % 2 == 1 else { throw ProofError.invalidArguments }
            var values: [String: String] = [:]
            for index in stride(from: 1, to: arguments.count, by: 2) { values[arguments[index]] = arguments[index + 1] }
            guard let configPath = values["--config"], let outputPath = values["--output"],
                  let scenario = values["--scenario"], let appLog = values["--app-log"] else { throw ProofError.invalidArguments }
            let priorSetupRun = values["--prior-setup-run"].flatMap(Int.init)
            let cachedInstallProfile = values["--cached-install-profile"]
            if values["--prior-setup-run"] != nil {
                guard scenario == "setup", let priorSetupRun, priorSetupRun > 0 else { throw ProofError.invalidArguments }
            }
            if let cachedInstallProfile {
                guard scenario == "setup", priorSetupRun == nil,
                      cachedInstallProfile == "currentNativeCachedInstall" else { throw ProofError.invalidArguments }
            }
            output = URL(fileURLWithPath: outputPath)
            let configuration = try JSONDecoder().decode(RuntimeHarnessConfiguration.self, from: Data(contentsOf: URL(fileURLWithPath: configPath)))
            if scenario == "positive-association-controls" || scenario == "association-cleanup" {
                let environment = ProcessInfo.processInfo.environment
                guard environment["GITHUB_ACTIONS"] == "true", environment["RUNNER_ENVIRONMENT"] == "github-hosted",
                      getuid() != 0 else { throw ProofError.invalidArguments }
                guard let executable = Bundle.main.executableURL else { throw ProofError.associationControl }
                let identity: [String: Any] = ["pid": getpid(), "bundleID": Bundle.main.bundleIdentifier ?? "",
                    "bundlePath": Bundle.main.bundleURL.path, "executablePath": executable.path,
                    "executableSHA256": sha(try Data(contentsOf: executable)), "scenario": scenario]
                try JSONSerialization.data(withJSONObject: identity, options: [.sortedKeys])
                    .write(to: output!.deletingPathExtension().appendingPathExtension("identity.json"), options: .atomic)
            }
            if scenario == "association-cleanup" {
                let cleanup = RuntimeTargetController.restoreAbandonedTargets(targets: configuration.targets)
                report["cleanup"] = try json(cleanup)
                report["passed"] = cleanup.passed
                try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                    .write(to: output!, options: .atomic)
                exit(cleanup.passed ? 0 : 1)
            }
            if scenario == "positive-association-controls" {
                report["scenario"] = scenario
                try runPositiveAssociationControls(configuration: configuration, report: &report,
                                                   directory: output!.deletingLastPathComponent())
                let controlExitCode: Int32 = report["passed"] as? Bool == true ? 0 : 1
                report["controlExitCode"] = controlExitCode
                let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                try data.write(to: output!, options: .atomic)
                exit(controlExitCode)
            }
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
            let applicationPID = application.processIdentifier
            guard applicationPID > 1 else { throw ProofError.appMissing }
            ownedApplication = application
            ownedApplicationPID = applicationPID
            report["ownedAppProcessIdentifier"] = applicationPID
            if scenario == "setup" {
                let cachedSetup = priorSetupRun != nil || cachedInstallProfile != nil
                report["setupProfile"] = cachedInstallProfile ?? (cachedSetup ? "verifiedCachedModelWithPriorSetup" : "freshPublisherDownload")
                report["freshDownloadAssessed"] = !cachedSetup
                report["actualSetupButtonPressed"] = false
                if let priorSetupRun { report["priorSetupRun"] = priorSetupRun }
                if cachedInstallProfile != nil {
                    report["historicalSetupUsed"] = false
                    report["currentFreshSetupAssessed"] = false
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
                        if let status {
                            report["readyControl"] = toggle.evidence
                            report["readyStatusControl"] = status.evidence
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
                guard let sourceManifest = values["--camera-source"], let video = values["--video"],
                      let audio = values["--audio"] else { throw ProofError.invalidArguments }
                let source = try await CMIOFixtureSource(manifestURL: URL(fileURLWithPath: sourceManifest), fixtureURL: URL(fileURLWithPath: video))
                cameraSource = source
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
                    acceptedFrameURL: output!.deletingLastPathComponent().appendingPathComponent(scenario + "-accepted.png"),
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
                try await source.prepareHeldFirst()
                try source.verifyHeldBeforeShortcut()
                let recorderLogOffset = (try? Data(contentsOf: URL(fileURLWithPath: appLog)).count) ?? startOffset
                let down = try RuntimeShortcutInjector.postLeftShiftDown()
                modifierHeld = true
                report["shortcutDown"] = try json(down)
                guard waitForLog(appLog, after: startOffset, containing: "event=engine.state.recording", timeout: 45) else { throw ProofError.recordingStart }
                guard let captureID = captureIdentifier(logSlice(appLog, after: startOffset)) else { throw ProofError.captureEvidence }
                report["captureID"] = captureID
                source.captureRecordingObserved(id: captureID)
                guard prepared.refreshRenderedBaseline() == nil else { throw ProofError.renderedBaseline }
                let audioURL = URL(fileURLWithPath: audio)
                let file = try AVAudioFile(forReading: audioURL)
                let duration = Double(file.length) / file.processingFormat.sampleRate
                let playing = RuntimeAudioPlayback(fixtureURL: audioURL, device: audioDevice, expectedDurationSeconds: duration)
                playback = playing
                try await source.playPreparedMotion()
                report["audioPlaybackStartedAtSystemUptime"] = try playing.start()
                try await source.observePlayingMotion()
                if scenario == "disable" {
                    wait(0.5)
                    try press(disableControl!)
                } else if scenario == "quit" {
                    wait(0.5)
                    guard application.terminate() else { throw ProofError.quit }
                    let deadline = Date().addingTimeInterval(45)
                    while !processExited(applicationPID), Date() < deadline { wait(0.1) }
                    guard processExited(applicationPID) else { throw ProofError.quit }
                } else {
                    report["audioPlayback"] = try json(playing.waitUntilFinished())
                    try await source.waitForMotionEnd()
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
                let readerCloseBoundary: String
                if scenario == "quit", processExited(applicationPID) {
                    readerCloseBoundary = "ownedAppProcessTerminated"
                } else {
                    let marker = "capture.closed id=\(captureID)"
                    guard waitForLog(appLog, after: startOffset, containing: marker, timeout: 45,
                                     processIdentifier: application.processIdentifier) else { throw ProofError.captureEvidence }
                    readerCloseBoundary = marker
                }
                try source.finishAfterReaderClosed(boundary: readerCloseBoundary, requireCompleteMotion: scenario != "disable" && scenario != "quit")
                var visible: RuntimeVisibleTextResult?
                if negative {
                    if scenario == "quit" {
                        guard processExited(applicationPID) else { throw ProofError.quit }
                        report["negativeCompletionBoundary"] = "ownedAppProcessTerminated"
                        report["terminatedAppPID"] = applicationPID
                    } else {
                        let terminal = "recording.drained id=\(captureID) canceled=true"
                        guard waitForLog(appLog, after: startOffset, containing: terminal, timeout: 45) else { throw ProofError.notDrained }
                        report["negativeCompletionBoundary"] = terminal
                    }
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
                    let observed = prepared.waitForVisibleText(
                        keyUpAtSystemUptime: up.postedAtSystemUptime, timeoutSeconds: 120
                    )
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
            cameraSource?.recordFailure(error)
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
        if let cameraSource {
            // On an earlier failure, restore() normally terminates the owned app before sink teardown.
            if !cameraSource.finished {
                let probe = ownedApplicationPID.map { processExitProbe($0) }
                report["ownedAppExitAfterRestore"] = [
                    "ownedPID": ownedApplicationPID.map { $0 as Any } ?? NSNull(),
                    "processAbsent": probe?.absent ?? false,
                    "killReturnCode": probe.flatMap { $0.returnCode }.map { $0 as Any } ?? NSNull(),
                    "capturedErrno": probe.flatMap { $0.capturedErrno }.map { $0 as Any } ?? NSNull(),
                    "observedCachedPID": ownedApplication.map { $0.processIdentifier as Any } ?? NSNull(),
                    "cachedIsTerminated": ownedApplication.map { $0.isTerminated as Any } ?? NSNull()
                ]
                cameraSource.cleanupAfterFailure(appAbsent: probe?.absent == true)
            }
            report["cameraSource"] = cameraSource.evidence
            if !cameraSource.passed { report["passed"] = false }
        }
        if let output, let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: output, options: .atomic)
        }
        exit(report["passed"] as? Bool == true ? 0 : 1)
    }

    static func json<T: Encodable>(_ value: T) throws -> Any {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
    }

    @MainActor static func runPositiveAssociationControls(
        configuration: RuntimeHarnessConfiguration, report: inout [String: Any], directory: URL
    ) throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["GITHUB_ACTIONS"] == "true", environment["RUNNER_ENVIRONMENT"] == "github-hosted",
              getuid() != 0, let target = configuration.targets.first,
              target.bundleIdentifier == "com.apple.TextEdit" else { throw ProofError.invalidArguments }
        NSApplication.shared.setActivationPolicy(.accessory)
        let words = "ASSOCIATION CONTROL WORDS "
        let fullText = NSMutableString(string: RuntimeTextScenario.existingText.initialText)
        fullText.insert(words, at: RuntimeTextScenario.existingText.cursorUTF16Offset)
        var cases: [[String: Any]] = []
        report["controlWords"] = words
        report["cases"] = cases
        for mutation in ["healthy", "transparent", "covered", "moved"] {
            report["currentControlCase"] = mutation
            let acceptedURL = directory.appendingPathComponent("association-" + mutation + "-accepted.png")
            let prepared = try RuntimeTargetController.prepare(
                target: target, textScenario: .existingText,
                runID: "association-\(mutation)-textedit-existingText-r1-\(UUID().uuidString.prefix(6))",
                acceptedFrameURL: acceptedURL,
                settleSeconds: configuration.targetSettleSeconds, availabilityPolicy: .launchIfNeeded
            )
            var item: [String: Any] = ["case": mutation, "passed": false, "fixtureValid": false]
            var cover: NSPanel?
            var originalPosition: CGPoint?
            var movedWindow: AXUIElement?
            var cleanedUp = false
            defer {
                cover?.orderOut(nil)
                cover?.close()
                if var position = originalPosition, let movedWindow,
                   let value = AXValueCreate(.cgPoint, &position) {
                    _ = AXUIElementSetAttributeValue(movedWindow, kAXPositionAttribute as CFString, value)
                }
                if !cleanedUp {
                    let cleanup = prepared.cleanup()
                    report["failedControlCleanup"] = try? json(cleanup)
                }
            }
            let appElement = AXUIElementCreateApplication(prepared.info.processIdentifier)
            guard let window = RuntimeAX.window(containing: prepared.info.windowTitleToken, in: appElement),
                  let editor = RuntimeAX.editableElement(in: window, identifying: prepared.info.windowTitleToken)
                    ?? RuntimeAX.firstEditableElement(in: window),
                  let windowFrame = RuntimeAX.frame(of: window),
                  let editorFrame = RuntimeAX.observationFrame(for: editor, fallbackWindow: window),
                  prepared.readFullText() == RuntimeTextScenario.existingText.initialText,
                  prepared.refreshRenderedBaseline() == nil else { throw ProofError.associationControl }
            item["target"] = try json(prepared.info)
            item["baselineWindowFrame"] = rectEvidence(windowFrame)
            item["baselineEditableFrame"] = rectEvidence(editorFrame)
            if mutation == "covered" || mutation == "transparent" {
                let display = CGDisplayBounds(CGMainDisplayID())
                let frame = mutation == "transparent"
                    ? NSRect(x: display.minX, y: 0, width: display.width, height: display.height)
                    : NSRect(x: editorFrame.minX - 8, y: display.height - editorFrame.maxY - 8,
                             width: editorFrame.width + 16, height: editorFrame.height + 16)
                let panel = NSPanel(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
                panel.isReleasedWhenClosed = false
                panel.alphaValue = 1
                panel.isOpaque = mutation == "covered"
                panel.hasShadow = false
                panel.backgroundColor = mutation == "transparent" ? .clear
                    : NSColor(calibratedRed: 0.15, green: 0.45, blue: 0.80, alpha: 1)
                panel.level = .floating
                panel.ignoresMouseEvents = true
                panel.orderFrontRegardless()
                cover = panel
                wait(0.25)
                guard panel.isVisible,
                      let stacking = coveredWindowEvidence(panel: panel, targetPID: prepared.info.processIdentifier,
                                                           targetFrame: windowFrame, coveredFrame: editorFrame) else { throw ProofError.associationControl }
                item["cover"] = stacking
                item["panelContent"] = mutation == "transparent" ? "clear" : "opaqueBlue"
            } else if mutation == "moved" {
                originalPosition = windowFrame.origin
                movedWindow = window
                var position = CGPoint(x: windowFrame.minX + 160, y: windowFrame.minY + 120)
                guard let value = AXValueCreate(.cgPoint, &position),
                      AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value) == .success else {
                    throw ProofError.associationControl
                }
                wait(0.25)
                guard let changed = RuntimeAX.frame(of: window),
                      abs(changed.minX - windowFrame.minX) > 20 || abs(changed.minY - windowFrame.minY) > 20 else {
                    throw ProofError.associationControl
                }
                item["movedWindowFrame"] = rectEvidence(changed)
            }
            guard AXUIElementSetAttributeValue(editor, kAXValueAttribute as CFString, fullText as CFString) == .success else {
                throw ProofError.associationControl
            }
            wait(0.15)
            guard let readableBefore = prepared.readFullText(), readableBefore == fullText as String else {
                throw ProofError.associationControl
            }
            item["fixtureValid"] = true
            item["mutationObserved"] = mutation != "healthy"
            item["readableAXBefore"] = readableBefore
            item["fixtureScreenshot"] = screenshot(directory.appendingPathComponent("association-" + mutation + "-fixture.png"))
            let observed = prepared.waitForVisibleText(
                keyUpAtSystemUptime: ProcessInfo.processInfo.systemUptime, timeoutSeconds: 3
            )
            let readableAfter = prepared.readFullText()
            guard readableAfter == readableBefore else { throw ProofError.associationControl }
            item["readableAXAfter"] = readableAfter
            item["observation"] = try json(observed)
            let accepted = observed.keyUpToVisibleMilliseconds != nil
            item["visibleAcceptance"] = accepted
            item["acceptedArtifactExists"] = FileManager.default.fileExists(atPath: acceptedURL.path)
            let frame = ((item["observation"] as? [String: Any])?["renderedText"] as? [String: Any])?["acceptedFrame"] as? [String: Any]
            let reference = frame?["reference"] as? [String: Any]
            let referenceURL = directory.appendingPathComponent(acceptedURL.deletingPathExtension().lastPathComponent + "-reference.png")
            let retained = accepted && observed.text == words && (frame?["pngPath"] as? String) == acceptedURL.path
                && (frame?["pngSHA256"] as? String) == (try? Data(contentsOf: acceptedURL)).map { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() }
                && (frame?["referenceMatched"] as? Bool) == true && (frame?["visibilityDifferingPixels"] as? Int) == 0
                && (reference?["pngPath"] as? String) == referenceURL.path
                && (reference?["pngSHA256"] as? String) == (try? Data(contentsOf: referenceURL)).map { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() }
                && (reference?["rgbaSHA256"] as? String) == (frame?["rgbaSHA256"] as? String)
            let expectedRejection = mutation == "covered" ? "Display pixels did not match the owned window"
                : "Editable target geometry changed"
            let shouldAccept = mutation == "healthy" || mutation == "transparent"
            if !shouldAccept { item["expectedRejection"] = expectedRejection }
            item["passed"] = shouldAccept ? retained
                : (!accepted && frame == nil && !FileManager.default.fileExists(atPath: acceptedURL.path)
                    && (mutation == "covered" ? observed.renderedText?.error?.hasPrefix(expectedRejection) == true
                        : observed.renderedText?.error == expectedRejection))
            if !shouldAccept, accepted {
                item["failure"] = observed.text == words ? "unexpectedVisibleAcceptance" : "unexpectedObservationText"
            }
            cover?.orderOut(nil)
            cover?.close()
            cover = nil
            if var position = originalPosition, let movedWindow,
               let value = AXValueCreate(.cgPoint, &position) {
                guard AXUIElementSetAttributeValue(movedWindow, kAXPositionAttribute as CFString, value) == .success else {
                    throw ProofError.associationControl
                }
                wait(0.15)
                guard let restoredFrame = RuntimeAX.frame(of: movedWindow),
                      abs(restoredFrame.minX - position.x) < 2, abs(restoredFrame.minY - position.y) < 2 else {
                    throw ProofError.associationControl
                }
                item["movedWindowRestored"] = true
            }
            originalPosition = nil
            let cleanup = prepared.cleanup()
            cleanedUp = true
            item["cleanup"] = try json(cleanup)
            item["passed"] = item["passed"] as? Bool == true && cleanup.passed
            cases.append(item)
            report["cases"] = cases
        }
        report["passed"] = cases.count == 4 && cases.allSatisfy { $0["passed"] as? Bool == true }
            && report["failedControlCleanup"] == nil
    }

    static func rectEvidence(_ rect: CGRect) -> [String: Double] {
        ["x": rect.minX, "y": rect.minY, "width": rect.width, "height": rect.height]
    }

    static func coveredWindowEvidence(panel: NSPanel, targetPID: pid_t, targetFrame: CGRect, coveredFrame: CGRect) -> [String: Any]? {
        guard let rows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
              let coverIndex = rows.firstIndex(where: { ($0[kCGWindowNumber as String] as? NSNumber)?.intValue == panel.windowNumber }),
              (rows[coverIndex][kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == getpid(),
              let alpha = rows[coverIndex][kCGWindowAlpha as String] as? Double, alpha == 1,
              let coverBounds = rows[coverIndex][kCGWindowBounds as String] as? [String: Any],
              let actualCoverFrame = CGRect(dictionaryRepresentation: coverBounds as CFDictionary), actualCoverFrame.contains(coveredFrame),
              let targetIndex = rows.firstIndex(where: { row in
                  guard (row[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == targetPID,
                        let bounds = row[kCGWindowBounds as String] as? [String: Any],
                        let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return false }
                  return abs(frame.minX - targetFrame.minX) < 2 && abs(frame.minY - targetFrame.minY) < 2
                      && abs(frame.width - targetFrame.width) < 2 && abs(frame.height - targetFrame.height) < 2
              }), coverIndex < targetIndex else { return nil }
        return ["windowID": panel.windowNumber, "ownerPID": getpid(), "alpha": alpha, "coverIndex": coverIndex,
                "targetIndex": targetIndex, "aboveTarget": true, "frame": rectEvidence(actualCoverFrame)]
    }
    static func runNegativeControls(configuration: RuntimeHarnessConfiguration, report: inout [String: Any], directory: URL) throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["GITHUB_ACTIONS"] == "true", environment["RUNNER_ENVIRONMENT"] == "github-hosted",
              getuid() != 0, let target = configuration.targets.first,
              target.bundleIdentifier == "com.apple.TextEdit" else { throw ProofError.invalidArguments }
        let prepared = try RuntimeTargetController.prepare(
            target: target, textScenario: .existingText,
            runID: "negative-controls-\(UUID().uuidString)",
            acceptedFrameURL: directory.appendingPathComponent("negative-controls-accepted.png"),
            settleSeconds: configuration.targetSettleSeconds, availabilityPolicy: .launchIfNeeded
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
    static func processExitProbe(_ processIdentifier: pid_t) -> (absent: Bool, returnCode: Int32?, capturedErrno: Int32?) {
        guard processIdentifier > 1 else { return (false, nil, nil) }
        let result = kill(processIdentifier, 0)
        let capturedErrno: Int32? = result == -1 ? errno : nil
        return (result == -1 && capturedErrno == ESRCH, result, capturedErrno)
    }
    static func processExited(_ processIdentifier: pid_t) -> Bool {
        processExitProbe(processIdentifier).absent
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
        case inferenceStart, notDrained, dictation, captureEvidence, unexpectedInsertion, targetUnreadable, negativeControl, associationControl, microphone, cancellation, quit
    }
}

// Public CMIO producer follows OBS 33.0.1, commit 65c320b46e1af5c7a555161aea6182cdf7a8c524.
// No live OBS process, websocket, renderer, or additional camera consumer participates.
private let fixtureSHA = "4d18638fa0fbbfc3c75ae06723b5a36cc9114147ea5a337eb1b17fdd2a120aab"
private let cameraUID = "7626645E-4425-469E-9D8B-97E0FA59AC75"
private let frameSeconds = 1.0 / 25.0
private struct ProbeFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
private func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw ProbeFailure(message) }
}
private func hostNow() -> Double { CMClockGetTime(CMClockGetHostTimeClock()).seconds }
private func sha(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
private func noOBSProcess() -> Bool {
    guard NSRunningApplication.runningApplications(withBundleIdentifier: "com.obsproject.obs-studio").isEmpty else { return false }
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    task.arguments = ["-x", "OBS"]
    task.standardOutput = FileHandle.nullDevice; task.standardError = FileHandle.nullDevice
    do { try task.run(); task.waitUntilExit(); return task.terminationStatus == 1 }
    catch { return false }
}

// Only public CMIO property/queue APIs. Stream direction is the HAL convention: output = 0.
private func property<T>(_ object: CMIOObjectID, _ selector: Int, initial: T) throws -> T {
    var address = CMIOObjectPropertyAddress(mSelector: UInt32(selector), mScope: UInt32(kCMIOObjectPropertyScopeGlobal), mElement: UInt32(kCMIOObjectPropertyElementMain))
    var value = initial; var used: UInt32 = 0
    let status = withUnsafeMutablePointer(to: &value) {
        CMIOObjectGetPropertyData(object, &address, 0, nil, UInt32(MemoryLayout<T>.size), &used, $0)
    }
    try require(status == noErr && used == UInt32(MemoryLayout<T>.size), "CMIO property \(selector) failed: \(status)")
    return value
}
private func objectIDs(_ object: CMIOObjectID, _ selector: Int) throws -> [CMIOObjectID] {
    var address = CMIOObjectPropertyAddress(mSelector: UInt32(selector), mScope: UInt32(kCMIOObjectPropertyScopeGlobal), mElement: UInt32(kCMIOObjectPropertyElementMain))
    var bytes: UInt32 = 0; var used: UInt32 = 0
    try require(CMIOObjectGetPropertyDataSize(object, &address, 0, nil, &bytes) == noErr && bytes > 0 && bytes <= 4096
                && bytes % UInt32(MemoryLayout<CMIOObjectID>.size) == 0, "CMIO object inventory unavailable")
    var values = [CMIOObjectID](repeating: 0, count: Int(bytes) / MemoryLayout<CMIOObjectID>.size)
    let status = values.withUnsafeMutableBytes { CMIOObjectGetPropertyData(object, &address, 0, nil, bytes, &used, $0.baseAddress) }
    try require(status == noErr && used == bytes, "CMIO object inventory changed")
    return values
}
private func stringProperty(_ object: CMIOObjectID, _ selector: Int) throws -> String {
    let result: Unmanaged<CFString>? = try property(object, selector, initial: Optional<Unmanaged<CFString>>.none)
    guard let result else { throw ProbeFailure("Missing CMIO string property") }
    return result.takeRetainedValue() as String
}
private struct SinkIdentity {
    let device: CMIODeviceID
    let stream: CMIOStreamID
    let advertised: [String: Any]
    static func discover() throws -> SinkIdentity {
        var matches: [CMIODeviceID] = []
        for device in try objectIDs(CMIOObjectID(kCMIOObjectSystemObject), kCMIOHardwarePropertyDevices) {
            if try stringProperty(device, kCMIODevicePropertyDeviceUID) == cameraUID { matches.append(device) }
        }
        try require(matches.count == 1, "Expected exactly one approved OBS device UID")
        let device = matches[0]
        let deviceName = try stringProperty(device, kCMIOObjectPropertyName)
        try require(deviceName == "OBS Virtual Camera", "CMIO device name differs")
        var streams: [CMIOStreamID] = []
        for stream in try objectIDs(device, kCMIODevicePropertyStreams) {
            let direction: UInt32 = try property(stream, kCMIOStreamPropertyDirection, initial: UInt32.max)
            if direction == 0 { streams.append(stream) }
        }
        try require(streams.count == 1, "Expected exactly one public output/sink stream")
        let stream = streams[0]
        let streamName = try stringProperty(stream, kCMIOObjectPropertyName)
        try require(streamName == "OBS Camera Extension Stream Sink", "CMIO sink name differs")
        let format: Unmanaged<CMFormatDescription>? = try property(stream, kCMIOStreamPropertyFormatDescription, initial: Optional<Unmanaged<CMFormatDescription>>.none)
        guard let format else { throw ProbeFailure("Sink format description unavailable") }
        let description = format.takeRetainedValue()
        let dimensions = CMVideoFormatDescriptionGetDimensions(description)
        return SinkIdentity(device: device, stream: stream, advertised: [
            "deviceUID": cameraUID, "deviceID": device, "streamID": stream,
            "width": dimensions.width, "height": dimensions.height,
            "subtype": CMFormatDescriptionGetMediaSubType(description),
            "boundary": "OBS33.0.1 advertises a fixed format; its own public sink producer sends actual payload descriptions. No alternative format is tried."
        ])
    }
    func requireIdle() throws {
        try require(noOBSProcess(), "OBS must be normally stopped and its PID absent")
        let deadline = hostNow() + 2
        var running: UInt32 = try property(device, kCMIODevicePropertyDeviceIsRunningSomewhere, initial: UInt32.max)
        while running != 0 && hostNow() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
            running = try property(device, kCMIODevicePropertyDeviceIsRunningSomewhere, initial: UInt32.max)
        }
        try require(running == 0, "OBS CMIO device is already running; exclusive producer/reader ownership unavailable")
        try require(noOBSProcess(), "OBS process appeared during idle verification")
    }
}

private struct DecodedFrame {
    let pixels: CVPixelBuffer
    let pts: CMTime
    let validPixelSHA256: String
}
private final class Fixture {
    let frames: [DecodedFrame]
    let duration: Double
    let format: CMVideoFormatDescription
    let timelineIndices: [Int]
    init(url: URL) async throws {
        let asset = AVURLAsset(url: url)
        let video = try await asset.loadTracks(withMediaType: .video)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        try require(video.count == 1 && audio.isEmpty, "Fixture must have exactly one video track and no audio")
        let track = video[0]
        let size = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let minimum = try await track.load(.minFrameDuration)
        let assetDuration = try await asset.load(.duration)
        let seconds = assetDuration.seconds
        try require(size == CGSize(width: 640, height: 480) && transform == .identity
                    && abs(minimum.seconds - frameSeconds) < 0.000001 && abs(seconds - 3.8) < 0.000001, "Pinned fixture geometry/timing differs")
        duration = seconds
        var pool: CVPixelBufferPool?
        let attributes: [String: Any] = [kCVPixelBufferWidthKey as String: 640, kCVPixelBufferHeightKey as String: 480,
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]]
        try require(CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attributes as CFDictionary, &pool) == kCVReturnSuccess, "IOSurface pool creation failed")
        guard let pool else { throw ProbeFailure("Missing IOSurface pool") }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange])
        output.alwaysCopiesSampleData = false
        try require(reader.canAdd(output), "Cannot add video-only decoder")
        reader.add(output)
        try require(reader.startReading(), "Cannot start fixture decoder")
        defer { reader.cancelReading() }
        var decoded: [DecodedFrame] = []
        let decodeDeadline = hostNow() + 20
        while let sample = output.copyNextSampleBuffer() {
            try require(hostNow() < decodeDeadline, "Predecode time bound exceeded")
            try require(decoded.count < 100, "Predecode allocation/frame bound exceeded")
            let pts = CMSampleBufferGetPresentationTimeStamp(sample)
            try require(pts.isNumeric && pts.seconds >= 0 && pts.seconds < seconds
                        && abs(pts.seconds / frameSeconds - (pts.seconds / frameSeconds).rounded()) < 0.000001,
                        "Fixture timestamp is outside its 25 Hz presentation grid")
            try require(decoded.last.map { pts.seconds > $0.pts.seconds } ?? true, "Fixture timestamps are not strictly ordered")
            guard let image = CMSampleBufferGetImageBuffer(sample) else { throw ProbeFailure("Decoder returned no image") }
            var destination: CVPixelBuffer?
            try require(CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &destination) == kCVReturnSuccess, "IOSurface allocation failed")
            guard let destination else { throw ProbeFailure("Missing decoded destination") }
            try require(CVPixelBufferGetIOSurface(destination) != nil, "Decoded frame is not IOSurface-backed")
            let validPixelSHA = try Self.copyNV12(image, destination)
            CVBufferPropagateAttachments(image, destination)
            decoded.append(DecodedFrame(pixels: destination, pts: pts, validPixelSHA256: validPixelSHA))
        }
        // Actual native EOF determines the plan; duration alone does not establish a decoded frame count.
        try require(reader.status == .completed && !decoded.isEmpty, "Fixture predecode incomplete: \(reader.status.rawValue)")
        try require(abs(decoded[0].pts.seconds) < 0.000001
                    && abs(decoded.last!.pts.seconds + frameSeconds - seconds) < 0.000001,
                    "Native fixture first/last PTS does not cover the pinned presentation range")
        // Pinned 4d186 source evidence d72454c6... has slots 0...94 except 25 (1.00s).
        // Only that known cloned-lead interval may be held; any other native decoder omission refuses.
        let actualSlots = Set(decoded.map { Int(($0.pts.seconds / frameSeconds).rounded()) })
        let allSlots = Set(0..<95)
        let requiredSlots = allSlots.subtracting([25])
        try require(actualSlots == requiredSlots || actualSlots == allSlots, "Native decode omitted/added a source presentation slot")
        let clonedLeadHashes = decoded.filter { [24, 25, 26].contains(Int(($0.pts.seconds / frameSeconds).rounded())) }.map(\.validPixelSHA256)
        try require(Set(clonedLeadHashes).count == 1, "Known cloned-lead interval is not byte-identical in native NV12 pixels")
        let slots = Int((seconds / frameSeconds).rounded())
        var indices: [Int] = []; var current = 0
        for slot in 0..<slots {
            while current + 1 < decoded.count && decoded[current + 1].pts.seconds <= Double(slot) * frameSeconds + 0.000001 { current += 1 }
            indices.append(current)
        }
        timelineIndices = indices
        frames = decoded
        var description: CMVideoFormatDescription?
        try require(CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: decoded[0].pixels, formatDescriptionOut: &description) == noErr, "Payload format unavailable")
        guard let description else { throw ProbeFailure("Missing payload format") }
        format = description
    }
    private static func copyNV12(_ source: CVPixelBuffer, _ destination: CVPixelBuffer) throws -> String {
        try require(CVPixelBufferGetPixelFormatType(source) == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
                    && CVPixelBufferGetWidth(source) == 640 && CVPixelBufferGetHeight(source) == 480
                    && CVPixelBufferGetPlaneCount(source) == 2, "Decoder did not deliver expected NV12")
        try require(CVPixelBufferLockBaseAddress(source, .readOnly) == kCVReturnSuccess, "Decode source lock failed")
        defer { CVPixelBufferUnlockBaseAddress(source, .readOnly) }
        try require(CVPixelBufferLockBaseAddress(destination, []) == kCVReturnSuccess, "IOSurface write lock failed")
        defer { CVPixelBufferUnlockBaseAddress(destination, []) }
        var validPixels = Data(capacity: 640 * 480 * 3 / 2)
        for plane in 0..<2 {
            guard let src = CVPixelBufferGetBaseAddressOfPlane(source, plane), let dst = CVPixelBufferGetBaseAddressOfPlane(destination, plane) else { throw ProbeFailure("Missing NV12 plane") }
            for row in 0..<CVPixelBufferGetHeightOfPlane(source, plane) {
                memcpy(dst.advanced(by: row * CVPixelBufferGetBytesPerRowOfPlane(destination, plane)),
                       src.advanced(by: row * CVPixelBufferGetBytesPerRowOfPlane(source, plane)), 640)
                validPixels.append(src.advanced(by: row * CVPixelBufferGetBytesPerRowOfPlane(source, plane)).assumingMemoryBound(to: UInt8.self), count: 640)
            }
        }
        return sha(validPixels)
    }
}

private struct SinkEnqueueObservation: Sendable {
    let enqueueEnteredHostSeconds: Double
    let entryLatenessSeconds: Double
    let deadlineHostSeconds: Double
    let failureObservedHostSeconds: Double
    let queueCountAtEntry: Int32?
    let lastObservedQueueCount: Int32?
    let lastQueueObservationHostSeconds: Double?
    let queueCountAtFailure: Int32?
    let firstNonEmptyObservedHostSeconds: Double?
    let queueObservationCount: Int
    let nonEmptyObservationCount: Int
    let queueWaitElapsedSeconds: Double
    let sleepCount: Int
    let maximumObservedSleepSeconds: Double
    let enqueueStatus: Int32?
    let enqueuedHostSeconds: Double?

    var packet: [String: Any] {
        ["enqueueEnteredHostSeconds": enqueueEnteredHostSeconds, "entryLatenessSeconds": entryLatenessSeconds,
         "deadlineHostSeconds": deadlineHostSeconds, "failureObservedHostSeconds": failureObservedHostSeconds,
         "queueCountAtEntry": queueCountAtEntry.map { $0 as Any } ?? NSNull(),
         "lastObservedQueueCount": lastObservedQueueCount.map { $0 as Any } ?? NSNull(),
         "lastQueueObservationHostSeconds": lastQueueObservationHostSeconds.map { $0 as Any } ?? NSNull(),
         "queueCountAtFailure": queueCountAtFailure.map { $0 as Any } ?? NSNull(),
         "firstNonEmptyObservedHostSeconds": firstNonEmptyObservedHostSeconds.map { $0 as Any } ?? NSNull(),
         "queueObservationCount": queueObservationCount, "nonEmptyObservationCount": nonEmptyObservationCount,
         "queueWaitElapsedSeconds": queueWaitElapsedSeconds, "sleepCount": sleepCount,
         "maximumObservedSleepSeconds": maximumObservedSleepSeconds,
         "enqueueStatus": enqueueStatus.map { $0 as Any } ?? NSNull(),
         "enqueuedHostSeconds": enqueuedHostSeconds.map { $0 as Any } ?? NSNull()]
    }
}
private struct SinkEnqueueFailure: Error, CustomStringConvertible {
    let description: String
    let observations: SinkEnqueueObservation
    let enqueued: Bool
}
private final class SinkQueue {
    let identity: SinkIdentity
    private var queue: CMSimpleQueue?
    private var started = false
    private var callbackRegistered = false
    private var queueAtAcquisition: [String: Int] = [:]
    private(set) var enqueueFailures = 0
    private(set) var backpressureTimeouts = 0
    init(_ identity: SinkIdentity) { self.identity = identity }
    func start() throws {
        var copied: Unmanaged<CMSimpleQueue>?
        // Empty callback + NULL refcon matches OBS; there is no callback context to outlive.
        let copiedStatus = CMIOStreamCopyBufferQueue(identity.stream, { _, _, _ in }, nil, &copied)
        if let copied { queue = copied.takeRetainedValue() }
        try require(copiedStatus == noErr, "Cannot copy public sink queue: \(copiedStatus)")
        callbackRegistered = true
        guard let queue else { throw ProbeFailure("Public sink queue missing") }
        let capacity = Int(CMSimpleQueueGetCapacity(queue))
        let count = Int(CMSimpleQueueGetCount(queue))
        queueAtAcquisition = ["capacity": capacity, "count": count]
        try require(capacity > 0 && count == 0, "Sink queue is not usable and empty: capacity=\(capacity), count=\(count)")
        let status = CMIODeviceStartStream(identity.device, identity.stream)
        try require(status == noErr, "Public sink start failed: \(status)")
        started = true
    }
    func enqueue(_ frame: DecodedFrame, format: CMVideoFormatDescription, scheduled: Double) throws -> [String: Any] {
        let entered = hostNow()
        let deadline = scheduled + frameSeconds
        var firstCount: Int32?, lastCount: Int32?
        var firstNonEmpty: Double?, lastObserved: Double?, waitEnded: Double?
        var observationCount = 0, nonEmptyCount = 0, sleepCount = 0
        var maximumSleep = 0.0
        var enqueueStatus: OSStatus?, enqueuedAt: Double?
        do {
            guard let queue, started else { throw ProbeFailure("Producer queue is not started") }
            let initialCount = CMSimpleQueueGetCount(queue)
            firstCount = initialCount
            try require(initialCount <= 1, "Sink queue has more than one outstanding buffer: \(initialCount)")
            while true {
                let count = CMSimpleQueueGetCount(queue)
                let observed = hostNow()
                observationCount += 1; lastCount = count; lastObserved = observed
                if count <= 0 { break }
                nonEmptyCount += 1
                if firstNonEmpty == nil { firstNonEmpty = observed }
                if hostNow() >= deadline { backpressureTimeouts += 1; throw ProbeFailure("Sink backpressure exceeded one frame interval") }
                let beforeSleep = hostNow()
                Thread.sleep(forTimeInterval: 0.001)
                sleepCount += 1
                maximumSleep = max(maximumSleep, hostNow() - beforeSleep)
            }
            waitEnded = hostNow()
            try require(hostNow() < deadline, "Scheduled frame deadline missed; no frame skipping/catch-up is allowed")
            var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 25), presentationTimeStamp: CMTime(seconds: scheduled, preferredTimescale: 1_000_000_000), decodeTimeStamp: .invalid)
            var sample: CMSampleBuffer?
            let created = CMSampleBufferCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: frame.pixels, dataReady: true, makeDataReadyCallback: nil, refcon: nil, formatDescription: format, sampleTiming: &timing, sampleBufferOut: &sample)
            try require(created == noErr, "Cannot construct host-clock sample")
            guard let sample else { throw ProbeFailure("Missing sample buffer") }
            // Successful enqueue transfers this +1 exactly as OBS's native producer does.
            try require(hostNow() < deadline, "Sample creation exceeded frame deadline; no late sample enqueued")
            let token = Unmanaged.passRetained(sample)
            let status = CMSimpleQueueEnqueue(queue, element: token.toOpaque())
            enqueueStatus = status
            if status != noErr { token.release(); enqueueFailures += 1; throw ProbeFailure("Sink enqueue failed: \(status)") }
            let enqueued = hostNow()
            enqueuedAt = enqueued
            let countAfter = CMSimpleQueueGetCount(queue)
            try require(countAfter <= 1, "Sink queue exceeded one outstanding buffer after enqueue: \(countAfter)")
            return ["queueCountBefore": initialCount, "queueCountAfter": countAfter, "enqueueStatus": status,
                    "enqueuedHostSeconds": enqueued, "latenessSeconds": enqueued - scheduled]
        } catch {
            let failedAt = hostNow()
            // Samples at separate reads are evidence of observations, not continuous queue occupancy.
            let observations = SinkEnqueueObservation(
                enqueueEnteredHostSeconds: entered, entryLatenessSeconds: entered - scheduled,
                deadlineHostSeconds: deadline, failureObservedHostSeconds: failedAt,
                queueCountAtEntry: firstCount, lastObservedQueueCount: lastCount,
                lastQueueObservationHostSeconds: lastObserved,
                queueCountAtFailure: queue.map { CMSimpleQueueGetCount($0) },
                firstNonEmptyObservedHostSeconds: firstNonEmpty,
                queueObservationCount: observationCount, nonEmptyObservationCount: nonEmptyCount,
                queueWaitElapsedSeconds: (waitEnded ?? failedAt) - entered,
                sleepCount: sleepCount, maximumObservedSleepSeconds: maximumSleep,
                enqueueStatus: enqueueStatus, enqueuedHostSeconds: enqueuedAt)
            throw SinkEnqueueFailure(description: String(describing: error), observations: observations, enqueued: enqueuedAt != nil)
        }
    }
    func cleanup() -> [String: Any] {
        let acquired = queue != nil
        let deadline = hostNow() + 2
        while let queue, CMSimpleQueueGetCount(queue) > 0 && hostNow() < deadline { Thread.sleep(forTimeInterval: 0.001) }
        let remaining = queue.map { Int(CMSimpleQueueGetCount($0)) } ?? 0
        var stopStatus: OSStatus = noErr
        var stopRequested: Double?, stopCompleted: Double?
        if started {
            stopRequested = hostNow()
            stopStatus = CMIODeviceStopStream(identity.device, identity.stream)
            stopCompleted = hostNow()
            if stopStatus == noErr { started = false }
        }
        var unregister: OSStatus = noErr
        if callbackRegistered {
            var extra: Unmanaged<CMSimpleQueue>?
            unregister = CMIOStreamCopyBufferQueue(identity.stream, nil, nil, &extra)
            if let extra { _ = extra.takeRetainedValue() }
            if unregister == noErr { callbackRegistered = false }
        }
        // Never manually release queued payloads. A nonempty queue remains an explicit failure.
        queue = nil
        return ["stopped": !started && stopStatus == noErr, "stopStatus": stopStatus,
                "stopRequestedHostSeconds": stopRequested.map { $0 as Any } ?? NSNull(),
                "stopCompletedHostSeconds": stopCompleted.map { $0 as Any } ?? NSNull(),
                "callbackUnregistered": !callbackRegistered, "unregisterStatus": unregister, "queueReleased": true, "queueWasAcquired": acquired,
                "queueAtAcquisition": queueAtAcquisition,
                "remainingQueueTokens": remaining, "enqueueFailures": enqueueFailures, "backpressureTimeouts": backpressureTimeouts,
                "callbackBoundary": "Empty C callback, NULL refcon; no callback context or sample dereference"]
    }
}

private final class Feeder: @unchecked Sendable {
    let sink: SinkQueue
    let fixture: Fixture
    private let lock = NSLock()
    private let done = DispatchGroup()
    private let first = DispatchSemaphore(value: 0)
    private var stopRequested = false
    private var playBase: Double?
    private var epoch = 0.0
    private var failure: String?
    private var events: [[String: Any]] = []
    init(sink: SinkQueue, fixture: Fixture) { self.sink = sink; self.fixture = fixture }
    func start() throws {
        try sink.start()
        epoch = hostNow() + 0.04
        done.enter()
        DispatchQueue.global(qos: .userInteractive).async { self.run(); self.done.leave() }
        try require(first.wait(timeout: .now() + 2) == .success, "Producer first frame did not enqueue")
        try check()
    }
    func schedulePlay(after seconds: Double) -> Double {
        lock.lock(); defer { lock.unlock() }
        let requested = hostNow() + seconds
        let time = epoch + ceil((requested - epoch) / frameSeconds) * frameSeconds
        playBase = time
        return time
    }
    func check() throws {
        lock.lock(); let error = failure; lock.unlock()
        if let error { throw ProbeFailure(error) }
    }
    private func run() {
        var tick = 0
        do {
            while true {
                lock.lock(); let stop = stopRequested; let play = playBase; lock.unlock()
                if stop { break }
                try require(tick < 4500, "Owned per-case producer exceeded 180 seconds")
                let scheduled = epoch + Double(tick) * frameSeconds
                while hostNow() < scheduled { Thread.sleep(forTimeInterval: max(0, min(0.002, scheduled - hostNow()))) }
                lock.lock(); let stopped = stopRequested; lock.unlock()
                if stopped { break }
                let motion = play.map { scheduled >= $0 - 0.000001 } ?? false
                let offset = motion ? Int(((scheduled - play!) / frameSeconds).rounded()) : 0
                let inFixture = motion && offset < fixture.timelineIndices.count
                let index = !motion ? 0 : (inFixture ? fixture.timelineIndices[offset] : fixture.frames.count - 1)
                let firstPresentation = inFixture && abs(fixture.frames[index].pts.seconds - Double(offset) * frameSeconds) < 0.000001
                let phase = !motion ? "heldFirst" : (!inFixture ? "heldLast" : (firstPresentation ? "motion" : "sourceGapHold"))
                var event: [String: Any] = ["ordinal": tick, "phase": phase, "index": index,
                    "sourcePTS": fixture.frames[index].pts.seconds, "scheduledHostSeconds": scheduled, "planned": true]
                do {
                    event.merge(try sink.enqueue(fixture.frames[index], format: fixture.format, scheduled: scheduled)) { _, right in right }
                    event["enqueued"] = true
                } catch {
                    if let failure = error as? SinkEnqueueFailure {
                        event.merge(failure.observations.packet) { _, right in right }
                        event["enqueued"] = failure.enqueued
                    } else { event["enqueued"] = false }
                    event["failure"] = String(describing: error)
                    lock.lock(); events.append(event); lock.unlock()
                    throw error
                }
                lock.lock(); events.append(event); lock.unlock()
                if tick == 0 { first.signal() }
                try require((event["latenessSeconds"] as? Double ?? .infinity) < frameSeconds, "Enqueue completed after frame deadline; actual delivery retained in events")
                tick += 1
            }
        } catch {
            lock.lock(); failure = String(describing: error); lock.unlock(); first.signal()
        }
    }
    func eventsSnapshot() -> [[String: Any]] {
        lock.lock(); defer { lock.unlock() }; return events
    }
    func failureSnapshot() -> ([[String: Any]], String?) {
        lock.lock(); defer { lock.unlock() }; return (events, failure)
    }
    func stop() -> (Bool, [[String: Any]], String?) {
        lock.lock(); stopRequested = true; lock.unlock()
        let stopped = done.wait(timeout: .now() + 2) == .success
        lock.lock(); defer { lock.unlock() }
        return (stopped, events, failure)
    }
}

private struct CMIOInputManifest: Decodable {
    let protocolVersion: Int
    let sourceKind: String
    let fixtureSHA256: String
    let cameraDeviceUID: String
    let obsPID: pid_t
    let obsOutputInactiveObserved: Bool
    let obsProcessExitObserved: Bool
}

@MainActor private final class CMIOFixtureSource {
    private let identity: SinkIdentity
    private let fixture: Fixture
    private let sink: SinkQueue
    private let feeder: Feeder
    private var prepared = false
    private var captureObserved: Double?
    private var play: Double?
    private(set) var finished = false
    private(set) var evidence: [String: Any]
    var passed: Bool { ["completed", "partialCaptureStopped"].contains(evidence["status"] as? String ?? "") }

    init(manifestURL: URL, fixtureURL: URL) async throws {
        let environment = ProcessInfo.processInfo.environment
        try require(environment["GITHUB_ACTIONS"] == "true" && environment["RUNNER_ENVIRONMENT"] == "github-hosted"
                    && environment["RUNNER_OS"] == "macOS" && getuid() != 0, "CMIO public fixture requires disposable hosted Mac")
        let console = try FileManager.default.attributesOfItem(atPath: "/dev/console")[.ownerAccountID] as? NSNumber
        try require(console?.uint32Value == getuid(), "CMIO source helper must own the console")
        let manifestData = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(CMIOInputManifest.self, from: manifestData)
        let manifestObject = try JSONSerialization.jsonObject(with: manifestData) as? [String: Any]
        let keys: Set<String> = ["protocolVersion", "sourceKind", "fixtureSHA256", "cameraDeviceUID", "obsPID", "obsOutputInactiveObserved", "obsProcessExitObserved"]
        try require(Set(manifestObject?.keys.map { $0 } ?? []) == keys && manifest.protocolVersion == 1
                    && manifest.sourceKind == "publicCMIOSinkFixture" && manifest.fixtureSHA256 == fixtureSHA
                    && manifest.cameraDeviceUID == cameraUID && manifest.obsPID > 1 && manifest.obsPID != getpid()
                    && manifest.obsOutputInactiveObserved && manifest.obsProcessExitObserved, "CMIO source manifest differs from the pinned public boundary")
        let priorPIDResult = kill(manifest.obsPID, 0)
        let priorPIDError = errno
        try require(priorPIDResult == -1 && priorPIDError == ESRCH && noOBSProcess(), "OBS must have normally exited before CMIO source acquisition")
        let attributes = try FileManager.default.attributesOfItem(atPath: fixtureURL.path)
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        let owner = attributes[.ownerAccountID] as? NSNumber
        try require(fixtureURL.path.hasPrefix("/") && attributes[.type] as? FileAttributeType == .typeRegular
                    && owner?.uint32Value == getuid() && size > 0 && size < 4_000_000, "CMIO fixture must be the small owned public video")
        let actualSHA = sha(try Data(contentsOf: fixtureURL))
        try require(actualSHA == fixtureSHA, "CMIO fixture SHA differs; no substitution accepted")
        let identity = try SinkIdentity.discover()
        try identity.requireIdle()
        let fixture = try await Fixture(url: fixtureURL)
        self.identity = identity; self.fixture = fixture
        let sink = SinkQueue(identity)
        self.sink = sink; feeder = Feeder(sink: sink, fixture: fixture)
        let heldSlots: [Int] = fixture.timelineIndices.enumerated().compactMap { slot, index in
            abs(fixture.frames[index].pts.seconds - Double(slot) * frameSeconds) > 0.000001 ? slot : nil
        }
        evidence = ["protocolVersion": 1, "sourceKind": "publicCMIOSinkFixture", "status": "inconclusive",
                    "helperPID": getpid(), "fixtureSHA256": fixtureSHA, "cameraDeviceUID": cameraUID,
                    "manifest": manifestObject ?? [:], "sink": identity.advertised, "resetBeforeCapture": false,
                    "reference": ["frames": fixture.frames.count, "durationSeconds": fixture.duration,
                                  "width": 640, "height": 480, "fps": 25, "nativeDecoderStatus": "completed",
                                  "sourcePTS": fixture.frames.map { $0.pts.seconds }, "sourceGapHeldSlots": heldSlots,
                                  "sourceNV12SHA256": fixture.frames.map(\.validPixelSHA256)],
                    "plannedMotion": fixture.frames.enumerated().map {
                        ["index": $0.offset, "sourcePTS": $0.element.pts.seconds, "relativeToPlaySeconds": $0.element.pts.seconds] as [String: Any]
                    },
                    "boundary": "Pinned public actor through public CMIO sink; actual app is the sole camera consumer. Enqueue evidence is not a physical-webcam or accuracy claim."]
    }

    func prepareHeldFirst() async throws {
        try identity.requireIdle()
        evidence["resetBeforeCapture"] = true
        try feeder.start()
        let first = feeder.eventsSnapshot().first?["enqueuedHostSeconds"] as? Double
        guard let first else { throw ProbeFailure("Held-first enqueue evidence unavailable") }
        evidence["producerFirstFrameEnqueuedHostSeconds"] = first
        try await waitUntil(first + 0.5)
        prepared = true
        evidence["preparedHostSeconds"] = hostNow()
    }
    func verifyHeldBeforeShortcut() throws {
        try feeder.check()
        try require(prepared && play == nil && !finished, "CMIO source is not held at its first frame before shortcut")
        evidence["beforeShortcutVerifiedHostSeconds"] = hostNow()
    }
    func captureRecordingObserved(id: String) {
        let now = hostNow()
        captureObserved = now
        evidence["captureID"] = id
        evidence["captureRecordingObservedHostSeconds"] = now
        evidence["heldFirstStartedHostSeconds"] = now
    }
    func playPreparedMotion() async throws {
        guard let captureObserved else { throw ProbeFailure("App recording boundary unavailable") }
        try require(prepared && play == nil && !finished, "CMIO source cannot begin motion in this state")
        try await waitUntil(captureObserved + 0.6)
        let start = feeder.schedulePlay(after: frameSeconds)
        play = start
        evidence["heldFirstEndedHostSeconds"] = start
        evidence["firstHoldSeconds"] = start - captureObserved
        evidence["playStartHostSeconds"] = start
    }
    func observePlayingMotion() async throws {
        guard let play else { throw ProbeFailure("Motion was not scheduled") }
        while hostNow() < play + 1 {
            try feeder.check()
            if let first = feeder.eventsSnapshot().first(where: { $0["phase"] as? String == "motion" && $0["enqueued"] as? Bool == true }) {
                evidence["firstMotionEnqueuedHostSeconds"] = first["enqueuedHostSeconds"]
                return
            }
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        throw ProbeFailure("Actual first motion enqueue was not observed")
    }
    func waitForMotionEnd() async throws {
        guard let play else { throw ProbeFailure("Motion was not scheduled") }
        try await waitUntil(play + fixture.duration)
        try require(completeMotion(feeder.eventsSnapshot()), "Not every original source frame was enqueued at source time")
        evidence["motionEndedHostSeconds"] = hostNow()
    }
    private func waitUntil(_ time: Double) async throws {
        while hostNow() < time {
            try feeder.check()
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        try feeder.check()
    }
    private func completeMotion(_ events: [[String: Any]]) -> Bool {
        let motion = events.filter { $0["phase"] as? String == "motion" }
        return motion.count == fixture.frames.count && motion.enumerated().allSatisfy {
            ($0.element["index"] as? Int) == $0.offset && $0.element["enqueued"] as? Bool == true
        }
    }
    private func recordSnapshot(events: [[String: Any]], failure: String?) {
        evidence["events"] = events
        evidence["sourceSnapshotHostSeconds"] = hostNow()
        evidence["sourceSnapshotBoundary"] = "Locked copy of completed producer events; worker joining is reported separately"
        evidence["lastRecordedPhase"] = events.last?["phase"] ?? NSNull()
        if let failure, evidence["failure"] == nil { evidence["failure"] = failure }
        let motion = events.filter { $0["phase"] as? String == "motion" }
        evidence["plannedMotionFrames"] = fixture.frames.count
        evidence["attemptedMotionFrames"] = motion.count
        evidence["enqueuedMotionFrames"] = motion.filter { $0["enqueued"] as? Bool == true }.count
        evidence["motionEnqueueFailures"] = motion.filter { $0["enqueued"] as? Bool != true }.count
        evidence["unattemptedMotionFrames"] = fixture.frames.count - motion.count
    }
    func recordFailure(_ error: Error) {
        let snapshot = feeder.failureSnapshot()
        if evidence["caseFailure"] == nil {
            evidence["caseFailure"] = String(describing: error)
            evidence["caseFailureObservedHostSeconds"] = hostNow()
            evidence["caseFailurePhase"] = snapshot.0.last?["phase"] ?? NSNull()
            evidence["caseFailureEventCount"] = snapshot.0.count
        }
        recordSnapshot(events: snapshot.0, failure: snapshot.1)
    }
    func finishAfterReaderClosed(boundary: String, requireCompleteMotion: Bool) throws {
        try require(!finished, "CMIO source was already finalized")
        evidence["cameraClosedObserved"] = true
        evidence["cameraClosedVerifiedHostSeconds"] = hostNow()
        evidence["readerCloseBoundary"] = boundary
        evidence["producerStopRequestedHostSeconds"] = hostNow()
        let stopped = feeder.stop()
        let producer: [String: Any]
        if stopped.0 {
            producer = sink.cleanup()
        } else {
            producer = ["stopped": false, "callbackUnregistered": false, "queueReleased": false,
                        "remainingQueueTokens": -1, "enqueueFailures": -1, "backpressureTimeouts": -1]
        }
        finished = true
        var cleanup = producer
        cleanup["workerJoined"] = stopped.0
        evidence["producer"] = cleanup
        recordSnapshot(events: stopped.1, failure: stopped.2)
        do {
            if let failure = stopped.2 { throw ProbeFailure(failure) }
            try require(prepared && captureObserved != nil && play != nil, "CMIO capture lifecycle did not start")
            try require(stopped.0 && producer["stopped"] as? Bool == true && producer["callbackUnregistered"] as? Bool == true
                        && producer["queueReleased"] as? Bool == true && producer["remainingQueueTokens"] as? Int == 0
                        && producer["enqueueFailures"] as? Int == 0 && producer["backpressureTimeouts"] as? Int == 0,
                        "Owned CMIO producer cleanup failed")
            // The app reader is already closed; retain the prototype's post-stop observation window.
            Thread.sleep(forTimeInterval: 0.1)
            try identity.requireIdle()
            evidence["postStopIdleObservedHostSeconds"] = hostNow()
            if requireCompleteMotion { try require(completeMotion(stopped.1), "Full capture omitted a source motion frame") }
            evidence["status"] = requireCompleteMotion ? "completed" : "partialCaptureStopped"
        } catch {
            if evidence["failure"] == nil { evidence["failure"] = String(describing: error) }
            throw error
        }
    }
    func cleanupAfterFailure(appAbsent: Bool) {
        let snapshot = feeder.failureSnapshot()
        recordSnapshot(events: snapshot.0, failure: snapshot.1)
        guard !finished else { return }
        guard appAbsent else {
            evidence["cleanupFailure"] = "Owned app exit was not observed; producer teardown cannot be reported after reader closure"
            evidence["cameraClosedObserved"] = false
            evidence["cleanupDeferredToProcessExit"] = true
            finished = true
            return
        }
        try? finishAfterReaderClosed(boundary: "ownedAppProcessTerminatedAfterFailure", requireCompleteMotion: false)
        evidence["status"] = "inconclusive"
    }
}
