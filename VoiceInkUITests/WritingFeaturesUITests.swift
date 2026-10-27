import AppKit
import CoreFoundation
import Foundation
import XCTest

final class WritingFeaturesUITests: XCTestCase {
    private static let mainWindowIdentifier = "com.negentropi.RomaJustTalk.mainWindow"
    private var modelSettingsOpening = 0
    private var shortcutPreferences: WritingFeaturesShortcutPreferences?
    private var writingApplication: XCUIApplication?
    private var writingApplicationOwnership: WritingFeaturesAppOwnership?

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
        assertModelSettingsResistsBackgroundPointer(preferences: preferences, in: app)
        assertProfile("Custom", storedValue: "custom", preferences: preferences, in: app)
        assertCustomFormatting(isEnabled: true, preferences: preferences, in: app)
        attachScreenshot(app, named: "Custom dictation cleanup settings")

        let none = profileChoice("None", in: app)
        revealModelSettingsControl(none, preferences: preferences, towardTop: true, in: app)
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
        revealModelSettingsControl(custom, preferences: preferences, towardTop: true, in: app)
        XCTAssertTrue(custom.isHittable)
        custom.click()
        assertProfile("Custom", storedValue: "custom", preferences: preferences, in: app)
        assertCustomFormatting(isEnabled: true, preferences: preferences, in: app)
        attachScreenshot(app, named: "Custom formatting restored without changing saved values")
        closeModelSettings(in: app, usingKeyboard: true)
        exerciseOtherSettingsSheets(in: app, preferences: preferences)
    }

    @MainActor func testDictationProfilesAndClarityStylesPersistWithoutChangingCustomSettings() throws {
        let (app, ownership) = try prepareApp()
        let preferences = try WritingFeaturesDictationPreferences()
        addTeardownBlock {
            guard ownership.terminateOwnedApplications() else {
                XCTFail("The owned app did not exit; retained profile/style preferences.")
                return
            }
            XCTAssertTrue(preferences.restore())
        }
        try preferences.install(clarityStyle: "natural")
        try launchApp(app, ownership: ownership)
        assertSeededDictionaryLibrary(in: app)
        let trigger = "ui profile library " + UUID().uuidString.lowercased()
        let content = "\r\nProfile library Cafe\u{301} 👩🏽‍💻\r\n"
        let snippetOwnership = try WritingFeaturesSnippetOwnership(trigger: trigger)
        addTeardownBlock {
            guard ownership.terminateOwnedApplications() else {
                XCTFail("The owned app did not exit; retained its snippet for inspection.")
                return
            }
            XCTAssertTrue(snippetOwnership.restore(), "The snippet library changed outside the owned entry.")
        }
        openSnippets(in: app)
        createSnippet(trigger: trigger, content: content, in: app)
        guard let libraries = preferences.panelValues() else {
            XCTFail("Unable to snapshot the nonempty snippet library.")
            return
        }

        openModelSettings(in: app)
        assertAllProfiles("Custom", storedValue: "custom", preferences: preferences, in: app)
        assertClarityStyle("Natural", storedValue: "natural", enabled: false, preferences: preferences, in: app)
        for (title, value) in [("None", "none"), ("Light", "light"), ("Clarity", "clarity")] {
            selectProfile(title, preferences: preferences, in: app)
            assertAllProfiles(title, storedValue: value, preferences: preferences, in: app)
            assertClarityStyle("Natural", storedValue: "natural", enabled: title == "Clarity", preferences: preferences, in: app)
            XCTAssertTrue(preferences.panelValuesAreUnchanged(from: libraries))
            attachScreenshot(app, named: title + " profile and retained library settings")
        }
        for (title, value) in [("Natural", "natural"), ("Casual", "casual"), ("Formal", "formal")] {
            let style = app.radioButtons[title]
            revealModelSettingsControl(style, preferences: preferences, in: app)
            XCTAssertTrue(style.isEnabled && style.isHittable)
            style.click()
            assertClarityStyle(title, storedValue: value, enabled: true, preferences: preferences, in: app)
            XCTAssertTrue(preferences.panelValuesAreUnchanged(from: libraries))
            attachScreenshot(app, named: "Clarity " + title + " style")
        }
        for (title, value) in [("Light", "light"), ("Custom", "custom")] {
            selectProfile(title, preferences: preferences, in: app)
            assertAllProfiles(title, storedValue: value, preferences: preferences, in: app)
            assertClarityStyle("Formal", storedValue: "formal", enabled: false, preferences: preferences, in: app)
        }
        revealModelSettingsControl(identified("transcriptionSettings.paragraphBreaks", in: app),
                                   preferences: preferences, towardTop: true, in: app)
        assertCustomFormatting(isEnabled: true, preferences: preferences, in: app)
        selectProfile("Clarity", preferences: preferences, in: app)
        closeModelSettings(in: app)
        openModelSettings(in: app)
        assertAllProfiles("Clarity", storedValue: "clarity", preferences: preferences, in: app)
        assertClarityStyle("Formal", storedValue: "formal", enabled: true, preferences: preferences, in: app)
        app.terminate()
        try launchApp(app, ownership: ownership)
        openModelSettings(in: app)
        assertAllProfiles("Clarity", storedValue: "clarity", preferences: preferences, in: app)
        assertClarityStyle("Formal", storedValue: "formal", enabled: true, preferences: preferences, in: app)
        XCTAssertTrue(preferences.panelValuesAreUnchanged(from: libraries))
        attachScreenshot(app, named: "Clarity Formal persisted after relaunch")
        closeModelSettings(in: app, usingKeyboard: true)
        assertSeededDictionaryLibrary(in: app)
        openSnippets(in: app)
        searchSnippets(trigger, in: app)
        let edit = snippetRow(trigger, in: app).buttons["snippets.row.edit"]
        reveal(edit, identifier: "snippets.row.edit", in: app)
        edit.click()
        assertExactText(content, in: app.textViews["snippets.editor.content"])
        app.buttons["snippets.editor.cancel"].click()
        deleteSnippet(trigger, in: app)
    }

    @MainActor func testHistoryPreservesRecognizedFallbackAndLegacyVariants() throws {
        let (app, ownership) = try prepareApp()
        let preferences = try WritingFeaturesDictationPreferences()
        let clipboard = try WritingFeaturesPasteboardOwnership()
        addTeardownBlock {
            guard ownership.terminateOwnedApplications() else {
                XCTFail("The owned app did not exit; retained History UI preferences and pasteboard.")
                return
            }
            let preferencesRestored = preferences.restore()
            let clipboardRestored = clipboard.restore()
            XCTAssertTrue(preferencesRestored)
            XCTAssertTrue(clipboardRestored, "The pasteboard changed ownership before restoration.")
        }
        try preferences.install(clarityStyle: "natural")
        try launchApp(app, ownership: ownership)
        XCTAssertEqual(preferences.profile(), "custom")
        XCTAssertEqual(preferences.clarityStyle(), "natural")
        XCTAssertNotEqual(Array(HistoryUIFixture.recognized.utf8), Array(HistoryUIFixture.processed.utf8))

        for fixture in HistoryUIFixture.rows {
            let row = openHistoryRow(fixture.id, search: fixture.search, in: app)
            let available = row.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "history.variant."))
            XCTAssertEqual(available.count, fixture.variants.count > 1 ? fixture.variants.count : 0)
            if let cleanup = fixture.cleanup {
                let label = identified("history.capturedCleanup", in: row)
                XCTAssertTrue(label.waitForExistence(timeout: 5))
                XCTAssertTrue(containsText(cleanup, in: label))
            } else {
                XCTAssertFalse(identified("history.capturedCleanup", in: row).exists)
            }
            if let failure = fixture.failure {
                let warning = identified("history.processingWarning", in: row)
                XCTAssertTrue(warning.exists)
                XCTAssertTrue(containsText("Clarity cleanup didn’t finish", in: warning))
                XCTAssertTrue(containsText("The recognized text was kept unchanged as Original. Nothing was removed.", in: warning))
                assertExactText(failure, in: row.staticTexts["history.processingWarning.reason"])
                XCTAssertFalse(row.buttons["history.variant.enhanced"].exists)
            } else {
                XCTAssertFalse(identified("history.processingWarning", in: row).exists)
            }
            XCTAssertEqual(row.buttons["history.variant.recognized"].exists, fixture.variants.contains { $0.name == "recognized" })
            for variant in fixture.variants {
                if fixture.variants.count > 1 {
                    let tab = row.buttons["history.variant." + variant.name]
                    XCTAssertTrue(tab.exists && tab.isEnabled)
                    XCTAssertEqual(tab.label, ["recognized": "Recognized", "original": "Original", "enhanced": "Enhanced"][variant.name])
                    reveal(tab, identifier: "history.row." + fixture.id, in: app)
                    tab.click()
                }
                let text = row.staticTexts["history.text." + variant.name]
                assertExactText(variant.text, in: text)
                let copy = row.buttons["history.copy." + variant.name]
                XCTAssertTrue(copy.waitForExistence(timeout: 5))
                reveal(copy, identifier: "history.row." + fixture.id, in: app)
                XCTAssertTrue(copy.isEnabled && copy.isHittable)
                XCTAssertTrue(clipboard.installMarker(), "The pasteboard no longer belonged to this UI case.")
                let previousChange = NSPasteboard.general.changeCount
                copy.click()
                XCTAssertTrue(waitUntil { NSPasteboard.general.changeCount != previousChange })
                let copied = try XCTUnwrap(NSPasteboard.general.string(forType: .string))
                XCTAssertEqual(Array(copied.utf8), Array(variant.text.utf8))
                XCTAssertEqual(Array(copied.utf16), Array(variant.text.utf16))
                XCTAssertTrue(clipboard.captureOwnedCopy(expected: variant.text))
                attachScreenshot(app, named: "History " + fixture.search + " " + variant.name)
            }
        }
        app.terminate()
        try launchApp(app, ownership: ownership)
        let saved = openHistoryRow(HistoryUIFixture.successID, search: "RJT History recognized", in: app)
        XCTAssertTrue(containsText("Cleanup: Clarity · Formal", in: identified("history.capturedCleanup", in: saved)))
        XCTAssertTrue(saved.buttons["history.variant.recognized"].exists)
        attachScreenshot(app, named: "History captured Clarity Formal survives relaunch")
    }

    @MainActor private func selectProfile(
        _ title: String, preferences: WritingFeaturesDictationPreferences, in app: XCUIApplication
    ) {
        let choice = profileChoice(title, in: app)
        revealModelSettingsControl(choice, preferences: preferences, towardTop: true, in: app)
        XCTAssertTrue(choice.isEnabled && choice.isHittable)
        choice.click()
    }

    @MainActor private func assertAllProfiles(
        _ title: String, storedValue: String, preferences: WritingFeaturesDictationPreferences, in app: XCUIApplication
    ) {
        let picker = identified("dictationProfile.picker", in: app)
        XCTAssertEqual(picker.radioButtons.count, 4)
        for name in ["Custom", "None", "Light", "Clarity"] {
            XCTAssertTrue(profileChoice(name, in: app).exists)
            XCTAssertTrue(waitUntil {
                String(describing: self.profileChoice(name, in: app).value ?? "") == (name == title ? "1" : "0")
            })
        }
        XCTAssertTrue(waitUntil { preferences.profile() == storedValue })
        XCTAssertTrue(preferences.customSettingsAreUnchanged())
    }

    @MainActor private func assertClarityStyle(
        _ title: String, storedValue: String, enabled: Bool,
        preferences: WritingFeaturesDictationPreferences, in app: XCUIApplication
    ) {
        let picker = identified("dictationProfile.clarityStyle.picker", in: app)
        revealModelSettingsControl(picker, preferences: preferences, in: app)
        XCTAssertEqual(picker.radioButtons.count, 3)
        for name in ["Natural", "Casual", "Formal"] {
            let choice = app.radioButtons[name]
            XCTAssertTrue(choice.exists)
            XCTAssertEqual(choice.isEnabled, enabled)
            XCTAssertTrue(waitUntil { String(describing: choice.value ?? "") == (name == title ? "1" : "0") })
        }
        XCTAssertTrue(waitUntil { preferences.clarityStyle() == storedValue })
        XCTAssertTrue(preferences.customSettingsAreUnchanged())
    }

    @MainActor private func assertSeededDictionaryLibrary(in app: XCUIApplication) {
        mainWindow(in: app).buttons["Dictionary"].click()
        let replacements = identified("dictionary.section.wordReplacements", in: app)
        XCTAssertTrue(replacements.waitForExistence(timeout: 5))
        reveal(replacements, identifier: "dictionary.section.wordReplacements", in: app)
        replacements.click()
        for expected in ["RJT UI library source", "RJT UI library target Café 👩🏽‍💻\r\n"] {
            assertLiteralLibraryText(expected, in: app)
        }
        let vocabulary = identified("dictionary.section.vocabulary", in: app)
        reveal(vocabulary, identifier: "dictionary.section.vocabulary", in: app)
        vocabulary.click()
        assertLiteralLibraryText("RJT UI vocabulary Cafe\u{301}", in: app)
        attachScreenshot(app, named: "Profile switching preserves the seeded vocabulary library")
    }

    @MainActor private func assertLiteralLibraryText(_ expected: String, in app: XCUIApplication) {
        let texts = app.staticTexts.matching(NSPredicate(format: "label == %@ OR value == %@", expected, expected))
        XCTAssertTrue(texts.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(texts.count, 1, "The owned library sentinel was not unique.")
        assertExactText(expected, in: texts.firstMatch)
    }

    @MainActor private func openHistoryRow(_ id: String, search: String, in app: XCUIApplication) -> XCUIElement {
        mainWindow(in: app).buttons["past"].click()
        let searchField = app.textFields["history.search"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        replaceText(in: searchField, with: search)
        let rows = app.descendants(matching: .any).matching(identifier: "history.row." + id)
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(rows.count, 1)
        let row = rows.firstMatch
        let expand = historyExpandTarget(id, row: row, in: app)
        reveal(expand, identifier: "history.row." + id, in: app)
        expand.click()
        XCTAssertTrue(row.staticTexts["history.text.original"].waitForExistence(timeout: 5))
        return row
    }

    @MainActor private func assertExactText(_ expected: String, in element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        let actual = element.value as? String ?? element.label
        XCTAssertEqual(Array(actual.utf8), Array(expected.utf8))
        XCTAssertEqual(Array(actual.utf16), Array(expected.utf16))
    }

    @MainActor private func historyExpandTarget(_ id: String, row: XCUIElement, in app: XCUIApplication) -> XCUIElement {
        let identifier = "history.row." + id + ".expand"
        let targets = app.descendants(matching: .any).matching(identifier: identifier)
        let target = targets.firstMatch
        guard target.waitForExistence(timeout: 5), targets.count == 1,
              !row.frame.isEmpty, !target.frame.isEmpty, row.frame.contains(target.frame) else {
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "History expansion target hierarchy " + id
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
            attachScreenshot(app, named: "History expansion target unavailable")
            XCTFail("History must expose one exact expansion target inside its owned row.")
            return target
        }
        return target
    }

    @MainActor private func prepareApp() throws -> (XCUIApplication, WritingFeaturesAppOwnership) {
        let ownership = try WritingFeaturesAppOwnership()
        writingApplicationOwnership = ownership
        let shortcuts = try WritingFeaturesShortcutPreferences()
        let dockPreference = try WritingFeaturesDockPreference()
        let app = XCUIApplication()
        writingApplication = app
        // XCTest runs teardown blocks in reverse order, including after a fatal UI lookup.
        addTeardownBlock {
            guard ownership.terminateOwnedApplications() else {
                XCTFail("The owned app did not exit; retained the Dock preference for inspection.")
                return
            }
            XCTAssertTrue(dockPreference.restore(), "Unable to restore the Dock preference.")
        }
        addTeardownBlock { @MainActor in
            guard ownership.terminateOwnedApplications() else {
                XCTFail("The owned app did not exit; retained shortcut preferences for inspection.")
                return
            }
            let restored = shortcuts.restore()
            self.attachShortcutCensus("restored", preferences: shortcuts)
            XCTAssertTrue(restored, "Unable to restore the exact owned shortcut preferences.")
        }
        addTeardownBlock { @MainActor in
            if ownership.hasOnlyOwnedRunningApplications {
                app.terminate()
            }
        }
        shortcutPreferences = shortcuts
        attachShortcutCensus("before", preferences: shortcuts)
        try ownership.requireNoRunningApplication()
        try shortcuts.install()
        attachShortcutCensus("isolated", preferences: shortcuts)
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
        if let shortcuts = shortcutPreferences {
            attachShortcutCensus("after-launch", preferences: shortcuts)
            XCTAssertTrue(shortcuts.isIsolated(), "App startup changed the isolated global shortcut settings.")
        } else {
            XCTFail("The UI app launched without its owned shortcut fixture.")
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
        modelSettingsOpening += 1
        let before = modelSettingsActors(in: app)
        attachModelSettingsBoundary("before-opening", actors: before, in: app)
        XCTAssertTrue(before["settings-open"]?.isInteractive == true,
                      "The model settings entry point was not enabled and hittable before opening.")
        XCTAssertTrue(before["background-filter"]?.isInteractive == true,
                      "The model filter was not enabled and hittable before opening settings.")
        settings.click()
        XCTAssertTrue(app.buttons["models.settings.close"].waitForExistence(timeout: 5))
        XCTAssertTrue(profileChoice("Custom", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(profileChoice("None", in: app).waitForExistence(timeout: 5))
        let after = modelSettingsActors(in: app)
        let failures = ["custom", "none", "settings-close"].filter { after[$0]?.isInteractive != true }
        attachModelSettingsBoundary("after-opening", actors: after, failures: failures, in: app)
        XCTAssertTrue(failures.isEmpty, "Opening model settings disabled the panel or blocked a visible panel control.")
        XCTAssertEqual(app.sheets.count, 1, "Model settings did not present one native sheet.")
    }

    @MainActor private func assertModelSettingsResistsBackgroundPointer(
        preferences: WritingFeaturesDictationPreferences,
        in app: XCUIApplication
    ) {
        let expectedProfile = preferences.profile()
        let customValue = String(describing: profileChoice("Custom", in: app).value ?? "")
        let noneValue = String(describing: profileChoice("None", in: app).value ?? "")
        let entry = app.buttons["models.settings.open"]
        let sheetFrame = app.sheets.firstMatch.frame
        // Native modal background traits can remain hittable; verify pointer routing by its effect.
        let attempted = clickBackgroundEntryIfReachable(entry, outside: app.sheets.firstMatch)
        let after = modelSettingsActors(in: app)
        let failures = ["custom", "none", "settings-close"].filter { after[$0]?.isInteractive != true }
        attachModelSettingsBoundary("after-background-pointer", actors: after, failures: failures,
                                    backgroundPointerAttempted: attempted, in: app)
        XCTAssertEqual(app.sheets.count, 1, "The background gear dismissed or replaced the model settings sheet.")
        XCTAssertEqual(app.sheets.firstMatch.frame, sheetFrame, "The background gear moved the active model settings sheet.")
        XCTAssertTrue(failures.isEmpty, "The background gear blocked the active model settings controls.")
        XCTAssertEqual(String(describing: profileChoice("Custom", in: app).value ?? ""), customValue)
        XCTAssertEqual(String(describing: profileChoice("None", in: app).value ?? ""), noneValue)
        XCTAssertEqual(preferences.profile(), expectedProfile, "The background gear changed the cleanup profile.")
        XCTAssertTrue(preferences.customSettingsAreUnchanged(), "The background gear changed saved Custom settings.")
    }

    @MainActor private func clickBackgroundEntryIfReachable(_ entry: XCUIElement, outside sheet: XCUIElement) -> Bool {
        guard SettingsActorObservation(entry).isInteractive else { return false }
        let entryFrame = entry.frame
        let sheetFrame = sheet.frame
        guard !entryFrame.isEmpty, !sheetFrame.isEmpty else {
            XCTFail("The background pointer probe had no native frame.")
            return false
        }
        guard !entryFrame.intersects(sheetFrame) else {
            XCTFail("The background pointer probe overlapped the active sheet.")
            return false
        }
        entry.click()
        return true
    }

    @MainActor private func closeModelSettings(in app: XCUIApplication, usingKeyboard: Bool = false) {
        let close = app.buttons["models.settings.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        XCTAssertTrue(close.isEnabled && close.isHittable)
        if usingKeyboard {
            app.typeKey(.escape, modifierFlags: [])
        } else {
            close.click()
        }
        XCTAssertTrue(waitUntil { !close.exists && app.sheets.count == 0 })
        let after = modelSettingsActors(in: app)
        attachModelSettingsBoundary("after-closing", actors: after, in: app)
        XCTAssertTrue(after["settings-open"]?.isInteractive == true,
                      "Closing settings did not restore the model settings entry point.")
        XCTAssertTrue(after["background-filter"]?.isInteractive == true,
                      "Closing settings did not restore the model filter.")
    }

    @MainActor private func modelSettingsActors(in app: XCUIApplication) -> [String: SettingsActorObservation] {
        let window = mainWindow(in: app)
        return [
            "application": SettingsActorObservation(app),
            "main-window": SettingsActorObservation(window),
            "settings-open": SettingsActorObservation(app.buttons["models.settings.open"]),
            "background-filter": SettingsActorObservation(app.buttons["Recommended"]),
            "form": SettingsActorObservation(app.scrollViews.containing(.any, identifier: "dictationProfile.picker").firstMatch),
            "custom": SettingsActorObservation(profileChoice("Custom", in: app)),
            "none": SettingsActorObservation(profileChoice("None", in: app)),
            "settings-close": SettingsActorObservation(app.buttons["models.settings.close"])
        ]
    }

    @MainActor private func attachModelSettingsBoundary(
        _ phase: String,
        actors: [String: SettingsActorObservation],
        failures: [String] = [],
        backgroundPointerAttempted: Bool? = nil,
        in app: XCUIApplication
    ) {
        var payload: [String: Any] = [
            "version": 1, "phase": phase, "opening": modelSettingsOpening,
            "mainWindowCount": app.windows.matching(identifier: Self.mainWindowIdentifier).count,
            "nativeSheetCount": app.sheets.count,
            "actors": actors.mapValues(\.json), "boundaryFailures": failures
        ]
        if let backgroundPointerAttempted { payload["backgroundPointerAttempted"] = backgroundPointerAttempted }
        do {
            let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
                                           uniformTypeIdentifier: "public.json")
            attachment.name = "Model settings boundary " + phase
            attachment.lifetime = .keepAlways
            add(attachment)
        } catch {
            XCTFail("Unable to retain the model settings boundary observation: \(error)")
        }
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "Model settings hierarchy " + phase
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }

    @MainActor private func exerciseOtherSettingsSheets(
        in app: XCUIApplication,
        preferences: WritingFeaturesDictationPreferences
    ) {
        mainWindow(in: app).buttons["Dictionary"].click()
        let dictionarySettings = app.buttons["dictionary.settings.open"]
        XCTAssertTrue(dictionarySettings.waitForExistence(timeout: 5))
        reveal(dictionarySettings, identifier: "dictionary.settings.open", in: app)
        XCTAssertTrue(dictionarySettings.isEnabled && dictionarySettings.isHittable)
        dictionarySettings.click()
        let dictionarySheet = requiredSettingsSheet(in: app)
        let shortcutWrapper = identified("dictionary.settings.shortcut", in: dictionarySheet)
        XCTAssertTrue(shortcutWrapper.waitForExistence(timeout: 5))
        let shortcut: XCUIElement
        if shortcutWrapper.elementType == .button {
            shortcut = shortcutWrapper
        } else {
            XCTAssertEqual(shortcutWrapper.buttons.count, 1, "The shortcut recorder did not expose one native button.")
            shortcut = shortcutWrapper.buttons.firstMatch
        }
        XCTAssertTrue(shortcut.isEnabled && shortcut.isHittable)
        guard let dictionarySnapshot = preferences.panelValues() else {
            XCTFail("Unable to read saved settings before the dictionary background pointer probe.")
            return
        }
        let dictionaryFrame = dictionarySheet.frame
        _ = clickBackgroundEntryIfReachable(dictionarySettings, outside: dictionarySheet)
        XCTAssertEqual(app.sheets.count, 1, "The background gear dismissed or replaced the dictionary settings sheet.")
        XCTAssertEqual(dictionarySheet.frame, dictionaryFrame)
        XCTAssertTrue(shortcut.exists && shortcut.isEnabled && shortcut.isHittable)
        let dictionaryClose = dictionarySheet.buttons["dictionary.settings.close"]
        XCTAssertTrue(dictionaryClose.exists && dictionaryClose.isEnabled && dictionaryClose.isHittable)
        XCTAssertTrue(preferences.panelValuesAreUnchanged(from: dictionarySnapshot), "The background gear changed saved settings.")
        XCTAssertTrue(preferences.customSettingsAreUnchanged())
        attachScreenshot(app, named: "Dictionary settings native sheet")
        dismissSettingsSheet("dictionary.settings.close", usingKeyboard: true, in: app)
        XCTAssertTrue(dictionarySettings.isEnabled && dictionarySettings.isHittable)

        mainWindow(in: app).buttons["style"].click()
        let enhancementSettings = app.buttons["enhancement.settings.open"]
        XCTAssertTrue(enhancementSettings.waitForExistence(timeout: 5))
        reveal(enhancementSettings, identifier: "enhancement.settings.open", in: app)
        enhancementSettings.click()
        let enhancementSheet = requiredSettingsSheet(in: app)
        let clipboard = enhancementSheet.switches["enhancement.settings.clipboard"]
        XCTAssertTrue(clipboard.waitForExistence(timeout: 5))
        XCTAssertTrue(clipboard.isEnabled && clipboard.isHittable)
        attachScreenshot(app, named: "Enhancement settings native sheet")
        dismissSettingsSheet("enhancement.settings.close", usingKeyboard: true, in: app)
        XCTAssertTrue(enhancementSettings.isEnabled && enhancementSettings.isHittable)

        guard let promptSnapshot = preferences.panelValues() else {
            XCTFail("Unable to read saved prompt settings before opening the editor.")
            return
        }
        let addPrompt = app.buttons["enhancement.prompts.add"]
        reveal(addPrompt, identifier: "enhancement.prompts.add", in: app)
        addPrompt.click()
        let promptSheet = requiredSettingsSheet(in: app)
        let promptName = promptSheet.textFields["promptEditor.name"]
        XCTAssertTrue(promptName.waitForExistence(timeout: 5))
        XCTAssertTrue(promptName.isEnabled && promptName.isHittable)
        let unsavedPrompt = "Unsent sheet proof " + UUID().uuidString
        replaceText(in: promptName, with: unsavedPrompt)
        assertValue(unsavedPrompt, of: promptName)
        attachScreenshot(app, named: "Prompt editor unsaved native sheet")
        dismissSettingsSheet("promptEditor.cancel", usingKeyboard: true, in: app)
        XCTAssertTrue(preferences.panelValuesAreUnchanged(from: promptSnapshot), "Cancel persisted an unsaved prompt draft.")
        XCTAssertTrue(addPrompt.isEnabled && addPrompt.isHittable)

        mainWindow(in: app).buttons["Power Mode"].click()
        let addMode = app.buttons["powerMode.configuration.add"]
        XCTAssertTrue(addMode.waitForExistence(timeout: 5))
        guard let modeSnapshot = preferences.panelValues() else {
            XCTFail("Unable to read saved modes before opening the editor.")
            return
        }
        addMode.click()
        let modeSheet = requiredSettingsSheet(in: app)
        let modeName = modeSheet.textFields["powerMode.configuration.name"]
        XCTAssertTrue(modeName.waitForExistence(timeout: 5))
        XCTAssertTrue(modeName.isEnabled && modeName.isHittable)
        let unsavedMode = "Unsent mode proof " + UUID().uuidString
        replaceText(in: modeName, with: unsavedMode)
        assertValue(unsavedMode, of: modeName)
        attachScreenshot(app, named: "Power Mode unsaved native sheet")
        dismissSettingsSheet("powerMode.configuration.cancel", usingKeyboard: true, in: app)
        XCTAssertTrue(preferences.panelValuesAreUnchanged(from: modeSnapshot), "Cancel persisted an unsaved Power Mode.")
        XCTAssertTrue(addMode.isEnabled && addMode.isHittable)

        let reorder = app.buttons["powerMode.reorder.open"]
        XCTAssertTrue(reorder.waitForExistence(timeout: 5))
        reorder.click()
        _ = requiredSettingsSheet(in: app)
        let closeReorder = app.sheets.firstMatch.buttons["powerMode.reorder.close"]
        XCTAssertTrue(closeReorder.waitForExistence(timeout: 5))
        XCTAssertTrue(closeReorder.isEnabled && closeReorder.isHittable)
        attachScreenshot(app, named: "Power Mode reorder native sheet")
        dismissSettingsSheet("powerMode.reorder.close", usingKeyboard: false, in: app)
        XCTAssertTrue(preferences.panelValuesAreUnchanged(from: modeSnapshot), "Opening reorder changed saved modes.")
        XCTAssertTrue(reorder.isEnabled && reorder.isHittable)
        XCTAssertTrue(preferences.customSettingsAreUnchanged())
    }

    @MainActor private func requiredSettingsSheet(in app: XCUIApplication) -> XCUIElement {
        XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.sheets.count, 1, "The settings action did not present one native sheet.")
        return app.sheets.firstMatch
    }

    @MainActor private func dismissSettingsSheet(_ closeIdentifier: String, usingKeyboard: Bool, in app: XCUIApplication) {
        let close = app.sheets.firstMatch.buttons[closeIdentifier]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        assertNoUnexpectedRecordingNotification(in: app)
        XCTAssertTrue(close.isEnabled && close.isHittable)
        if usingKeyboard {
            app.typeKey(.escape, modifierFlags: [])
        } else {
            close.click()
        }
        XCTAssertTrue(waitUntil { !close.exists && app.sheets.count == 0 }, "The native settings sheet did not dismiss.")
    }

    @MainActor private func profileChoice(_ title: String, in app: XCUIApplication) -> XCUIElement {
        app.radioButtons[title]
    }

    @MainActor private func assertProfile(
        _ title: String,
        storedValue: String,
        preferences: WritingFeaturesDictationPreferences,
        in app: XCUIApplication
    ) {
        let choices = app.radioButtons.matching(
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
            let control = identified(identifier, in: app)
            revealModelSettingsControl(control, preferences: preferences, in: app)
            XCTAssertEqual(control.isEnabled, isEnabled, "Unexpected enabled state for \(identifier).")
            XCTAssertEqual(String(describing: control.value ?? ""), "1", "Saved toggle value changed for \(identifier).")
        }
        XCTAssertTrue(preferences.customSettingsAreUnchanged(), "The saved Custom values changed.")
    }

    @MainActor private func revealModelSettingsControl(
        _ control: XCUIElement,
        preferences: WritingFeaturesDictationPreferences,
        towardTop: Bool = false,
        in app: XCUIApplication
    ) {
        let scrollers = app.scrollViews.containing(.any, identifier: "dictationProfile.picker")
        XCTAssertTrue(scrollers.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(scrollers.count, 1, "The cleanup controls did not belong to one settings scroller.")
        let scroller = scrollers.firstMatch
        func attachScrollFailure() {
            let hierarchy = XCTAttachment(string: scroller.debugDescription)
            hierarchy.name = "Model settings scroll hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
            attachScreenshot(app, named: "Model settings scroll failure")
        }
        guard let expectedProfile = preferences.profile(),
              let expectedScrollSettings = preferences.scrollAnchorValues() else {
            attachScrollFailure()
            XCTFail("The current settings could not be read before scrolling.")
            return
        }
        for _ in 0..<10 {
            if control.exists, !control.frame.isEmpty, scroller.frame.contains(control.frame) { return }
            if scroller.isHittable {
                scroller.scroll(byDeltaX: 0, deltaY: towardTop ? 180 : -180)
            } else {
                let controls = scroller.switches.allElementsBoundByIndex
                    + scroller.radioButtons.allElementsBoundByIndex + scroller.buttons.matching(identifier: "Edit").allElementsBoundByIndex
                guard let receiver = controls.first(where: {
                    $0.exists && $0.isEnabled && !$0.frame.isEmpty
                        && scroller.frame.contains($0.frame) && $0.isHittable
                }) else {
                    attachScrollFailure()
                    XCTFail("The active settings sheet exposed no reachable scroll receiver.")
                    return
                }
                receiver.scroll(byDeltaX: 0, deltaY: towardTop ? 180 : -180)
            }
            XCTAssertEqual(preferences.profile(), expectedProfile, "Scrolling changed the selected cleanup profile.")
            XCTAssertTrue(preferences.scrollingSettingsAreUnchanged(from: expectedScrollSettings), "Scrolling changed a saved setting.")
        }
        if control.exists, !control.frame.isEmpty, scroller.frame.contains(control.frame) { return }
        attachScrollFailure()
        XCTAssertTrue(control.exists, "The settings control was not exposed.")
        XCTAssertTrue(scroller.frame.contains(control.frame), "The settings control was not fully visible after scrolling.")
    }

    @MainActor private func mainWindow(in app: XCUIApplication) -> XCUIElement {
        app.windows[Self.mainWindowIdentifier]
    }

    @MainActor private func createSnippet(trigger: String, content: String, in app: XCUIApplication) {
        guard let ownership = writingApplicationOwnership else {
            XCTFail("Literal snippet input requires the owned app lifecycle.")
            return
        }
        let clipboard: WritingFeaturesPasteboardOwnership
        do {
            clipboard = try ownLiteralPasteboard(ownership: ownership)
        } catch {
            XCTFail("Unable to preserve the literal-input pasteboard: \(error)")
            return
        }
        app.buttons["snippets.new"].click()
        let triggerField = app.textFields["snippets.editor.trigger"]
        XCTAssertTrue(triggerField.waitForExistence(timeout: 10))
        replaceText(in: triggerField, with: trigger)
        let editor = app.textViews["snippets.editor.content"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        pasteLiteralText(content, into: editor, clipboard: clipboard, in: app)
        assertValue(content, of: editor)
        let actual = editor.value as? String ?? ""
        XCTAssertEqual(Array(actual.utf8), Array(content.utf8))
        XCTAssertEqual(Array(actual.utf16), Array(content.utf16))
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

    @MainActor private func ownLiteralPasteboard(
        ownership: WritingFeaturesAppOwnership
    ) throws -> WritingFeaturesPasteboardOwnership {
        let clipboard = try WritingFeaturesPasteboardOwnership()
        addTeardownBlock {
            guard ownership.terminateOwnedApplications() else {
                XCTFail("The owned app did not exit; retained its literal-input pasteboard for inspection.")
                return
            }
            XCTAssertTrue(clipboard.restore(), "The literal-input pasteboard changed ownership before restoration.")
        }
        return clipboard
    }

    @MainActor private func pasteLiteralText(
        _ text: String, into editor: XCUIElement, clipboard: WritingFeaturesPasteboardOwnership,
        in app: XCUIApplication
    ) {
        XCTAssertTrue(clipboard.installOwnedText(text), "The literal-input pasteboard no longer belonged to this case.")
        editor.click()
        editor.typeKey("a", modifierFlags: .command)
        editor.typeKey("v", modifierFlags: .command)
        XCTAssertTrue(clipboard.retainsOwnedText(text), "Pasting changed the literal-input pasteboard's ownership.")
        assertNoUnexpectedRecordingNotification(in: app)
    }

    @MainActor private func replaceText(in element: XCUIElement, with text: String) {
        element.click()
        element.typeKey("a", modifierFlags: .command)
        element.typeText(text)
        guard let app = writingApplication else {
            XCTFail("The text editor had no owned UI application.")
            return
        }
        assertNoUnexpectedRecordingNotification(in: app)
    }

    @MainActor private func assertNoUnexpectedRecordingNotification(in app: XCUIApplication) {
        let notification = app.staticTexts.matching(
            NSPredicate(format: "label == %@ OR value == %@", "Microphone permission required", "Microphone permission required")
        )
        guard notification.firstMatch.exists else { return }
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "Unexpected recording notification hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        attachScreenshot(app, named: "Unexpected recording notification during UI editing")
        if let shortcuts = shortcutPreferences { attachShortcutCensus("unexpected-recording", preferences: shortcuts) }
        XCTFail("Editing UI settings unexpectedly started a recording permission request.")
    }

    @MainActor private func attachShortcutCensus(_ phase: String, preferences: WritingFeaturesShortcutPreferences) {
        do {
            let attachment = XCTAttachment(data: try JSONSerialization.data(
                withJSONObject: preferences.census(phase: phase), options: [.prettyPrinted, .sortedKeys]
            ), uniformTypeIdentifier: "public.json")
            attachment.name = "UI shortcut preference census " + phase
            attachment.lifetime = .keepAlways
            add(attachment)
        } catch {
            XCTFail("Unable to retain the owned shortcut preference census: \(error)")
        }
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

private enum HistoryUIFixture {
    struct Row {
        let id: String
        let search: String
        let cleanup: String?
        let failure: String?
        let variants: [(name: String, text: String)]
    }
    static let successID = "A1000000-0000-4000-8000-000000000002"
    static let recognized = "RJT History recognized\r\nCafe\u{301} 👩🏽‍💻\u{00A0}42\r\n"
    static let processed = "RJT History recognized\r\nCafé 👩🏽‍💻\u{00A0}42\r\n"
    static let rows = [
        Row(id: "A1000000-0000-4000-8000-000000000001", search: "RJT History legacy", cleanup: nil, failure: nil,
            variants: [("original", "RJT History legacy\r\nCafe\u{301} 👩🏽‍💻\r\n"), ("enhanced", "RJT legacy enhanced — 42")]),
        Row(id: successID, search: "RJT History recognized", cleanup: "Cleanup: Clarity · Formal", failure: nil,
            variants: [("recognized", recognized), ("original", processed), ("enhanced", "RJT Clarity polished — Café 👩🏽‍💻 42\r\n")]),
        Row(id: "A1000000-0000-4000-8000-000000000003", search: "RJT History fallback", cleanup: "Cleanup: Clarity · Casual",
            failure: "RJT fixture provider unavailable — raw text kept",
            variants: [("original", "RJT History fallback\r\nCafe\u{301} 👩🏽‍💻\r\n")]),
        Row(id: "A1000000-0000-4000-8000-000000000004", search: "RJT History unknown", cleanup: nil, failure: nil,
            variants: [("original", "RJT History unknown\r\nCafe\u{301} 👩🏽‍💻\r\n")])
    ]
}

private final class WritingFeaturesPasteboardOwnership {
    private let savedItems: [[(NSPasteboard.PasteboardType, Data)]]
    private var lastOwnedChange: Int

    init() throws {
        let pasteboard = NSPasteboard.general
        let count = pasteboard.changeCount
        savedItems = try Self.snapshot(pasteboard)
        guard pasteboard.changeCount == count else { throw WritingFeaturesUIError.pasteboardOwnershipChanged }
        lastOwnedChange = count
    }

    func installMarker() -> Bool {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount == lastOwnedChange else { return false }
        let marker = "RJT owned copy marker " + UUID().uuidString
        pasteboard.clearContents()
        guard pasteboard.setString(marker, forType: .string) else { return false }
        let count = pasteboard.changeCount
        guard pasteboard.string(forType: .string) == marker, pasteboard.changeCount == count else { return false }
        lastOwnedChange = count
        return true
    }

    func captureOwnedCopy(expected: String) -> Bool {
        let pasteboard = NSPasteboard.general
        let count = pasteboard.changeCount
        guard let value = pasteboard.string(forType: .string),
              value.utf8.elementsEqual(expected.utf8), value.utf16.elementsEqual(expected.utf16),
              pasteboard.changeCount == count else { return false }
        lastOwnedChange = count
        return true
    }

    func installOwnedText(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount == lastOwnedChange else { return false }
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else { return false }
        return captureOwnedCopy(expected: text)
    }

    func retainsOwnedText(_ expected: String) -> Bool {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount == lastOwnedChange,
              let text = pasteboard.string(forType: .string),
              text.utf8.elementsEqual(expected.utf8), text.utf16.elementsEqual(expected.utf16) else { return false }
        return pasteboard.changeCount == lastOwnedChange
    }

    func restore() -> Bool {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount == lastOwnedChange else { return false }
        pasteboard.clearContents()
        let items = savedItems.map { values in
            let item = NSPasteboardItem()
            for (type, data) in values { item.setData(data, forType: type) }
            return item
        }
        guard items.isEmpty || pasteboard.writeObjects(items) else { return false }
        let count = pasteboard.changeCount
        guard let restored = try? Self.snapshot(pasteboard), pasteboard.changeCount == count,
              restored.count == savedItems.count else { return false }
        return zip(restored, savedItems).allSatisfy { actual, expected in
            actual.count == expected.count && zip(actual, expected).allSatisfy { lhs, rhs in lhs.0 == rhs.0 && lhs.1 == rhs.1 }
        }
    }

    private static func snapshot(_ pasteboard: NSPasteboard) throws -> [[(NSPasteboard.PasteboardType, Data)]] {
        try (pasteboard.pasteboardItems ?? []).map { item in
            try item.types.sorted { $0.rawValue < $1.rawValue }.map { type in
                guard let data = item.data(forType: type) else { throw WritingFeaturesUIError.pasteboardSnapshotUnavailable }
                return (type, data)
            }
        }
    }
}

private final class WritingFeaturesSnippetOwnership {
    private static let bundleIdentifier = "com.negentropi.RomaJustTalk" as CFString
    private static let key = "VoiceInkSpokenSnippets" as CFString
    private let trigger: String
    private let saved: Data?
    private let originalRows: [[String: Any]]

    init(trigger: String) throws {
        self.trigger = trigger
        guard CFPreferencesAppSynchronize(Self.bundleIdentifier) else { throw WritingFeaturesUIError.preferenceSyncFailed }
        let value = CFPreferencesCopyValue(Self.key, Self.bundleIdentifier, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        if let value {
            guard let data = value as? Data,
                  let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                throw WritingFeaturesUIError.preferenceSyncFailed
            }
            saved = data
            originalRows = rows
        } else {
            saved = nil
            originalRows = []
        }
        guard !originalRows.contains(where: { ($0["trigger"] as? String)?.utf8.elementsEqual(trigger.utf8) == true }) else {
            throw WritingFeaturesUIError.preferenceSyncFailed
        }
    }

    func restore() -> Bool {
        guard CFPreferencesAppSynchronize(Self.bundleIdentifier) else { return false }
        let value = CFPreferencesCopyValue(Self.key, Self.bundleIdentifier, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        let rows: [[String: Any]]
        if let value {
            guard let data = value as? Data,
                  let decoded = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return false }
            rows = decoded
        } else { rows = [] }
        let unowned = rows.filter { ($0["trigger"] as? String)?.utf8.elementsEqual(trigger.utf8) != true }
        guard let actual = try? JSONSerialization.data(withJSONObject: unowned, options: [.sortedKeys]),
              let expected = try? JSONSerialization.data(withJSONObject: originalRows, options: [.sortedKeys]),
              actual == expected else { return false }
        CFPreferencesSetValue(Self.key, saved as CFPropertyList?, Self.bundleIdentifier, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        guard CFPreferencesAppSynchronize(Self.bundleIdentifier) else { return false }
        let restored = CFPreferencesCopyValue(Self.key, Self.bundleIdentifier, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        return saved.map { ($0 as NSData).isEqual(restored) } ?? (restored == nil)
    }
}

private enum WritingFeaturesUIError: Error {
    case disposableRunnerRequired, preferenceSyncFailed, appDidNotBecomeForeground, mainWindowDidNotOpen
    case appAlreadyRunning, appOwnershipUnavailable, settingsMenuUnavailable, existingPowerModeSession
    case pasteboardOwnershipChanged, pasteboardSnapshotUnavailable
}

private struct SettingsActorObservation {
    let exists: Bool
    let enabled: Bool?
    let hittable: Bool?

    @MainActor init(_ element: XCUIElement) {
        exists = element.exists
        enabled = exists ? element.isEnabled : nil
        hittable = exists ? element.isHittable : nil
    }

    var isInteractive: Bool { exists && enabled == true && hittable == true }

    var json: [String: Any] {
        ["exists": exists, "enabled": enabled.map { $0 as Any } ?? NSNull(),
         "hittable": hittable.map { $0 as Any } ?? NSNull()]
    }
}

private final class WritingFeaturesDictationPreferences {
    private static let bundleIdentifier = "com.negentropi.RomaJustTalk" as CFString
    private static let profileKey = "VoiceInkDictationProfile"
    private static let clarityStyleKey = "VoiceInkClarityStyle"
    private static let customValues: [String: Any] = [
        "IsTextFormattingEnabled": true,
        "LowercaseTranscription": true,
        "RemoveFillerWords": false,
        "PunctuationCleanupMode": "removeTrailingPeriod",
        "RemovePunctuation": false,
        "AppendTrailingSpace": true
    ]
    private static let scrollAnchorKeys = ["IsVADEnabled", "PrewarmModelOnWake", "showLiveTextPreview"]
    private static let panelKeys = ["customPrompts", "selectedPromptId", "useClipboardContext", "powerModeConfigurationsV2"]
    private static let libraryKeys = ["VoiceInkSpokenSnippets"]
    private static let keys = [profileKey, clarityStyleKey, "powerModeUIFlag"] + customValues.keys.sorted() + scrollAnchorKeys + panelKeys
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

    func install(clarityStyle: String? = nil) throws {
        Self.write("custom", for: Self.profileKey)
        if let clarityStyle { Self.write(clarityStyle, for: Self.clarityStyleKey) }
        Self.write(true, for: "powerModeUIFlag")
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

    func clarityStyle() -> String? {
        guard CFPreferencesAppSynchronize(Self.bundleIdentifier) else { return nil }
        return Self.read(Self.clarityStyleKey) as? String
    }

    func customSettingsAreUnchanged() -> Bool {
        guard CFPreferencesAppSynchronize(Self.bundleIdentifier) else { return false }
        return Self.customValues.allSatisfy { Self.equal($0.value, Self.read($0.key)) }
    }

    func scrollAnchorValues() -> [String: Any]? {
        guard CFPreferencesAppSynchronize(Self.bundleIdentifier) else { return nil }
        return Dictionary(uniqueKeysWithValues: Self.scrollAnchorKeys.compactMap { key in
            Self.read(key).map { (key, $0) }
        })
    }

    func scrollingSettingsAreUnchanged(from values: [String: Any]) -> Bool {
        guard customSettingsAreUnchanged() else { return false }
        return Self.scrollAnchorKeys.allSatisfy { Self.equal(values[$0], Self.read($0)) }
    }

    func panelValues() -> [String: Any]? {
        guard CFPreferencesAppSynchronize(Self.bundleIdentifier) else { return nil }
        return Dictionary(uniqueKeysWithValues: (Self.panelKeys + Self.libraryKeys).compactMap { key in
            Self.read(key).map { (key, $0) }
        })
    }

    func panelValuesAreUnchanged(from values: [String: Any]) -> Bool {
        guard CFPreferencesAppSynchronize(Self.bundleIdentifier) else { return false }
        return (Self.panelKeys + Self.libraryKeys).allSatisfy { Self.equal(values[$0], Self.read($0)) }
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

private final class WritingFeaturesShortcutPreferences {
    private static let bundleIdentifier = "com.negentropi.RomaJustTalk" as CFString
    private static let values: [String: Any] = [
        "primaryRecordingShortcut": "custom",
        "secondaryRecordingShortcut": "none",
        "primaryRecordingShortcutMode": "hybrid",
        "secondaryRecordingShortcutMode": "hybrid",
        "Shortcut_LegacyKeyboardShortcutsMigrated": true,
        "Shortcut_LegacyCustomRecordingShortcutsMigrated": true,
        "isMiddleClickToggleEnabled": false,
        "specialShortcutDoubleShiftTapInterval": 0
    ]
    private static let actionNames = [
        "primaryRecording", "secondaryRecording", "pasteLastTranscription", "pasteLastEnhancement",
        "retryLastTranscription", "openHistoryWindow", "quickAddToDictionary", "translateRecording",
        "rewriteSelectionRecording", "draftRecording"
    ]
    private let shortcutKeys: [String]
    private let keys: [String]
    private let saved: [String: Any]

    init() throws {
        guard CFPreferencesAppSynchronize(Self.bundleIdentifier) else {
            throw WritingFeaturesUIError.preferenceSyncFailed
        }
        let existing = CFPreferencesCopyKeyList(Self.bundleIdentifier, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? [String] ?? []
        let prefix = "Shortcut_powerMode_"
        let powerModeKeys = existing.compactMap { key -> String? in
            let base = key.hasSuffix("_cleared") ? String(key.dropLast("_cleared".count)) : key
            guard base.hasPrefix(prefix), UUID(uuidString: String(base.dropFirst(prefix.count))) != nil else { return nil }
            return base
        }
        shortcutKeys = Array(Set(Self.actionNames.map { "Shortcut_" + $0 } + powerModeKeys)).sorted()
        keys = Array(Set(Array(Self.values.keys) + ["selectedHotkey1", "selectedHotkey2", "hotkeyMode1", "hotkeyMode2"]
            + shortcutKeys.flatMap { [$0, $0 + "_cleared"] })).sorted()
        saved = Dictionary(uniqueKeysWithValues: keys.compactMap { key in Self.read(key).map { (key, $0) } })
    }

    func install() throws {
        // Missing primary selection recreates Left Shift. Keep a valid selection and clear its binding.
        for (key, value) in Self.values { Self.write(value, for: key) }
        for key in shortcutKeys { Self.write(true, for: key + "_cleared") }
        guard isIsolated() else { throw WritingFeaturesUIError.preferenceSyncFailed }
    }

    func isIsolated() -> Bool {
        guard CFPreferencesAppSynchronize(Self.bundleIdentifier) else { return false }
        return Self.values.allSatisfy { Self.equal($0.value, Self.read($0.key)) }
            && shortcutKeys.allSatisfy {
                Self.equal(true, Self.read($0 + "_cleared")) && Self.equal(saved[$0], Self.read($0))
            }
    }

    func restore() -> Bool {
        for key in keys { Self.write(saved[key], for: key) }
        guard CFPreferencesAppSynchronize(Self.bundleIdentifier) else { return false }
        return keys.allSatisfy { Self.equal(saved[$0], Self.read($0)) }
    }

    func census(phase: String) -> [String: Any] {
        let synchronized = CFPreferencesAppSynchronize(Self.bundleIdentifier)
        let visibleStrings: Set<String> = ["custom", "none", "hybrid", "special", "toggle", "pushToTalk"]
        return [
            "version": 1, "phase": phase, "synchronized": synchronized,
            "keys": Dictionary(uniqueKeysWithValues: keys.map { key -> (String, [String: Any]) in
                guard let value = Self.read(key) else { return (key, ["exists": false]) }
                var observation: [String: Any] = ["exists": true, "cfTypeID": CFGetTypeID(value as CFTypeRef)]
                if let data = value as? Data {
                    observation["dataBytes"] = data.count
                } else if let number = value as? NSNumber {
                    observation["value"] = number
                    observation["numberEncoding"] = String(cString: number.objCType)
                } else if let string = value as? String {
                    if visibleStrings.contains(string) { observation["value"] = string }
                    else { observation["redactedStringLength"] = string.count }
                } else {
                    observation["valueRedacted"] = true
                }
                return (key, observation)
            })
        ]
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
