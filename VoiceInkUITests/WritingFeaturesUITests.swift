import AppKit
import CoreFoundation
import Foundation
import XCTest

final class WritingFeaturesUITests: XCTestCase {
    private static let mainWindowIdentifier = "com.negentropi.RomaJustTalk.mainWindow"

    override func setUpWithError() throws {
        continueAfterFailure = false
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(
            environment["RJT_WRITING_UI_CHECKS"] == "1"
                || environment["TEST_RUNNER_RJT_WRITING_UI_CHECKS"] == "1",
            "Run Writing Features UI checks only on the dedicated disposable Mac."
        )
        guard environment["GITHUB_ACTIONS"] == "true"
                || environment["TEST_RUNNER_GITHUB_ACTIONS"] == "true" else {
            throw WritingFeaturesUIError.disposableRunnerRequired
        }
    }

    @MainActor func testSnippetLibraryPreservesLiteralContentAcrossEditAndRelaunch() throws {
        let (app, ownership) = try prepareApp()
        try launchApp(app, ownership: ownership)
        let trigger = "ui signature \(UUID().uuidString.lowercased())"
        let original = "\nFelix C. Order\nRJT \"Lab\" -- line\n\n"
        let revised = "\nFelix C. Order\nLiteral \"quotes\" -- unchanged\n\nSecond paragraph\n"

        openSnippets(in: app)
        createSnippet(trigger: trigger, content: original, in: app)
        searchSnippets(trigger, in: app)
        let row = snippetRow(trigger, in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        let edit = row.buttons["snippets.row.edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        reveal(edit, identifier: "snippets.row.edit", in: app)
        attachScreenshot(app, named: "Spoken snippets library")

        edit.click()
        let content = app.textViews["snippets.editor.content"]
        assertValue(original, of: content)
        replaceText(in: content, with: revised)
        assertValue(revised, of: content)
        attachScreenshot(app, named: "Literal multiline snippet editor")
        app.buttons["snippets.editor.save"].click()
        XCTAssertTrue(waitUntil { !content.exists })

        let toggle = identified("snippets.row.toggle", in: row)
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        reveal(toggle, identifier: "snippets.row.toggle", in: app)
        toggle.click()
        XCTAssertTrue(waitUntil { self.toggleIsOff(toggle) }, "The saved snippet did not turn off.")

        let delete = row.buttons["snippets.row.delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        reveal(delete, identifier: "snippets.row.delete", in: app)
        delete.click()
        XCTAssertTrue(app.buttons["snippets.delete.cancel"].waitForExistence(timeout: 5))
        attachScreenshot(app, named: "Snippet deletion confirmation")
        app.buttons["snippets.delete.cancel"].click()
        XCTAssertTrue(row.exists, "Cancel deleted the snippet.")

        app.terminate()
        try launchApp(app, ownership: ownership)
        openSnippets(in: app)
        searchSnippets(trigger, in: app)
        let saved = snippetRow(trigger, in: app)
        XCTAssertTrue(saved.waitForExistence(timeout: 10))
        XCTAssertTrue(toggleIsOff(identified("snippets.row.toggle", in: saved)))
        let savedEdit = saved.buttons["snippets.row.edit"]
        XCTAssertTrue(savedEdit.waitForExistence(timeout: 5))
        reveal(savedEdit, identifier: "snippets.row.edit", in: app)
        savedEdit.click()
        assertValue(revised, of: app.textViews["snippets.editor.content"])
        app.buttons["snippets.editor.cancel"].click()
        deleteSnippet(trigger, in: app)
    }

    @MainActor func testCSVImportPreviewsMultilineContentBeforeReplacing() throws {
        let (app, ownership) = try prepareApp()
        try launchApp(app, ownership: ownership)
        let trigger = "ui csv \(UUID().uuidString.lowercased())"
        let original = "Original saved text\nKeep until import"
        let replacement = "Imported \"quoted\" text, with comma\n\nSecond line"
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("rjt-writing-ui-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("snippet-preview.csv")
        let escaped = replacement.replacingOccurrences(of: "\"", with: "\"\"")
        try "trigger,content,enabled\r\n\(trigger),\"\(escaped)\",false\r\n"
            .write(to: file, atomically: true, encoding: .utf8)

        openSnippets(in: app)
        createSnippet(trigger: trigger, content: original, in: app)
        searchSnippets(trigger, in: app)
        app.buttons["snippets.import"].click()
        chooseFile(file, in: app)
        let sheets = mainWindow(in: app).sheets
        XCTAssertTrue(sheets.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(sheets.count, 1, "The import review did not open one owned sheet.")
        let sheet = sheets.element(boundBy: 0)
        let confirm = sheet.buttons["Import"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        XCTAssertFalse(confirm.isEnabled, "Duplicate replacement did not require a policy choice.")
        let previewRow = sheet.disclosureTriangles["snippets.import.row.0"]
        XCTAssertTrue(previewRow.waitForExistence(timeout: 5))
        previewRow.click()
        XCTAssertTrue(waitUntil { String(describing: previewRow.value ?? "") == "1" })
        XCTAssertTrue(waitUntil { self.containsText(original, in: sheet) })
        XCTAssertTrue(waitUntil { self.containsText(replacement, in: sheet) })
        attachScreenshot(app, named: "CSV current and imported multiline preview")

        let replace = sheet.radioButtons["Replace it with the imported row"]
        XCTAssertTrue(replace.waitForExistence(timeout: 5))
        replace.click()
        XCTAssertTrue(confirm.isEnabled)
        confirm.click()
        XCTAssertTrue(waitUntil { !sheet.exists })

        searchSnippets(trigger, in: app)
        let row = snippetRow(trigger, in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(toggleIsOff(identified("snippets.row.toggle", in: row)))
        let edit = row.buttons["snippets.row.edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        reveal(edit, identifier: "snippets.row.edit", in: app)
        edit.click()
        assertValue(replacement, of: app.textViews["snippets.editor.content"])
        app.buttons["snippets.editor.cancel"].click()
        deleteSnippet(trigger, in: app)
    }

    @MainActor func testTranslationTargetsReorderSelectAndPersist() throws {
        let (app, ownership) = try prepareApp()
        try launchApp(app, ownership: ownership)
        openWritingActions(in: app)
        let languages = [("de", "German"), ("fr", "French"), ("it", "Italian"), ("es", "Spanish")]
        let available = languages.filter { !app.buttons["writingActions.target.\($0.0).select"].exists }
        XCTAssertGreaterThanOrEqual(available.count, 2, "The disposable fixture needs two unused target languages.")
        guard available.count >= 2 else { return }
        let first = available[0]
        let second = available[1]
        let previousSelection = app.buttons
            .matching(NSPredicate(format: "identifier BEGINSWITH %@ AND identifier ENDSWITH %@", "writingActions.target.", ".select"))
            .allElementsBoundByIndex.first { button in
                let code = button.identifier
                    .replacingOccurrences(of: "writingActions.target.", with: "")
                    .replacingOccurrences(of: ".select", with: "")
                return targetIsSelected(code, in: app)
            }?.identifier

        addLanguage(first.0, name: first.1, in: app)
        addLanguage(second.0, name: second.1, in: app)
        let selected = app.buttons["writingActions.target.\(second.0).select"]
        selected.click()
        XCTAssertTrue(waitUntil { self.targetIsSelected(second.0, in: app) })
        let moveUp = app.buttons["writingActions.target.\(second.0).moveUp"]
        var remainingMoves = 12
        while moveUp.isEnabled && remainingMoves > 0 {
            moveUp.click()
            remainingMoves -= 1
        }
        XCTAssertFalse(moveUp.isEnabled, "The language did not reach the first position.")
        let firstFrame = identified("writingActions.target.\(first.0)", in: app).frame
        let secondFrame = identified("writingActions.target.\(second.0)", in: app).frame
        XCTAssertLessThan(secondFrame.minY, firstFrame.minY)
        attachScreenshot(app, named: "Writing actions and ordered translation targets")

        app.terminate()
        try launchApp(app, ownership: ownership)
        openWritingActions(in: app)
        XCTAssertTrue(targetIsSelected(second.0, in: app))
        XCTAssertFalse(app.buttons["writingActions.target.\(second.0).moveUp"].isEnabled)
        XCTAssertTrue(app.buttons["writingActions.target.\(first.0).select"].exists)
        attachScreenshot(app, named: "Translation target persisted after relaunch")

        if let previousSelection, app.buttons[previousSelection].exists {
            app.buttons[previousSelection].click()
        }
        app.buttons["writingActions.target.\(first.0).remove"].click()
        app.buttons["writingActions.target.\(second.0).remove"].click()
        XCTAssertTrue(waitUntil { !app.buttons["writingActions.target.\(first.0).select"].exists })
        XCTAssertTrue(waitUntil { !app.buttons["writingActions.target.\(second.0).select"].exists })
    }

    @MainActor func testDictationProfilePreservesCustomSettingsAndPersists() throws {
        let (app, ownership) = try prepareApp()
        let preferences = try WritingFeaturesDictationPreferences()
        addTeardownBlock {
            guard ownership.terminateOwnedApplications() else {
                XCTFail("The owned app did not exit; retained dictation preferences for inspection.")
                return
            }
            XCTAssertTrue(preferences.restore(), "Unable to restore the owned dictation preferences.")
        }
        try preferences.install()
        try launchApp(app, ownership: ownership)
        openModelSettings(in: app)
        assertProfile("Custom", storedValue: "custom", preferences: preferences, in: app)
        assertCustomFormatting(isEnabled: true, preferences: preferences, in: app)
        attachScreenshot(app, named: "Custom dictation cleanup settings")

        let none = profileChoice("None", in: app)
        revealModelSettingsControl(none, towardTop: true, in: app)
        XCTAssertTrue(none.isHittable)
        none.click()
        assertProfile("None", storedValue: "none", preferences: preferences, in: app)
        attachScreenshot(app, named: "None dictation cleanup selected")
        assertCustomFormatting(isEnabled: false, preferences: preferences, in: app)
        attachScreenshot(app, named: "None preserves inactive Custom formatting")

        closeModelSettings(in: app)
        openModelSettings(in: app)
        assertProfile("None", storedValue: "none", preferences: preferences, in: app)
        assertCustomFormatting(isEnabled: false, preferences: preferences, in: app)

        app.terminate()
        try launchApp(app, ownership: ownership)
        openModelSettings(in: app)
        assertProfile("None", storedValue: "none", preferences: preferences, in: app)
        attachScreenshot(app, named: "None dictation cleanup persisted after relaunch")
        assertCustomFormatting(isEnabled: false, preferences: preferences, in: app)

        let custom = profileChoice("Custom", in: app)
        revealModelSettingsControl(custom, towardTop: true, in: app)
        XCTAssertTrue(custom.isHittable)
        custom.click()
        assertProfile("Custom", storedValue: "custom", preferences: preferences, in: app)
        assertCustomFormatting(isEnabled: true, preferences: preferences, in: app)
        attachScreenshot(app, named: "Custom formatting restored without changing saved values")
    }

    @MainActor private func prepareApp() throws -> (XCUIApplication, WritingFeaturesAppOwnership) {
        let ownership = try WritingFeaturesAppOwnership()
        let dockPreference = try WritingFeaturesDockPreference()
        let app = XCUIApplication()
        // XCTest runs teardown blocks in reverse order, including after a fatal UI lookup.
        addTeardownBlock {
            guard ownership.terminateOwnedApplications() else {
                XCTFail("The owned app did not exit; retained the Dock preference for inspection.")
                return
            }
            XCTAssertTrue(dockPreference.restore(), "Unable to restore the Dock preference.")
        }
        addTeardownBlock { @MainActor in
            if ownership.hasOnlyOwnedRunningApplications {
                app.terminate()
            }
        }
        return (app, ownership)
    }

    @MainActor private func launchApp(_ app: XCUIApplication, ownership: WritingFeaturesAppOwnership) throws {
        try ownership.requireNoRunningApplication()
        app.launchArguments = [
            "-hasCompletedOnboarding", "YES",
            "-ShowMenuBarIcon", "YES",
            "-DidApplyLaunchAtLoginDefault", "YES",
            "-enableAnnouncements", "NO",
            "-PrewarmModelOnWake", "NO",
            "-automaticUpdatesEnabled", "NO",
            "-SUEnableAutomaticChecks", "NO",
            "-SUAutomaticallyUpdate", "NO",
            "-selectedAIProvider", "Local CLI"
        ]
        app.launch()
        try ownership.captureLaunchedApplication()
        app.activate()
        guard app.wait(for: .runningForeground, timeout: 20) else {
            attachLaunchFailure(app)
            throw WritingFeaturesUIError.appDidNotBecomeForeground
        }
        // Settings opens the main SwiftUI scene even when launch restores no window.
        let statusItems = app.descendants(matching: .statusItem)
        guard statusItems.firstMatch.waitForExistence(timeout: 10), statusItems.count == 1 else {
            attachLaunchFailure(app)
            throw WritingFeaturesUIError.settingsMenuUnavailable
        }
        statusItems.firstMatch.click()
        let settings = app.menuItems["Settings"]
        guard settings.waitForExistence(timeout: 5) else {
            attachLaunchFailure(app)
            throw WritingFeaturesUIError.settingsMenuUnavailable
        }
        settings.click()
        let mainWindows = app.windows.matching(identifier: Self.mainWindowIdentifier)
        guard mainWindows.firstMatch.waitForExistence(timeout: 15), mainWindows.count == 1,
              mainWindow(in: app).buttons["Dictionary"].waitForExistence(timeout: 10),
              app.state == .runningForeground else {
            attachLaunchFailure(app)
            throw WritingFeaturesUIError.mainWindowDidNotOpen
        }
    }

    @MainActor private func attachLaunchFailure(_ app: XCUIApplication) {
        let value = WritingFeaturesDockPreference.currentValue()
        let details = "Application state: \(app.state)\nIsMenuBarOnly: \(String(describing: value))\nPreference type: \(value.map { String(reflecting: type(of: $0)) } ?? "missing")\n\n\(app.debugDescription)"
        let hierarchy = XCTAttachment(string: details)
        hierarchy.name = "Writing Features failed launch state and hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        attachScreenshot(app, named: "Writing Features failed launch")
    }

    @MainActor private func openSnippets(in app: XCUIApplication) {
        let dictionary = mainWindow(in: app).buttons["Dictionary"]
        XCTAssertTrue(dictionary.waitForExistence(timeout: 10))
        dictionary.click()
        let snippets = identified("dictionary.section.snippets", in: app)
        XCTAssertTrue(snippets.waitForExistence(timeout: 10))
        snippets.click()
        let add = app.buttons["snippets.new"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        reveal(add, identifier: "snippets.new", in: app)
    }

    @MainActor private func openWritingActions(in app: XCUIApplication) {
        let style = mainWindow(in: app).buttons["style"]
        XCTAssertTrue(style.waitForExistence(timeout: 10))
        style.click()
        let add = app.buttons["writingActions.target.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        reveal(add, identifier: "writingActions.target.add", in: app)
    }

    @MainActor private func openModelSettings(in app: XCUIApplication) {
        let models = mainWindow(in: app).buttons["models"]
        XCTAssertTrue(models.waitForExistence(timeout: 10))
        models.click()
        let settings = mainWindow(in: app).buttons["models.settings.open"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        reveal(settings, identifier: "models.settings.open", in: app)
        settings.click()
        XCTAssertTrue(mainWindow(in: app).buttons["models.settings.close"].waitForExistence(timeout: 5))
        XCTAssertTrue(profileChoice("Custom", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(profileChoice("None", in: app).waitForExistence(timeout: 5))
    }

    @MainActor private func closeModelSettings(in app: XCUIApplication) {
        let close = mainWindow(in: app).buttons["models.settings.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.click()
        XCTAssertTrue(waitUntil { !close.exists })
    }

    @MainActor private func profileChoice(_ title: String, in app: XCUIApplication) -> XCUIElement {
        mainWindow(in: app).radioButtons[title]
    }

    @MainActor private func assertProfile(
        _ title: String,
        storedValue: String,
        preferences: WritingFeaturesDictationPreferences,
        in app: XCUIApplication
    ) {
        let choices = mainWindow(in: app).radioButtons.matching(
            NSPredicate(format: "label IN %@", ["Custom", "None"])
        )
        XCTAssertEqual(choices.count, 2, "The cleanup picker did not expose its two native choices.")
        XCTAssertTrue(waitUntil { String(describing: self.profileChoice(title, in: app).value ?? "") == "1" })
        let other = title == "Custom" ? "None" : "Custom"
        XCTAssertEqual(String(describing: profileChoice(other, in: app).value ?? ""), "0")
        XCTAssertTrue(waitUntil { preferences.profile() == storedValue })
        XCTAssertTrue(preferences.customSettingsAreUnchanged(), "Changing the profile changed saved Custom settings.")
    }

    @MainActor private func assertCustomFormatting(
        isEnabled: Bool,
        preferences: WritingFeaturesDictationPreferences,
        in app: XCUIApplication
    ) {
        for identifier in [
            "transcriptionSettings.paragraphBreaks",
            "transcriptionSettings.lowercase",
            "transcriptionSettings.appendTrailingSpace"
        ] {
            let control = identified(identifier, in: mainWindow(in: app))
            revealModelSettingsControl(control, in: app)
            XCTAssertEqual(control.isEnabled, isEnabled, "Unexpected enabled state for \(identifier).")
            XCTAssertEqual(String(describing: control.value ?? ""), "1", "Saved toggle value changed for \(identifier).")
        }
        XCTAssertTrue(preferences.customSettingsAreUnchanged(), "The saved Custom values changed.")
    }

    @MainActor private func revealModelSettingsControl(
        _ control: XCUIElement,
        towardTop: Bool = false,
        in app: XCUIApplication
    ) {
        let scrollers = mainWindow(in: app).scrollViews.containing(.any, identifier: "dictationProfile.picker")
        XCTAssertTrue(scrollers.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(scrollers.count, 1, "The cleanup controls did not belong to one settings scroller.")
        let scroller = scrollers.firstMatch
        for _ in 0..<10 {
            if control.exists, !control.frame.isEmpty, scroller.frame.contains(control.frame) { return }
            scroller.scroll(byDeltaX: 0, deltaY: towardTop ? 180 : -180)
        }
        XCTAssertTrue(control.exists, "The settings control was not exposed.")
        XCTAssertTrue(scroller.frame.contains(control.frame), "The settings control was not fully visible after scrolling.")
    }

    @MainActor private func mainWindow(in app: XCUIApplication) -> XCUIElement {
        app.windows[Self.mainWindowIdentifier]
    }

    @MainActor private func createSnippet(trigger: String, content: String, in app: XCUIApplication) {
        app.buttons["snippets.new"].click()
        let triggerField = app.textFields["snippets.editor.trigger"]
        XCTAssertTrue(triggerField.waitForExistence(timeout: 10))
        replaceText(in: triggerField, with: trigger)
        let editor = app.textViews["snippets.editor.content"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        replaceText(in: editor, with: content)
        assertValue(content, of: editor)
        app.buttons["snippets.editor.save"].click()
        XCTAssertTrue(waitUntil { !editor.exists })
    }

    @MainActor private func deleteSnippet(_ trigger: String, in app: XCUIApplication) {
        searchSnippets(trigger, in: app)
        let row = snippetRow(trigger, in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let delete = row.buttons["snippets.row.delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        reveal(delete, identifier: "snippets.row.delete", in: app)
        delete.click()
        let confirm = app.buttons["snippets.delete.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.click()
        XCTAssertTrue(waitUntil { !row.exists })
    }

    @MainActor private func searchSnippets(_ query: String, in app: XCUIApplication) {
        let search = app.textFields["snippets.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        reveal(search, identifier: "snippets.search", in: app)
        replaceText(in: search, with: query)
    }

    @MainActor private func snippetRow(_ trigger: String, in app: XCUIApplication) -> XCUIElement {
        identified("snippets.row.\(trigger)", in: app)
    }

    @MainActor private func addLanguage(_ code: String, name: String, in app: XCUIApplication) {
        let add = app.buttons["writingActions.target.add"]
        reveal(add, identifier: "writingActions.target.add", in: app)
        add.click()
        let search = app.textFields["writingActions.target.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        replaceText(in: search, with: name)
        let option = app.buttons["writingActions.target.option.\(code)"]
        XCTAssertTrue(option.waitForExistence(timeout: 5))
        option.click()
        XCTAssertTrue(app.buttons["writingActions.target.\(code).select"].waitForExistence(timeout: 5))
    }

    @MainActor private func chooseFile(_ file: URL, in app: XCUIApplication) {
        let panel = app.dialogs["open-panel"]
        XCTAssertTrue(panel.waitForExistence(timeout: 10))
        app.typeKey("g", modifierFlags: [.command, .shift])
        let goTo = panel.sheets["GoToWindow"]
        XCTAssertTrue(goTo.waitForExistence(timeout: 5))
        let path = goTo.textFields["PathTextField"]
        XCTAssertTrue(path.waitForExistence(timeout: 5), "The file panel did not expose its Go to Folder field.")
        replaceText(in: path, with: file.path)
        path.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitUntil { !goTo.exists }, "The file panel did not finish navigating to the CSV.")
        let preview = panel.buttons["OKButton"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntil { preview.isEnabled }, "Preview Import did not enable for the selected CSV.")
        preview.click()
    }

    @MainActor private func replaceText(in element: XCUIElement, with text: String) {
        element.click()
        element.typeKey("a", modifierFlags: .command)
        element.typeText(text)
    }

    @MainActor private func assertValue(_ expected: String, of element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertTrue(waitUntil { element.value as? String == expected }, "Literal editor content changed.", file: file, line: line)
        XCTAssertEqual(element.value as? String, expected, file: file, line: line)
    }

    @MainActor private func toggleIsOff(_ element: XCUIElement) -> Bool {
        guard let value = element.value else { return false }
        return String(describing: value) == "0"
    }

    @MainActor private func targetIsSelected(_ code: String, in app: XCUIApplication) -> Bool {
        let row = identified("writingActions.target.\(code)", in: app)
        return app.buttons["writingActions.target.\(code).select"].isSelected
            || row.staticTexts["Current target"].exists
    }

    @MainActor private func containsText(_ text: String, in element: XCUIElement) -> Bool {
        element.label.contains(text) || element.descendants(matching: .any)
            .allElementsBoundByIndex.contains {
                $0.label.contains(text) || ($0.value as? String)?.contains(text) == true
            }
    }

    @MainActor private func identified(_ identifier: String, in element: XCUIElement) -> XCUIElement {
        element.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @MainActor private func reveal(_ element: XCUIElement, identifier: String, in app: XCUIApplication) {
        XCTAssertTrue(element.exists, "Missing control: \(identifier)")
        let scrollView = app.scrollViews.containing(.any, identifier: identifier).firstMatch
        for _ in 0..<8 where !element.isHittable {
            guard scrollView.exists else { break }
            scrollView.scroll(byDeltaX: 0, deltaY: -180)
        }
        XCTAssertTrue(element.isHittable, "The control exists but cannot be reached in the current window.")
    }

    @MainActor private func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        } while Date() < deadline
        return condition()
    }

    @MainActor private func attachScreenshot(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private enum WritingFeaturesUIError: Error {
    case disposableRunnerRequired, preferenceSyncFailed, appDidNotBecomeForeground, mainWindowDidNotOpen
    case appAlreadyRunning, appOwnershipUnavailable, settingsMenuUnavailable, existingPowerModeSession
}

private final class WritingFeaturesDictationPreferences {
    private static let bundleIdentifier = "com.negentropi.RomaJustTalk" as CFString
    private static let profileKey = "VoiceInkDictationProfile"
    private static let customValues: [String: Any] = [
        "IsTextFormattingEnabled": true,
        "LowercaseTranscription": true,
        "RemoveFillerWords": false,
        "PunctuationCleanupMode": "removeTrailingPeriod",
        "RemovePunctuation": false,
        "AppendTrailingSpace": true
    ]
    private static let keys = [profileKey] + customValues.keys.sorted()
    private let saved: [String: Any]

    init() throws {
        guard CFPreferencesAppSynchronize(Self.bundleIdentifier) else {
            throw WritingFeaturesUIError.preferenceSyncFailed
        }
        guard Self.read("powerModeActiveSession.v1") == nil else {
            throw WritingFeaturesUIError.existingPowerModeSession
        }
        saved = Dictionary(uniqueKeysWithValues: Self.keys.compactMap { key in
            Self.read(key).map { (key, $0) }
        })
    }

    func install() throws {
        Self.write("custom", for: Self.profileKey)
        for (key, value) in Self.customValues { Self.write(value, for: key) }
        guard CFPreferencesAppSynchronize(Self.bundleIdentifier),
              profile() == "custom", customSettingsAreUnchanged() else {
            throw WritingFeaturesUIError.preferenceSyncFailed
        }
    }

    func profile() -> String? {
        guard CFPreferencesAppSynchronize(Self.bundleIdentifier) else { return nil }
        return Self.read(Self.profileKey) as? String
    }

    func customSettingsAreUnchanged() -> Bool {
        guard CFPreferencesAppSynchronize(Self.bundleIdentifier) else { return false }
        return Self.customValues.allSatisfy { Self.equal($0.value, Self.read($0.key)) }
    }

    func restore() -> Bool {
        for key in Self.keys { Self.write(saved[key], for: key) }
        guard CFPreferencesAppSynchronize(Self.bundleIdentifier) else { return false }
        return Self.keys.allSatisfy { Self.equal(saved[$0], Self.read($0)) }
    }

    private static func equal(_ expected: Any?, _ actual: Any?) -> Bool {
        switch (expected, actual) {
        case (nil, nil): return true
        case let (expected?, actual?):
            return CFGetTypeID(expected as CFTypeRef) == CFGetTypeID(actual as CFTypeRef)
                && (expected as? NSObject)?.isEqual(actual) == true
        default: return false
        }
    }

    private static func read(_ key: String) -> Any? {
        CFPreferencesCopyValue(key as CFString, bundleIdentifier, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }

    private static func write(_ value: Any?, for key: String) {
        CFPreferencesSetValue(key as CFString, value as CFPropertyList?, bundleIdentifier,
                              kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }
}

private final class WritingFeaturesAppOwnership {
    private struct OwnedProcess {
        let pid: pid_t
        let executableURL: URL
        let launchDate: Date
    }

    private static let bundleIdentifier = "com.negentropi.RomaJustTalk"
    private var processes: [OwnedProcess] = []

    init() throws {
        try requireNoRunningApplication()
    }

    func requireNoRunningApplication() throws {
        guard Self.runningApplications.isEmpty else { throw WritingFeaturesUIError.appAlreadyRunning }
    }

    func captureLaunchedApplication() throws {
        let applications = Self.runningApplications
        guard applications.count == 1, let application = applications.first,
              let executableURL = application.executableURL, let launchDate = application.launchDate else {
            throw WritingFeaturesUIError.appOwnershipUnavailable
        }
        processes.append(OwnedProcess(pid: application.processIdentifier,
                                      executableURL: executableURL, launchDate: launchDate))
    }

    var hasOnlyOwnedRunningApplications: Bool {
        let applications = Self.runningApplications
        return !applications.isEmpty && applications.allSatisfy(isOwned)
    }

    func terminateOwnedApplications() -> Bool {
        let applications = Self.runningApplications
        guard applications.allSatisfy(isOwned) else { return false }
        for application in applications { _ = application.terminate() }
        if waitForExit(timeout: 2) { return true }
        let remaining = Self.runningApplications
        guard remaining.allSatisfy(isOwned) else { return false }
        for application in remaining { _ = application.forceTerminate() }
        return waitForExit(timeout: 5)
    }

    private func isOwned(_ application: NSRunningApplication) -> Bool {
        processes.contains {
            $0.pid == application.processIdentifier
                && $0.executableURL == application.executableURL
                && $0.launchDate == application.launchDate
        }
    }

    private static var runningApplications: [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
    }

    private func waitForExit(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if Self.runningApplications.isEmpty { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        } while Date() < deadline
        return Self.runningApplications.isEmpty
    }
}

private final class WritingFeaturesDockPreference {
    private static let bundleIdentifier = "com.negentropi.RomaJustTalk" as CFString
    private static let key = "IsMenuBarOnly" as CFString
    private let saved: Any?

    init() throws {
        guard CFPreferencesAppSynchronize(Self.bundleIdentifier) else {
            throw WritingFeaturesUIError.preferenceSyncFailed
        }
        saved = Self.currentValue()
        // The production reader requires Bool; NSArgumentDomain supplies a String.
        Self.write(false)
        guard CFPreferencesAppSynchronize(Self.bundleIdentifier), Self.currentValue() as? Bool == false else {
            _ = restore()
            throw WritingFeaturesUIError.preferenceSyncFailed
        }
    }

    func restore() -> Bool {
        Self.write(saved)
        guard CFPreferencesAppSynchronize(Self.bundleIdentifier) else { return false }
        if let saved { return (saved as? NSObject)?.isEqual(Self.currentValue()) == true }
        return Self.currentValue() == nil
    }

    static func currentValue() -> Any? {
        CFPreferencesCopyValue(key, bundleIdentifier, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }

    private static func write(_ value: Any?) {
        CFPreferencesSetValue(key, value as CFPropertyList?, bundleIdentifier,
                              kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }
}
