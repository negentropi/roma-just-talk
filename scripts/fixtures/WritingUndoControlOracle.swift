import AppKit
import Carbon.HIToolbox
import CryptoKit
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
            let unavailableDismissal = try await dismissMenu(unavailable.session)
            try mark("unavailable.dismiss-menu.after")
            states["unavailable"] = ["passed": true, "menu": unavailable.facts, "dismissal": unavailableDismissal]
            try await configureShortcut()

            for (index, id) in selectedCases.enumerated() {
                try await successCase(id, kind: index < 2 ? .textEdit : .safari)
            }
            try await focusRefusal()
            try require(Issue.messages.isEmpty, "The editor helper reported a failure: \(Issue.messages)")
            try mark("execute.exit")
        }

        static let setupWindowTitle = "RJT Undo control check"
        static let recorderIdentifier = "shortcutRecorder.undoLastWritingEdit"
        static let captureFailureFile = "shortcut-capture-failure.json"
        static let capturePreInputFile = "shortcut-capture-preinput.json"

        /// NAMED INPUT CONTRACT 1 (recorder capture only): the expected chord reaches the actual focused setup
        /// recorder through the same native `CGEvent.postToPid` pattern as `LiveWritingEditor.key`, posted
        /// exactly once to the verified host PID after a final synchronous read-only capture proof. No fallback,
        /// retry, direct handler/model call or QA shortcut write. NAMED INPUT CONTRACT 2 is untouched: every
        /// later configured global Undo invocation stays `postChord` on `cghidEventTap` through the actual
        /// registered manager/event tap.
        func configureShortcut() async throws {
            let expected = Shortcut.key(keyCode: keyCode, modifierFlags: modifiers)
            try mark("shortcut.window-wait.before")
            try await wait("The fixture setup window did not appear.") {
                NSApp.windows.contains { $0.title == Self.setupWindowTitle && $0.isVisible }
            }
            guard let window = NSApp.windows.first(where: { $0.title == Self.setupWindowTitle }) else {
                throw UndoControlCheckFailure("Missing fixture setup window.")
            }
            try mark("shortcut.activate.before")
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            try mark("shortcut.active-wait.before")
            try await wait("The setup window did not become active.") { NSApp.isActive && window.isKeyWindow }
            try mark("shortcut.recorder-lookup.before")
            let recorder = try await unique(identifier: Self.recorderIdentifier)
            try mark("shortcut.recorder-describe.before")
            let control = try describe(recorder, "shortcut.recorder")
            try mark("shortcut.state-before-click.before")
            let beforeClick = ownShortcutState("before-click", expected: expected)
            let conflictBeforeClick = conflictCheck(expected)
            guard conflictBeforeClick["conflictFree"] as? Bool == true else {
                let error = UndoControlCheckFailure("The expected chord conflicts before recorder input: "
                    + "\(conflictBeforeClick["issue"] ?? "unknown"); no input posted.")
                retainCaptureFailure("before-click", error, inputPosted: false,
                                     facts: ["ownShortcutBeforeClick": beforeClick, "conflictBeforeClick": conflictBeforeClick])
                throw error
            }
            try mark("shortcut.recorder-press.before")
            let recorderClick = try await click(recorder, "shortcut.recorder", roles: ["AXButton"],
                                                identity: .identifier(Self.recorderIdentifier, fixtureTitle: nil))
            try mark("shortcut.clear-wait.before")
            try await wait("The real recorder did not clear its shortcut for capture.") {
                ShortcutStore.isShortcutCleared(for: .undoLastWritingEdit)
            }

            // Pre-input readiness: read-only polling only; nothing is posted until a proof is fully ready.
            try mark("shortcut.capture-readiness.before")
            var readiness: [String: Any] = [:]
            do {
                try await wait("The recorder capture state was not proven before input; no input posted.") {
                    readiness = self.recorderCaptureProof(recorder, window: window, expected: expected, phase: "readiness")
                    return readiness["ready"] as? Bool == true
                }
            } catch {
                retainCaptureFailure("capture-readiness", error, inputPosted: false,
                                     facts: ["ownShortcutBeforeClick": beforeClick, "conflictBeforeClick": conflictBeforeClick,
                                             "lastReadiness": readiness])
                throw error
            }

            // Posting phase: synchronous from event construction and final proof to the single post pair.
            try mark("shortcut.capture-events.before")
            let host = ProcessInfo.processInfo.processIdentifier
            let flags = CGEventFlags(rawValue: UInt64(modifiers.rawValue))
            guard let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
                  let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else {
                let error = UndoControlCheckFailure("Cannot create native recorder capture events; no input posted.")
                retainCaptureFailure("capture-events", error, inputPosted: false, facts: ["lastReadiness": readiness])
                throw error
            }
            down.flags = flags
            up.flags = flags
            let events: [[String: Any]] = [down, up].map { (event: CGEvent) -> [String: Any] in
                ["type": event.type == .keyDown ? "keyDown" : event.type == .keyUp ? "keyUp" : "unexpected-\(event.type.rawValue)",
                 "keyCode": Int(event.getIntegerValueField(.keyboardEventKeycode)),
                 "flagsRawValue": event.flags.rawValue]
            }
            let eventsExact = down.type == .keyDown && up.type == .keyUp
                && [down, up].allSatisfy { $0.getIntegerValueField(.keyboardEventKeycode) == Int64(keyCode) && $0.flags == flags }
            try mark("shortcut.capture-final-proof.before")
            let (finalProof, verifiedAXWindow) = recorderCaptureProofWithWindow(recorder, window: window, expected: expected,
                                                                                phase: "final-preinput")
            let verifiedWindowNumber = window.windowNumber
            let beforeInput = ownShortcutState("before-input", expected: expected)
            var input: [String: Any] = [
                "contract": "focused-recorder-capture-postToPid", "route": "CGEvent.postToPid",
                "pattern": "LiveWritingEditor.key", "targetPID": Int(host), "hostPID": Int(host),
                "eventTypes": ["keyDown", "keyUp"], "eventCount": 2, "events": events, "eventsExact": eventsExact,
                "keyCode": Int(keyCode), "modifierFlagsRawValue": modifiers.rawValue,
                "eventFlagsRawValue": flags.rawValue, "eventSource": "nil",
                "fallbackUsed": false, "retryUsed": false, "physicalKeyboard": false,
                "laterGlobalInvocationRoute": "postChord-cghidEventTap-unchanged",
                "finalProofReady": finalProof["ready"] as? Bool == true, "inputPosted": false]
            let preInput: [String: Any] = ["schemaVersion": 1, "kind": "recorder-capture-preinput", "input": input,
                                           "finalProof": finalProof, "ownShortcutBeforeInput": beforeInput]
            guard eventsExact, finalProof["ready"] as? Bool == true, let verifiedAXWindow else {
                let error = UndoControlCheckFailure("The final recorder capture proof or event shape failed; no input posted.")
                retainCaptureFailure("capture-final-proof", error, inputPosted: false, facts: preInput)
                throw error
            }
            try marked("shortcut.capture-preinput-write") {
                try writeJSON(preInput, to: owner.output.appendingPathComponent(Self.capturePreInputFile))
            }
            try mark("shortcut.capture-post.before")
            down.postToPid(host)
            up.postToPid(host)
            input["inputPosted"] = true
            try mark("shortcut.capture-post.after")

            // Post-capture readback: read-only only. The control may be re-created after capture (the retained
            // pre-input reference was observed invalid), so the display is read from the CURRENT control bound
            // to the same verified setup AXWindow. Relookup polls only; no input, retry or shortcut write.
            var retainedAfterCapture: [String: Any]?
            var currentReadback: [String: Any] = [:]
            var currentReadbackPolls = 0
            var currentControl: AXUIElement?
            do {
                try mark("shortcut.save-wait.before")
                try await wait("The real recorder did not save the exact captured chord.") {
                    ShortcutStore.shortcut(for: .undoLastWritingEdit) == expected
                }
                try mark("shortcut.retained-reference-facts.before")
                retainedAfterCapture = rawReferenceFacts(recorder)
                // A subsequent global chord must reach the registered event tap, not
                // the setup recorder's local capture monitor.
                try mark("shortcut.current-recorder-readback.before")
                try await wait("The current recorder control did not prove the saved chord display in the verified setup window.") {
                    currentReadbackPolls += 1
                    let readback = self.currentRecorderReadback(expected: expected, window: window,
                                                                windowNumber: verifiedWindowNumber,
                                                                verifiedAXWindow: verifiedAXWindow, retained: recorder)
                    currentReadback = readback.facts
                    currentControl = readback.control
                    return readback.control != nil
                }
                try require(currentControl != nil && currentReadback["ready"] as? Bool == true,
                            "The current recorder readback was not proven.")
            } catch {
                // Read-only post-input diagnostic; the original failure is rethrown unchanged, never retried.
                retainCaptureFailure("capture-readback", error, inputPosted: true, facts: [
                    "preInput": preInput, "input": input,
                    "ownShortcutAfterReadback": ownShortcutState("after-readback-failure", expected: expected),
                    "retainedReferenceAfterCapture": retainedAfterCapture ?? rawReferenceFacts(recorder),
                    "lastCurrentReadback": currentReadback, "currentReadbackPolls": currentReadbackPolls])
                throw error
            }
            let afterReadback = ownShortcutState("after-readback", expected: expected)
            let currentFacts = currentReadback["currentControl"] as? [String: Any] ?? [:]
            let recorderLabel = currentFacts["description"] as? String
            shortcut = ["recordedViaActualRecorder": true, "keyCode": Int(keyCode),
                        "modifierFlagsRawValue": modifiers.rawValue, "displayString": expected.displayString,
                        "recorderControl": control.merging(["click": recorderClick]) { _, new in new },
                        "captureInput": input, "captureProof": finalProof,
                        "capturePreInputFile": Self.capturePreInputFile,
                        "conflictBeforeClick": conflictBeforeClick,
                        "ownShortcutState": ["beforeClick": beforeClick, "beforeInput": beforeInput,
                                             "afterReadback": afterReadback],
                        "readback": ["storeEqualsExpected": ShortcutStore.shortcut(for: .undoLastWritingEdit) == expected,
                                     "recorderDescription": recorderLabel as Any? ?? NSNull(),
                                     "recorderIdleDisplayMatches": recorderLabel == expected.displayString,
                                     "displaySource": "current-control",
                                     "currentControlReadback": currentReadback,
                                     "currentReadbackPolls": currentReadbackPolls,
                                     "retainedReferenceAfterCapture": retainedAfterCapture as Any? ?? NSNull()]]
            try mark("shortcut.screenshot.before")
            try await screenshot("shortcut-configured")
            try mark("shortcut.hierarchy.before")
            try dumpHierarchy("shortcut-configured")
            try mark("shortcut.exit")
        }

        func shortcutFacts(_ value: Shortcut) -> [String: Any] {
            ["kind": value.kind.rawValue, "keyCode": Int(value.keyCode),
             "modifierFlagsRawValue": value.modifierFlags.rawValue, "displayString": value.displayString]
        }

        /// Typed public stored state of ONLY the undo action (no broad preference or raw data dump).
        func ownShortcutState(_ phase: String, expected: Shortcut) -> [String: Any] {
            let state = ShortcutStore.storedState(for: .undoLastWritingEdit)
            let effective = ShortcutStore.shortcut(for: .undoLastWritingEdit)
            var facts: [String: Any] = [
                "phase": phase, "action": "undoLastWritingEdit",
                "clearedValue": state.clearedValue.map { $0 as Any } ?? NSNull(),
                "clearedValueKind": state.clearedValue.map { $0 ? "true" : "false" } ?? "nil",
                "isShortcutCleared": ShortcutStore.isShortcutCleared(for: .undoLastWritingEdit),
                "dataPresent": state.shortcutData != nil,
                "effective": effective.map { shortcutFacts($0) as Any } ?? NSNull(), "effectiveEqualsExpected": effective == expected]
            if let data = state.shortcutData {
                facts["dataBytes"] = data.count
                facts["dataSHA256"] = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                let decoded = try? JSONDecoder().decode(Shortcut.self, from: data)
                facts["decodeSucceeded"] = decoded != nil
                facts["decoded"] = decoded.map { shortcutFacts($0) as Any } ?? NSNull()
            }
            return facts
        }

        /// Existing public validator for the expected chord (stored actions, reserved and system shortcuts).
        func conflictCheck(_ expected: Shortcut) -> [String: Any] {
            let issue = ShortcutValidator.validationError(for: expected, action: .undoLastWritingEdit)
            return ["api": "ShortcutValidator.validationError", "action": "undoLastWritingEdit",
                    "expected": shortcutFacts(expected), "conflictFree": issue == nil,
                    "issue": issue.map { String(describing: $0) as Any } ?? NSNull()]
        }

        func axElement(_ raw: CFTypeRef?) -> AXUIElement? {
            guard let raw, CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
            return (raw as! AXUIElement)
        }

        /// Synchronous, read-only recorder capture proof. Never posts. Every unproven fact or AX error is a
        /// named reason and `ready` is false; nothing is clamped or substituted.
        func recorderCaptureProof(_ recorder: AXUIElement, window: NSWindow, expected: Shortcut,
                                  phase: String) -> [String: Any] {
            recorderCaptureProofWithWindow(recorder, window: window, expected: expected, phase: phase).facts
        }

        /// Same proof; also hands back the exact AXWindow reference it verified, so the post-capture readback
        /// can bind the current control to that same window by CFEqual (never by a global title search).
        func recorderCaptureProofWithWindow(_ recorder: AXUIElement, window: NSWindow, expected: Shortcut,
                                            phase: String) -> (facts: [String: Any], axWindow: AXUIElement?) {
            let host = ProcessInfo.processInfo.processIdentifier
            let placeholder = VoiceInkRecordingShortcutPreference.macOSRecorderPresentation.recordingPlaceholderText
            var reasons: [String] = []
            func need(_ ok: Bool, _ reason: String) { if !ok { reasons.append(reason) } }
            func pidFact(_ value: pid_t?) -> Any { value.map { Int($0) as Any } ?? NSNull() }
            func text(_ value: String?) -> Any { value as Any? ?? NSNull() }

            let matches = nodes().filter { string(kAXIdentifierAttribute, $0) == Self.recorderIdentifier && hasVisibleFrame($0) }
            let sameReference = matches.count == 1 && CFEqual(matches[0], recorder)
            let role = string(kAXRoleAttribute, recorder)
            let label = string(kAXDescriptionAttribute, recorder)
            let recorderPID = pid(recorder)
            let recorderFacts: [String: Any] = [
                "identifier": text(string(kAXIdentifierAttribute, recorder)), "uniqueCount": matches.count,
                "sameReferenceAsLookup": sameReference, "role": text(role), "pid": pidFact(recorderPID),
                "description": text(label), "title": text(string(kAXTitleAttribute, recorder)),
                "help": text(string(kAXHelpAttribute, recorder)), "enabled": enabled(recorder),
                "labelIsRecordingPlaceholder": label == placeholder]
            need(sameReference, "recorder is not the unique same-reference control")
            need(role == "AXButton", "recorder role is not AXButton")
            need(recorderPID == host, "recorder is not owned by the host")
            need(label == placeholder, "recorder label is not the public recording placeholder")

            let state = ShortcutStore.storedState(for: .undoLastWritingEdit)
            let own = ownShortcutState(phase, expected: expected)
            need(ShortcutStore.isShortcutCleared(for: .undoLastWritingEdit) && state.clearedValue == true
                 && state.shortcutData == nil, "own shortcut is not in the cleared capture state")
            let conflict = conflictCheck(expected)
            need(conflict["conflictFree"] as? Bool == true, "expected chord conflicts per ShortcutValidator")

            let (windowError, windowRaw) = copy(kAXWindowAttribute, recorder)
            let axWindow = axElement(windowRaw)
            let axWindowPID = axWindow.flatMap { pid($0) }
            let axWindowRole = axWindow.flatMap { string(kAXRoleAttribute, $0) }
            let axWindowTitle = axWindow.flatMap { string(kAXTitleAttribute, $0) }
            let (windowsError, windowsRaw) = copy(kAXWindowsAttribute, app)
            let titled = (windowsRaw as? [AXUIElement] ?? []).filter { string(kAXTitleAttribute, $0) == Self.setupWindowTitle }
            let uniqueAXWindow = axWindow.map { owned in titled.count == 1 && CFEqual(titled[0], owned) } ?? false
            let (focusedWindowError, focusedWindowRaw) = copy(kAXFocusedWindowAttribute, app)
            let focusedWindow = axElement(focusedWindowRaw)
            let focusedWindowIsSetup = axWindow.flatMap { a in focusedWindow.map { CFEqual(a, $0) } } ?? false
            need(windowError == .success && axWindow != nil, "recorder AX window unavailable")
            need(axWindowPID == host && axWindowRole == "AXWindow" && axWindowTitle == Self.setupWindowTitle,
                 "recorder AX window is not the owned setup window")
            need(windowsError == .success && uniqueAXWindow, "setup AX window is not unique")
            need(focusedWindowError == .success && focusedWindowIsSetup, "host focused AX window is not the setup window")

            let systemWide = AXUIElementCreateSystemWide()
            let (focusedAppError, focusedAppRaw) = copy(kAXFocusedApplicationAttribute, systemWide)
            let focusedAppPID = axElement(focusedAppRaw).flatMap { pid($0) }
            need(focusedAppError == .success && focusedAppPID == host, "system focused application is not the host")
            // The recorder captures through an app-wide local key monitor, so the focused UI element is
            // recorded; it must be host-owned when present and any AX error other than no-value refuses.
            let (focusedElementError, focusedElementRaw) = copy(kAXFocusedUIElementAttribute, systemWide)
            let focusedElement = axElement(focusedElementRaw)
            let focusedElementPID = focusedElement.flatMap { pid($0) }
            let focusedElementWindow = focusedElement.flatMap { element(kAXWindowAttribute, $0) }
            need((focusedElementError == .success && focusedElementPID == host) || focusedElementError == .noValue,
                 "system focused UI element is ambiguous or not host-owned")

            let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
            let titledNSWindows = NSApp.windows.filter { $0.title == Self.setupWindowTitle }
            let uniqueNSWindow = titledNSWindows.count == 1 && titledNSWindows[0] === window
            need(NSApp.isActive, "host app is not active")
            need(uniqueNSWindow && window.isVisible, "setup NSWindow is not the unique visible window")
            need(window.isKeyWindow && NSApp.keyWindow === window, "setup NSWindow is not the key window")
            need(frontmostPID == host, "frontmost application is not the host")

            return ([
                "schemaVersion": 1, "kind": "recorder-capture-proof", "phase": phase, "readOnly": true,
                "inputPosted": false, "hostPID": Int(host), "systemUptime": ProcessInfo.processInfo.systemUptime,
                "expectedPlaceholder": placeholder, "recorder": recorderFacts, "ownShortcut": own, "conflictCheck": conflict,
                "axWindow": ["axError": Int(windowError.rawValue), "present": axWindow != nil, "pid": pidFact(axWindowPID),
                             "role": text(axWindowRole), "title": text(axWindowTitle),
                             "windowsAXError": Int(windowsError.rawValue), "titledCount": titled.count,
                             "uniqueSameReference": uniqueAXWindow,
                             "focusedWindowAXError": Int(focusedWindowError.rawValue),
                             "focusedWindowIsSetupWindow": focusedWindowIsSetup] as [String: Any],
                "systemFocus": ["focusedApplicationAXError": Int(focusedAppError.rawValue),
                                "focusedApplicationPID": pidFact(focusedAppPID),
                                "focusedElementAXError": Int(focusedElementError.rawValue),
                                "focusedElementPresent": focusedElement != nil, "focusedElementPID": pidFact(focusedElementPID),
                                "focusedElementRole": text(focusedElement.flatMap { string(kAXRoleAttribute, $0) }),
                                "focusedElementIsRecorder": focusedElement.map { CFEqual($0, recorder) } ?? false,
                                "focusedElementInSetupWindow": axWindow.flatMap { a in focusedElementWindow.map { CFEqual(a, $0) } } ?? false,
                                "frontmostPID": pidFact(frontmostPID)] as [String: Any],
                "appKit": ["isActive": NSApp.isActive, "windowNumber": window.windowNumber, "isKeyWindow": window.isKeyWindow,
                           "isVisible": window.isVisible, "appKeyWindowIsSetup": NSApp.keyWindow === window,
                           "titledWindowCount": titledNSWindows.count, "uniqueSameWindow": uniqueNSWindow] as [String: Any],
                "ready": reasons.isEmpty, "reasons": reasons], reasons.isEmpty ? axWindow : nil)
        }

        /// Raw facts of a retained AX reference, AXErrors kept verbatim (an invalid element is a fact, not absence).
        func rawReferenceFacts(_ node: AXUIElement) -> [String: Any] {
            var facts: [String: Any] = ["getPidPID": pid(node).map { Int($0) as Any } ?? NSNull()]
            for (key, name) in [("role", kAXRoleAttribute), ("identifier", kAXIdentifierAttribute),
                                ("description", kAXDescriptionAttribute), ("window", kAXWindowAttribute)] {
                let (error, raw) = copy(name, node)
                facts[key] = ["axError": Int(error.rawValue), "present": raw != nil,
                              "string": (raw as? String) as Any? ?? NSNull()] as [String: Any]
            }
            return facts
        }

        /// Read-only post-capture readback of the CURRENT recorder control. Never posts, writes or activates.
        /// Identity authority: exactly one exact-ID control in the host app tree (also exactly one visible),
        /// AXButton, current host PID, enabled, and its AXWindow CFEqual to the pre-input verified setup AXWindow,
        /// plus the same unique key NSWindow. The retained pre-input recorder reference only feeds the
        /// `currentDiffersFromRetained` fact and is never identity. Returns the control only when every fact holds.
        func currentRecorderReadback(expected: Shortcut, window: NSWindow, windowNumber: Int,
                                     verifiedAXWindow: AXUIElement,
                                     retained: AXUIElement) -> (facts: [String: Any], control: AXUIElement?) {
            let host = ProcessInfo.processInfo.processIdentifier
            var reasons: [String] = []
            func need(_ ok: Bool, _ reason: String) { if !ok { reasons.append(reason) } }
            func pidFact(_ value: pid_t?) -> Any { value.map { Int($0) as Any } ?? NSNull() }
            func text(_ value: String?) -> Any { value as Any? ?? NSNull() }

            let exact = nodes().filter { string(kAXIdentifierAttribute, $0) == Self.recorderIdentifier }
            let visible = exact.filter { hasVisibleFrame($0) }
            need(exact.count == 1 && visible.count == 1, "current recorder is not exactly one visible exact-ID control")
            let current = exact.count == 1 && visible.count == 1 ? visible[0] : nil
            var control: [String: Any] = ["exactIDCount": exact.count, "visibleExactIDCount": visible.count,
                                          "present": current != nil]
            if let current {
                let (roleError, roleRaw) = copy(kAXRoleAttribute, current)
                let (idError, idRaw) = copy(kAXIdentifierAttribute, current)
                let (descriptionError, descriptionRaw) = copy(kAXDescriptionAttribute, current)
                let (enabledError, enabledRaw) = copy(kAXEnabledAttribute, current)
                let (windowError, windowRaw) = copy(kAXWindowAttribute, current)
                let role = roleRaw as? String
                let identifier = idRaw as? String
                let description = descriptionRaw as? String
                let isEnabled = (enabledRaw as? NSNumber)?.boolValue == true
                let currentPID = pid(current)
                let currentWindow = axElement(windowRaw)
                let sameWindow = currentWindow.map { CFEqual($0, verifiedAXWindow) } ?? false
                need(roleError == .success && role == "AXButton", "current recorder role is not AXButton")
                need(idError == .success && identifier == Self.recorderIdentifier, "current recorder identifier differs")
                need(currentPID == host, "current recorder is not owned by the host PID")
                need(enabledError == .success && isEnabled, "current recorder is not enabled")
                need(descriptionError == .success && description == expected.displayString,
                     "current recorder description is not the expected idle chord display")
                need(windowError == .success && sameWindow, "current recorder is not in the same verified setup AXWindow")
                control.merge([
                    "role": text(role), "roleAXError": Int(roleError.rawValue),
                    "identifier": text(identifier), "identifierAXError": Int(idError.rawValue),
                    "pid": pidFact(currentPID), "enabled": isEnabled, "enabledAXError": Int(enabledError.rawValue),
                    "description": text(description), "descriptionAXError": Int(descriptionError.rawValue),
                    "title": text(string(kAXTitleAttribute, current)), "help": text(string(kAXHelpAttribute, current)),
                    "idleDisplayMatches": description == expected.displayString,
                    "windowAXError": Int(windowError.rawValue), "windowPresent": currentWindow != nil,
                    "windowSameAsVerifiedSetupAXWindow": sameWindow,
                    "currentDiffersFromRetained": !CFEqual(current, retained)]) { _, new in new }
            }

            // The verified pre-input setup AXWindow must still be the host's unique, focused setup window.
            let (vRoleError, vRoleRaw) = copy(kAXRoleAttribute, verifiedAXWindow)
            let (vTitleError, vTitleRaw) = copy(kAXTitleAttribute, verifiedAXWindow)
            let verifiedPID = pid(verifiedAXWindow)
            let (windowsError, windowsRaw) = copy(kAXWindowsAttribute, app)
            let titled = (windowsRaw as? [AXUIElement] ?? []).filter { string(kAXTitleAttribute, $0) == Self.setupWindowTitle }
            let uniqueAXWindow = titled.count == 1 && CFEqual(titled[0], verifiedAXWindow)
            let (focusedWindowError, focusedWindowRaw) = copy(kAXFocusedWindowAttribute, app)
            let focusedIsSetup = axElement(focusedWindowRaw).map { CFEqual($0, verifiedAXWindow) } ?? false
            need(vRoleError == .success && vRoleRaw as? String == "AXWindow" && vTitleError == .success
                 && vTitleRaw as? String == Self.setupWindowTitle && verifiedPID == host,
                 "verified setup AXWindow is no longer the owned setup window")
            need(windowsError == .success && uniqueAXWindow, "verified setup AXWindow is not the unique titled window")
            need(focusedWindowError == .success && focusedIsSetup, "host focused AX window is not the verified setup window")

            let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
            let titledNSWindows = NSApp.windows.filter { $0.title == Self.setupWindowTitle }
            let uniqueNSWindow = titledNSWindows.count == 1 && titledNSWindows[0] === window
            need(NSApp.isActive, "host app is not active")
            need(uniqueNSWindow && window.isVisible && window.windowNumber == windowNumber,
                 "setup NSWindow is not the same unique visible window")
            need(window.isKeyWindow && NSApp.keyWindow === window, "setup NSWindow is not the key window")
            need(frontmostPID == host, "frontmost application is not the host")

            // Exact public stored value: effective, decoded and not cleared.
            let state = ShortcutStore.storedState(for: .undoLastWritingEdit)
            let decoded = state.shortcutData.flatMap { try? JSONDecoder().decode(Shortcut.self, from: $0) }
            let effective = ShortcutStore.shortcut(for: .undoLastWritingEdit)
            let cleared = ShortcutStore.isShortcutCleared(for: .undoLastWritingEdit)
            need(effective == expected && decoded == expected && !cleared,
                 "public stored shortcut is not exactly the expected chord")

            let ready = reasons.isEmpty && current != nil
            return ([
                "schemaVersion": 1, "kind": "recorder-post-capture-readback", "readOnly": true, "postsInput": false,
                "hostPID": Int(host), "systemUptime": ProcessInfo.processInfo.systemUptime,
                "identityAuthority": "current-exact-id-host-pid-same-verified-setup-axwindow",
                "retainedReferenceUsedForIdentity": false, "globalTitleFallbackUsed": false,
                "expectedDisplay": expected.displayString, "currentControl": control,
                "verifiedSetupAXWindow": ["roleAXError": Int(vRoleError.rawValue), "role": text(vRoleRaw as? String),
                                          "titleAXError": Int(vTitleError.rawValue), "title": text(vTitleRaw as? String),
                                          "pid": pidFact(verifiedPID), "windowsAXError": Int(windowsError.rawValue),
                                          "titledCount": titled.count, "uniqueSameReference": uniqueAXWindow,
                                          "focusedWindowAXError": Int(focusedWindowError.rawValue),
                                          "focusedWindowIsSetupWindow": focusedIsSetup] as [String: Any],
                "appKit": ["isActive": NSApp.isActive, "windowNumber": window.windowNumber,
                           "expectedWindowNumber": windowNumber, "isKeyWindow": window.isKeyWindow,
                           "isVisible": window.isVisible, "appKeyWindowIsSetup": NSApp.keyWindow === window,
                           "titledWindowCount": titledNSWindows.count, "uniqueSameWindow": uniqueNSWindow,
                           "frontmostPID": pidFact(frontmostPID)] as [String: Any],
                "store": ["effectiveEqualsExpected": effective == expected, "decodedEqualsExpected": decoded == expected,
                          "isShortcutCleared": cleared,
                          "ownShortcut": ownShortcutState("post-capture-readback", expected: expected)] as [String: Any],
                "ready": ready, "reasons": reasons], ready ? current : nil)
        }

        /// Bounded typed capture diagnostic in its own immutable file; never replaces or retries the failure.
        func retainCaptureFailure(_ stage: String, _ error: Error, inputPosted: Bool, facts: [String: Any]) {
            retainFailureFacts(["schemaVersion": 1, "kind": "recorder-capture-failure", "diagnosticOnly": true,
                                "stage": stage, "failure": String(describing: error), "inputPosted": inputPosted,
                                "retryUsed": false, "fallbackUsed": false, "facts": facts], Self.captureFailureFile)
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
                // The command is the element openMenu proved under the SAME
                // retained status item; no global or identifier lookup.
                try mark("case.\(id).menu-command-lookup.before")
                let session = opened.session
                try mark("case.\(id).menu-command-press.before")
                let activationClick = try await click(session.command, "case.\(id).menu-command", roles: ["AXMenuItem"],
                                                      identity: .statusOwnedMenuItem(status: session.status, title: session.title))
                command = opened.facts.merging(["activationClick": activationClick]) { _, new in new }
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
            let dismissal = try await dismissMenu(menu.session)
            try mark("busy.global-chord.before")
            try postChord()
            try mark("busy.notice-wait.before")
            let feedback = try await notice(expected: "RJT is busy right now, so Undo didn't replace any text.")
            try mark("busy.snapshot.before")
            let observed = try snapshot(editor)
            try expect(observed, value: result, range: caret)
            try require(owner.engine.writingActionUndoController.isAvailable, "A busy command consumed the native edit.")
            states["busy"] = ["passed": true, "recordingStateFixture": "busy", "menu": menu.facts, "dismissal": dismissal,
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

        // OBSERVED NSMenuItem IDENTITY CONTRACT (QA-only calibration from native run 40627170433; not a
        // product fix and no claim that the native pass succeeds). Through the SwiftUI MenuBarExtra ->
        // NSMenu bridge, the product Button surfaced as an AXMenuItem with the exact product title and an
        // EMPTY AXIdentifier, so its `.accessibilityIdentifier(menuCommand)` is not observable there. The
        // command is therefore identified only as: role AXMenuItem, exact `UndoLastWritingEditPresentation.title`,
        // host PID, the UNIQUE such descendant found by bounded traversal of the SAME retained status item
        // (itself host-owned with a direct parent equal to the host's own AXExtrasMenuBar) whose downward
        // path is a host-owned AXMenu chain, plus the unchanged actual center hit-test proof in `click`.
        // Native run 40629369072 observed that the NSMenu's AXParent is a host AXMenuBar, NOT the status
        // AXMenuBarItem, so the AX graph is not a reciprocal tree: upward AXParent reads are recorded raw as
        // `upwardParentDiagnostics` (diagnosticOnly, authorizationCondition false) and never authorize or
        // refuse. The actual identifier is recorded, never required or invented. There is no global, text
        // or identifier fallback; status and recorder contracts are unchanged.
        static let menuScanMaxDepth = 4
        static let menuScanMaxNodes = 64
        static let menuClosureMaxHitAncestors = 10

        /// The retained native menu identity from one proven open; reused for activation and dismissal.
        struct MenuSession {
            let status: AXUIElement, menu: AXUIElement, command: AXUIElement
            let openCenter: CGPoint, title: String, checkpoint: String
        }

        struct MenuScan {
            var facts: [String: Any]
            var command: AXUIElement?, menu: AXUIElement?, frame: CGRect?
        }

        func openMenu(expectedEnabled: Bool, checkpoint: String) async throws -> (facts: [String: Any], session: MenuSession) {
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
            let statusClick = try await click(status, "menu.\(checkpoint).status", roles: ["AXMenuBarItem", "AXButton"],
                                              identity: .identifier("undoControlHost.statusItem", fixtureTitle: "RJT Undo check"))
            try mark("menu.\(checkpoint).item-lookup.before")
            let title = UndoLastWritingEditPresentation.title
            var last = MenuScan(facts: ["attempted": false], command: nil, menu: nil, frame: nil)
            var polls = 0
            try mark("menu.\(checkpoint).enabled-wait.before")
            do {
                // Read-only polling of the same retained status reference; no input inside.
                try await wait("The status-owned menu command was not proven with the expected enabled state.") {
                    polls += 1
                    last = self.scanMenuCommand(status: status, title: title)
                    last.facts["expectedEnabled"] = expectedEnabled
                    last.facts["polls"] = polls
                    guard let command = last.command else { return false }
                    let visible = self.hasVisibleFrame(command), isEnabled = self.enabled(command)
                    last.facts["visibleFrame"] = visible
                    last.facts["enabledObserved"] = isEnabled
                    return visible && isEnabled == expectedEnabled
                }
            } catch {
                retainFailureFacts(last.facts, "menu-identity-\(checkpoint).json")
                throw UndoControlCheckFailure("\(error) [\(checkpoint): \(last.facts["reason"] as? String ?? "identity proven; visibility or enabled state differed")]")
            }
            guard let command = last.command, let menu = last.menu, let frame = last.frame else {
                retainFailureFacts(last.facts, "menu-identity-\(checkpoint).json")
                throw UndoControlCheckFailure("The status-owned menu command lost its proven identity at \(checkpoint).")
            }
            let session = MenuSession(status: status, menu: menu, command: command,
                                      openCenter: CGPoint(x: frame.midX, y: frame.midY), title: title, checkpoint: checkpoint)
            try mark("menu.\(checkpoint).item-describe.before")
            let observed = try describe(command, "menu.\(checkpoint).item")
            try require(observed["role"] as? String == "AXMenuItem",
                        "The status-owned Undo command was not a native AXMenuItem.")
            try mark("menu.\(checkpoint).hierarchy.before")
            try dumpHierarchy(checkpoint)
            try mark("menu.\(checkpoint).screenshot.before")
            try await screenshot(checkpoint)
            try mark("menu.\(checkpoint).status-describe.before")
            let statusControl = try describe(status, "menu.\(checkpoint).status")
            try mark("menu.\(checkpoint).exit")
            let facts = observed.merging(["kind": "product-menu", "statusControl": statusControl,
                                          "statusClick": statusClick, "nativeMenuIdentity": last.facts]) { _, new in new }
            return (facts, session)
        }

        /// Pure read-only bounded scan from the retained status item. Never marks, never posts. Every AX
        /// read whose error could hide a candidate fails the proof; uniqueness is never assumed past a bound.
        func scanMenuCommand(status: AXUIElement, title: String) -> MenuScan {
            let host = ProcessInfo.processInfo.processIdentifier
            func pidValue(_ value: pid_t?) -> Any { value.map { Int($0) as Any } ?? NSNull() }
            func summary(_ node: AXUIElement, depth: Int) -> [String: Any] {
                ["role": string(kAXRoleAttribute, node) ?? "", "identifier": string(kAXIdentifierAttribute, node) ?? "",
                 "title": string(kAXTitleAttribute, node) as Any? ?? NSNull(), "pid": pidValue(pid(node)), "depth": depth]
            }
            var facts: [String: Any] = [
                "schemaVersion": 2, "attempted": true, "kind": "native-menu-bridge-identity",
                "contract": "status-owned-native-menu-item-title", "expectedTitle": title, "expectedRole": "AXMenuItem",
                "identityAuthority": "retained-status-downward-subtree", "upwardParentAuthorizes": false,
                "hostPID": Int(host), "identifierRequired": false, "globalSearchUsed": false, "textFallbackUsed": false,
                "maxDepth": Self.menuScanMaxDepth, "maxNodes": Self.menuScanMaxNodes, "proven": false]
            func fail(_ reason: String) -> MenuScan {
                facts["reason"] = reason
                return MenuScan(facts: facts, command: nil, menu: nil, frame: nil)
            }

            // Owner: the same retained status reference, host-owned, directly under the host's AXExtrasMenuBar.
            let statusRole = string(kAXRoleAttribute, status) ?? ""
            let statusID = string(kAXIdentifierAttribute, status) ?? ""
            let statusPID = pid(status)
            let statusContract = statusID == "undoControlHost.statusItem" ? "identifier"
                : [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute].contains { string($0, status) == "RJT Undo check" }
                    ? "fixture-title" : ""
            let (parentError, parentRaw) = copy(kAXParentAttribute, status)
            let statusParent = parentRaw.flatMap { CFGetTypeID($0) == AXUIElementGetTypeID() ? ($0 as! AXUIElement) : nil }
            let extras = element("AXExtrasMenuBar", app)
            let extrasPID = extras.flatMap { pid($0) }
            let parentIsExtras = statusParent.map { parent in extras.map { CFEqual($0, parent) } ?? false } ?? false
            facts["status"] = [
                "role": statusRole, "identifier": statusID, "pid": pidValue(statusPID), "identityContract": statusContract,
                "sameRetainedReference": true, "parentAXError": Int(parentError.rawValue),
                "parentRole": statusParent.flatMap { string(kAXRoleAttribute, $0) } as Any? ?? NSNull(),
                "extrasMenuBarPresent": extras != nil, "extrasMenuBarPID": pidValue(extrasPID),
                "parentIsHostExtrasMenuBar": parentIsExtras] as [String: Any]
            guard statusPID == host, ["AXMenuBarItem", "AXButton"].contains(statusRole), !statusContract.isEmpty else {
                return fail("retained status item lost its host-owned identity")
            }
            guard parentError == .success, parentIsExtras, extrasPID == host else {
                return fail("retained status item is not a direct child of the host AXExtrasMenuBar")
            }

            // Bounded breadth-first descendant traversal from that status only.
            var queue: [(node: AXUIElement, depth: Int, path: [AXUIElement])] = [(status, 0, [])]
            var index = 0, truncated = false, otherRoleTitleMatches = 0
            var unreadable: [[String: Any]] = []
            var matches: [[AXUIElement]] = []
            while index < queue.count {
                let (node, depth, path) = queue[index]
                index += 1
                _ = AXUIElementSetMessagingTimeout(node, 0.05)
                let (childError, childRaw) = copy(kAXChildrenAttribute, node)
                let children: [AXUIElement]
                switch childError {
                case .success: children = childRaw as? [AXUIElement] ?? []
                case .noValue, .attributeUnsupported: children = []
                default:
                    unreadable.append(["depth": depth, "axError": Int(childError.rawValue)])
                    continue
                }
                if children.isEmpty { continue }
                if depth >= Self.menuScanMaxDepth { truncated = true; continue }
                for child in children {
                    guard queue.count < Self.menuScanMaxNodes else { truncated = true; break }
                    if string(kAXTitleAttribute, child) == title {
                        if string(kAXRoleAttribute, child) == "AXMenuItem" && pid(child) == host {
                            matches.append(path + [child])
                        } else {
                            otherRoleTitleMatches += 1
                        }
                    }
                    queue.append((child, depth + 1, path + [child]))
                }
            }
            facts["traversal"] = ["discoveredCount": queue.count, "expandedCount": index, "truncated": truncated,
                                  "unreadableChildren": unreadable, "exactMatchCount": matches.count,
                                  "otherRoleTitleMatches": otherRoleTitleMatches] as [String: Any]
            facts["uniqueMatch"] = matches.count == 1
            guard unreadable.isEmpty, !truncated else { return fail("bounded status subtree was not fully readable") }
            guard matches.count == 1, let path = matches.first, let command = path.last else {
                return fail("expected exactly one host AXMenuItem with the exact title under the status item")
            }
            let downward = path.enumerated().map { summary($0.element, depth: $0.offset + 1) }
            facts["downwardPath"] = downward
            let intermediates = path.dropLast()
            guard let menu = intermediates.last, string(kAXRoleAttribute, menu) == "AXMenu",
                  intermediates.allSatisfy({ ["AXMenu", "AXMenuItem"].contains(string(kAXRoleAttribute, $0) ?? "")
                      && pid($0) == host }) else {
                return fail("downward path is not a host-owned native submenu chain")
            }
            // Authoritative identity: everything checked above, all from the same retained status reference.
            facts["downwardProof"] = [
                "rootIsRetainedStatus": true, "statusParentIsHostExtrasMenuBar": true,
                "fullyReadable": true, "truncated": false, "uniqueExactMatch": true,
                "pathLength": path.count, "allHostPID": true, "menuRole": "AXMenu",
                "commandRole": "AXMenuItem", "exactTitle": title] as [String: Any]

            // DIAGNOSTICS ONLY, not an authorization condition: the native AX graph is not a reciprocal
            // tree (run 40629369072: menu AXParent was a host AXMenuBar, not the status item). Raw upward
            // reads, bounded to the downward path length, never change `proven` and never invent a backlink.
            var upward: [[String: Any]] = []
            var cursor = command
            let expectedUp = Array(intermediates.reversed()) + [status]
            for (level, expected) in expectedUp.enumerated() {
                let (error, raw) = copy(kAXParentAttribute, cursor)
                let parent = raw.flatMap { CFGetTypeID($0) == AXUIElementGetTypeID() ? ($0 as! AXUIElement) : nil }
                var entry: [String: Any] = ["level": level + 1, "axError": Int(error.rawValue),
                                            "elementPresent": parent != nil,
                                            "expectedDownwardRole": string(kAXRoleAttribute, expected) ?? ""]
                if let parent { entry.merge(summary(parent, depth: path.count - level - 1)) { _, new in new } }
                entry["matchesDownwardPath"] = parent.map { CFEqual($0, expected) } ?? false
                entry["isRetainedStatus"] = parent.map { CFEqual($0, status) } ?? false
                upward.append(entry)
                guard error == .success, let parent else { break }
                cursor = parent
            }
            let reciprocal = upward.count == expectedUp.count
                && upward.allSatisfy { $0["axError"] as? Int == 0 && $0["matchesDownwardPath"] as? Bool == true }
            facts["upwardParentDiagnostics"] = [
                "diagnosticOnly": true, "authorizationCondition": false, "maxLevels": expectedUp.count,
                "observations": upward, "reciprocalToDownwardPath": reciprocal,
                "reachesRetainedStatus": upward.contains { $0["isRetainedStatus"] as? Bool == true }] as [String: Any]

            var frame: CGRect?
            if let raw = attribute(kAXPositionAttribute, command), CFGetTypeID(raw) == AXValueGetTypeID(),
               let rawSize = attribute(kAXSizeAttribute, command), CFGetTypeID(rawSize) == AXValueGetTypeID() {
                var point = CGPoint.zero, size = CGSize.zero
                if AXValueGetValue(raw as! AXValue, .cgPoint, &point), AXValueGetValue(rawSize as! AXValue, .cgSize, &size),
                   point.x.isFinite, point.y.isFinite, size.width.isFinite, size.height.isFinite,
                   size.width > 0, size.height > 0 {
                    frame = CGRect(origin: point, size: size)
                }
            }
            let actualID = string(kAXIdentifierAttribute, command) ?? ""
            facts["command"] = ["role": "AXMenuItem", "title": title, "pid": Int(host), "identifier": actualID,
                                "identifierEmpty": actualID.isEmpty, "enabled": enabled(command),
                                "frame": frame.map { rect($0) as Any } ?? NSNull()] as [String: Any]
            guard frame != nil else { return fail("status-owned command frame was unavailable") }
            facts["proven"] = true
            facts["reason"] = NSNull()
            return MenuScan(facts: facts, command: command, menu: menu, frame: frame)
        }

        /// One Escape pair, then bounded read-only proof that the SAME retained status menu is no longer
        /// displayed: a successful system-wide hit test at the command's open-time center must resolve to an
        /// element outside the retained status/menu/command (another process, or a host element whose fully
        /// read ancestry reaches the host application without any native menu), and the status item's
        /// AXSelected must not read true. Any AX error keeps the menu "not proven closed"; no extra input.
        func dismissMenu(_ session: MenuSession) async throws -> [String: Any] {
            try postKey(UInt16(kVK_Escape), flags: [])
            var last: [String: Any] = ["attempted": false]
            var polls = 0
            do {
                try await wait("The native status menu did not dismiss.") {
                    polls += 1
                    let (closed, facts) = self.menuClosureObservation(session)
                    last = facts
                    return closed
                }
            } catch {
                last["polls"] = polls
                retainFailureFacts(last, "menu-dismissal-\(session.checkpoint).json")
                throw UndoControlCheckFailure("\(error) [\(session.checkpoint): \(last["reason"] as? String ?? "unknown")]")
            }
            return ["kind": "native-menu-dismissal", "contract": "same-status-owned-menu-not-displayed",
                    "escapeEventsPosted": 2, "inputRetries": 0, "polls": polls,
                    "statusRetainedFromOpen": true, "closure": last]
        }

        func menuClosureObservation(_ s: MenuSession) -> (Bool, [String: Any]) {
            let host = ProcessInfo.processInfo.processIdentifier
            var f: [String: Any] = ["schemaVersion": 1, "hostPID": Int(host), "axErrorTreatedAsClosed": false,
                                    "point": ["x": Double(s.openCenter.x), "y": Double(s.openCenter.y)]]
            func result(_ closed: Bool, _ reason: String?) -> (Bool, [String: Any]) {
                f["closed"] = closed
                f["reason"] = reason as Any? ?? NSNull()
                return (closed, f)
            }
            // Recorded facts on the same status submenu (informational; errors never mean closed).
            let (childError, childRaw) = copy(kAXChildrenAttribute, s.status)
            let children = childError == .success ? childRaw as? [AXUIElement] ?? [] : []
            f["statusChildrenAXError"] = Int(childError.rawValue)
            f["statusMenuChildCount"] = children.filter { string(kAXRoleAttribute, $0) == "AXMenu" }.count
            f["retainedMenuStillChild"] = children.contains { CFEqual($0, s.menu) }
            f["commandVisibleFrame"] = hasVisibleFrame(s.command)
            let (selectedError, selectedRaw) = copy(kAXSelectedAttribute, s.status)
            let selected = selectedError == .success ? (selectedRaw as? NSNumber)?.boolValue : nil
            f["statusSelectedAXError"] = Int(selectedError.rawValue)
            f["statusSelected"] = selected as Any? ?? NSNull()
            if selected == true { return result(false, "status item still reports AXSelected") }

            let systemWide = AXUIElementCreateSystemWide()
            var hitRef: AXUIElement?
            let hitError = AXUIElementCopyElementAtPosition(systemWide, Float(s.openCenter.x), Float(s.openCenter.y), &hitRef)
            f["hitAXError"] = Int(hitError.rawValue)
            guard hitError == .success, let hit = hitRef else { return result(false, "hit test failed") }
            guard let hitPID = pid(hit) else { return result(false, "hit element PID unreadable") }
            f["hitPID"] = Int(hitPID)
            f["hitRole"] = string(kAXRoleAttribute, hit) ?? ""
            if hitPID != host {
                f["evidence"] = "hit-other-process"
                return result(true, nil)
            }
            var node = hit
            var chain: [String] = []
            for _ in 0...Self.menuClosureMaxHitAncestors {
                if CFEqual(node, s.status) || CFEqual(node, s.menu) || CFEqual(node, s.command) {
                    f["hitAncestry"] = chain
                    return result(false, "hit test still reaches the retained status menu")
                }
                let role = string(kAXRoleAttribute, node) ?? ""
                chain.append(role)
                f["hitAncestry"] = chain
                if ["AXMenu", "AXMenuItem", "AXMenuBarItem"].contains(role) {
                    return result(false, "hit test reaches a host native menu element")
                }
                if CFEqual(node, app) {
                    f["evidence"] = "hit-host-non-menu-element"
                    return result(true, nil)
                }
                let (error, raw) = copy(kAXParentAttribute, node)
                guard error == .success, let raw, CFGetTypeID(raw) == AXUIElementGetTypeID() else {
                    return result(false, "hit ancestry unreadable (\(error.rawValue))")
                }
                node = raw as! AXUIElement
            }
            return result(false, "hit ancestry exceeded its bound")
        }

        /// Failure-path diagnostic retention; a write failure is reported and never replaces the original error.
        func retainFailureFacts(_ facts: [String: Any], _ name: String) {
            do { try writeJSON(facts, to: owner.output.appendingPathComponent(name)) }
            catch { fputs("Undo control identity facts not written (\(name)): \(error)\n", stderr) }
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

        /// Read-only facts and the frozen proof from one fully ready pre-input observation.
        struct ClickProof {
            let frame: CGRect, center: CGPoint, display: CGDirectDisplayID, bounds: CGRect
            let id: String, role: String, contract: String, depth: Int, policy: String
            let targetWindowPresent: Bool, hitWindowPresent: Bool, windowOwned: Bool, menuAncestor: String
            let menuIdentity: [String: Any]?
        }

        /// Click identity contracts. `.identifier` is the unchanged contract for the recorder (strict ID) and
        /// status item (ID or fixture title) via the global owned-node scan. `.statusOwnedMenuItem` is the
        /// observed NSMenuItem contract (see `scanMenuCommand`): no identifier, only the exact title,
        /// AXMenuItem role and host PID as the unique descendant of the SAME retained status item.
        enum ClickIdentity {
            case identifier(String, fixtureTitle: String?)
            case statusOwnedMenuItem(status: AXUIElement, title: String)
        }

        /// PRE-INPUT READINESS / CALIBRATION EXPERIMENT (not a confirmed display or root-cause fix).
        /// Native run 40624443133 refused before any input because the status item frame was not in
        /// exactly one active display, without saving the raw facts. Here each read-only attempt writes
        /// its raw observation before deciding, and a not-ready attempt may wait boundedly. Every guard
        /// is unchanged (unique same-reference control, role, identifier/title, enabled, host PID, finite
        /// AX frame inside exactly one CG display, owned hit-test ancestry, window or native-menu policy,
        /// stable frame). No clamping, alternate control, AX action, activation or post-input retry.
        static let readinessMaxAttempts = 6
        static let readinessDeadlineSeconds: TimeInterval = 6
        static let readinessIntervalMilliseconds = 1000

        /// Native input transport for the host's own controls: one genuine left click at the observed
        /// AX frame center (AX global top-left coordinates, the CG display space), posted only after a
        /// fully ready read-only observation. The read-only readiness loop lives in this same function and
        /// never posts; each attempt's observation is written as its own immutable file before the decision,
        /// and diagnostic write or mark failures propagate. The loop's only await is the not-ready sleep
        /// before the next attempt, so the final observeReadiness, its write, the proof and both posts run
        /// synchronously with no suspension point. Posting is after the loop, at most once, never retried.
        func click(_ target: AXUIElement, _ checkpoint: String, roles: [String],
                   identity: ClickIdentity) async throws -> [String: Any] {
            let s = "click." + checkpoint
            let start = ProcessInfo.processInfo.systemUptime
            let deadline = start + Self.readinessDeadlineSeconds
            var files: [String] = []
            var lastReason = ""
            var ready: (proof: ClickProof, summary: [String: Any])?
            for attempt in 1...Self.readinessMaxAttempts {
                let (observation, attemptProof) = try observeReadiness(target, s, attempt: attempt, roles: roles,
                                                                       identity: identity)
                let name = "click-readiness-\(checkpoint)-attempt-\(attempt).json"
                try marked(s + ".a\(attempt).observation-write") {
                    try writeJSON(observation, to: owner.output.appendingPathComponent(name))
                }
                files.append(name)
                if let attemptProof {
                    ready = (attemptProof, [
                        "experiment": "preinput-readiness-calibration", "attemptCount": attempt,
                        "maxAttempts": Self.readinessMaxAttempts, "deadlineSeconds": Self.readinessDeadlineSeconds,
                        "intervalMilliseconds": Self.readinessIntervalMilliseconds,
                        "elapsedSeconds": ProcessInfo.processInfo.systemUptime - start,
                        "noInputBeforeReady": true, "finalObservation": name, "finalObservationReady": true,
                        "observations": files])
                    break
                }
                lastReason = observation["reason"] as? String ?? "unknown"
                let nextAt = ProcessInfo.processInfo.systemUptime + Double(Self.readinessIntervalMilliseconds) / 1000
                if attempt == Self.readinessMaxAttempts || nextAt > deadline { break }
                try await Task.sleep(for: .milliseconds(Self.readinessIntervalMilliseconds))
            }
            guard let ready else {
                throw UndoControlCheckFailure("Native click refused at \(s): \(lastReason) "
                    + "[pre-input readiness calibration experiment: not ready after \(files.count) read-only attempt(s) "
                    + "(max \(Self.readinessMaxAttempts), deadline \(Self.readinessDeadlineSeconds)s); no input posted; "
                    + "observations: \(files.joined(separator: ", "))]")
            }
            let (proof, readiness) = ready
            // Posting phase: synchronous from the final proof to both posts; never retried.
            guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: proof.center, mouseButton: .left),
                  let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: proof.center, mouseButton: .left) else {
                throw UndoControlCheckFailure("Native click refused at \(s): cannot create native mouse events")
            }
            for event in [down, up] {
                event.flags = []
                event.setIntegerValueField(.mouseEventClickState, value: 1)
            }
            try mark(s + ".post.before")
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
            try mark(s + ".post.after")
            let host = Int(ProcessInfo.processInfo.processIdentifier)
            return ["kind": "native-mouse-click", "eventTypes": ["leftMouseDown", "leftMouseUp"], "eventCount": 2,
                    "tap": "cghidEventTap", "clickState": 1, "flagsRawValue": 0,
                    "hostPID": host, "targetID": proof.id, "targetRole": proof.role, "identityContract": proof.contract,
                    "targetFrame": rect(proof.frame), "point": ["x": Double(proof.center.x), "y": Double(proof.center.y)],
                    "activeDisplayID": Int(proof.display), "activeDisplayBounds": rect(proof.bounds), "hitPID": host,
                    "hitDepth": proof.depth, "sameTargetOrDescendant": true, "uniqueTarget": true, "frameStable": true,
                    "targetOwnedByHost": true, "hitOwnedByHost": true, "windowPolicy": proof.policy,
                    "targetWindowPresent": proof.targetWindowPresent, "hitWindowPresent": proof.hitWindowPresent,
                    "sameWindow": proof.policy == "same-window", "windowOwnedByHost": proof.windowOwned,
                    "nativeMenuAncestry": !proof.menuAncestor.isEmpty, "menuAncestorRole": proof.menuAncestor,
                    "nativeMenuIdentity": proof.menuIdentity.map { $0 as Any } ?? NSNull(),
                    "readiness": readiness]
        }

        /// One read-only pre-input observation. Predicate failures return `nil` proof with the reason and all
        /// facts read so far; sections never reached stay `{"attempted": false}`. Only marks throw.
        func observeReadiness(_ target: AXUIElement, _ s: String, attempt: Int, roles: [String],
                              identity: ClickIdentity) throws -> ([String: Any], ClickProof?) {
            let p = s + ".a\(attempt)"
            let host = ProcessInfo.processInfo.processIdentifier
            let unattempted: [String: Any] = ["attempted": false]
            let expected: [String: Any]
            switch identity {
            case let .identifier(identifier, title):
                expected = ["identifier": identifier, "title": title as Any? ?? NSNull(), "roles": roles,
                            "contract": "identifier-or-fixture-title", "identifierRequired": title == nil]
            case let .statusOwnedMenuItem(_, title):
                expected = ["identifier": NSNull(), "title": title, "roles": roles,
                            "contract": "status-owned-native-menu-item-title", "identifierRequired": false]
            }
            var obs: [String: Any] = [
                "schemaVersion": 1, "kind": "native-click-preinput-readiness-observation", "diagnosticOnly": true,
                "experiment": "preinput-readiness-calibration", "checkpoint": s, "attempt": attempt,
                "maxAttempts": Self.readinessMaxAttempts, "inputPosted": false, "hostPID": Int(host),
                "systemUptime": ProcessInfo.processInfo.systemUptime,
                "coordinateSpace": "AX global top-left (CG display space); no NSScreen or pixel conversion",
                "expected": expected, "nativeMenuIdentity": unattempted, "identity": unattempted,
                "target": unattempted, "frame": unattempted, "provenance": unattempted,
                "displays": unattempted, "hitTest": unattempted, "window": unattempted, "frameRecheck": unattempted]
            func notReady(_ reason: String) -> ([String: Any], ClickProof?) {
                obs["ready"] = false
                obs["reason"] = reason
                return (obs, nil)
            }

            let labels = [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute]
            let current: [AXUIElement]
            var menuIdentity: [String: Any]?
            switch identity {
            case let .identifier(identifier, title):
                current = try marked(p + ".unique-scan") {
                    nodes().filter { node in
                        (string(kAXIdentifierAttribute, node) == identifier
                            || (title != nil && roles.contains(string(kAXRoleAttribute, node) ?? "")
                                && labels.contains { string($0, node) == title }))
                            && hasVisibleFrame(node)
                    }
                }
            case let .statusOwnedMenuItem(status, title):
                // Bounded scan of the same retained status subtree only; same 2 records as the global scan.
                let scan = try marked(p + ".owner-scan") { scanMenuCommand(status: status, title: title) }
                menuIdentity = scan.facts
                obs["nativeMenuIdentity"] = scan.facts
                current = (scan.facts["proven"] as? Bool == true ? scan.command.map { [$0] } ?? [] : [])
                    .filter { hasVisibleFrame($0) }
            }
            // Same-reference check is recorded, never weakened: a different element is never substituted.
            let sameReference = current.count == 1 && CFEqual(current[0], target)
            obs["identity"] = ["attempted": true, "uniqueCount": current.count, "sameReferenceAsLookup": sameReference,
                               "scope": menuIdentity == nil ? "host-owned-nodes" : "retained-status-subtree"] as [String: Any]
            guard sameReference else { return notReady("target is not the current unique control") }

            var targetFacts: [String: Any] = ["attempted": true]
            let role = try marked(p + ".role") { string(kAXRoleAttribute, target) } ?? ""
            let id = try marked(p + ".identifier") { string(kAXIdentifierAttribute, target) } ?? ""
            let axTitle = try marked(p + ".title-attribute") { string(kAXTitleAttribute, target) }
            targetFacts["role"] = role
            targetFacts["identifier"] = id
            targetFacts["title"] = axTitle as Any? ?? NSNull()
            obs["target"] = targetFacts
            guard roles.contains(role) else { return notReady("unexpected role \(role)") }
            var contract = "identifier"
            switch identity {
            case let .identifier(identifier, title):
                if id != identifier {
                    guard let title else { return notReady("identifier mismatch") }
                    var matched = false
                    for (index, name) in labels.enumerated() where !matched {
                        matched = try marked(p + ".title.\(index)") { string(name, target) } == title
                    }
                    guard matched else { return notReady("neither identifier nor fixture title matched") }
                    contract = "fixture-title"
                }
            case let .statusOwnedMenuItem(_, title):
                // Native identifier recorded (observed empty), never required; exact AXTitle is mandatory.
                targetFacts["identifierEmpty"] = id.isEmpty
                guard role == "AXMenuItem", axTitle == title else { return notReady("exact product menu title mismatch") }
                contract = "status-owned-native-menu-item-title"
            }
            targetFacts["identityContract"] = contract
            let isEnabled = try marked(p + ".enabled") { enabled(target) }
            targetFacts["enabled"] = isEnabled
            obs["target"] = targetFacts
            guard isEnabled else { return notReady("control is disabled") }
            let targetPID = try marked(p + ".pid") { pid(target) }
            targetFacts["pid"] = targetPID.map { Int($0) as Any } ?? NSNull()
            obs["target"] = targetFacts
            guard targetPID == host else { return notReady("target is not owned by the host") }

            let (frameOrNil, frameFacts) = try readFrame(target, p + ".frame")
            obs["frame"] = frameFacts
            guard let frame = frameOrNil else {
                return notReady("the actual control frame was unavailable or invalid at \(p).frame")
            }
            let center = CGPoint(x: frame.midX, y: frame.midY)
            guard frame.contains(center) else { return notReady("center outside frame") }

            // Bounded parent provenance distinguishes the app menu bar from AXExtrasMenuBar; facts only.
            let menuBar = try marked(p + ".root-menu-bar") { element(kAXMenuBarAttribute, app) }
            let extras = try marked(p + ".root-extras-menu-bar") { element("AXExtrasMenuBar", app) }
            var chain: [[String: Any]] = []
            var rootKind = "unresolved-within-bound"
            var cursor = target
            for level in 0..<4 {
                guard let parent = try marked(p + ".provenance-parent.\(level)", { element(kAXParentAttribute, cursor) }) else {
                    rootKind = "no-parent"
                    break
                }
                let parentRole = try marked(p + ".provenance-role.\(level)") { string(kAXRoleAttribute, parent) } ?? ""
                let parentID = try marked(p + ".provenance-identifier.\(level)") { string(kAXIdentifierAttribute, parent) } ?? ""
                let parentTitle = try marked(p + ".provenance-title.\(level)") { string(kAXTitleAttribute, parent) } ?? ""
                let parentPID = try marked(p + ".provenance-pid.\(level)") { pid(parent) }
                let isMenuBar = menuBar.map { CFEqual($0, parent) } ?? false
                let isExtras = extras.map { CFEqual($0, parent) } ?? false
                let isApp = CFEqual(app, parent)
                chain.append(["role": parentRole, "identifier": parentID, "title": parentTitle,
                              "depth": level + 1, "pid": parentPID.map { Int($0) as Any } ?? NSNull(),
                              "isAppMenuBar": isMenuBar, "isExtrasMenuBar": isExtras, "isApplication": isApp])
                if isMenuBar { rootKind = "app-menu-bar"; break }
                if isExtras { rootKind = "extras-menu-bar"; break }
                if isApp { rootKind = "application"; break }
                cursor = parent
            }
            obs["provenance"] = ["attempted": true, "maxDepth": 4, "appMenuBarPresent": menuBar != nil,
                                 "extrasMenuBarPresent": extras != nil, "ancestors": chain, "rootKind": rootKind] as [String: Any]

            var displayCount: UInt32 = 0
            var displays = [CGDirectDisplayID](repeating: 0, count: 32)
            let displayError = try marked(p + ".displays") { CGGetActiveDisplayList(32, &displays, &displayCount) }
            var displayFacts: [String: Any] = ["attempted": true, "apiError": Int(displayError.rawValue),
                                               "count": Int(displayCount)]
            guard displayError == .success else {
                obs["displays"] = displayFacts
                return notReady("active display list unavailable")
            }
            let active = Array(displays.prefix(Int(displayCount)))
            displayFacts["displays"] = active.map { display -> [String: Any] in
                let bounds = CGDisplayBounds(display)
                return ["id": Int(display), "bounds": rect(bounds), "containsTarget": bounds.contains(frame),
                        "containsCenter": bounds.contains(center), "intersectsTarget": bounds.intersects(frame)]
            }
            let containing = active.filter { CGDisplayBounds($0).contains(frame) }
            displayFacts["containingCount"] = containing.count
            obs["displays"] = displayFacts
            guard containing.count == 1, let display = containing.first else {
                return notReady("frame is not contained in exactly one active display")
            }
            let bounds = CGDisplayBounds(display)

            let systemWide = AXUIElementCreateSystemWide()
            var hitRef: AXUIElement?
            let hitError = try marked(p + ".hit-test") { () -> AXError in
                return AXUIElementCopyElementAtPosition(systemWide, Float(center.x), Float(center.y), &hitRef)
            }
            var hitFacts: [String: Any] = ["attempted": true, "point": ["x": Double(center.x), "y": Double(center.y)],
                                           "axError": Int(hitError.rawValue), "elementPresent": hitRef != nil]
            obs["hitTest"] = hitFacts
            guard hitError == .success, let hit = hitRef else { return notReady("hit test failed (\(hitError.rawValue))") }
            let hitPID = try marked(p + ".hit-pid") { pid(hit) }
            hitFacts["pid"] = hitPID.map { Int($0) as Any } ?? NSNull()
            obs["hitTest"] = hitFacts
            guard hitPID == host else { return notReady("hit element belongs to another process") }
            var node = hit, depth = 0
            while !CFEqual(node, target) {
                guard depth < 8, let parent = try marked(p + ".hit-ancestor.\(depth)", { element(kAXParentAttribute, node) }) else {
                    hitFacts["reachedTarget"] = false
                    hitFacts["walkedDepth"] = depth
                    obs["hitTest"] = hitFacts
                    return notReady("hit element is not the target or its descendant")
                }
                node = parent
                depth += 1
            }
            hitFacts["reachedTarget"] = true
            hitFacts["depth"] = depth
            obs["hitTest"] = hitFacts

            let targetWindow = try marked(p + ".target-window") { element(kAXWindowAttribute, target) }
            let hitWindow = try marked(p + ".hit-window") { element(kAXWindowAttribute, hit) }
            var windowFacts: [String: Any] = ["attempted": true, "targetWindowPresent": targetWindow != nil,
                                              "hitWindowPresent": hitWindow != nil]
            obs["window"] = windowFacts
            var policy = "", windowOwned = false, menuAncestor = ""
            if let targetWindow, let hitWindow {
                guard CFEqual(targetWindow, hitWindow) else { return notReady("hit element is in another window") }
                windowOwned = try marked(p + ".window-pid") { pid(targetWindow) } == host
                windowFacts["windowOwnedByHost"] = windowOwned
                obs["window"] = windowFacts
                guard windowOwned else { return notReady("window is not owned by the host") }
                policy = "same-window"
            } else if targetWindow == nil, hitWindow == nil, ["AXMenuItem", "AXMenuBarItem"].contains(role) {
                var ancestor = target
                for level in 0..<6 where menuAncestor.isEmpty {
                    guard let parent = try marked(p + ".menu-ancestor.\(level)", { element(kAXParentAttribute, ancestor) }),
                          try marked(p + ".menu-ancestor-pid.\(level)", { pid(parent) }) == host else {
                        return notReady("windowless control lacks owned native menu ancestry")
                    }
                    let parentRole = try marked(p + ".menu-ancestor-role.\(level)") { string(kAXRoleAttribute, parent) } ?? ""
                    if ["AXMenu", "AXMenuBar"].contains(parentRole) { menuAncestor = parentRole }
                    ancestor = parent
                }
                windowFacts["menuAncestorRole"] = menuAncestor
                obs["window"] = windowFacts
                guard !menuAncestor.isEmpty else { return notReady("windowless control lacks native menu ancestry") }
                policy = "windowless-native-menu"
            } else {
                return notReady("window ownership is ambiguous")
            }
            windowFacts["policy"] = policy
            obs["window"] = windowFacts

            let (recheck, rawRecheckFacts) = try readFrame(target, p + ".frame-recheck")
            var recheckFacts = rawRecheckFacts
            recheckFacts["stable"] = recheck == frame
            obs["frameRecheck"] = recheckFacts
            guard recheck == frame else { return notReady("frame changed before posting") }
            obs["ready"] = true
            obs["reason"] = NSNull()
            return (obs, ClickProof(frame: frame, center: center, display: display, bounds: bounds, id: id, role: role,
                                    contract: contract, depth: depth, policy: policy,
                                    targetWindowPresent: targetWindow != nil, hitWindowPresent: hitWindow != nil,
                                    windowOwned: windowOwned, menuAncestor: menuAncestor, menuIdentity: menuIdentity))
        }

        func marked<T>(_ stage: String, _ body: () throws -> T) throws -> T {
            try mark(stage + ".before")
            let value = try body()
            try mark(stage + ".after")
            return value
        }

        /// Raw AX frame facts. Returns a rect only for decodable, finite, positive values; never throws a
        /// predicate failure (only marks throw). Non-finite raw numbers are kept as strings for JSON.
        func readFrame(_ node: AXUIElement, _ stage: String) throws -> (CGRect?, [String: Any]) {
            let rawPosition = try marked(stage + ".position") { attribute(kAXPositionAttribute, node) }
            let rawSize = try marked(stage + ".size") { attribute(kAXSizeAttribute, node) }
            var point = CGPoint(x: CGFloat.nan, y: .nan), size = CGSize(width: CGFloat.nan, height: .nan)
            var positionDecoded = false, sizeDecoded = false
            if let rawPosition, CFGetTypeID(rawPosition) == AXValueGetTypeID() {
                positionDecoded = AXValueGetValue(rawPosition as! AXValue, .cgPoint, &point)
            }
            if let rawSize, CFGetTypeID(rawSize) == AXValueGetTypeID() {
                sizeDecoded = AXValueGetValue(rawSize as! AXValue, .cgSize, &size)
            }
            func number(_ value: CGFloat) -> Any { value.isFinite ? Double(value) : String(describing: Double(value)) }
            var facts: [String: Any] = ["attempted": true, "positionRead": rawPosition != nil, "sizeRead": rawSize != nil,
                                        "positionDecoded": positionDecoded, "sizeDecoded": sizeDecoded]
            if positionDecoded { facts["x"] = number(point.x); facts["y"] = number(point.y) }
            if sizeDecoded { facts["width"] = number(size.width); facts["height"] = number(size.height) }
            let valid = positionDecoded && sizeDecoded && point.x.isFinite && point.y.isFinite
                && size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0
            facts["finitePositive"] = valid
            guard valid else { return (nil, facts) }
            let frame = CGRect(origin: point, size: size)
            facts["center"] = ["x": Double(frame.midX), "y": Double(frame.midY)]
            return (frame, facts)
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
        /// Attribute read that keeps the AXError, for predicates that must never read an error as absence.
        func copy(_ name: String, _ node: AXUIElement) -> (AXError, CFTypeRef?) {
            var value: CFTypeRef?
            let error = AXUIElementCopyAttributeValue(node, name as CFString, &value)
            return (error, error == .success ? value : nil)
        }
        func attribute(_ name: String, _ node: AXUIElement) -> CFTypeRef? {
            var value: CFTypeRef?
            return AXUIElementCopyAttributeValue(node, name as CFString, &value) == .success ? value : nil
        }
    }
}
