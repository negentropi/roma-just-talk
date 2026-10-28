import AppKit
import Foundation
import Testing
import VoiceInkCore
@testable import VoiceInk

extension VoiceInkTests {
    @Test(.enabled(if: WritingUndoLiveFixture.isEnabled), .timeLimit(.minutes(3)))
    @MainActor func liveWritingUndoTextEditRejectsTerminatedProcess() async throws {
        let fixture = try WritingUndoLiveFixture(#function)
        defer { fixture.finishIfIncomplete(); fixture.restorePreferences() }
        try #require(NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.TextEdit").isEmpty,
                     "The termination case requires a fresh, exclusively owned TextEdit process.")
        let editor = try await LiveWritingEditor.open(.textEdit)
        var closed = false
        defer { if !closed { editor.close() } }
        try #require(editor.previousWindows.isEmpty)
        try await editor.selectOriginalPassage()
        try fixture.observe("process-before", editor: editor, expected: LiveWritingEditor.original, range: fixture.originalRange)
        let controller = WritingActionUndoController()
        let replacement = "Owned process rewrite 😀"
        try await fixture.deliver(replacement, to: editor, controller: controller)
        try fixture.observe("process-forward", editor: editor, expected: fixture.result(replacement), range: fixture.caret(replacement))
        let application = editor.application
        let pid = application.processIdentifier
        fixture.extra["processTermination"] = try editor.terminateOwnedApplication()
        closed = true
        try await fixture.wait("The owned process did not terminate.") { application.isTerminated }
        try await fixture.wait("Terminated target retained Undo authority.") { !controller.isAvailable }
        fixture.stage("process-terminated", ["pid": Int(pid), "bundleIdentifier": "com.apple.TextEdit",
            "token": editor.token, "isTerminated": application.isTerminated, "undoAvailable": controller.isAvailable])
        let replacementEditor = try await LiveWritingEditor.open(.textEdit)
        defer { replacementEditor.close() }
        try await replacementEditor.selectOriginalPassage()
        try fixture.check("differentApplicationInstance", !application.isEqual(replacementEditor.application))
        let outcome = await controller.undo()
        guard case .unavailable = outcome else { throw WritingUndoLiveFailure("Old process authority remained usable.") }
        try fixture.observe("replacement-process-refused", editor: replacementEditor,
                            expected: LiveWritingEditor.original, range: fixture.originalRange)
        try fixture.check("terminatedProcessRejected", true)
        try fixture.finish(["process-before", "process-forward", "process-terminated", "replacement-process-refused"])
    }

    @Test(.enabled(if: WritingUndoLiveFixture.isEnabled), .timeLimit(.minutes(3)))
    @MainActor func liveWritingUndoTextEditRestoresExactUnicodeSelection() async throws {
        let fixture = try WritingUndoLiveFixture(#function)
        defer { fixture.finishIfIncomplete(); fixture.restorePreferences() }
        let editor = try await LiveWritingEditor.open(.textEdit)
        defer { editor.close() }
        let controller = WritingActionUndoController()
        let replacements = ["短い 😀", "Longer e\u{301} 👩🏽‍💻\nSecond paragraph: Roma, 台灣, 🧑‍🚀."]
        for (index, replacement) in replacements.enumerated() {
            try await editor.selectOriginalPassage()
            try await fixture.deliver(replacement, to: editor, controller: controller)
            try fixture.observe("unicode\(index + 1)-forward", editor: editor,
                                expected: fixture.result(replacement), range: fixture.caret(replacement))
            guard case .restored = await controller.undo() else { throw WritingUndoLiveFailure("Native TextEdit Undo did not restore text and selection.") }
            try fixture.observe("unicode\(index + 1)-restored", editor: editor,
                                expected: LiveWritingEditor.original, range: fixture.originalRange)
        }
        guard case .unavailable = await controller.undo() else { throw WritingUndoLiveFailure("Undo was replayable.") }
        try fixture.observe("second-undo-refused", editor: editor, expected: LiveWritingEditor.original, range: fixture.originalRange)
        try fixture.check("unicodeAndSelectionRestoredOnce", true)
        try fixture.finish(["unicode1-forward", "unicode1-restored", "unicode2-forward", "unicode2-restored", "second-undo-refused"])
    }

    @Test(.enabled(if: WritingUndoLiveFixture.isEnabled), .timeLimit(.minutes(3)))
    @MainActor func liveWritingUndoSafariPreservesClipboardWithEitherForwardPreference() async throws {
        let fixture = try WritingUndoLiveFixture(#function)
        defer { fixture.finishIfIncomplete(); fixture.restorePreferences() }
        let editor = try await LiveWritingEditor.open(.safari)
        defer { editor.close() }
        let controller = WritingActionUndoController()
        for restoreForward in [true, false] {
            fixture.setRestore(restoreForward)
            try await editor.selectOriginalPassage()
            let prefix = restoreForward ? "restore-on" : "restore-off"
            let initial = try fixture.writeClipboard("Forward C e\u{301} 🧪", discriminator: prefix)
            let replacement = "Safari \(prefix) e\u{301}\n😀 literal output"
            try await fixture.deliver(replacement, to: editor, controller: controller)
            try fixture.observe(prefix + "-forward", editor: editor, expected: fixture.result(replacement), range: fixture.caret(replacement))
            let expectedClipboard: [WritingUndoLiveClipboardItem]
            if restoreForward {
                expectedClipboard = initial
            } else {
                expectedClipboard = try fixture.writeClipboard("New current C after forward 🧑‍🚀", discriminator: prefix + "-current")
                try fixture.observeClipboard(prefix + "-current-copy", expected: expectedClipboard)
            }
            guard case .restored = await controller.undo() else { throw WritingUndoLiveFailure("Native Safari Undo did not restore text and selection.") }
            try fixture.observe(prefix + "-restored", editor: editor, expected: LiveWritingEditor.original, range: fixture.originalRange)
            try await CursorPaster.settlePendingClipboardRestore()
            try fixture.observeClipboard(prefix + "-clipboard", expected: expectedClipboard)
        }
        try fixture.check("bothForwardPreferencesPreserveCurrentClipboard", true)
        try fixture.finish(["restore-on-forward", "restore-on-restored", "restore-on-clipboard", "restore-off-forward",
                            "restore-off-current-copy", "restore-off-restored", "restore-off-clipboard"])
    }

    @Test(.enabled(if: WritingUndoLiveFixture.isEnabled), .timeLimit(.minutes(3)))
    @MainActor func liveWritingUndoSafariKeepsNewClipboardGeneration() async throws {
        let fixture = try WritingUndoLiveFixture(#function)
        defer { fixture.finishIfIncomplete(); fixture.restorePreferences() }
        let editor = try await LiveWritingEditor.open(.safari)
        defer { editor.close() }
        let controller = WritingActionUndoController()
        fixture.setRestore(true)
        try await editor.selectOriginalPassage()
        _ = try fixture.writeClipboard("Older C", discriminator: "old-generation")
        let replacement = "Safari replacement e\u{301} 😀"
        try await fixture.deliver(replacement, to: editor, controller: controller)
        try fixture.observe("forward", editor: editor, expected: fixture.result(replacement), range: fixture.caret(replacement))
        let forwardCount = NSPasteboard.general.changeCount
        let newer = try fixture.writeClipboard("User's new clipboard \(UUID().uuidString)", discriminator: "new-generation")
        try fixture.check("newClipboardGeneration", NSPasteboard.general.changeCount > forwardCount)
        try fixture.observeClipboard("new-copy", expected: newer)
        guard case .restored = await controller.undo() else { throw WritingUndoLiveFailure("Safari Undo failed after a newer copy.") }
        try fixture.observe("restored", editor: editor, expected: LiveWritingEditor.original, range: fixture.originalRange)
        try await CursorPaster.settlePendingClipboardRestore()
        try fixture.observeClipboard("clipboard", expected: newer)
        try fixture.check("newerCopySurvivedBothRestorationOwners", true)
        try fixture.finish(["forward", "new-copy", "restored", "clipboard"])
    }

    @Test(.enabled(if: WritingUndoLiveFixture.isEnabled), .timeLimit(.minutes(3)))
    @MainActor func liveWritingUndoRefusesTextCaretAndWindowDrift() async throws {
        let fixture = try WritingUndoLiveFixture(#function)
        defer { fixture.finishIfIncomplete(); fixture.restorePreferences() }
        let editor = try await LiveWritingEditor.open(.textEdit)
        defer { editor.close() }
        let controller = WritingActionUndoController()
        let replacement = "Drift target e\u{301} 😀"
        try await editor.selectOriginalPassage()
        try await fixture.deliver(replacement, to: editor, controller: controller)
        try fixture.observe("caret-forward", editor: editor, expected: fixture.result(replacement), range: fixture.caret(replacement))
        let changedRange = NSRange(location: 0, length: 1)
        try await editor.select(changedRange)
        try fixture.requireRefused(await controller.undo())
        try fixture.observe("caret-refused", editor: editor, expected: fixture.result(replacement), range: changedRange)
        try await fixture.reset(editor)
        try await fixture.deliver(replacement, to: editor, controller: controller)
        try fixture.observe("text-forward", editor: editor, expected: fixture.result(replacement), range: fixture.caret(replacement))
        try await editor.select(NSRange(location: 0, length: 0))
        let userText = "User typed 🧪 "
        try editor.replaceSelection(userText)
        let changedValue = userText + fixture.result(replacement)
        try await editor.waitForValue(changedValue)
        try fixture.requireRefused(await controller.undo())
        try fixture.observe("text-refused", editor: editor, expected: changedValue, range: NSRange(location: userText.utf16.count, length: 0))
        try await fixture.reset(editor)
        try await fixture.deliver(replacement, to: editor, controller: controller)
        try fixture.observe("window-forward", editor: editor, expected: fixture.result(replacement), range: fixture.caret(replacement))
        let other = try await LiveWritingEditor.open(.textEdit)
        defer { other.close() }
        try await other.selectOriginalPassage()
        try fixture.check("sameProcessDifferentWindow", editor.application.isEqual(other.application) && !CFEqual(editor.window, other.window))
        try fixture.requireRefused(await controller.undo())
        try #require(other.value?.utf16.elementsEqual(LiveWritingEditor.original.utf16) == true)
        try fixture.observe("window-refused", editor: editor, expected: fixture.result(replacement), range: fixture.caret(replacement), focused: false)
        try fixture.check("driftNeverRetargetedOrMutated", !controller.isAvailable)
        try fixture.finish(["caret-forward", "caret-refused", "text-forward", "text-refused", "window-forward", "window-refused"])
    }

    @Test(.enabled(if: WritingUndoLiveFixture.isEnabled), .timeLimit(.minutes(3)))
    @MainActor func liveWritingUndoLatestOwnerAndCancellation() async throws {
        let fixture = try WritingUndoLiveFixture(#function)
        defer { fixture.finishIfIncomplete(); fixture.restorePreferences() }
        let editor = try await LiveWritingEditor.open(.safari)
        defer { editor.close() }
        let controller = WritingActionUndoController()
        fixture.setRestore(true)
        try await editor.selectOriginalPassage()
        let first = "first rewrite 😀"
        try await fixture.deliver(first, to: editor, controller: controller)
        try fixture.observe("first-forward", editor: editor, expected: fixture.result(first), range: fixture.caret(first))
        try await CursorPaster.settlePendingClipboardRestore()
        let firstRange = NSRange(location: LiveWritingEditor.prefix.utf16.count, length: first.utf16.count)
        try await editor.select(firstRange)
        let second = "second, longer e\u{301} 👩🏽‍💻"
        try await fixture.deliver(second, to: editor, controller: controller)
        try fixture.observe("second-forward", editor: editor, expected: fixture.result(second), range: fixture.caret(second))
        let pendingLeaseStarted = ProcessInfo.processInfo.systemUptime
        var oldUndoFinished = false
        let oldUndo = Task { @MainActor in
            let outcome = await controller.undo()
            oldUndoFinished = true
            return outcome
        }
        defer { oldUndo.cancel() }
        try await fixture.wait("The Undo operation did not become busy.") { controller.isBusy || oldUndoFinished }
        try await Task.sleep(nanoseconds: 50_000_000)
        try #require(controller.isBusy && !oldUndoFinished, "The expected forward restoration lease did not hold Undo.")
        let pending = controller.beginDelivery(transcriptionID: UUID())
        let canceled = await oldUndo.value
        try fixture.requireRefused(canceled)
        try fixture.check("newPendingDeliveryOwnsBusyState", controller.isBusy && controller.isCurrentDelivery(pending))
        controller.finishDelivery(.notAttempted(CancellationError()), for: pending)
        try fixture.observe("canceled-before-attempt", editor: editor, expected: fixture.result(second), range: fixture.caret(second))
        try fixture.check("leaseOverlapPreservedPreviousCapability", controller.isAvailable)
        fixture.extra["leaseOverlapElapsedSeconds"] = ProcessInfo.processInfo.systemUptime - pendingLeaseStarted
        fixture.extra["leaseOverlapBoundary"] = "Undo requested while real Safari forward clipboard lease remained pending; private settler entry was not instrumented."
        guard case .restored = await controller.undo() else { throw WritingUndoLiveFailure("Latest Undo did not restore the first rewrite.") }
        try fixture.observe("latest-restored", editor: editor, expected: fixture.result(first), range: firstRange)
        guard case .unavailable = await controller.undo() else { throw WritingUndoLiveFailure("Earlier rewrite authority survived the latest Undo.") }
        try fixture.observe("second-undo-refused", editor: editor, expected: fixture.result(first), range: firstRange)
        try await CursorPaster.settlePendingClipboardRestore()
        try fixture.check("onlyLatestRewriteWasUndoable", true)
        try fixture.finish(["first-forward", "second-forward", "canceled-before-attempt", "latest-restored", "second-undo-refused"])
    }
}

private struct WritingUndoLiveFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

private struct WritingUndoLiveClipboardItem: Equatable {
    struct Representation: Equatable { let type: String; let data: Data }
    let representations: [Representation]
    var json: [[String: Any]] { representations.map { ["type": $0.type, "dataBase64": $0.data.base64EncodedString()] } }
}

@MainActor
private final class WritingUndoLiveFixture {
    nonisolated static var isEnabled: Bool {
        value("RJT_WRITING_UNDO_LIVE_CHECKS") == "1" && value("GITHUB_ACTIONS") == "true"
    }
    private nonisolated static func value(_ key: String) -> String? {
        let environment = ProcessInfo.processInfo.environment
        return environment[key] ?? environment["TEST_RUNNER_" + key]
    }
    let caseName: String
    private let output: URL
    private let domain: String
    private let previous: [String: Any]
    private var observations: [[String: Any]] = []
    private var checks: [String: Bool] = [:]
    private var written = false
    var extra: [String: Any] = [:]
    var originalRange: NSRange { NSRange(location: LiveWritingEditor.prefix.utf16.count, length: LiveWritingEditor.passage.utf16.count) }

    init(_ function: String) throws {
        #if !LOCAL_BUILD
        throw WritingUndoLiveFailure("Native Undo checks require the disposable LOCAL_BUILD host.")
        #else
        guard Self.isEnabled, Self.value("RUNNER_ENVIRONMENT") == "github-hosted",
              LiveWritingEditor.isEnabled,
              let root = Self.value("RJT_WRITING_UNDO_EVIDENCE"), root.hasPrefix("/"),
              let temporary = Self.value("RUNNER_TEMP"), temporary.hasPrefix("/"),
              let identifier = Bundle.main.bundleIdentifier else {
            throw WritingUndoLiveFailure("Native Undo checks require explicit disposable-host inputs.")
        }
        caseName = String(function.prefix { $0 != "(" })
        output = URL(fileURLWithPath: root, isDirectory: true).resolvingSymlinksInPath()
        try #require(output.path.hasPrefix(URL(fileURLWithPath: temporary).resolvingSymlinksInPath().path + "/"))
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        domain = identifier
        previous = UserDefaults.standard.persistentDomain(forName: identifier) ?? [:]
        let arguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        try #require(arguments[VoiceInkPastePreference.restoreClipboardAfterPasteKey] == nil)
        try #require(arguments[VoiceInkPastePreference.clipboardRestoreDelayKey] == nil)
        VoiceInkPastePreference.saveClipboardRestoreDelay(2)
        #endif
    }

    func restorePreferences() {
        for key in [VoiceInkPastePreference.restoreClipboardAfterPasteKey, VoiceInkPastePreference.clipboardRestoreDelayKey] {
            if let value = previous[key] { UserDefaults.standard.set(value, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        UserDefaults.standard.synchronize()
    }
    func setRestore(_ value: Bool) { VoiceInkPastePreference.saveShouldRestoreClipboardAfterPaste(value) }
    func result(_ text: String) -> String { LiveWritingEditor.prefix + text + LiveWritingEditor.suffix }
    func caret(_ text: String) -> NSRange { NSRange(location: LiveWritingEditor.prefix.utf16.count + text.utf16.count, length: 0) }

    func deliver(_ text: String, to editor: LiveWritingEditor, controller: WritingActionUndoController) async throws {
        recordDeliveryDiagnostic("before-capture", editor: editor, output: text)
        let focused = Self.element(kAXFocusedUIElementAttribute, from: AXUIElementCreateSystemWide())
        try #require(focused.map { CFEqual($0, editor.editor) } == true)
        let usesSystemPaste = CursorTextContextReader.usesSystemPaste(for: editor.editor)
        try check("expectedEditorRoutes", usesSystemPaste == (editor.kind == .safari))
        let target: WritingTarget
        do { target = try WritingTarget.capture(requiresSelection: true) }
        catch {
            recordDeliveryDiagnostic("capture-failed", editor: editor, output: text, failure: error)
            throw error
        }
        let id = controller.beginDelivery(transcriptionID: UUID())
        var attempts = 0
        var confirmations = 0
        let outcome = await target.deliver(
            with: text,
            willAttempt: { attempts += 1; try controller.willAttemptDelivery(id) },
            onConfirmed: { edit in confirmations += 1; controller.confirmedDelivery(edit, for: id) }
        )
        controller.finishDelivery(outcome, for: id)
        extra["latestForwardAttempts"] = attempts
        extra["latestForwardConfirmations"] = confirmations
        recordDeliveryDiagnostic("after-delivery", editor: editor, output: text, outcome: outcome,
                                 attempts: attempts, confirmations: confirmations)
        try #require(outcome.isConfirmed && attempts == 1 && confirmations == 1)
        try #require(controller.isAvailable, "Native output was confirmed without a coherent Undo receipt.")
        try await editor.waitForValue(result(text))
    }

    private func recordDeliveryDiagnostic(
        _ phase: String, editor: LiveWritingEditor, output: String,
        outcome: WritingTarget.DeliveryOutcome? = nil, attempts: Int = 0,
        confirmations: Int = 0, failure: Error? = nil
    ) {
        let application = AXUIElementCreateApplication(editor.application.processIdentifier)
        let system = AXUIElementCreateSystemWide()
        let windows = Self.diagnosticAttribute(kAXWindowsAttribute, from: application)
        let title = Self.diagnosticAttribute(kAXTitleAttribute, from: editor.window)
        let document = Self.diagnosticAttribute(kAXDocumentAttribute, from: editor.window)
        let editorWindow = Self.diagnosticAttribute(kAXWindowAttribute, from: editor.editor)
        let globalFocus = Self.diagnosticAttribute(kAXFocusedUIElementAttribute, from: system)
        let appFocus = Self.diagnosticAttribute(kAXFocusedUIElementAttribute, from: application)
        let focusedWindow = Self.diagnosticAttribute(kAXFocusedWindowAttribute, from: application)
        let documentURL = (document.value as? URL) ?? (document.value as? String).flatMap(URL.init(string:))
        let ownedDocument = documentURL.map { $0.isFileURL && $0.standardizedFileURL == editor.resource.standardizedFileURL } == true
        let tokenTitle = (title.value as? String)?.contains(editor.token) == true
        let windowPresent = (windows.value as? [AXUIElement])?.contains { CFEqual($0, editor.window) } == true
        let sameWindow = Self.diagnosticElement(editorWindow.value).map { CFEqual($0, editor.window) } == true
        let sameApplication = !editor.application.isTerminated && NSRunningApplication(processIdentifier: editor.application.processIdentifier)
            .map { editor.application.isEqual($0) } == true
        let owned = sameApplication && windowPresent && sameWindow && (tokenTitle || ownedDocument)
        let value = Self.diagnosticAttribute(kAXValueAttribute, from: editor.editor)
        let range = Self.diagnosticAttribute(kAXSelectedTextRangeAttribute, from: editor.editor)
        let selection = Self.diagnosticAttribute(kAXSelectedTextAttribute, from: editor.editor)
        var selectedRange = CFRange()
        let rangeDecoded = range.value.map {
            CFGetTypeID($0) == AXValueGetTypeID() && AXValueGetValue($0 as! AXValue, .cfRange, &selectedRange)
        } == true
        var receipt: [String: Any] = [
            "phase": phase, "uptime": ProcessInfo.processInfo.systemUptime,
            "pid": Int(editor.application.processIdentifier), "token": editor.token,
            "bundleIdentifier": editor.kind.bundleIdentifier, "applicationTerminated": editor.application.isTerminated,
            "currentApplicationInstanceMatches": sameApplication,
            "frontmostPID": Int(NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1),
            "sameFrontmostApplication": NSWorkspace.shared.frontmostApplication.map { editor.application.isEqual($0) } == true,
            "windowPresent": windowPresent, "sameEditorWindow": sameWindow,
            "tokenWindowTitle": tokenTitle, "ownedDocumentURL": ownedDocument, "ownsRetainedSurface": owned,
            "sameGlobalFocusedEditor": Self.diagnosticElement(globalFocus.value).map { CFEqual($0, editor.editor) } == true,
            "globalFocusedElementReturned": globalFocus.value != nil,
            "globalFocusIsAXElement": Self.diagnosticElement(globalFocus.value) != nil,
            "sameApplicationFocusedEditor": Self.diagnosticElement(appFocus.value).map { CFEqual($0, editor.editor) } == true,
            "sameFocusedWindow": Self.diagnosticElement(focusedWindow.value).map { CFEqual($0, editor.window) } == true,
            "AXErrors": ["windows": windows.error, "windowTitle": title.error, "documentURL": document.error,
                "editorWindow": editorWindow.error, "globalFocusedElement": globalFocus.error,
                "applicationFocusedElement": appFocus.error, "focusedWindow": focusedWindow.error,
                "value": value.error, "selectedRange": range.error, "selectedText": selection.error],
            "observedUTF16": owned ? (value.value as? String).map { Array($0.utf16).map(Int.init) } as Any? ?? NSNull() : NSNull(),
            "selectedUTF16": owned ? (selection.value as? String).map { Array($0.utf16).map(Int.init) } as Any? ?? NSNull() : NSNull(),
            "range": owned && rangeDecoded ? ["location": selectedRange.location, "length": selectedRange.length] as Any : NSNull(),
            "outputUTF16": Array(output.utf16).map(Int.init),
            "expectedFullUTF16": Array(result(output).utf16).map(Int.init),
            "clipboardChangeCount": NSPasteboard.general.changeCount,
            "usesSystemPaste": CursorTextContextReader.usesSystemPaste(for: editor.editor),
            "attemptCallbacks": attempts, "confirmationCallbacks": confirmations,
            "nativeAttemptResult": "AXPress result is not exposed by the product delivery API; no native result inferred from callback counts.",
            "snapshotScope": "Independent AX reads of the retained surface using existing timeout policy; no atomic snapshot or delivery-time focus stability claim."
        ]
        if let outcome {
            switch outcome {
            case .notAttempted: receipt["outcome"] = "notAttempted"
            case .attemptedUnconfirmed: receipt["outcome"] = "attemptedUnconfirmed"
            case .confirmed(let edit):
                receipt["outcome"] = "confirmed"
                receipt["undoReceiptPresent"] = edit != nil
            }
        }
        if let error = failure ?? outcome?.failure {
            receipt["failure"] = ["type": String(reflecting: type(of: error)),
                "description": String(describing: error), "localizedDescription": error.localizedDescription,
                "domain": (error as NSError).domain, "code": (error as NSError).code]
        }
        var diagnostics = extra["deliveryDiagnostics"] as? [[String: Any]] ?? []
        diagnostics.append(receipt)
        extra["deliveryDiagnostics"] = diagnostics
    }

    private static func diagnosticAttribute(_ name: String, from owner: AXUIElement) -> (value: CFTypeRef?, error: Int) {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(owner, name as CFString, &value)
        return (error == .success ? value : nil, Int(error.rawValue))
    }

    private static func diagnosticElement(_ value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    func reset(_ editor: LiveWritingEditor) async throws {
        let current = try #require(editor.value)
        try await editor.select(NSRange(location: 0, length: current.utf16.count))
        try editor.replaceSelection(LiveWritingEditor.original)
        try await editor.waitForValue(LiveWritingEditor.original)
        try await editor.selectOriginalPassage()
    }

    func requireRefused(_ outcome: WritingTarget.UndoOutcome) throws {
        guard case .notAttempted = outcome else { throw WritingUndoLiveFailure("Expected a pre-attempt Undo refusal.") }
    }

    func observe(_ name: String, editor: LiveWritingEditor, expected: String, range: NSRange, focused: Bool = true) throws {
        let observed = try #require(editor.value)
        let actualRange = try #require(editor.selectedRange)
        let sameProcess = NSWorkspace.shared.frontmostApplication.map { editor.application.isEqual($0) } == true
        let current = Self.element(kAXFocusedUIElementAttribute, from: AXUIElementCreateSystemWide())
        let sameEditor = current.map { CFEqual($0, editor.editor) } == true
        let sameWindow = Self.element(kAXWindowAttribute, from: editor.editor).map { CFEqual($0, editor.window) } == true
        let windows = try #require(Self.windows(of: editor.application))
        let windowPresent = windows.contains { CFEqual($0, editor.window) }
        let usesSystemPaste = CursorTextContextReader.usesSystemPaste(for: editor.editor)
        stage(name, ["pid": Int(editor.application.processIdentifier), "bundleIdentifier": editor.kind.bundleIdentifier,
            "token": editor.token, "sourceUTF16": Array(LiveWritingEditor.original.utf16).map(Int.init),
            "expectedUTF16": Array(expected.utf16).map(Int.init), "observedUTF16": Array(observed.utf16).map(Int.init),
            "expectedRange": Self.range(range), "range": Self.range(actualRange), "sameProcess": sameProcess,
            "sameFocusedEditor": sameEditor, "sameWindow": sameWindow, "windowPresent": windowPresent,
            "expectsFocused": focused, "usesSystemPaste": usesSystemPaste,
            "expectedUsesSystemPaste": editor.kind == .safari])
        editor.recordOperationFailure("undo-" + name, expected: expected)
        try #require(observed.utf16.elementsEqual(expected.utf16))
        try #require(actualRange == range)
        try #require(sameWindow && windowPresent)
        try #require(usesSystemPaste == (editor.kind == .safari))
        try #require(focused ? sameProcess && sameEditor : !sameEditor)
    }

    func writeClipboard(_ text: String, discriminator: String) throws -> [WritingUndoLiveClipboardItem] {
        let binaryType = NSPasteboard.PasteboardType("com.negentropi.undo-native.binary")
        let secondType = NSPasteboard.PasteboardType("com.negentropi.undo-native.second")
        let binary = Data([0, 255, 12, 0, 128])
        let expected = [
            WritingUndoLiveClipboardItem(representations: [
                .init(type: NSPasteboard.PasteboardType.string.rawValue, data: Data(text.utf8)),
                .init(type: binaryType.rawValue, data: binary)
            ].sorted { $0.type < $1.type }),
            WritingUndoLiveClipboardItem(representations: [.init(type: secondType.rawValue, data: Data(discriminator.utf8))])
        ]
        let first = NSPasteboardItem()
        try #require(first.setData(Data(text.utf8), forType: .string))
        try #require(first.setData(binary, forType: binaryType))
        let second = NSPasteboardItem()
        try #require(second.setData(Data(discriminator.utf8), forType: secondType))
        NSPasteboard.general.clearContents()
        try #require(NSPasteboard.general.writeObjects([first, second]))
        try #require(Self.clipboardSnapshot() == expected, "Clipboard setup lost an item or seeded representation.")
        return expected
    }

    func observeClipboard(_ name: String, expected: [WritingUndoLiveClipboardItem]) throws {
        let before = NSPasteboard.general.changeCount
        let observed = try Self.clipboardSnapshot()
        let after = NSPasteboard.general.changeCount
        stage(name, ["clipboardExpected": expected.map { ["types": $0.json] },
            "clipboardObserved": observed.map { ["types": $0.json] }, "readBeforeCount": before, "readAfterCount": after])
        try #require(before == after && observed == expected)
    }

    func stage(_ name: String, _ values: [String: Any]) {
        var observation = values
        observation["name"] = name
        observation["uptime"] = ProcessInfo.processInfo.systemUptime
        observations.append(observation)
    }
    func check(_ key: String, _ value: Bool) throws { checks[key] = value; try #require(value) }

    func finish(_ requiredStages: Set<String>) throws {
        let names = observations.compactMap { $0["name"] as? String }
        checks["completedStages"] = Set(names) == requiredStages && names.count == requiredStages.count
        checks["exactTextObservations"] = observations.allSatisfy {
            guard let expected = $0["expectedUTF16"] as? [Int] else { return true }
            return expected == $0["observedUTF16"] as? [Int]
        }
        checks["exactRangeObservations"] = observations.allSatisfy {
            guard let expected = $0["expectedRange"] as? [String: Int] else { return true }
            return expected == $0["range"] as? [String: Int]
        }
        try #require(checks.values.allSatisfy { $0 })
        try write(completed: true)
    }
    func finishIfIncomplete() { if !written { try? write(completed: false) } }

    func wait(_ message: String, until predicate: () -> Bool) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 8
        while !predicate() {
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw WritingUndoLiveFailure(message) }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
    }

    static func windows(of application: NSRunningApplication) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(application.processIdentifier), kAXWindowsAttribute as CFString, &value) == .success else { return nil }
        return value as? [AXUIElement]
    }
    private static func element(_ attribute: String, from owner: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(owner, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
    private static func range(_ value: NSRange) -> [String: Int] { ["location": value.location, "length": value.length] }
    private static func clipboardSnapshot() throws -> [WritingUndoLiveClipboardItem] {
        let board = NSPasteboard.general
        let before = board.changeCount
        let items = try (board.pasteboardItems ?? []).map { item in
            WritingUndoLiveClipboardItem(representations: try item.types.sorted { $0.rawValue < $1.rawValue }.map { type in
                WritingUndoLiveClipboardItem.Representation(type: type.rawValue, data: try #require(item.data(forType: type)))
            })
        }
        try #require(board.changeCount == before, "Clipboard changed during materialization.")
        return items
    }
    private func write(completed: Bool) throws {
        let payload: [String: Any] = ["schemaVersion": 1, "caseName": caseName, "completed": completed,
            "hostPID": Int(ProcessInfo.processInfo.processIdentifier),
            "hostExecutablePath": Bundle.main.executableURL?.path ?? "<unavailable>",
            "observations": observations, "checks": checks, "extra": extra,
            "runtimeBounds": ["controllerAPI": true, "productMenuOrShortcut": false, "syntheticProvider": false, "ASR": false,
                              "clipboardBaseline": "Dedicated disposable runner pasteboard; no shared user clipboard. Test payloads left for host disposal."]]
        let pending = output.appendingPathComponent(caseName + ".pending-" + UUID().uuidString)
        try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            .write(to: pending, options: .withoutOverwriting)
        try FileManager.default.moveItem(at: pending, to: output.appendingPathComponent(caseName + ".json"))
        written = true
    }
}
