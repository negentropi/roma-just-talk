import AppKit
import Carbon.HIToolbox
import CoreFoundation
import Foundation
import XCTest

final class WritingPowerModeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
        let environment = ProcessInfo.processInfo.environment
        let enabled = environment["RJT_WRITING_POWER_MODE_UI_CHECKS"] == "1"
            || environment["TEST_RUNNER_RJT_WRITING_POWER_MODE_UI_CHECKS"] == "1"
        try XCTSkipUnless(enabled, "Run the Power Mode UI regression only on the dedicated disposable Mac.")
        guard environment["GITHUB_ACTIONS"] == "true"
                || environment["TEST_RUNNER_GITHUB_ACTIONS"] == "true" else {
            throw PowerModeUIFixtureError.disposableRunnerRequired
        }
    }

    @MainActor func testSnippetEditsPreservePowerModeRestoration() throws {
        try withActivePowerMode { app, fixture, sessionID in
            try openSnippets(in: app)
            try required(app.buttons["snippets.new"]).click()
            let trigger = "mode proof \(UUID().uuidString.lowercased())"
            try replaceText(in: required(app.textFields["snippets.editor.trigger"]), with: trigger)
            let content = try required(app.textViews["snippets.editor.content"])
            try replaceText(in: content, with: "Saved during an active Power Mode.\nLiteral second line.")
            try required(app.buttons["snippets.editor.save"]).click()
            XCTAssertTrue(waitUntil { !content.exists }, "The snippet editor did not close after saving.")
            XCTAssertTrue(waitUntil { fixture.containsSnippet(trigger: trigger) }, "The actual snippet save did not persist.")
            try assertActiveBaseline(fixture, sessionID: sessionID, phase: "after snippet save")
            attachScreenshot(app, named: "Snippet saved during active Power Mode")

            let row = try required(identified("snippets.row.\(trigger)", in: app))
            let toggle = try required(identified("snippets.row.toggle", in: row))
            try reveal(toggle, identifier: "snippets.row.toggle", in: app)
            toggle.click()
            XCTAssertTrue(waitUntil { fixture.snippetEnabled(trigger: trigger) == false })
            try assertActiveBaseline(fixture, sessionID: sessionID, phase: "after snippet toggle")
        }
    }

    @MainActor func testTargetChangesPreservePowerModeRestoration() throws {
        try withActivePowerMode { app, fixture, sessionID in
            try required(mainWindow(in: app).buttons["style"]).click()
            let add = try required(app.buttons["writingActions.target.add"])
            try reveal(add, identifier: "writingActions.target.add", in: app)
            add.click()
            try replaceText(in: required(app.textFields["writingActions.target.search"]), with: "German")
            try required(app.buttons["writingActions.target.option.de"]).click()
            XCTAssertTrue(waitUntil { fixture.targetLanguages() == ["en", "de"] }, "The actual target add did not persist.")
            try assertActiveBaseline(fixture, sessionID: sessionID, phase: "after target add")

            let move = try required(app.buttons["writingActions.target.de.moveUp"])
            try reveal(move, identifier: "writingActions.target.de.moveUp", in: app)
            XCTAssertTrue(move.isEnabled)
            move.click()
            XCTAssertTrue(waitUntil { fixture.targetLanguages() == ["de", "en"] }, "The actual target reorder did not persist.")
            try assertActiveBaseline(fixture, sessionID: sessionID, phase: "after target reorder")
            attachScreenshot(app, named: "Target reordered during active Power Mode")
        }
    }

    @MainActor private func withActivePowerMode(
        _ mutation: (XCUIApplication, PowerModeUIPreferences, UUID) throws -> Void
    ) throws {
        let app = XCUIApplication(bundleIdentifier: PowerModeUIPreferences.bundleIdentifier)
        guard app.state == .notRunning,
              NSRunningApplication.runningApplications(withBundleIdentifier: PowerModeUIPreferences.bundleIdentifier).isEmpty else {
            throw PowerModeUIFixtureError.appAlreadyRunning
        }
        let fixture = try PowerModeUIPreferences()
        let cleanup = PowerModeUICleanup(app: app, preferences: fixture)
        addTeardownBlock { [self] in
            await MainActor.run {
                self.restoreOwnedPreferences(cleanup)
            }
        }
        addTeardownBlock { [self] in
            await MainActor.run {
                self.cancelOwnedRecording(cleanup)
            }
        }
        cleanup.didInstall = true
        try fixture.install()
        app.launchArguments = [
            "-hasCompletedOnboarding", "YES",
            "-DidApplyLaunchAtLoginDefault", "YES",
            "-enableAnnouncements", "NO",
            "-PrewarmModelOnWake", "NO",
            "-automaticUpdatesEnabled", "NO",
            "-SUEnableAutomaticChecks", "NO",
            "-SUAutomaticallyUpdate", "NO"
        ]
        app.launch()
        let launched = NSRunningApplication.runningApplications(withBundleIdentifier: PowerModeUIPreferences.bundleIdentifier)
        guard launched.count == 1, let process = launched.first,
              let executable = process.executableURL else { throw PowerModeUIFixtureError.launchedProcessUnidentified }
        cleanup.process = process
        cleanup.executableURL = executable.standardizedFileURL
        guard app.wait(for: .runningForeground, timeout: 20) else {
            attachLaunchState(app, fixture: fixture)
            attachHierarchy(app, named: "App failed to enter foreground")
            throw PowerModeUIFixtureError.appDidNotOpen
        }
        try openSettingsFromStatusMenu(in: app)
        guard mainWindow(in: app).waitForExistence(timeout: 15),
              app.windows.matching(identifier: Self.mainWindowIdentifier).count == 1 else {
            attachLaunchState(app, fixture: fixture)
            attachHierarchy(app, named: "App failed to open")
            throw PowerModeUIFixtureError.appDidNotOpen
        }
        XCTAssertEqual(fixture.lowercase(), false)
        XCTAssertNil(fixture.object(for: PowerModeUIPreferences.sessionKey))
        let statusItems = app.descendants(matching: .statusItem)
        guard statusItems.firstMatch.waitForExistence(timeout: 10), statusItems.count == 1 else {
            attachHierarchy(app, named: "Recorder status item unavailable")
            throw PowerModeUIFixtureError.recorderMenuUnavailable
        }
        statusItems.firstMatch.click()
        try required(app.menuItems["Toggle Recorder"]).click()
        guard waitUntil(timeout: 20, {
            if cleanup.sessionID == nil,
               fixture.object(for: "activeConfigurationId") as? String == fixture.configurationID.uuidString,
               let session = try? fixture.session() {
                cleanup.sessionID = session.id
            }
            return fixture.lowercase() == true
                && fixture.object(for: "activeConfigurationId") as? String == fixture.configurationID.uuidString
                && fixture.object(for: PowerModeUIPreferences.sessionKey) is Data
        }) else {
            attachHierarchy(app, named: "Power Mode recording failed to start")
            throw PowerModeUIFixtureError.recordingDidNotActivateMode
        }
        let sessionID = try fixture.session().id
        cleanup.sessionID = sessionID
        try assertActiveBaseline(fixture, sessionID: sessionID, phase: "before writing feature mutation")
        app.activate()
        try mutation(app, fixture, sessionID)
        cancelWithConfiguredShortcut(in: app)
        XCTAssertTrue(waitUntil(timeout: 10) {
            fixture.object(for: PowerModeUIPreferences.sessionKey) == nil
        }, "Configured Cancel Recording did not end the actual Power Mode recording.")
        XCTAssertTrue(waitUntil { fixture.lowercase() == false }, "Cancel restored active-mode lowercase instead of the original false value.")
        XCTAssertEqual(fixture.lowercase(), false)
        XCTAssertNil(fixture.object(for: "activeConfigurationId"))
        attachObservation(fixture, named: "after recording cancellation")
        attachScreenshot(app, named: "After configured Cancel Recording")
    }

    @MainActor private func assertActiveBaseline(
        _ fixture: PowerModeUIPreferences, sessionID: UUID, phase: String
    ) throws {
        let session = try fixture.session()
        XCTAssertEqual(session.id, sessionID, "The actual session changed during \(phase).")
        XCTAssertEqual(fixture.lowercase(), true, "The fixture mode stopped being active during \(phase).")
        XCTAssertEqual(session.originalState.lowercaseTranscription, false,
                       "A writing feature mutation replaced the original Power Mode snapshot during \(phase).")
        attachObservation(fixture, named: phase)
    }

    @MainActor private func openSnippets(in app: XCUIApplication) throws {
        try required(mainWindow(in: app).buttons["Dictionary"]).click()
        try required(identified("dictionary.section.snippets", in: app)).click()
        try reveal(required(app.buttons["snippets.new"]), identifier: "snippets.new", in: app)
    }

    @MainActor private func openSettingsFromStatusMenu(in app: XCUIApplication) throws {
        let statusItems = app.descendants(matching: .statusItem)
        guard statusItems.firstMatch.waitForExistence(timeout: 10), statusItems.count == 1 else {
            attachHierarchy(app, named: "Settings status menu unavailable")
            throw PowerModeUIFixtureError.recorderMenuUnavailable
        }
        statusItems.firstMatch.click()
        try required(app.menuItems["Settings"]).click()
    }

    @MainActor private func cancelWithConfiguredShortcut(in app: XCUIApplication) {
        XCTContext.runActivity(named: "Cancel recording using the configured F18 shortcut") { _ in
            app.typeKey(.F18, modifierFlags: [])
        }
    }

    @MainActor private func required(_ element: XCUIElement) throws -> XCUIElement {
        try XCTUnwrap(element.waitForExistence(timeout: 10) ? element : nil,
                      "A required real UI control was unavailable.")
    }

    @MainActor private func cancelOwnedRecording(_ cleanup: PowerModeUICleanup) {
        guard cleanup.didInstall, cleanup.isOwnedProcessRunning else { return }
        let fixture = cleanup.preferences
        if fixture.object(for: PowerModeUIPreferences.sessionKey) != nil {
            guard cleanup.ownsStoredSession else {
                attachCleanup(cleanup, phase: "refused foreign session cancellation")
                XCTFail("Cleanup refused a session that was not created by this fixture.")
                return
            }
            attachCleanup(cleanup, phase: "before owned recording cancellation")
            cleanup.app.activate()
            cancelWithConfiguredShortcut(in: cleanup.app)
            XCTAssertTrue(waitUntil(timeout: 10) {
                fixture.object(for: PowerModeUIPreferences.sessionKey) == nil
            }, "Fixture cleanup could not use the configured Cancel Recording shortcut.")
        }
        cleanup.app.terminate()
    }

    @MainActor private func restoreOwnedPreferences(_ cleanup: PowerModeUICleanup) {
        guard cleanup.didInstall else { return }
        if cleanup.isOwnedProcessRunning {
            _ = cleanup.process?.terminate()
            guard waitUntil(timeout: 10, { !cleanup.isOwnedProcessRunning }) else {
                attachCleanup(cleanup, phase: "owned process did not exit")
                XCTFail("Cleanup could not confirm that its exact app process exited; preferences were preserved.")
                return
            }
        }
        let unexpectedProcess = NSRunningApplication.runningApplications(withBundleIdentifier: PowerModeUIPreferences.bundleIdentifier)
            .contains { !$0.isTerminated }
        guard !unexpectedProcess else {
            attachCleanup(cleanup, phase: "refused preference restoration while another app process runs")
            XCTFail("Cleanup refused to restore preferences while an unowned app process was running.")
            return
        }
        let fixture = cleanup.preferences
        let activeConfiguration = fixture.object(for: "activeConfigurationId")
        guard activeConfiguration == nil || activeConfiguration as? String == fixture.configurationID.uuidString else {
            attachCleanup(cleanup, phase: "refused foreign active configuration preference restoration")
            XCTFail("Cleanup preserved an unowned active configuration and its preferences.")
            return
        }
        guard fixture.object(for: PowerModeUIPreferences.sessionKey) == nil || cleanup.ownsStoredSession else {
            attachCleanup(cleanup, phase: "refused foreign session preference restoration")
            XCTFail("Cleanup preserved an unowned persistent session and its preferences.")
            return
        }
        attachCleanup(cleanup, phase: "before owned preference restoration")
        XCTAssertTrue(fixture.restore(), "The fixture's owned preference keys could not be restored and read back.")
    }

    @MainActor private func attachCleanup(_ cleanup: PowerModeUICleanup, phase: String) {
        let fixture = cleanup.preferences
        let details: [String: Any] = [
            "cleanupPhase": phase,
            "ownedProcessID": cleanup.process.map { Int($0.processIdentifier) } as Any? ?? NSNull(),
            "ownedExecutable": cleanup.executableURL?.path as Any? ?? NSNull(),
            "ownedProcessRunning": cleanup.isOwnedProcessRunning,
            "ownedSessionID": cleanup.sessionID?.uuidString as Any? ?? NSNull(),
            "expectedConfigurationID": fixture.configurationID.uuidString,
            "activeConfigurationID": fixture.object(for: "activeConfigurationId") ?? NSNull(),
            "storedSessionID": (try? fixture.session().id.uuidString) as Any? ?? NSNull()
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: details, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            XCTFail("Unable to encode fixture cleanup ownership.")
            return
        }
        let attachment = XCTAttachment(string: text)
        attachment.name = phase
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor private func replaceText(in element: XCUIElement, with text: String) throws {
        element.click()
        element.typeKey("a", modifierFlags: .command)
        element.typeText(text)
    }

    @MainActor private func reveal(_ element: XCUIElement, identifier: String, in app: XCUIApplication) throws {
        let scrollView = app.scrollViews.containing(.any, identifier: identifier).firstMatch
        for _ in 0..<8 where !element.isHittable {
            guard scrollView.exists else { break }
            scrollView.scroll(byDeltaX: 0, deltaY: -180)
        }
        guard element.isHittable else { throw PowerModeUIFixtureError.unreachableControl(identifier) }
    }

    @MainActor private func identified(_ identifier: String, in element: XCUIElement) -> XCUIElement {
        element.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private static let mainWindowIdentifier = "com.negentropi.RomaJustTalk.mainWindow"

    @MainActor private func mainWindow(in app: XCUIApplication) -> XCUIElement {
        app.windows.matching(identifier: Self.mainWindowIdentifier).firstMatch
    }

    @MainActor private func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        } while Date() < deadline
        return condition()
    }

    @MainActor private func attachObservation(_ fixture: PowerModeUIPreferences, named name: String) {
        let observation: [String: Any] = [
            "phase": name,
            "expectedConfigurationID": fixture.configurationID.uuidString,
            "currentLowercase": fixture.lowercase() as Any? ?? NSNull(),
            "activeConfigurationID": fixture.object(for: "activeConfigurationId") ?? NSNull(),
            "configuredCancelShortcut": fixture.object(for: "Shortcut_cancelRecorder")
                .flatMap { $0 as? Data }
                .flatMap { try? JSONSerialization.jsonObject(with: $0) } ?? NSNull(),
            "session": fixture.object(for: PowerModeUIPreferences.sessionKey)
                .flatMap { $0 as? Data }
                .flatMap { try? JSONSerialization.jsonObject(with: $0) } ?? NSNull()
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: observation, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            XCTFail("Unable to encode the observed Power Mode state.")
            return
        }
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor private func attachHierarchy(_ app: XCUIApplication, named name: String) {
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = name
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        attachScreenshot(app, named: name)
    }

    @MainActor private func attachLaunchState(_ app: XCUIApplication, fixture: PowerModeUIPreferences) {
        let dockPreference = fixture.object(for: "IsMenuBarOnly")
        let details: [String: Any] = [
            "applicationState": String(describing: app.state),
            "bundleIdentifier": PowerModeUIPreferences.bundleIdentifier,
            "IsMenuBarOnly": dockPreference ?? NSNull(),
            "IsMenuBarOnlyType": dockPreference.map { String(reflecting: type(of: $0)) } ?? "missing",
            "ShowMenuBarIcon": fixture.object(for: "ShowMenuBarIcon") ?? NSNull(),
            "CurrentTranscriptionModel": fixture.object(for: "CurrentTranscriptionModel") ?? NSNull()
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: details, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            XCTFail("Unable to encode the failed launch state.")
            return
        }
        let attachment = XCTAttachment(string: text)
        attachment.name = "Power Mode fixture launch state"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor private func attachScreenshot(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private enum PowerModeUIFixtureError: Error {
    case disposableRunnerRequired, appAlreadyRunning, appDidNotOpen, recorderMenuUnavailable
    case recordingDidNotActivateMode, existingActiveSession, preferenceSyncFailed, missingSession
    case launchedProcessUnidentified
    case unreachableControl(String)
}

@MainActor
private final class PowerModeUICleanup {
    let app: XCUIApplication
    let preferences: PowerModeUIPreferences
    var didInstall = false
    var process: NSRunningApplication?
    var executableURL: URL?
    var sessionID: UUID?

    init(app: XCUIApplication, preferences: PowerModeUIPreferences) {
        self.app = app
        self.preferences = preferences
    }

    var isOwnedProcessRunning: Bool {
        guard let process, let executableURL,
              let running = NSRunningApplication(processIdentifier: process.processIdentifier) else { return false }
        return !running.isTerminated
            && running.bundleIdentifier == PowerModeUIPreferences.bundleIdentifier
            && running.launchDate == process.launchDate
            && running.bundleURL?.standardizedFileURL == process.bundleURL?.standardizedFileURL
            && running.executableURL?.standardizedFileURL == executableURL
    }

    var ownsStoredSession: Bool {
        guard let sessionID,
              let session = try? preferences.session() else { return false }
        return session.id == sessionID
            && preferences.object(for: "activeConfigurationId") as? String == preferences.configurationID.uuidString
    }
}

private struct PowerModeUIObservedSession: Decodable {
    struct OriginalState: Decodable { let lowercaseTranscription: Bool? }
    let id: UUID
    let originalState: OriginalState
}

private final class PowerModeUIPreferences {
    static let bundleIdentifier = "com.negentropi.RomaJustTalk"
    static let sessionKey = "powerModeActiveSession.v1"
    let configurationID = UUID()
    private let saved: [String: Any]
    private static let keys = [
        "powerModeConfigurationsV2", "activeConfigurationId", sessionKey,
        "LowercaseTranscription", "IsTextFormattingEnabled", "PunctuationCleanupMode", "RemovePunctuation",
        "powerModePersistConfig", "powerModeUIFlag", "CurrentTranscriptionModel", "SelectedLanguage", "TranscriptionPrompt",
        "isAIEnhancementEnabled", "useClipboardContext", "useScreenCaptureContext", "selectedAIProvider", "selectedPromptId",
        "RecorderType", "ShowMenuBarIcon", "IsMenuBarOnly", "isSoundFeedbackEnabled", "VoiceInkSpokenSnippets", "VoiceInkWritingActionPreferences",
        "Shortcut_cancelRecorder", "Shortcut_cancelRecorder_cleared", "CustomRecordingShortcut_cancelRecorder", "KeyboardShortcuts_cancelRecorder"
    ]

    init() throws {
        _ = CFPreferencesAppSynchronize(Self.bundleIdentifier as CFString)
        saved = Dictionary(uniqueKeysWithValues: Self.keys.compactMap { key in
            Self.read(key).map { (key, $0) }
        })
        guard saved[Self.sessionKey] == nil else { throw PowerModeUIFixtureError.existingActiveSession }
    }

    func install() throws {
        let configuration: [[String: Any]] = [[
            "id": configurationID.uuidString,
            "name": "Writing proof \(configurationID.uuidString)",
            "emoji": "T",
            "isAIEnhancementEnabled": false,
            "selectedTranscriptionModelName": "whisper-large-v3-turbo",
            "selectedLanguage": "auto",
            "isTextFormattingEnabled": false,
            "punctuationCleanupMode": "keep",
            "lowercaseTranscription": true,
            "useScreenCapture": false,
            "selectedAIProvider": "Local CLI",
            "autoSendKey": "none",
            "isEnabled": true,
            "isDefault": true
        ]]
        let values: [String: Any] = [
            "powerModeConfigurationsV2": try JSONSerialization.data(withJSONObject: configuration),
            "LowercaseTranscription": false, "IsTextFormattingEnabled": false,
            "PunctuationCleanupMode": "keep", "RemovePunctuation": false,
            "powerModePersistConfig": false, "powerModeUIFlag": true,
            "CurrentTranscriptionModel": "whisper-large-v3-turbo", "SelectedLanguage": "auto",
            "isAIEnhancementEnabled": false, "useClipboardContext": false, "useScreenCaptureContext": false,
            "selectedAIProvider": "Local CLI", "RecorderType": "mini", "ShowMenuBarIcon": true, "IsMenuBarOnly": false,
            "isSoundFeedbackEnabled": false, "Shortcut_cancelRecorder_cleared": false,
            "Shortcut_cancelRecorder": try JSONSerialization.data(withJSONObject: [
                "kind": "key", "keyCode": Int(kVK_F18), "modifierFlagsRawValue": 0
            ]),
            "VoiceInkSpokenSnippets": try JSONSerialization.data(withJSONObject: []),
            "VoiceInkWritingActionPreferences": try JSONSerialization.data(withJSONObject: [
                "targetLanguages": ["en"], "selectedTargetLanguage": "en"
            ])
        ]
        for (key, value) in values { write(value, for: key) }
        for key in ["activeConfigurationId", Self.sessionKey, "CustomRecordingShortcut_cancelRecorder", "KeyboardShortcuts_cancelRecorder"] {
            write(nil, for: key)
        }
        guard CFPreferencesAppSynchronize(Self.bundleIdentifier as CFString) else {
            throw PowerModeUIFixtureError.preferenceSyncFailed
        }
    }

    func restore() -> Bool {
        for key in Self.keys { write(saved[key], for: key) }
        guard CFPreferencesAppSynchronize(Self.bundleIdentifier as CFString) else { return false }
        return Self.keys.allSatisfy { key in
            switch (saved[key], Self.read(key)) {
            case (nil, nil): return true
            case let (expected?, actual?):
                return (expected as? NSObject)?.isEqual(actual) == true
            default: return false
            }
        }
    }

    func object(for key: String) -> Any? {
        _ = CFPreferencesAppSynchronize(Self.bundleIdentifier as CFString)
        return Self.read(key)
    }

    func lowercase() -> Bool? { object(for: "LowercaseTranscription") as? Bool }

    func session() throws -> PowerModeUIObservedSession {
        guard let data = object(for: Self.sessionKey) as? Data else { throw PowerModeUIFixtureError.missingSession }
        return try JSONDecoder().decode(PowerModeUIObservedSession.self, from: data)
    }

    func targetLanguages() -> [String]? {
        guard let data = object(for: "VoiceInkWritingActionPreferences") as? Data,
              let preferences = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return preferences["targetLanguages"] as? [String]
    }

    func containsSnippet(trigger: String) -> Bool { snippetEnabled(trigger: trigger) != nil }

    func snippetEnabled(trigger: String) -> Bool? {
        guard let data = object(for: "VoiceInkSpokenSnippets") as? Data,
              let snippets = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        return snippets.first { $0["trigger"] as? String == trigger }?["enabled"] as? Bool
    }

    private static func read(_ key: String) -> Any? {
        CFPreferencesCopyValue(key as CFString, bundleIdentifier as CFString,
                               kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }

    private func write(_ value: Any?, for key: String) {
        CFPreferencesSetValue(key as CFString, value as CFPropertyList?, Self.bundleIdentifier as CFString,
                              kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }
}
