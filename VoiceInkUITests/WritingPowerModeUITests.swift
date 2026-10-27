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
            try reveal(toggle, in: app)
            toggle.click()
            XCTAssertTrue(waitUntil { fixture.snippetEnabled(trigger: trigger) == false })
            try assertActiveBaseline(fixture, sessionID: sessionID, phase: "after snippet toggle")
        }
    }

    @MainActor func testTargetChangesPreservePowerModeRestoration() throws {
        try withActivePowerMode { app, fixture, sessionID in
            try required(app.staticTexts["style"].firstMatch).click()
            let add = try required(app.buttons["writingActions.target.add"])
            try reveal(add, in: app)
            add.click()
            try replaceText(in: required(app.textFields["writingActions.target.search"]), with: "German")
            try required(app.buttons["writingActions.target.option.de"]).click()
            XCTAssertTrue(waitUntil { fixture.targetLanguages() == ["en", "de"] }, "The actual target add did not persist.")
            try assertActiveBaseline(fixture, sessionID: sessionID, phase: "after target add")

            let move = try required(app.buttons["writingActions.target.de.moveUp"])
            try reveal(move, in: app)
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
        guard app.state == .notRunning else { throw PowerModeUIFixtureError.appAlreadyRunning }
        let fixture = try PowerModeUIPreferences()
        defer {
            if app.state != .notRunning {
                if fixture.object(for: PowerModeUIPreferences.sessionKey) != nil {
                    app.activate()
                    app.typeKey(.escape, modifierFlags: [])
                    app.typeKey(.escape, modifierFlags: [])
                    _ = waitUntil(timeout: 10) { fixture.object(for: PowerModeUIPreferences.sessionKey) == nil }
                }
                app.terminate()
            }
            XCTAssertTrue(fixture.restore(), "The fixture's owned preference keys could not be restored.")
        }
        try fixture.install()
        app.launchArguments = [
            "-hasCompletedOnboarding", "YES",
            "-IsMenuBarOnly", "NO",
            "-DidApplyLaunchAtLoginDefault", "YES",
            "-enableAnnouncements", "NO",
            "-PrewarmModelOnWake", "NO",
            "-automaticUpdatesEnabled", "NO",
            "-SUEnableAutomaticChecks", "NO",
            "-SUAutomaticallyUpdate", "NO"
        ]
        app.launch()
        guard app.wait(for: .runningForeground, timeout: 20),
              app.windows.firstMatch.waitForExistence(timeout: 15) else {
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
            fixture.lowercase() == true
                && fixture.object(for: "activeConfigurationId") as? String == fixture.configurationID.uuidString
                && fixture.object(for: PowerModeUIPreferences.sessionKey) is Data
        }) else {
            attachHierarchy(app, named: "Power Mode recording failed to start")
            throw PowerModeUIFixtureError.recordingDidNotActivateMode
        }
        let sessionID = try fixture.session().id
        try assertActiveBaseline(fixture, sessionID: sessionID, phase: "before writing feature mutation")
        app.activate()
        try mutation(app, fixture, sessionID)
        app.typeKey(.escape, modifierFlags: [])
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 10) {
            fixture.object(for: PowerModeUIPreferences.sessionKey) == nil
        }, "Double Escape did not end the actual Power Mode recording.")
        XCTAssertTrue(waitUntil { fixture.lowercase() == false }, "Cancel restored active-mode lowercase instead of the original false value.")
        XCTAssertEqual(fixture.lowercase(), false)
        XCTAssertNil(fixture.object(for: "activeConfigurationId"))
        attachObservation(fixture, named: "after recording cancellation")
        attachScreenshot(app, named: "Original settings restored after cancellation")
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
        try required(app.staticTexts["Dictionary"].firstMatch).click()
        try required(identified("dictionary.section.snippets", in: app)).click()
        try reveal(required(app.buttons["snippets.new"]), in: app)
    }

    @MainActor private func required(_ element: XCUIElement) throws -> XCUIElement {
        try XCTUnwrap(element.waitForExistence(timeout: 10) ? element : nil,
                      "Required real UI control was unavailable: \(element.identifier)")
    }

    @MainActor private func replaceText(in element: XCUIElement, with text: String) throws {
        try reveal(element, in: XCUIApplication(bundleIdentifier: PowerModeUIPreferences.bundleIdentifier))
        element.click()
        element.typeKey("a", modifierFlags: .command)
        element.typeText(text)
    }

    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication) throws {
        let scrollView = app.scrollViews.containing(.any, identifier: element.identifier).firstMatch
        for _ in 0..<8 where !element.isHittable {
            guard scrollView.exists else { break }
            scrollView.scroll(byDeltaX: 0, deltaY: -180)
        }
        guard element.isHittable else { throw PowerModeUIFixtureError.unreachableControl(element.identifier) }
    }

    @MainActor private func identified(_ identifier: String, in element: XCUIElement) -> XCUIElement {
        element.descendants(matching: .any).matching(identifier: identifier).firstMatch
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
    case unreachableControl(String)
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
        "RecorderType", "ShowMenuBarIcon", "isSoundFeedbackEnabled", "VoiceInkSpokenSnippets", "VoiceInkWritingActionPreferences",
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
            "selectedAIProvider": "Local CLI", "RecorderType": "mini", "ShowMenuBarIcon": true,
            "isSoundFeedbackEnabled": false, "Shortcut_cancelRecorder_cleared": true,
            "VoiceInkSpokenSnippets": try JSONSerialization.data(withJSONObject: []),
            "VoiceInkWritingActionPreferences": try JSONSerialization.data(withJSONObject: [
                "targetLanguages": ["en"], "selectedTargetLanguage": "en"
            ])
        ]
        for (key, value) in values { write(value, for: key) }
        for key in ["activeConfigurationId", Self.sessionKey, "Shortcut_cancelRecorder", "CustomRecordingShortcut_cancelRecorder", "KeyboardShortcuts_cancelRecorder"] {
            write(nil, for: key)
        }
        guard CFPreferencesAppSynchronize(Self.bundleIdentifier as CFString) else {
            throw PowerModeUIFixtureError.preferenceSyncFailed
        }
    }

    func restore() -> Bool {
        for key in Self.keys { write(saved[key], for: key) }
        return CFPreferencesAppSynchronize(Self.bundleIdentifier as CFString)
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
