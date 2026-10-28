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
        let check = Check(owner: owner)
        do {
            try await check.execute()
            try check.finish(completed: true, failure: nil)
            Darwin.exit(0)
        } catch {
            try? check.dumpHierarchy("failure")
            try? await check.screenshot("failure")
            try? check.finish(completed: false, failure: String(describing: error))
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

        func execute() async throws {
            try require(AXIsProcessTrusted(), "The exact signed host lacks Accessibility access.")
            try require(CGPreflightListenEventAccess(), "The exact signed host lacks Input Monitoring access.")
            try require(CGPreflightPostEventAccess(), "The exact signed host cannot post native keyboard events.")
            try require(CGPreflightScreenCaptureAccess(), "The exact signed host lacks Screen Recording access.")
            let argumentDomain = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
            let pasteKeys = [VoiceInkPastePreference.restoreClipboardAfterPasteKey, VoiceInkPastePreference.clipboardRestoreDelayKey]
            let hasArgumentOverrides = pasteKeys.contains { argumentDomain[$0] != nil }
            let bundleID = Bundle.main.bundleIdentifier ?? ""
            let expectedHome = ProcessInfo.processInfo.environment["CFFIXED_USER_HOME"] ?? ""
            try require(bundleID == "com.negentropi.RomaJustTalk" && expectedHome.hasPrefix("/") && !hasArgumentOverrides,
                        "The controlled preference input requires the exact host and no policy launch overrides.")
            let before = policySnapshot(bundleID: bundleID)
            // Configure test-owned inputs through the same public preference APIs
            // as Settings. A plist placed by another process is not the oracle.
            VoiceInkPastePreference.saveShouldRestoreClipboardAfterPaste(VoiceInkPastePreference.defaultRestoreClipboardAfterPaste)
            VoiceInkPastePreference.saveClipboardRestoreDelay(VoiceInkPastePreference.defaultClipboardRestoreDelay)
            let synchronized = UserDefaults.standard.synchronize()
            let after = policySnapshot(bundleID: bundleID)
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
            try await dismissMenu()
            states["unavailable"] = ["passed": true, "menu": unavailable]
            try await configureShortcut()

            for (index, id) in selectedCases.enumerated() {
                try await successCase(id, kind: index < 2 ? .textEdit : .safari)
            }
            try await focusRefusal()
            try require(Issue.messages.isEmpty, "The editor helper reported a failure: \(Issue.messages)")
        }

        func configureShortcut() async throws {
            try await wait("The fixture setup window did not appear.") {
                NSApp.windows.contains { $0.title == "RJT Undo control check" && $0.isVisible }
            }
            guard let window = NSApp.windows.first(where: { $0.title == "RJT Undo control check" }) else {
                throw UndoControlCheckFailure("Missing fixture setup window.")
            }
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            try await wait("The setup window did not become active.") { NSApp.isActive && window.isKeyWindow }
            let recorder = try await unique(identifier: "shortcutRecorder.undoLastWritingEdit")
            let control = try describe(recorder)
            try press(recorder)
            try await wait("The real recorder did not clear its shortcut for capture.") {
                ShortcutStore.isShortcutCleared(for: .undoLastWritingEdit)
            }
            try postChord()
            let expected = Shortcut.key(keyCode: keyCode, modifierFlags: modifiers)
            try await wait("The real recorder did not save the exact captured chord.") {
                ShortcutStore.shortcut(for: .undoLastWritingEdit) == expected
            }
            // A subsequent global chord must reach the registered event tap, not
            // the setup recorder's local capture monitor.
            try await wait("The shortcut recorder stayed in capture mode.") {
                self.string(kAXDescriptionAttribute, recorder) == expected.displayString
                    || self.string(kAXTitleAttribute, recorder) == expected.displayString
                    || self.string(kAXHelpAttribute, recorder) == expected.displayString
            }
            shortcut = ["recordedViaActualRecorder": true, "keyCode": Int(keyCode),
                        "modifierFlagsRawValue": modifiers.rawValue, "displayString": expected.displayString,
                        "recorderControl": control]
            try await screenshot("shortcut-configured")
            try dumpHierarchy("shortcut-configured")
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
            let editor = try await LiveWritingEditor.open(kind)
            defer { editor.close() }
            try await editor.selectOriginalPassage()
            let before = try snapshot(editor)
            try expect(before, value: LiveWritingEditor.original, range: originalRange)
            let replacement = id.contains("shortcut") ? "Short e\u{301} 😀" : "Longer 👩🏽‍💻 e\u{301}\nRJT, 台灣, 🧑‍🚀."
            let result = LiveWritingEditor.prefix + replacement + LiveWritingEditor.suffix
            let caret = NSRange(location: LiveWritingEditor.prefix.utf16.count + replacement.utf16.count, length: 0)
            let counts = try await deliver(replacement)
            let forward = try snapshot(editor)
            try expect(forward, value: result, range: caret)
            try require(owner.engine.canUndoLastWritingEdit, "A confirmed native edit did not enable the engine command.")
            try await screenshot(id + "-forward")
            if id == "textedit-shortcut" { try await busyCheck(editor, result: result, caret: caret) }
            // Each command must produce its own feedback. A prior success has
            // identical copy, so observing that older panel is insufficient.
            try await wait("Prior passive feedback did not dismiss.", seconds: 7) {
                self.nodes().allSatisfy {
                    self.string(kAXIdentifierAttribute, $0) != "undoLastWritingEdit.notice" || !self.hasVisibleFrame($0)
                }
            }

            let command: [String: Any]
            if id.hasSuffix("menu") {
                command = try await openMenu(expectedEnabled: true, checkpoint: id + "-menu")
                // This is the actual product Button through the native menu
                // bridge. No engine, shared-command or private handler call.
                try press(try await unique(identifier: "undoLastWritingEdit.menuCommand"))
            } else {
                command = ["kind": "configured-global-shortcut", "keyCode": Int(keyCode),
                           "modifierFlagsRawValue": modifiers.rawValue, "nativeEventsPosted": 2]
                try postChord()
            }
            try await wait("The product control did not restore the original text and selection.", seconds: 12) {
                editor.value?.utf16.elementsEqual(LiveWritingEditor.original.utf16) == true
                    && editor.selectedRange == self.originalRange
                    && !self.owner.engine.writingActionUndoController.isAvailable
            }
            let notice = try await notice(expected: "Restored the original text and selection.")
            // Check focus after the new product panel appears, not merely after
            // the engine changed the text but before feedback was displayed.
            let restored = try snapshot(editor)
            try expect(restored, value: LiveWritingEditor.original, range: originalRange)
            try await screenshot(id + "-restored")
            try dumpHierarchy(id + "-restored")
            try await CursorPaster.settlePendingClipboardRestore()
            try require(!owner.engine.writingActionUndoController.isAvailable, "The consumed edit remained available.")
            cases.append(["id": id, "editor": kind == .textEdit ? "textedit" : "safari",
                          "commandKind": id.hasSuffix("menu") ? "menu" : "shortcut",
                          "forwardAttempts": counts.0, "forwardConfirmations": counts.1,
                          "originalUTF16": units(LiveWritingEditor.original), "resultUTF16": units(result),
                          "originalRange": range(originalRange), "before": before, "forward": forward,
                          "restored": restored, "command": command, "notice": notice,
                          "noticeWasAbsentBeforeCommand": true,
                          "capabilityConsumed": true,
                          "screenshots": [id + "-forward.png", id + "-restored.png"]])
        }

        func busyCheck(_ editor: LiveWritingEditor, result: String, caret: NSRange) async throws {
            owner.engine.recordingState = .busy
            defer { owner.engine.recordingState = .idle }
            let menu = try await openMenu(expectedEnabled: false, checkpoint: "busy-menu")
            try await dismissMenu()
            try postChord()
            let feedback = try await notice(expected: "RJT is busy right now, so Undo didn't replace any text.")
            let observed = try snapshot(editor)
            try expect(observed, value: result, range: caret)
            try require(owner.engine.writingActionUndoController.isAvailable, "A busy command consumed the native edit.")
            states["busy"] = ["passed": true, "recordingStateFixture": "busy", "menu": menu,
                              "notice": feedback, "observed": observed, "capabilityRetained": true]
            try await screenshot("busy-shortcut-refused")
        }

        func focusRefusal() async throws {
            let source = try await LiveWritingEditor.open(.textEdit)
            defer { source.close() }
            try await source.selectOriginalPassage()
            let replacement = "Source remains e\u{301} 🧪"
            let result = LiveWritingEditor.prefix + replacement + LiveWritingEditor.suffix
            let caret = NSRange(location: LiveWritingEditor.prefix.utf16.count + replacement.utf16.count, length: 0)
            _ = try await deliver(replacement)
            let other = try await LiveWritingEditor.open(.textEdit)
            defer { other.close() }
            try await other.selectOriginalPassage()
            try require(!CFEqual(source.window, other.window), "Focus-refusal setup reused the source window.")
            let otherBefore = try snapshot(other)
            try postChord()
            let feedback = try await notice(expected: "The edited field changed or isn't focused, so Undo didn't replace any text.")
            try await wait("Focus refusal did not retire stale authority.") {
                !self.owner.engine.writingActionUndoController.isAvailable
            }
            let sourceAfter = try snapshot(source)
            let otherAfter = try snapshot(other)
            try expect(sourceAfter, value: result, range: caret, focused: false)
            try expect(otherBefore, value: LiveWritingEditor.original, range: originalRange)
            try expect(otherAfter, value: LiveWritingEditor.original, range: originalRange)
            states["focusRefusal"] = ["passed": true, "sourceAfter": sourceAfter,
                                      "otherBefore": otherBefore, "otherAfter": otherAfter,
                                      "notice": feedback, "capabilityRetired": true,
                                      "differentWindow": true]
            try await screenshot("focus-refusal")
        }

        func deliver(_ text: String) async throws -> (Int, Int) {
            let target = try WritingTarget.capture(requiresSelection: true)
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
            try require(outcome.isConfirmed && attempts == 1 && confirmations == 1 && controller.isAvailable,
                        "Forward delivery lacked exactly one confirmed native edit receipt.")
            return (attempts, confirmations)
        }

        func openMenu(expectedEnabled: Bool, checkpoint: String) async throws -> [String: Any] {
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
            try press(status)
            let item = try await unique(identifier: "undoLastWritingEdit.menuCommand")
            try await wait("The real menu command had the wrong enabled state.") {
                self.hasVisibleFrame(item) && self.enabled(item) == expectedEnabled
            }
            let observed = try describe(item)
            try require(["AXMenuItem", "AXButton"].contains(observed["role"] as? String ?? ""),
                        "The Undo identifier did not identify a native actionable control.")
            try dumpHierarchy(checkpoint)
            try await screenshot(checkpoint)
            return observed.merging(["kind": "product-menu", "statusControl": try describe(status)]) { _, new in new }
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
            return try describe(control).merging(["expectedMessage": expected]) { _, new in new }
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

        func describe(_ node: AXUIElement) throws -> [String: Any] {
            var actions: CFArray?
            let actionError = AXUIElementCopyActionNames(node, &actions)
            let names = actions as? [String] ?? []
            var frame: [String: Double] = [:]
            if let raw = attribute(kAXPositionAttribute, node), CFGetTypeID(raw) == AXValueGetTypeID() {
                var point = CGPoint.zero
                if AXValueGetValue(raw as! AXValue, .cgPoint, &point) { frame["x"] = point.x; frame["y"] = point.y }
            }
            if let raw = attribute(kAXSizeAttribute, node), CFGetTypeID(raw) == AXValueGetTypeID() {
                var size = CGSize.zero
                if AXValueGetValue(raw as! AXValue, .cgSize, &size) { frame["width"] = size.width; frame["height"] = size.height }
            }
            return ["id": string(kAXIdentifierAttribute, node) ?? "", "role": string(kAXRoleAttribute, node) ?? "",
                    "label": string(kAXDescriptionAttribute, node) ?? string(kAXTitleAttribute, node) ?? "",
                    "value": string(kAXValueAttribute, node) ?? "", "enabled": enabled(node),
                    "actions": names, "actionsAXError": actionError.rawValue, "frame": frame]
        }

        func press(_ node: AXUIElement) throws {
            let details = try describe(node)
            try require(hasVisibleFrame(node) && enabled(node) && (details["actions"] as? [String])?.contains(kAXPressAction) == true,
                        "Expected an enabled control with a real AXPress action.")
            try require(AXUIElementPerformAction(node, kAXPressAction as CFString) == .success, "Native AXPress failed.")
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
