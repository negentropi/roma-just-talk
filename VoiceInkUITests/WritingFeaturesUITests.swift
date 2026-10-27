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
        let row = snippetRow(trigger, in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        reveal(row, identifier: "snippets.row.\(trigger)", in: app)
        attachScreenshot(app, named: "Spoken snippets library")

        row.buttons["snippets.row.edit"].click()
        let content = app.textViews["snippets.editor.content"]
        assertValue(original, of: content)
        replaceText(in: content, with: revised)
        assertValue(revised, of: content)
        attachScreenshot(app, named: "Literal multiline snippet editor")
        app.buttons["snippets.editor.save"].click()
        XCTAssertTrue(waitUntil { !content.exists })

        let toggle = identified("snippets.row.toggle", in: row)
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.click()
        XCTAssertTrue(waitUntil { self.toggleIsOff(toggle) }, "The saved snippet did not turn off.")

        row.buttons["snippets.row.delete"].click()
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
        saved.buttons["snippets.row.edit"].click()
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
        app.buttons["snippets.import"].click()
        chooseFile(file, in: app)
        let sheet = identified("snippets.import.sheet", in: app)
        XCTAssertTrue(sheet.waitForExistence(timeout: 10))
        let confirm = app.buttons["snippets.import.confirm"]
        XCTAssertFalse(confirm.isEnabled, "Duplicate replacement did not require a policy choice.")
        let previewRow = identified("snippets.import.row.0", in: app)
        XCTAssertTrue(previewRow.waitForExistence(timeout: 5))
        if previewRow.disclosureTriangles.firstMatch.exists {
            previewRow.disclosureTriangles.firstMatch.click()
        } else {
            previewRow.click()
        }
        XCTAssertTrue(waitUntil { self.containsText(original, in: previewRow) })
        XCTAssertTrue(waitUntil { self.containsText(replacement, in: previewRow) })
        attachScreenshot(app, named: "CSV current and imported multiline preview")

        let replace = app.radioButtons["Replace it with the imported row"]
        XCTAssertTrue(replace.waitForExistence(timeout: 5))
        replace.click()
        XCTAssertTrue(confirm.isEnabled)
        confirm.click()
        XCTAssertTrue(waitUntil { !sheet.exists })

        searchSnippets(trigger, in: app)
        let row = snippetRow(trigger, in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(toggleIsOff(identified("snippets.row.toggle", in: row)))
        row.buttons["snippets.row.edit"].click()
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
        reveal(row, identifier: "snippets.row.\(trigger)", in: app)
        row.buttons["snippets.row.delete"].click()
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
        XCTAssertTrue(app.buttons["Preview Import"].waitForExistence(timeout: 10))
        app.typeKey("g", modifierFlags: [.command, .shift])
        let path = app.comboBoxes.firstMatch
        XCTAssertTrue(path.waitForExistence(timeout: 5), "The file panel did not expose its Go to Folder field.")
        replaceText(in: path, with: file.path)
        path.typeKey(.return, modifierFlags: [])
        let preview = app.buttons["Preview Import"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        XCTAssertTrue(preview.isEnabled)
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
    case appAlreadyRunning, appOwnershipUnavailable, settingsMenuUnavailable
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
