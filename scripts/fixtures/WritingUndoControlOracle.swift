import AppKit
import Carbon.HIToolbox
import Darwin
import Foundation
import VoiceInkCore

// Test-only companion to WritingUndoControlHost. The remote driver compiles the
// existing LiveWritingEditor helper unchanged; its cleanup failures remain fatal.
@MainActor
enum Issue {
    static var messages: [String] = []
    static func record(_ message: String) { messages.append(message) }
}

private struct UndoControlCheckFailure: Error, CustomStringConvertible {
    let description: String
    init(_ message: String) { description = message }
}

@MainActor
enum WritingUndoControlOracle {
    static func run(owner: WritingUndoControlHostOwner) async {
        // Diagnostic breadcrumbs only (see WritingUndoControlHostProgress). A failed record before
        // `execute` is latched and fails the first `record` inside it, so it reaches `finish` below.
        WritingUndoControlHostProgress.recordDeferringFailure("oracle.run.entry")
        WritingUndoControlHostProgress.recordDeferringFailure("oracle.check-init.before")
        let check = Check(owner: owner)
        WritingUndoControlHostProgress.recordDeferringFailure("oracle.check-init.after")
        do {
            try await check.execute()
            try WritingUndoControlHostProgress.record("oracle.finish-success.before")
            try check.finish(completed: true, failure: nil)
            try WritingUndoControlHostProgress.record("oracle.finish-success.after")
            Darwin.exit(0)
        } catch {
            // The original reason reaches stderr before any AX work, so a stalled failure dump stays diagnosable.
            // Breadcrumb or secondary evidence failures here are reported and never replace this error.
            fputs("Undo control check failing; collecting failure evidence: \(error)\n", stderr)
            WritingUndoControlHostProgress.recordDeferringFailure("oracle.catch.entry")
            WritingUndoControlHostProgress.recordDeferringFailure("oracle.catch.hierarchy.before")
            do { try check.dumpHierarchy("failure") }
            catch let secondary { fputs("Undo control failure hierarchy not written: \(secondary)\n", stderr) }
            WritingUndoControlHostProgress.recordDeferringFailure("oracle.catch.hierarchy.after")
            WritingUndoControlHostProgress.recordDeferringFailure("oracle.catch.screenshot.before")
            do { try await check.screenshot("failure") }
            catch let secondary { fputs("Undo control failure screenshot not written: \(secondary)\n", stderr) }
            WritingUndoControlHostProgress.recordDeferringFailure("oracle.catch.screenshot.after")
            WritingUndoControlHostProgress.recordDeferringFailure("oracle.catch.finish.before")
            do { try check.finish(completed: false, failure: String(describing: error)) }
            catch let secondary { fputs("Undo control failure result not written: \(secondary)\n", stderr) }
            WritingUndoControlHostProgress.recordDeferringFailure("oracle.catch.finish.after")
            fputs("Undo control check failed: \(error)\n", stderr)
            Darwin.exit(1)
        }
    }

    @MainActor
    private final class Check {
        let owner: WritingUndoControlHostOwner
        let app = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        let selectedCases = ["textedit-menu", "textedit-shortcut", "safari-menu", "safari-shortcut"]
        var cases: [[String: Any]] = []
        var states: [String: Any] = [:]
        var shortcut: [String: Any] = [:]
        var pastePreferences: [String: Any] = [:]
        var policyBootstrap: [String: Any] = [:]
        let keyCode = UInt16(kVK_ANSI_U)
        let modifiers: NSEvent.ModifierFlags = [.command, .option, .control]
        let originalRange = NSRange(location: LiveWritingEditor.prefix.utf16.count,
                                    length: LiveWritingEditor.passage.utf16.count)

        init(owner: WritingUndoControlHostOwner) { self.owner = owner }

        /// Diagnostic breadcrumb naming the step about to start; the next mark proves that step returned.
        func mark(_ stage: String) throws { try WritingUndoControlHostProgress.record(stage) }

        func execute() async throws {
            // One fixed before/after pair per permission check: a missing ".after"
            // names the exact permission that blocked the run.
            try mark("execute.preflight.before")
            try mark("execute.preflight.accessibility.before")
            try require(AXIsProcessTrusted(), "The exact signed host lacks Accessibility access.")
            try mark("execute.preflight.accessibility.after")
            try mark("execute.preflight.listen-event.before")
            try require(CGPreflightListenEventAccess(), "The exact signed host lacks Input Monitoring access.")
            try mark("execute.preflight.listen-event.after")
            try mark("execute.preflight.post-event.before")
            try require(CGPreflightPostEventAccess(), "The exact signed host cannot post native keyboard events.")
            try mark("execute.preflight.post-event.after")
            try mark("execute.preflight.screen-capture.before")
            try require(CGPreflightScreenCaptureAccess(), "The exact signed host lacks Screen Recording access.")
            try mark("execute.preflight.screen-capture.after")
            try mark("execute.preflight.after")
            let argumentDomain = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
            let pasteKeys = [VoiceInkPastePreference.restoreClipboardAfterPasteKey, VoiceInkPastePreference.clipboardRestoreDelayKey]
            let hasArgumentOverrides = pasteKeys.contains { argumentDomain[$0] != nil }
            let bundleID = Bundle.main.bundleIdentifier ?? ""
            let expectedHome = ProcessInfo.processInfo.environment["CFFIXED_USER_HOME"] ?? ""
            try require(bundleID == "com.negentropi.RomaJustTalk" && expectedHome.hasPrefix("/") && !hasArgumentOverrides,
                        "The controlled preference input requires the exact host and no policy launch overrides.")
            try mark("policy.snapshot-before.before")
            let before = policySnapshot(bundleID: bundleID)
            try mark("policy.snapshot-before.after")
            // Configure test-owned inputs through the same public preference APIs
            // as Settings. A plist placed by another process is not the oracle.
            try mark("policy.public-writes.before")
            VoiceInkPastePreference.saveShouldRestoreClipboardAfterPaste(VoiceInkPastePreference.defaultRestoreClipboardAfterPaste)
            VoiceInkPastePreference.saveClipboardRestoreDelay(VoiceInkPastePreference.defaultClipboardRestoreDelay)
            let synchronized = UserDefaults.standard.synchronize()
            try mark("policy.public-writes.after")
            try mark("policy.snapshot-after.before")
            let after = policySnapshot(bundleID: bundleID)
            try mark("policy.snapshot-after.after")
            policyBootstrap = ["bundleIdentifier": bundleID, "expectedUserHome": expectedHome,
                               "observedUserHome": NSHomeDirectory(),
                               "homeMatchesExpected": URL(fileURLWithPath: NSHomeDirectory()).standardizedFileURL
                                   == URL(fileURLWithPath: expectedHome).standardizedFileURL,
                               "publicPreferenceAPIsUsed": true, "synchronizeSucceeded": synchronized,
                               "hasArgumentOverrides": hasArgumentOverrides, "before": before, "after": after]
            let restore = VoiceInkPastePreference.shouldRestoreClipboardAfterPaste()
            let delay = VoiceInkPastePreference.clipboardRestoreDelay()
            pastePreferences = ["restoreClipboardAfterPaste": restore, "clipboardRestoreDelay": delay,
                                "hasArgumentOverrides": hasArgumentOverrides]
            try require(restore && delay == 2 && !hasArgumentOverrides,
                        "The controls check requires the actual persistent default clipboard restoration policy.")
            let persistent = after["persistent"] as? [String: Any]
            let storedRestore = persistent?[VoiceInkPastePreference.restoreClipboardAfterPasteKey] as? [String: Any]
            let storedDelay = persistent?[VoiceInkPastePreference.clipboardRestoreDelayKey] as? [String: Any]
            try require(synchronized && storedRestore?["type"] as? String == "boolean"
                        && storedRestore?["value"] as? Bool == true && storedDelay?["type"] as? String == "number"
                        && storedDelay?["value"] as? Double == 2,
                        "The public preference APIs did not confirm the persistent clipboard policy.")
            try require(!owner.engine.writingActionUndoController.isAvailable, "A fresh engine already owns an edit.")
            let unavailable = try await openMenu(expectedEnabled: false, checkpoint: "unavailable-menu")
            try mark("unavailable.dismiss-menu.before")
            try await dismissMenu()
            try mark("unavailable.dismiss-menu.after")
            states["unavailable"] = ["passed": true, "menu": unavailable]
            try await configureShortcut()

            for (index, id) in selectedCases.enumerated() {
                try await successCase(id, kind: index < 2 ? .textEdit : .safari)
            }
            try await focusRefusal()
            try require(Issue.messages.isEmpty, "The editor helper reported a failure: \(Issue.messages)")
            try mark("execute.exit")
        }

        func configureShortcut() async throws {
            try mark("shortcut.window-wait.before")
            try await wait("The fixture setup window did not appear.") {
                NSApp.windows.contains { $0.title == "RJT Undo control check" && $0.isVisible }
            }
            guard let window = NSApp.windows.first(where: { $0.title == "RJT Undo control check" }) else {
                throw UndoControlCheckFailure("Missing fixture setup window.")
            }
            try mark("shortcut.activate.before")
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            try mark("shortcut.active-wait.before")
            try await wait("The setup window did not become active.") { NSApp.isActive && window.isKeyWindow }
            try mark("shortcut.recorder-lookup.before")
            let recorder = try await unique(identifier: "shortcutRecorder.undoLastWritingEdit")
            try mark("shortcut.recorder-describe.before")
            let control = try describe(recorder, "shortcut.recorder")
            try mark("shortcut.recorder-press.before")
            let recorderClick = try click(recorder, "shortcut.recorder", roles: ["AXButton"],
                                          identifier: "shortcutRecorder.undoLastWritingEdit")
            try mark("shortcut.clear-wait.before")
            try await wait("The real recorder did not clear its shortcut for capture.") {
                ShortcutStore.isShortcutCleared(for: .undoLastWritingEdit)
            }
            try mark("shortcut.chord-post.before")
            try postChord()
            let expected = Shortcut.key(keyCode: keyCode, modifierFlags: modifiers)
            try mark("shortcut.save-wait.before")
            try await wait("The real recorder did not save the exact captured chord.") {
                ShortcutStore.shortcut(for: .undoLastWritingEdit) == expected
            }
            // A subsequent global chord must reach the registered event tap, not
            // the setup recorder's local capture monitor.
            try mark("shortcut.display-wait.before")
            try await wait("The shortcut recorder stayed in capture mode.") {
                self.string(kAXDescriptionAttribute, recorder) == expected.displayString
                    || self.string(kAXTitleAttribute, recorder) == expected.displayString
                    || self.string(kAXHelpAttribute, recorder) == expected.displayString
            }
            shortcut = ["recordedViaActualRecorder": true, "keyCode": Int(keyCode),
                        "modifierFlagsRawValue": modifiers.rawValue, "displayString": expected.displayString,
                        "recorderControl": control.merging(["click": recorderClick]) { _, new in new }]
            try mark("shortcut.screenshot.before")
            try await screenshot("shortcut-configured")
            try mark("shortcut.hierarchy.before")
            try dumpHierarchy("shortcut-configured")
            try mark("shortcut.exit")
        }

        func policySnapshot(bundleID: String) -> [String: Any] {
            let defaults = UserDefaults.standard
            let persistent = defaults.persistentDomain(forName: bundleID) ?? [:]
            let registered = defaults.volatileDomain(forName: UserDefaults.registrationDomain)
            let keys = [VoiceInkPastePreference.restoreClipboardAfterPasteKey, VoiceInkPastePreference.clipboardRestoreDelayKey]
            func typed(_ raw: Any?) -> [String: Any] {
                guard let raw else { return ["type": "missing"] }
                guard let number = raw as? NSNumber else { return ["type": "unsupported"] }
                if CFGetTypeID(number) == CFBooleanGetTypeID() { return ["type": "boolean", "value": number.boolValue] }
                return number.doubleValue.isFinite ? ["type": "number", "value": number.doubleValue] : ["type": "nonfinite"]
            }
            return ["effective": ["restoreClipboardAfterPaste": VoiceInkPastePreference.shouldRestoreClipboardAfterPaste(),
                                  "clipboardRestoreDelay": VoiceInkPastePreference.clipboardRestoreDelay()],
                    "persistent": Dictionary(uniqueKeysWithValues: keys.map { ($0, typed(persistent[$0])) }),
                    "registered": Dictionary(uniqueKeysWithValues: keys.map { ($0, typed(registered[$0])) })]
        }

        func successCase(_ id: String, kind: LiveWritingEditor.Kind) async throws {
            // Native run 40615667402 requested NFD "e\u{301}" in Safari and read back
            // NFC "\u{e9}" through AX after delivery. That run does not show where the
            // change happened (clipboard, editor, DOM, storage or AX). Safari positive
            // controls therefore use explicit NFC fixture text. TextEdit keeps the
            // default NFD source and output. Editor reads and receipts are never
            // normalized; all checks stay UTF-16 exact.
            let isShortcut = id.contains("shortcut")
            let replacement: String
            try mark("case.\(id).editor-open.before")
            let editor: LiveWritingEditor
            if kind == .safari {
                editor = try await LiveWritingEditor.open(kind, passage: "target \u{e9}")
                replacement = isShortcut ? "Short \u{e9} 😀" : "Longer 👩🏽‍💻 \u{e9}\nRJT, 台灣, 🧑‍🚀."
            } else {
                editor = try await LiveWritingEditor.open(kind)
                replacement = isShortcut ? "Short e\u{301} 😀" : "Longer 👩🏽‍💻 e\u{301}\nRJT, 台灣, 🧑‍🚀."
            }
            defer {
                WritingUndoControlHostProgress.recordDeferringFailure("case.\(id).editor-close.before")
                editor.close()
                WritingUndoControlHostProgress.recordDeferringFailure("case.\(id).editor-close.after")
            }
            try mark("case.\(id).select.before")
            try await editor.selectOriginalPassage()
            try mark("case.\(id).before-snapshot.before")
            let sourceOriginal = editor.sourceOriginal
            let sourceRange = editor.sourceRange
            let before = try snapshot(editor)
            try expect(before, value: sourceOriginal, range: sourceRange)
            let result = LiveWritingEditor.prefix + replacement + LiveWritingEditor.suffix
            let caret = NSRange(location: LiveWritingEditor.prefix.utf16.count + replacement.utf16.count, length: 0)
            try mark("case.\(id).deliver.before")
            let counts = try await deliver(replacement)
            try mark("case.\(id).forward-snapshot.before")
            let forward = try snapshot(editor)
            try expect(forward, value: result, range: caret)
            try require(owner.engine.canUndoLastWritingEdit, "A confirmed native edit did not enable the engine command.")
            try mark("case.\(id).forward-screenshot.before")
            try await screenshot(id + "-forward")
            if id == "textedit-shortcut" { try await busyCheck(editor, result: result, caret: caret) }
            // Each command must produce its own feedback. A prior success has
            // identical copy, so observing that older panel is insufficient.
            try mark("case.\(id).prior-notice-wait.before")
            try await wait("Prior passive feedback did not dismiss.", seconds: 7) {
                self.nodes().allSatisfy {
                    self.string(kAXIdentifierAttribute, $0) != "undoLastWritingEdit.notice" || !self.hasVisibleFrame($0)
                }
            }

            let command: [String: Any]
            if id.hasSuffix("menu") {
                let opened = try await openMenu(expectedEnabled: true, checkpoint: id + "-menu")
                // This is the actual product Button through the native menu
                // bridge. No engine, shared-command or private handler call.
                try mark("case.\(id).menu-command-lookup.before")
                let menuCommand = try await unique(identifier: "undoLastWritingEdit.menuCommand")
                try mark("case.\(id).menu-command-press.before")
                let activationClick = try click(menuCommand, "case.\(id).menu-command", roles: ["AXMenuItem", "AXButton"],
                                                identifier: "undoLastWritingEdit.menuCommand")
                command = opened.merging(["activationClick": activationClick]) { _, new in new }
            } else {
                command = ["kind": "configured-global-shortcut", "keyCode": Int(keyCode),
                           "modifierFlagsRawValue": modifiers.rawValue, "nativeEventsPosted": 2]
                try mark("case.\(id).global-chord.before")
                try postChord()
            }
            try mark("case.\(id).restore-wait.before")
            try await wait("The product control did not restore the original text and selection.", seconds: 12) {
                editor.value?.utf16.elementsEqual(sourceOriginal.utf16) == true
                    && editor.selectedRange == sourceRange
                    && !self.owner.engine.writingActionUndoController.isAvailable
            }
            try mark("case.\(id).notice-wait.before")
            let notice = try await notice(expected: "Restored the original text and selection.")
            // Check focus after the new product panel appears, not merely after
            // the engine changed the text but before feedback was displayed.
            try mark("case.\(id).restored-snapshot.before")
            let restored = try snapshot(editor)
            try expect(restored, value: sourceOriginal, range: sourceRange)
            try mark("case.\(id).restored-screenshot.before")
            try await screenshot(id + "-restored")
            try mark("case.\(id).restored-hierarchy.before")
            try dumpHierarchy(id + "-restored")
            try mark("case.\(id).clipboard-settle.before")
            try await CursorPaster.settlePendingClipboardRestore()
            try require(!owner.engine.writingActionUndoController.isAvailable, "The consumed edit remained available.")
            cases.append(["id": id, "editor": kind == .textEdit ? "textedit" : "safari",
                          "commandKind": id.hasSuffix("menu") ? "menu" : "shortcut",
                          "forwardAttempts": counts.0, "forwardConfirmations": counts.1,
                          "originalUTF16": units(sourceOriginal), "resultUTF16": units(result),
                          "originalRange": range(sourceRange), "before": before, "forward": forward,
                          "restored": restored, "command": command, "notice": notice,
                          "noticeWasAbsentBeforeCommand": true,
                          "capabilityConsumed": true,
                          "screenshots": [id + "-forward.png", id + "-restored.png"]])
            try mark("case.\(id).exit")
        }

        func busyCheck(_ editor: LiveWritingEditor, result: String, caret: NSRange) async throws {
            owner.engine.recordingState = .busy
            defer { owner.engine.recordingState = .idle }
            let menu = try await openMenu(expectedEnabled: false, checkpoint: "busy-menu")
            try mark("busy.dismiss-menu.before")
            try await dismissMenu()
            try mark("busy.global-chord.before")
            try postChord()
            try mark("busy.notice-wait.before")
            let feedback = try await notice(expected: "RJT is busy right now, so Undo didn't replace any text.")
            try mark("busy.snapshot.before")
            let observed = try snapshot(editor)
            try expect(observed, value: result, range: caret)
            try require(owner.engine.writingActionUndoController.isAvailable, "A busy command consumed the native edit.")
            states["busy"] = ["passed": true, "recordingStateFixture": "busy", "menu": menu,
                              "notice": feedback, "observed": observed, "capabilityRetained": true]
            try mark("busy.screenshot.before")
            try await screenshot("busy-shortcut-refused")
            try mark("busy.exit")
        }

        func focusRefusal() async throws {
            try mark("focus.source-open.before")
            let source = try await LiveWritingEditor.open(.textEdit)
            defer {
                WritingUndoControlHostProgress.recordDeferringFailure("focus.source-close.before")
                source.close()
                WritingUndoControlHostProgress.recordDeferringFailure("focus.source-close.after")
            }
            try mark("focus.source-select.before")
            try await source.selectOriginalPassage()
            let replacement = "Source remains e\u{301} 🧪"
            let result = LiveWritingEditor.prefix + replacement + LiveWritingEditor.suffix
            let caret = NSRange(location: LiveWritingEditor.prefix.utf16.count + replacement.utf16.count, length: 0)
            try mark("focus.deliver.before")
            _ = try await deliver(replacement)
            try mark("focus.other-open.before")
            let other = try await LiveWritingEditor.open(.textEdit)
            defer {
                WritingUndoControlHostProgress.recordDeferringFailure("focus.other-close.before")
                other.close()
                WritingUndoControlHostProgress.recordDeferringFailure("focus.other-close.after")
            }
            try mark("focus.other-select.before")
            try await other.selectOriginalPassage()
            try require(!CFEqual(source.window, other.window), "Focus-refusal setup reused the source window.")
            try mark("focus.other-snapshot.before")
            let otherBefore = try snapshot(other)
            try mark("focus.global-chord.before")
            try postChord()
            try mark("focus.notice-wait.before")
            let feedback = try await notice(expected: "The edited field changed or isn't focused, so Undo didn't replace any text.")
            try mark("focus.retire-wait.before")
            try await wait("Focus refusal did not retire stale authority.") {
                !self.owner.engine.writingActionUndoController.isAvailable
            }
            try mark("focus.after-snapshots.before")
            let sourceAfter = try snapshot(source)
            let otherAfter = try snapshot(other)
            try expect(sourceAfter, value: result, range: caret, focused: false)
            try expect(otherBefore, value: LiveWritingEditor.original, range: originalRange)
            try expect(otherAfter, value: LiveWritingEditor.original, range: originalRange)
            states["focusRefusal"] = ["passed": true, "sourceAfter": sourceAfter,
                                      "otherBefore": otherBefore, "otherAfter": otherAfter,
                                      "notice": feedback, "capabilityRetired": true,
                                      "differentWindow": true]
            try mark("focus.screenshot.before")
            try await screenshot("focus-refusal")
            try mark("focus.exit")
        }

        func deliver(_ text: String) async throws -> (Int, Int) {
            try mark("deliver.capture.before")
            let target = try WritingTarget.capture(requiresSelection: true)
            // Marked before beginDelivery so no breadcrumb can interrupt an open delivery.
            try mark("deliver.native-delivery.before")
            let controller = owner.engine.writingActionUndoController
            let id = controller.beginDelivery(transcriptionID: UUID())
            var attempts = 0, confirmations = 0
            let outcome = await target.deliver(with: text, willAttempt: {
                attempts += 1
                try controller.willAttemptDelivery(id)
            }, onConfirmed: { edit in
                confirmations += 1
                controller.confirmedDelivery(edit, for: id)
            })
            controller.finishDelivery(outcome, for: id)
            try mark("deliver.native-delivery.after")
            try require(outcome.isConfirmed && attempts == 1 && confirmations == 1 && controller.isAvailable,
                        "Forward delivery lacked exactly one confirmed native edit receipt.")
            return (attempts, confirmations)
        }

        func openMenu(expectedEnabled: Bool, checkpoint: String) async throws -> [String: Any] {
            try mark("menu.\(checkpoint).status-lookup.before")
            let status = try await waitForElement("The actual status item was unavailable.") { nodes in
                nodes.filter { node in
                    let role = self.string(kAXRoleAttribute, node)
                    return ["AXMenuBarItem", "AXButton"].contains(role ?? "")
                        && (self.string(kAXIdentifierAttribute, node) == "undoControlHost.statusItem"
                            || [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute].contains {
                                self.string($0, node) == "RJT Undo check"
                            })
                }
            }
            try mark("menu.\(checkpoint).status-press.before")
            let statusClick = try click(status, "menu.\(checkpoint).status", roles: ["AXMenuBarItem", "AXButton"],
                                        identifier: "undoControlHost.statusItem", title: "RJT Undo check")
            try mark("menu.\(checkpoint).item-lookup.before")
            let item = try await unique(identifier: "undoLastWritingEdit.menuCommand")
            try mark("menu.\(checkpoint).enabled-wait.before")
            try await wait("The real menu command had the wrong enabled state.") {
                self.hasVisibleFrame(item) && self.enabled(item) == expectedEnabled
            }
            try mark("menu.\(checkpoint).item-describe.before")
            let observed = try describe(item, "menu.\(checkpoint).item")
            try require(["AXMenuItem", "AXButton"].contains(observed["role"] as? String ?? ""),
                        "The Undo identifier did not identify a native actionable control.")
            try mark("menu.\(checkpoint).hierarchy.before")
            try dumpHierarchy(checkpoint)
            try mark("menu.\(checkpoint).screenshot.before")
            try await screenshot(checkpoint)
            try mark("menu.\(checkpoint).status-describe.before")
            let statusControl = try describe(status, "menu.\(checkpoint).status")
            try mark("menu.\(checkpoint).exit")
            return observed.merging(["kind": "product-menu", "statusControl": statusControl,
                                    "statusClick": statusClick]) { _, new in new }
        }

        func dismissMenu() async throws {
            try postKey(UInt16(kVK_Escape), flags: [])
            try await wait("The native status menu did not dismiss.") {
                self.nodes().filter {
                    self.string(kAXIdentifierAttribute, $0) == "undoLastWritingEdit.menuCommand" && self.hasVisibleFrame($0)
                }.isEmpty
            }
        }

        func notice(expected: String) async throws -> [String: Any] {
            let control = try await waitForElement("The real passive result notice was not observed.") { nodes in
                nodes.filter { node in
                    self.string(kAXIdentifierAttribute, node) == "undoLastWritingEdit.notice"
                        && [kAXDescriptionAttribute, kAXTitleAttribute, kAXValueAttribute].contains {
                            self.string($0, node) == expected
                        }
                }
            }
            return try describe(control, "notice").merging(["expectedMessage": expected]) { _, new in new }
        }

        func postChord() throws { try postKey(keyCode, flags: CGEventFlags(rawValue: UInt64(modifiers.rawValue))) }

        func postKey(_ code: UInt16, flags: CGEventFlags) throws {
            for down in [true, false] {
                guard let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down) else {
                    throw UndoControlCheckFailure("Cannot create a native keyboard event.")
                }
                event.flags = flags
                event.post(tap: .cghidEventTap)
            }
        }

        func snapshot(_ editor: LiveWritingEditor) throws -> [String: Any] {
            guard let value = editor.value, let selected = editor.selectedRange else {
                throw UndoControlCheckFailure("The owned editor's exact value or range was unavailable.")
            }
            let focused = element(kAXFocusedUIElementAttribute, AXUIElementCreateSystemWide())
            let window = element(kAXWindowAttribute, editor.editor)
            let windows = attribute(kAXWindowsAttribute, editor.appElement) as? [AXUIElement] ?? []
            return ["valueUTF16": units(value), "range": range(selected),
                    "selectedTextUTF16": units(string(kAXSelectedTextAttribute, editor.editor) ?? ""),
                    "sameProcess": NSWorkspace.shared.frontmostApplication.map { editor.application.isEqual($0) } == true,
                    "sameFocusedEditor": focused.map { CFEqual($0, editor.editor) } == true,
                    "sameWindow": window.map { CFEqual($0, editor.window) } == true,
                    "windowPresent": windows.contains { CFEqual($0, editor.window) },
                    "targetAlive": !editor.application.isTerminated,
                    "usesSystemPaste": CursorTextContextReader.usesSystemPaste(for: editor.editor),
                    "pid": Int(editor.application.processIdentifier), "bundleIdentifier": editor.kind.bundleIdentifier,
                    "token": editor.token]
        }

        func expect(_ snapshot: [String: Any], value: String, range expected: NSRange, focused: Bool = true) throws {
            try require(snapshot["valueUTF16"] as? [Int] == units(value)
                        && snapshot["range"] as? [String: Int] == range(expected), "Exact editor value or range differs.")
            let selected = Array(value.utf16).dropFirst(expected.location).prefix(expected.length).map(Int.init)
            try require(snapshot["selectedTextUTF16"] as? [Int] == selected, "Selected text differs from its exact UTF-16 range.")
            try require(snapshot["sameFocusedEditor"] as? Bool == focused, "The command changed or targeted the wrong focused editor.")
            for key in ["sameWindow", "windowPresent", "targetAlive"] {
                try require(snapshot[key] as? Bool == true, "The captured editor identity changed: \(key).")
            }
            try require(snapshot["usesSystemPaste"] as? Bool == (snapshot["bundleIdentifier"] as? String == "com.apple.Safari"),
                        "The native editor did not use its expected AX or system Paste route.")
            if focused { try require(snapshot["sameProcess"] as? Bool == true, "The command activated another application.") }
        }

        func unique(identifier: String) async throws -> AXUIElement {
            try await waitForElement("Expected one actual control for \(identifier).") {
                $0.filter { self.string(kAXIdentifierAttribute, $0) == identifier }
            }
        }

        func waitForElement(_ message: String, matches: ([AXUIElement]) -> [AXUIElement]) async throws -> AXUIElement {
            var result: AXUIElement?
            try await wait(message) {
                let found = matches(self.nodes()).filter { self.hasVisibleFrame($0) }
                if found.count == 1 { result = found[0]; return true }
                return false
            }
            guard let result else { throw UndoControlCheckFailure(message) }
            return result
        }

        func nodes() -> [AXUIElement] {
            var pending = [app]
            for name in [kAXMenuBarAttribute, "AXExtrasMenuBar"] {
                if let root = element(name, app) { pending.append(root) }
            }
            var seen: [AXUIElement] = []
            let deadline = ProcessInfo.processInfo.systemUptime + 1
            while let node = pending.popLast(), seen.count < 1200, ProcessInfo.processInfo.systemUptime < deadline {
                if seen.contains(where: { CFEqual($0, node) }) { continue }
                _ = AXUIElementSetMessagingTimeout(node, 0.05)
                seen.append(node)
                pending.append(contentsOf: attribute(kAXChildrenAttribute, node) as? [AXUIElement] ?? [])
            }
            return seen
        }

        /// Diagnostic only: each AX read is preceded by its own fixed mark and the final mark proves the last returned.
        func describe(_ node: AXUIElement, _ stage: String) throws -> [String: Any] {
            let s = stage + ".describe"
            var actions: CFArray?
            try mark(s + ".actions")
            let actionError = AXUIElementCopyActionNames(node, &actions)
            var frame: [String: Double] = [:]
            try mark(s + ".position")
            if let raw = attribute(kAXPositionAttribute, node), CFGetTypeID(raw) == AXValueGetTypeID() {
                var point = CGPoint.zero
                if AXValueGetValue(raw as! AXValue, .cgPoint, &point) { frame["x"] = point.x; frame["y"] = point.y }
            }
            try mark(s + ".size")
            if let raw = attribute(kAXSizeAttribute, node), CFGetTypeID(raw) == AXValueGetTypeID() {
                var size = CGSize.zero
                if AXValueGetValue(raw as! AXValue, .cgSize, &size) { frame["width"] = size.width; frame["height"] = size.height }
            }
            try mark(s + ".identifier")
            let id = string(kAXIdentifierAttribute, node) ?? ""
            try mark(s + ".role")
            let role = string(kAXRoleAttribute, node) ?? ""
            try mark(s + ".label")
            let label = string(kAXDescriptionAttribute, node) ?? string(kAXTitleAttribute, node) ?? ""
            try mark(s + ".value")
            let value = string(kAXValueAttribute, node) ?? ""
            try mark(s + ".enabled")
            let isEnabled = enabled(node)
            try mark(s + ".exit")
            return ["id": id, "role": role, "label": label, "value": value, "enabled": isEnabled,
                    "actions": actions as? [String] ?? [], "actionsAXError": actionError.rawValue, "frame": frame]
        }

        /// Native input transport for the host's own controls: one genuine left click at the
        /// observed AX frame center, posted only after the hit-tested element there is proven to
        /// be this exact control (or its descendant) in this process. No AX actions are performed.
        /// Every AX call below has its own fixed before/after mark; any ownership doubt throws.
        func click(_ target: AXUIElement, _ checkpoint: String, roles: [String], identifier: String,
                   title: String? = nil) throws -> [String: Any] {
            let s = "click." + checkpoint
            let host = ProcessInfo.processInfo.processIdentifier
            func fail(_ reason: String) -> UndoControlCheckFailure {
                UndoControlCheckFailure("Native click refused at \(s): \(reason)")
            }
            let labels = [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute]
            let current = try marked(s + ".unique-scan") {
                nodes().filter { node in
                    (string(kAXIdentifierAttribute, node) == identifier
                        || (title != nil && roles.contains(string(kAXRoleAttribute, node) ?? "")
                            && labels.contains { string($0, node) == title }))
                        && hasVisibleFrame(node)
                }
            }
            guard current.count == 1, CFEqual(current[0], target) else { throw fail("target is not the current unique control") }
            let role = try marked(s + ".role") { string(kAXRoleAttribute, target) } ?? ""
            guard roles.contains(role) else { throw fail("unexpected role \(role)") }
            let id = try marked(s + ".identifier") { string(kAXIdentifierAttribute, target) } ?? ""
            var contract = "identifier"
            if id != identifier {
                guard let title else { throw fail("identifier mismatch") }
                var matched = false
                for (index, name) in labels.enumerated() where !matched {
                    matched = try marked(s + ".title.\(index)") { string(name, target) } == title
                }
                guard matched else { throw fail("neither identifier nor fixture title matched") }
                contract = "fixture-title"
            }
            guard try marked(s + ".enabled", { enabled(target) }) else { throw fail("control is disabled") }
            guard try marked(s + ".pid", { pid(target) }) == host else { throw fail("target is not owned by the host") }
            let frame = try axFrame(target, s + ".frame")
            let center = CGPoint(x: frame.midX, y: frame.midY)
            guard frame.contains(center) else { throw fail("center outside frame") }

            var displayCount: UInt32 = 0
            var displays = [CGDirectDisplayID](repeating: 0, count: 32)
            let displayError = try marked(s + ".displays") { CGGetActiveDisplayList(32, &displays, &displayCount) }
            guard displayError == .success else { throw fail("active display list unavailable") }
            let containing = displays.prefix(Int(displayCount)).filter { CGDisplayBounds($0).contains(frame) }
            guard containing.count == 1, let display = containing.first else {
                throw fail("frame is not contained in exactly one active display")
            }
            let bounds = CGDisplayBounds(display)

            let systemWide = AXUIElementCreateSystemWide()
            var hitRef: AXUIElement?
            let hitError = try marked(s + ".hit-test") { () -> AXError in
                _ = AXUIElementSetMessagingTimeout(systemWide, 1)
                return AXUIElementCopyElementAtPosition(systemWide, Float(center.x), Float(center.y), &hitRef)
            }
            guard hitError == .success, let hit = hitRef else { throw fail("hit test failed (\(hitError.rawValue))") }
            let hitPID = try marked(s + ".hit-pid") { pid(hit) }
            guard hitPID == host else { throw fail("hit element belongs to another process") }
            var node = hit, depth = 0
            while !CFEqual(node, target) {
                guard depth < 8, let parent = try marked(s + ".hit-ancestor.\(depth)", { element(kAXParentAttribute, node) }) else {
                    throw fail("hit element is not the target or its descendant")
                }
                node = parent
                depth += 1
            }

            let targetWindow = try marked(s + ".target-window") { element(kAXWindowAttribute, target) }
            let hitWindow = try marked(s + ".hit-window") { element(kAXWindowAttribute, hit) }
            var policy = "", windowOwned = false, menuAncestor = ""
            if let targetWindow, let hitWindow {
                guard CFEqual(targetWindow, hitWindow) else { throw fail("hit element is in another window") }
                windowOwned = try marked(s + ".window-pid") { pid(targetWindow) } == host
                guard windowOwned else { throw fail("window is not owned by the host") }
                policy = "same-window"
            } else if targetWindow == nil, hitWindow == nil, ["AXMenuItem", "AXMenuBarItem"].contains(role) {
                var ancestor = target
                for level in 0..<6 where menuAncestor.isEmpty {
                    guard let parent = try marked(s + ".menu-ancestor.\(level)", { element(kAXParentAttribute, ancestor) }),
                          try marked(s + ".menu-ancestor-pid.\(level)", { pid(parent) }) == host else {
                        throw fail("windowless control lacks owned native menu ancestry")
                    }
                    let parentRole = try marked(s + ".menu-ancestor-role.\(level)") { string(kAXRoleAttribute, parent) } ?? ""
                    if ["AXMenu", "AXMenuBar"].contains(parentRole) { menuAncestor = parentRole }
                    ancestor = parent
                }
                guard !menuAncestor.isEmpty else { throw fail("windowless control lacks native menu ancestry") }
                policy = "windowless-native-menu"
            } else {
                throw fail("window ownership is ambiguous")
            }
            guard try axFrame(target, s + ".frame-recheck") == frame else { throw fail("frame changed before posting") }

            guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: center, mouseButton: .left),
                  let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: center, mouseButton: .left) else {
                throw fail("cannot create native mouse events")
            }
            for event in [down, up] {
                event.flags = []
                event.setIntegerValueField(.mouseEventClickState, value: 1)
            }
            try mark(s + ".post.before")
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
            try mark(s + ".post.after")
            return ["kind": "native-mouse-click", "eventTypes": ["leftMouseDown", "leftMouseUp"], "eventCount": 2,
                    "tap": "cghidEventTap", "clickState": 1, "flagsRawValue": 0,
                    "hostPID": Int(host), "targetID": id, "targetRole": role, "identityContract": contract,
                    "targetFrame": rect(frame), "point": ["x": Double(center.x), "y": Double(center.y)],
                    "activeDisplayID": Int(display), "activeDisplayBounds": rect(bounds), "hitPID": Int(host),
                    "hitDepth": depth, "sameTargetOrDescendant": true, "uniqueTarget": true, "frameStable": true,
                    "targetOwnedByHost": true, "hitOwnedByHost": true, "windowPolicy": policy,
                    "targetWindowPresent": targetWindow != nil, "hitWindowPresent": hitWindow != nil,
                    "sameWindow": policy == "same-window", "windowOwnedByHost": windowOwned,
                    "nativeMenuAncestry": !menuAncestor.isEmpty, "menuAncestorRole": menuAncestor]
        }

        func marked<T>(_ stage: String, _ body: () throws -> T) throws -> T {
            try mark(stage + ".before")
            let value = try body()
            try mark(stage + ".after")
            return value
        }

        func axFrame(_ node: AXUIElement, _ stage: String) throws -> CGRect {
            let rawPosition = try marked(stage + ".position") { attribute(kAXPositionAttribute, node) }
            let rawSize = try marked(stage + ".size") { attribute(kAXSizeAttribute, node) }
            var point = CGPoint(x: CGFloat.nan, y: .nan), size = CGSize.zero
            guard let rawPosition, let rawSize,
                  CFGetTypeID(rawPosition) == AXValueGetTypeID(), CFGetTypeID(rawSize) == AXValueGetTypeID(),
                  AXValueGetValue(rawPosition as! AXValue, .cgPoint, &point), AXValueGetValue(rawSize as! AXValue, .cgSize, &size),
                  point.x.isFinite, point.y.isFinite, size.width.isFinite, size.height.isFinite,
                  size.width > 0, size.height > 0 else {
                throw UndoControlCheckFailure("The actual control frame was unavailable or invalid at \(stage).")
            }
            return CGRect(origin: point, size: size)
        }

        func rect(_ value: CGRect) -> [String: Double] {
            ["x": Double(value.origin.x), "y": Double(value.origin.y),
             "width": Double(value.size.width), "height": Double(value.size.height)]
        }

        func pid(_ node: AXUIElement) -> pid_t? {
            var value: pid_t = 0
            return AXUIElementGetPid(node, &value) == .success ? value : nil
        }

        func dumpHierarchy(_ name: String) throws {
            let value = nodes().map { node in
                ["role": string(kAXRoleAttribute, node) ?? "", "id": string(kAXIdentifierAttribute, node) ?? "",
                 "title": string(kAXTitleAttribute, node) ?? "", "label": string(kAXDescriptionAttribute, node) ?? "",
                 "enabled": enabled(node)] as [String: Any]
            }
            try writeJSON(value, to: owner.output.appendingPathComponent(name + "-hierarchy.json"))
        }

        func screenshot(_ name: String) async throws {
            let path = owner.output.appendingPathComponent(name + ".png")
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = ["-x", "-t", "png", path.path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            do { try await wait("Native screenshot timed out.", seconds: 5) { !process.isRunning } }
            catch { process.terminate(); throw error }
            try require(process.terminationStatus == 0 && FileManager.default.fileExists(atPath: path.path),
                        "Native screenshot failed.")
        }

        func finish(completed: Bool, failure: String?) throws {
            let host: [String: Any] = ["pid": Int(ProcessInfo.processInfo.processIdentifier),
                                      "bundleIdentifier": Bundle.main.bundleIdentifier ?? "",
                                      "executablePath": Bundle.main.executablePath ?? ""]
            try writeJSON(["schemaVersion": 1, "completed": completed, "selectedCases": selectedCases,
                           "executedCases": cases.compactMap { $0["id"] }, "cases": cases,
                           "stateChecks": states, "shortcut": shortcut, "host": host, "pastePreferences": pastePreferences,
                           "policyBootstrap": policyBootstrap,
                           "runtimeBounds": ["productMenuOrShortcut": true, "normalAppComposition": false,
                                             "fullPipeline": false, "ASR": false, "provider": false],
                           "forwardBoundary": "Real WritingTarget delivery into the sole engine-owned controller",
                           "issues": Issue.messages, "failure": failure as Any? ?? NSNull()],
                          to: owner.output.appendingPathComponent("result.json"))
        }

        func writeJSON(_ value: Any, to path: URL) throws {
            try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
                .write(to: path, options: .withoutOverwriting)
        }

        func wait(_ message: String, seconds: TimeInterval = 6, _ predicate: () -> Bool) async throws {
            let deadline = ProcessInfo.processInfo.systemUptime + seconds
            repeat {
                if predicate() { return }
                try await Task.sleep(for: .milliseconds(30))
            } while ProcessInfo.processInfo.systemUptime < deadline
            throw UndoControlCheckFailure(message)
        }

        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw UndoControlCheckFailure(message) }
        }
        func units(_ text: String) -> [Int] { text.utf16.map(Int.init) }
        func range(_ value: NSRange) -> [String: Int] { ["location": value.location, "length": value.length] }
        func enabled(_ node: AXUIElement) -> Bool { (attribute(kAXEnabledAttribute, node) as? NSNumber)?.boolValue == true }
        func hasVisibleFrame(_ node: AXUIElement) -> Bool {
            guard (attribute("AXHidden", node) as? NSNumber)?.boolValue != true,
                  let raw = attribute(kAXSizeAttribute, node), CFGetTypeID(raw) == AXValueGetTypeID() else { return false }
            var size = CGSize.zero
            return AXValueGetValue(raw as! AXValue, .cgSize, &size) && size.width > 0 && size.height > 0
        }
        func string(_ name: String, _ node: AXUIElement) -> String? { attribute(name, node) as? String }
        func element(_ name: String, _ node: AXUIElement) -> AXUIElement? {
            guard let raw = attribute(name, node), CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
            return (raw as! AXUIElement)
        }
        func attribute(_ name: String, _ node: AXUIElement) -> CFTypeRef? {
            var value: CFTypeRef?
            return AXUIElementCopyAttributeValue(node, name as CFString, &value) == .success ? value : nil
        }
    }
}
