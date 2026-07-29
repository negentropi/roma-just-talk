import Foundation
import AppKit
import Carbon
import os
import VoiceInkCore

class CursorPaster {
    fileprivate typealias ClipboardItemSnapshot = [(NSPasteboard.PasteboardType, Data)]
    fileprivate typealias ClipboardSnapshot = [ClipboardItemSnapshot]
    private static let logger = Logger(
        subsystem: VoiceInkAppIdentity.loggingSubsystem,
        category: VoiceInkMacOSLogCategory.cursorPaster
    )
    @MainActor private static var pasteCommandPosterForTesting: (() async -> PasteResult)?

    struct PreparedPasteContext {
        fileprivate let changeCount: Int
        fileprivate let savedContents: ClipboardSnapshot
    }

    enum PasteResult: Equatable {
        case commandPosted
        case commandNotPosted

        var didPostPasteCommand: Bool {
            self == .commandPosted
        }
    }

    static func pasteAtCursor(_ text: String) {
        Task {
            let pasteTask = await MainActor.run {
                startPasteAtCursor(text)
            }
            _ = await pasteTask.value
        }
    }

    @MainActor
    static func preparedTextForPaste(_ text: String) -> String {
        let plan = VoiceInkTranscriptionPasteOutputPolicy.cursorPasteTextPlan(text)
        return plan.text(
            beforeCursor: plan.shouldReadCursorContext ? CursorTextContextReader.textBeforeCursor() : nil
        )
    }

    @MainActor
    static func preparedTextForPaste(
        _ text: String,
        preparedCursorTextContext: Task<CursorTextContextReader.PreparedContext?, Never>?
    ) async -> String {
        let plan = VoiceInkTranscriptionPasteOutputPolicy.cursorPasteTextPlan(text)
        guard plan.shouldReadCursorContext else { return text }

        let beforeCursor = if let preparedCursorTextContext {
            CursorTextContextReader.textBeforeCursor(
                preparedContext: await preparedCursorTextContext.value
            )
        } else {
            CursorTextContextReader.textBeforeCursor()
        }
        return plan.text(beforeCursor: beforeCursor)
    }

    @MainActor
    static func configurePasteCommandPosterForTesting(_ poster: (() async -> PasteResult)? = nil) {
        pasteCommandPosterForTesting = poster
    }

    @MainActor
    @discardableResult
    static func startPasteAtCursor(
        _ text: String,
        preparedContext: PreparedPasteContext? = nil,
        latencyTraceToken: VoiceInkLatencyTrace.Token? = nil
    ) -> Task<PasteResult, Never> {
        let traceToken = latencyTraceToken ?? VoiceInkLatencyTrace.shared.currentToken()
        return Task { @MainActor in
            await performPasteSession(
                text,
                preparedContext: preparedContext,
                latencyTraceToken: traceToken
            )
        }
    }

    @MainActor
    static func pasteAtCursorAndWaitUntilPosted(_ text: String) async -> PasteResult {
        await startPasteAtCursor(text).value
    }

    @MainActor
    static func preparePasteContext() -> PreparedPasteContext? {
        guard VoiceInkPastePreference.shouldRestoreClipboardAfterPaste() else {
            return nil
        }

        let pasteboard = NSPasteboard.general
        return PreparedPasteContext(
            changeCount: pasteboard.changeCount,
            savedContents: snapshotClipboard(from: pasteboard)
        )
    }

    @MainActor
    private static func performPasteSession(
        _ text: String,
        preparedContext: PreparedPasteContext? = nil,
        latencyTraceToken: VoiceInkLatencyTrace.Token?
    ) async -> PasteResult {
        let latencyTrace = VoiceInkLatencyTrace.shared
        let pasteboard = NSPasteboard.general
        let shouldRestoreClipboard = VoiceInkPastePreference.shouldRestoreClipboardAfterPaste()
        latencyTrace.event(
            "paste_session.enter",
            details: "chars=\(text.count) restoreClipboard=\(shouldRestoreClipboard) method=\(VoiceInkPasteMethod.current().rawValue)",
            token: latencyTraceToken
        )
        let clipboardSnapshotSpan = latencyTrace.begin(
            "paste_session.snapshot_clipboard",
            token: latencyTraceToken
        )
        let savedContents: ClipboardSnapshot = if shouldRestoreClipboard {
            if let preparedContext,
               preparedContext.changeCount == pasteboard.changeCount {
                preparedContext.savedContents
            } else {
                snapshotClipboard(from: pasteboard)
            }
        } else {
            []
        }
        latencyTrace.end(
            clipboardSnapshotSpan,
            details: "items=\(savedContents.count)"
        )
        let sessionID = UUID().uuidString

        let clipboardWriteSpan = latencyTrace.begin(
            "paste_session.write_clipboard",
            token: latencyTraceToken
        )
        guard ClipboardManager.setClipboard(
            text,
            transient: shouldRestoreClipboard,
            sessionID: shouldRestoreClipboard ? sessionID : nil
        ) else {
            latencyTrace.end(clipboardWriteSpan, details: "result=failure")
            logger.error("\(VoiceInkPasteDiagnostics.failedToPrepareClipboardMessage, privacy: .public)")
            return .commandNotPosted
        }
        latencyTrace.end(clipboardWriteSpan, details: "result=success")

        let commandSpan = latencyTrace.begin("paste_session.post_command", token: latencyTraceToken)
        let pasteResult = await postPasteCommand(latencyTraceToken: latencyTraceToken)
        latencyTrace.end(
            commandSpan,
            details: "result=\(String(describing: pasteResult))"
        )
        if shouldRestoreClipboard, pasteResult.didPostPasteCommand {
            latencyTrace.event(
                "paste_session.restore_scheduled",
                details: "delayMs=\(String(format: "%.1f", VoiceInkPastePreference.boundedClipboardRestoreDelay() * 1_000))",
                token: latencyTraceToken
            )
            scheduleClipboardRestore(
                savedContents,
                expectedText: text,
                sessionID: sessionID,
                on: pasteboard,
                latencyTraceToken: latencyTraceToken
            )
        } else if shouldRestoreClipboard {
            logger.notice("\(VoiceInkPasteDiagnostics.skippedClipboardRestoreCommandNotPostedMessage, privacy: .public)")
        }

        return pasteResult
    }

    private static func snapshotClipboard(from pasteboard: NSPasteboard) -> ClipboardSnapshot {
        (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in
                if let data = item.data(forType: type) {
                    return (type, data)
                }
                return nil
            }
        }
    }

    @MainActor
    private static func postPasteCommand(
        latencyTraceToken: VoiceInkLatencyTrace.Token?
    ) async -> PasteResult {
        if let pasteCommandPosterForTesting {
            return await pasteCommandPosterForTesting()
        }

        if VoiceInkPasteMethod.current() == .appleScript {
            let didPost = pasteUsingAppleScript()
            if didPost {
                VoiceInkLatencyTrace.shared.event(
                    "paste_event_posted",
                    details: "method=appleScript",
                    token: latencyTraceToken
                )
            }
            return didPost ? .commandPosted : .commandNotPosted
        } else {
            return await pasteFromClipboard(latencyTraceToken: latencyTraceToken)
        }
    }

    private static func scheduleClipboardRestore(
        _ savedContents: ClipboardSnapshot,
        expectedText: String,
        sessionID: String,
        on pasteboard: NSPasteboard,
        latencyTraceToken: VoiceInkLatencyTrace.Token?
    ) {
        let delay = VoiceInkPastePreference.boundedClipboardRestoreDelay()

        Task { @MainActor in
            await wait(delay)
            guard pasteboardStillOwnedByPasteSession(pasteboard, expectedText: expectedText, sessionID: sessionID) else {
                VoiceInkLatencyTrace.shared.event(
                    "paste_session.restore_skipped",
                    details: "reason=clipboard_changed",
                    token: latencyTraceToken
                )
                return
            }
            pasteboard.clearContents()
            if !savedContents.isEmpty {
                pasteboard.writeObjects(pasteboardItems(from: savedContents))
            }
            VoiceInkLatencyTrace.shared.event(
                "paste_session.restore_executed",
                details: "items=\(savedContents.count)",
                token: latencyTraceToken
            )
        }
    }

    private static func pasteboardStillOwnedByPasteSession(
        _ pasteboard: NSPasteboard,
        expectedText: String,
        sessionID: String
    ) -> Bool {
        pasteboard.string(forType: .string) == expectedText &&
            pasteboard.string(forType: ClipboardManager.pasteSessionType) == sessionID
    }

    private static func pasteboardItems(from snapshot: ClipboardSnapshot) -> [NSPasteboardItem] {
        snapshot.map { itemSnapshot in
            let item = NSPasteboardItem()
            for (type, data) in itemSnapshot {
                item.setData(data, forType: type)
            }
            return item
        }
    }

    // MARK: - AppleScript paste

    // "X – QWERTY ⌘" layouts remap to QWERTY when Command is held, so keystroke "v" resolves
    // the wrong key code. key code 9 (physical V) bypasses layout translation for those layouts.
    private static func makeScript(_ source: String) -> NSAppleScript? {
        let script = NSAppleScript(source: source)
        var error: NSDictionary?
        script?.compileAndReturnError(&error)
        return script
    }

    private static let pasteScriptKeystroke = makeScript("tell application \"System Events\" to keystroke \"v\" using command down")
    private static let pasteScriptKeyCode   = makeScript("tell application \"System Events\" to key code 9 using command down")

    @MainActor
    private static var layoutSwitchesToQWERTYOnCommand: Bool {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        guard let nameRef = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) else { return false }
        return (Unmanaged<CFString>.fromOpaque(nameRef).takeUnretainedValue() as String).hasSuffix("⌘")
    }

    @MainActor
    private static func pasteUsingAppleScript() -> Bool {
        guard let script = layoutSwitchesToQWERTYOnCommand ? pasteScriptKeyCode : pasteScriptKeystroke else {
            logger.error("\(VoiceInkPasteDiagnostics.appleScriptPasteScriptUnavailableMessage, privacy: .public)")
            return false
        }

        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if let error {
            let message = VoiceInkPasteDiagnostics.appleScriptPasteFailedMessage(
                errorDescription: String(describing: error)
            )
            logger.error("\(message, privacy: .public)")
        }
        return error == nil
    }

    // MARK: - CGEvent paste

    // Posts Cmd+V via CGEvent without modifying the active input source.
    @MainActor
    private static func pasteFromClipboard(
        latencyTraceToken: VoiceInkLatencyTrace.Token?
    ) async -> PasteResult {
        VoiceInkLatencyTrace.shared.event(
            "paste_cgevent.enter",
            token: latencyTraceToken
        )
        guard AXIsProcessTrusted() else {
            VoiceInkLatencyTrace.shared.event(
                "paste_cgevent.accessibility_denied",
                token: latencyTraceToken
            )
            logger.error(
                "\(VoiceInkPasteDiagnostics.accessibilityPermissionRequiredForSimulatedPasteMessage, privacy: .public)"
            )
            return .commandNotPosted
        }

        let source = CGEventSource(stateID: .privateState)

        guard let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true),
              let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false),
              let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false) else {
            logger.error("\(VoiceInkPasteDiagnostics.failedToCreateCommandVPasteEventsMessage, privacy: .public)")
            return .commandNotPosted
        }

        cmdDown.flags = .maskCommand
        vDown.flags   = .maskCommand
        vUp.flags     = .maskCommand

        cmdDown.post(tap: .cghidEventTap)
        vDown.post(tap: .cghidEventTap)
        vUp.post(tap: .cghidEventTap)
        cmdUp.post(tap: .cghidEventTap)
        VoiceInkLatencyTrace.shared.event(
            "paste_event_posted",
            details: "method=cgEvent",
            token: latencyTraceToken
        )

        return .commandPosted
    }

    private static func wait(_ seconds: TimeInterval) async {
        guard seconds > 0 else { return }
        let nanoseconds = UInt64(seconds * 1_000_000_000)
        try? await Task.sleep(nanoseconds: nanoseconds)
    }

    // MARK: - Auto Send Keys

    static func performAutoSend(_ key: VoiceInkAutoSendKey) {
        guard key.isEnabled else { return }
        guard AXIsProcessTrusted() else { return }

        let source = CGEventSource(stateID: .privateState)
        let enterDown = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: true)
        let enterUp   = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: false)

        switch key {
        case .none: return
        case .enter: break
        case .shiftEnter:
            enterDown?.flags = .maskShift
            enterUp?.flags   = .maskShift
        case .commandEnter:
            enterDown?.flags = .maskCommand
            enterUp?.flags   = .maskCommand
        }

        enterDown?.post(tap: .cghidEventTap)
        enterUp?.post(tap: .cghidEventTap)
    }
}
