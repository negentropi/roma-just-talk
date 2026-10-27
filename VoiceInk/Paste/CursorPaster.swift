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
    // Let target apps observe modifier release before the synthesized Cmd-V chord.
    private static let prePasteDelay: TimeInterval = 0.1
    private static let pasteShortcutEventDelay: TimeInterval = 0.01
    @MainActor private static var pasteCommandPosterForTesting: ((Bool) async -> PasteResult)?
    @MainActor private static var accessibilityTextInserterForTesting:
        ((String, CursorTextContextReader.PreparedContext?) -> CursorTextContextReader.SelectedTextInsertionResult)?
    @MainActor private static var clipboardRestorations: [NSPasteboard.Name: ClipboardRestoration] = [:]
    @MainActor private static var clipboardPreparations: [NSPasteboard.Name: UUID] = [:]

    @MainActor
    private final class ClipboardRestoration {
        enum State { case pending, settled, failed(Int) }
        let board: NSPasteboard
        var contents: ClipboardSnapshot
        let text: String
        let sessionID: String
        let changeCount: Int
        let deadline: TimeInterval
        var state: State = .pending
        var timer: Task<Void, Never>?

        init(board: NSPasteboard, contents: ClipboardSnapshot, text: String, sessionID: String,
             changeCount: Int, delay: TimeInterval) {
            self.board = board
            self.contents = contents
            self.text = text
            self.sessionID = sessionID
            self.changeCount = changeCount
            deadline = ProcessInfo.processInfo.systemUptime + max(0, delay)
        }

        var ownsClipboard: Bool {
            board.changeCount == changeCount
                && board.string(forType: .string)?.utf16.elementsEqual(text.utf16) == true
                && board.string(forType: ClipboardManager.pasteSessionType) == sessionID
                && board.changeCount == changeCount
        }
    }

    struct PreparedPasteContext {
        fileprivate let changeCount: Int
        fileprivate let savedContents: ClipboardSnapshot
    }

    enum PasteResult: Equatable {
        case textInserted
        case commandPosted
        case commandDeliveryUncertain
        case commandNotPosted

        var didPostPasteCommand: Bool {
            self == .commandPosted
        }

        var didDeliverText: Bool {
            self == .textInserted || self == .commandPosted
        }
    }

    enum WritingPasteResult: Equatable {
        case confirmed
        case notAttempted
        case attemptedUnconfirmed
    }

    enum WritingPasteError: LocalizedError {
        case clipboardChanged
        case clipboardWriteFailed
        case clipboardUnreadable
        case clipboardRestorationFailed

        var errorDescription: String? {
            switch self {
            case .clipboardChanged:
                return "Another paste was using the clipboard, or the clipboard changed. Let any other paste finish, then check your clipboard."
            case .clipboardWriteFailed:
                return "Roma Just Talk couldn't put the text on the clipboard, so your clipboard may have changed. Check it and copy what you need again."
            case .clipboardUnreadable:
                return "Roma Just Talk couldn't read your clipboard. Check your clipboard and copy what you need again."
            case .clipboardRestorationFailed:
                return "Roma Just Talk couldn't safely put back what was on your clipboard. Check your clipboard and copy what you need again."
            }
        }
    }

    @MainActor
    static func settlePendingClipboardRestore(
        pasteboard: NSPasteboard = .general,
        shouldCancel: () -> Bool = { false }
    ) async throws {
        while let restoration = clipboardRestorations[pasteboard.name] {
            try checkPasteCancellation(shouldCancel)
            switch restoration.state {
            case .settled:
                retireRestoration(restoration)
            case .failed(let generation):
                guard pasteboard.changeCount != generation else { throw WritingPasteError.clipboardRestorationFailed }
                retireRestoration(restoration)
            case .pending:
                guard restoration.ownsClipboard else {
                    retireRestoration(restoration)
                    continue
                }
                let remaining = restoration.deadline - ProcessInfo.processInfo.systemUptime
                if remaining > 0 {
                    // Cancel this waiter without canceling the earlier paste's independent timer.
                    try await Task.sleep(for: .seconds(min(remaining, 0.05)))
                } else {
                    settleRestoration(restoration)
                }
            }
        }
        try checkPasteCancellation(shouldCancel)
    }

    @MainActor
    private static func checkPasteCancellation(_ shouldCancel: () -> Bool) throws {
        if Task.isCancelled || shouldCancel() { throw CancellationError() }
    }

    @MainActor
    private static func claimClipboardPreparation(on board: NSPasteboard) throws -> UUID {
        guard clipboardPreparations[board.name] == nil else { throw WritingPasteError.clipboardChanged }
        let id = UUID()
        clipboardPreparations[board.name] = id
        return id
    }

    @MainActor
    private static func releaseClipboardPreparation(_ id: UUID, on board: NSPasteboard) {
        if clipboardPreparations[board.name] == id { clipboardPreparations.removeValue(forKey: board.name) }
    }

    @MainActor
    private static func retireRestoration(_ restoration: ClipboardRestoration) {
        guard clipboardRestorations[restoration.board.name] === restoration else { return }
        restoration.state = .settled
        restoration.timer?.cancel()
        restoration.timer = nil
        clipboardRestorations.removeValue(forKey: restoration.board.name)
    }

    @MainActor
    private static func settleRestoration(_ restoration: ClipboardRestoration) {
        guard clipboardRestorations[restoration.board.name] === restoration,
              case .pending = restoration.state else { return }
        guard restoration.ownsClipboard else { retireRestoration(restoration); return }
        do {
            try restoreClipboardSnapshot(restoration.contents, on: restoration.board, expectedChangeCount: restoration.changeCount)
            retireRestoration(restoration)
        } catch WritingPasteError.clipboardChanged {
            retireRestoration(restoration)
        } catch {
            restoration.state = .failed(restoration.board.changeCount)
            restoration.contents = []
            restoration.timer = nil
            logger.error("Could not restore the owned clipboard: \(String(describing: error), privacy: .public)")
        }
    }

    @MainActor
    protocol WritingPasteAccess {
        func validateTarget() throws
        func readValue() -> String?
        func pressMenu(authorize: () throws -> Void, willAttempt: () -> Void) async throws
            -> CursorTextContextReader.CapturedMenuAttempt
    }

    @MainActor
    static func pasteWritingReplacement(
        _ text: String,
        expectedValue: String,
        access: any WritingPasteAccess,
        shouldCancel: () -> Bool,
        pasteboard: NSPasteboard = .general,
        restoreClipboard: Bool = VoiceInkPastePreference.shouldRestoreClipboardAfterPaste(),
        restorationDelay: TimeInterval = VoiceInkPastePreference.boundedClipboardRestoreDelay(),
        onConfirmed: (@MainActor () -> Void)? = nil
    ) async throws -> WritingPasteResult {
        func checkCancellation() throws {
            if Task.isCancelled || shouldCancel() { throw CancellationError() }
        }
        try checkCancellation()
        try access.validateTarget()
        guard !restoreClipboard || restorationDelay.isFinite else { throw WritingPasteError.clipboardRestorationFailed }
        try await settlePendingClipboardRestore(pasteboard: pasteboard, shouldCancel: shouldCancel)
        try access.validateTarget()
        let preparation = try claimClipboardPreparation(on: pasteboard)
        defer { releaseClipboardPreparation(preparation, on: pasteboard) }
        let previousChangeCount = pasteboard.changeCount
        let savedContents = try snapshotClipboard(from: pasteboard)
        try checkCancellation()
        try access.validateTarget()
        guard pasteboard.changeCount == previousChangeCount else {
            throw WritingPasteError.clipboardChanged
        }

        let sessionID = UUID().uuidString
        let item = NSPasteboardItem()
        guard item.setString(text, forType: .string),
              item.setString(sessionID, forType: ClipboardManager.pasteSessionType) else {
            throw WritingPasteError.clipboardWriteFailed
        }
        if restoreClipboard {
            guard item.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType")),
                  item.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.AutoGeneratedType")) else {
                throw WritingPasteError.clipboardWriteFailed
            }
        }
        guard pasteboard.changeCount == previousChangeCount else {
            throw WritingPasteError.clipboardChanged
        }
        let clearedChangeCount = pasteboard.clearContents()
        guard pasteboard.changeCount == clearedChangeCount else { throw WritingPasteError.clipboardChanged }
        let written = pasteboard.writeObjects([item])
        let ownedChangeCount = clearedChangeCount
        func ownsClipboard() -> Bool {
            pasteboard.changeCount == ownedChangeCount
                && pasteboard.string(forType: .string)?.utf16.elementsEqual(text.utf16) == true
                && pasteboard.string(forType: ClipboardManager.pasteSessionType) == sessionID
                && pasteboard.changeCount == ownedChangeCount
        }
        var restorationAttempted = false
        func restoreIfOwned() throws {
            guard !restorationAttempted, ownsClipboard() else { return }
            restorationAttempted = true
            do { try restoreClipboardSnapshot(savedContents, on: pasteboard, expectedChangeCount: ownedChangeCount) }
            catch WritingPasteError.clipboardChanged { throw WritingPasteError.clipboardChanged }
            catch { recordFailedRestoration(on: pasteboard); throw error }
        }
        guard written, ownsClipboard() else {
            if ownsClipboard() {
                try restoreIfOwned()
            } else if pasteboard.changeCount == clearedChangeCount,
                      pasteboard.pasteboardItems?.isEmpty != false,
                      pasteboard.changeCount == clearedChangeCount {
                do { try restoreClipboardSnapshot(savedContents, on: pasteboard, expectedChangeCount: clearedChangeCount) }
                catch WritingPasteError.clipboardChanged { throw WritingPasteError.clipboardChanged }
                catch { recordFailedRestoration(on: pasteboard); throw error }
            }
            throw WritingPasteError.clipboardWriteFailed
        }

        var attempted = false
        func authorize() throws {
            try checkCancellation()
            try access.validateTarget()
            guard ownsClipboard() else { throw WritingPasteError.clipboardChanged }
        }
        do {
            try authorize()
            let result = try await access.pressMenu(authorize: authorize, willAttempt: { attempted = true })
            switch result {
            case .notAttempted:
                guard !attempted else { return .attemptedUnconfirmed }
                try restoreIfOwned()
                return .notAttempted
            case .attempted:
                attempted = true
                for attempt in 0..<CursorTextContextReader.pasteDeliveryObservationAttempts {
                    if let value = access.readValue(), value.utf16.elementsEqual(expectedValue.utf16) {
                        if restoreClipboard {
                            scheduleClipboardRestore(
                                savedContents, expectedText: text, sessionID: sessionID,
                                on: pasteboard, latencyTraceToken: nil,
                                expectedChangeCount: ownedChangeCount, delay: restorationDelay,
                                settleImmediately: false
                            )
                        }
                        // Delivery is a fact before cancellation, actor reentry or restoration work.
                        onConfirmed?()
                        if restoreClipboard, restorationDelay <= 0,
                           let restoration = clipboardRestorations[pasteboard.name] { settleRestoration(restoration) }
                        return .confirmed
                    }
                    guard !Task.isCancelled, !shouldCancel() else { return .attemptedUnconfirmed }
                    guard attempt < CursorTextContextReader.pasteDeliveryObservationAttempts - 1 else { break }
                    do {
                        try await Task.sleep(nanoseconds: UInt64(CursorTextContextReader.pasteDeliveryObservationDelay * 1_000_000_000))
                    } catch { continue }
                }
                return .attemptedUnconfirmed
            }
        } catch {
            if attempted { return .attemptedUnconfirmed }
            try restoreIfOwned()
            throw error
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
    static func configurePasteCommandPosterForTesting(
        _ poster: ((Bool) async -> PasteResult)? = nil
    ) {
        pasteCommandPosterForTesting = poster
    }

    @MainActor
    static func configureAccessibilityTextInserterForTesting(
        _ inserter: (
            (String, CursorTextContextReader.PreparedContext?)
                -> CursorTextContextReader.SelectedTextInsertionResult
        )? = nil
    ) {
        accessibilityTextInserterForTesting = inserter
    }

    @MainActor
    @discardableResult
    static func startPasteAtCursor(
        _ text: String,
        preparedContext: PreparedPasteContext? = nil,
        preparedCursorTextContext: Task<CursorTextContextReader.PreparedContext?, Never>? = nil,
        latencyTraceToken: VoiceInkLatencyTrace.Token? = nil,
        willAttempt: (@MainActor () throws -> Void)? = nil
    ) -> Task<PasteResult, Never> {
        let traceToken = latencyTraceToken ?? VoiceInkLatencyTrace.shared.currentToken()
        return Task { @MainActor in
            await performPasteSession(
                text,
                preparedContext: preparedContext,
                preparedCursorTextContext: preparedCursorTextContext,
                latencyTraceToken: traceToken,
                willAttempt: willAttempt
            )
        }
    }

    @MainActor
    static func preparePasteContext() -> PreparedPasteContext? {
        guard VoiceInkPastePreference.shouldRestoreClipboardAfterPaste() else {
            return nil
        }

        let pasteboard = NSPasteboard.general
        let generation = pasteboard.changeCount
        guard let contents = try? snapshotClipboard(from: pasteboard), pasteboard.changeCount == generation else { return nil }
        return PreparedPasteContext(changeCount: generation, savedContents: contents)
    }

    @MainActor
    static func preflightPasteAuthorization() -> Bool {
        AXIsProcessTrusted()
    }

    @MainActor
    private static func performPasteSession(
        _ text: String,
        preparedContext: PreparedPasteContext? = nil,
        preparedCursorTextContext: Task<CursorTextContextReader.PreparedContext?, Never>? = nil,
        latencyTraceToken: VoiceInkLatencyTrace.Token?,
        willAttempt: (@MainActor () throws -> Void)?
    ) async -> PasteResult {
        guard !Task.isCancelled else { return .commandNotPosted }
        let latencyTrace = VoiceInkLatencyTrace.shared
        let pasteboard = NSPasteboard.general
        let shouldRestoreClipboard = VoiceInkPastePreference.shouldRestoreClipboardAfterPaste()
        let restorationDelay = VoiceInkPastePreference.boundedClipboardRestoreDelay()
        guard !shouldRestoreClipboard || restorationDelay.isFinite else { return .commandNotPosted }
        var authorizationRejected = false
        var attempted = false
        func authorizeAttempt() throws {
            do {
                try checkPasteCancellation({ false })
                try willAttempt?()
                attempted = true
            } catch {
                authorizationRejected = true
                throw error
            }
        }
        var shouldRetryCommandVMenuDiscovery = false
        let cursorContext = if VoiceInkPasteMethod.current() == .standard {
            await preparedCursorTextContext?.value
        } else {
            nil as CursorTextContextReader.PreparedContext?
        }
        guard !Task.isCancelled else { return .commandNotPosted }
        latencyTrace.event(
            "paste_session.enter",
            details: "chars=\(text.count) restoreClipboard=\(shouldRestoreClipboard) method=\(VoiceInkPasteMethod.current().rawValue)",
            token: latencyTraceToken
        )
        if VoiceInkPasteMethod.current() == .standard,
           accessibilityTextInserterForTesting != nil || pasteCommandPosterForTesting == nil {
            let insertionSpan = latencyTrace.begin(
                "paste_session.accessibility_insert",
                token: latencyTraceToken
            )
            guard !Task.isCancelled else {
                latencyTrace.end(insertionSpan, details: "result=cancelled_before_insert")
                return .commandNotPosted
            }
            let insertionResult = if let accessibilityTextInserterForTesting {
                if (try? authorizeAttempt()) != nil {
                    accessibilityTextInserterForTesting(text, cursorContext)
                } else {
                    CursorTextContextReader.SelectedTextInsertionResult.notApplied
                }
            } else {
                CursorTextContextReader.insertSelectedText(
                    text,
                    preparedContext: cursorContext,
                    willAttempt: authorizeAttempt
                )
            }
            guard !authorizationRejected else { return .commandNotPosted }
            latencyTrace.end(
                insertionSpan,
                details: "result=\(insertionResult.rawValue)"
            )
            shouldRetryCommandVMenuDiscovery = insertionResult.shouldRetryCommandVMenuDiscovery
            if insertionResult.didInsert {
                latencyTrace.event(
                    "paste_text_inserted",
                    details: "method=\(insertionResult.method ?? "accessibility")",
                    token: latencyTraceToken
                )
                return .textInserted
            }
        }

        let clipboardSnapshotSpan = latencyTrace.begin(
            "paste_session.snapshot_clipboard",
            token: latencyTraceToken
        )
        do {
            try await settlePendingClipboardRestore(pasteboard: pasteboard)
        } catch { return .commandNotPosted }
        let preparation: UUID
        let savedContents: ClipboardSnapshot
        do {
            preparation = try claimClipboardPreparation(on: pasteboard)
        } catch { return .commandNotPosted }
        defer { releaseClipboardPreparation(preparation, on: pasteboard) }
        do {
            // A retired temporary payload cannot be reused through an earlier prepared context.
            if let preparedContext, preparedContext.changeCount == pasteboard.changeCount {
                savedContents = preparedContext.savedContents
            } else {
                savedContents = try snapshotClipboard(from: pasteboard)
            }
        } catch { return .commandNotPosted }
        latencyTrace.end(
            clipboardSnapshotSpan,
            details: "items=\(savedContents.count)"
        )
        let sessionID = UUID().uuidString

        let clipboardWriteSpan = latencyTrace.begin(
            "paste_session.write_clipboard",
            token: latencyTraceToken
        )
        guard !Task.isCancelled else {
            latencyTrace.end(clipboardWriteSpan, details: "result=cancelled_before_write")
            return .commandNotPosted
        }
        var preparedGeneration: Int?
        var stillOwnsPreparation = false
        guard ClipboardManager.setClipboard(
            text,
            transient: shouldRestoreClipboard,
            sessionID: shouldRestoreClipboard ? sessionID : nil,
            didWrite: { generation, owned in
                preparedGeneration = generation
                stillOwnsPreparation = owned
            }
        ) else {
            if let preparedGeneration, stillOwnsPreparation, pasteboard.changeCount == preparedGeneration {
                do { try restoreClipboardSnapshot(savedContents, on: pasteboard, expectedChangeCount: preparedGeneration) }
                catch WritingPasteError.clipboardChanged { }
                catch { recordFailedRestoration(on: pasteboard) }
            }
            latencyTrace.end(clipboardWriteSpan, details: "result=failure")
            logger.error("\(VoiceInkPasteDiagnostics.failedToPrepareClipboardMessage, privacy: .public)")
            return .commandNotPosted
        }
        guard let ownedChangeCount = preparedGeneration, stillOwnsPreparation else { return .commandNotPosted }
        func ownsClipboard() -> Bool {
            pasteboard.changeCount == ownedChangeCount
                && pasteboard.string(forType: .string)?.utf16.elementsEqual(text.utf16) == true
                && (!shouldRestoreClipboard || pasteboard.string(forType: ClipboardManager.pasteSessionType) == sessionID)
                && pasteboard.changeCount == ownedChangeCount
        }
        guard ownsClipboard() else { return .commandNotPosted }
        latencyTrace.end(clipboardWriteSpan, details: "result=success")

        let commandSpan = latencyTrace.begin("paste_session.post_command", token: latencyTraceToken)
        let pasteResult = await postPasteCommand(
            expectedText: text,
            retryCommandVMenuDiscovery: shouldRetryCommandVMenuDiscovery,
            preparedCursorTextContext: cursorContext,
            latencyTraceToken: latencyTraceToken,
            willAttempt: {
                guard ownsClipboard() else { authorizationRejected = true; throw WritingPasteError.clipboardChanged }
                try authorizeAttempt()
            }
        )
        latencyTrace.end(
            commandSpan,
            details: "result=\(String(describing: pasteResult))"
        )
        if authorizationRejected, !attempted, ownsClipboard() {
            do { try restoreClipboardSnapshot(savedContents, on: pasteboard, expectedChangeCount: ownedChangeCount) }
            catch WritingPasteError.clipboardChanged { }
            catch { recordFailedRestoration(on: pasteboard) }
        }
        guard !authorizationRejected else { return attempted ? .commandDeliveryUncertain : .commandNotPosted }
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
                latencyTraceToken: latencyTraceToken,
                expectedChangeCount: ownedChangeCount,
                delay: restorationDelay
            )
        } else if shouldRestoreClipboard {
            latencyTrace.event(
                "paste_session.restore_skipped",
                details: "reason=\(String(describing: pasteResult))",
                token: latencyTraceToken
            )
            if pasteResult == .commandNotPosted {
                logger.notice("\(VoiceInkPasteDiagnostics.skippedClipboardRestoreCommandNotPostedMessage, privacy: .public)")
            }
        }

        return pasteResult
    }

    @MainActor
    private static func snapshotClipboard(from pasteboard: NSPasteboard) throws -> ClipboardSnapshot {
        let generation = pasteboard.changeCount
        let items = pasteboard.pasteboardItems
        guard items != nil || (pasteboard.types ?? []).isEmpty else { throw WritingPasteError.clipboardUnreadable }
        let contents = try (items ?? []).map { item in
            let types = item.types
            guard Set(types).count == types.count else { throw WritingPasteError.clipboardUnreadable }
            return try types.map { type in
                guard let data = item.data(forType: type) else { throw WritingPasteError.clipboardUnreadable }
                return (type, data)
            }
        }
        guard pasteboard.changeCount == generation else { throw WritingPasteError.clipboardChanged }
        return contents
    }

    @MainActor
    private static func postPasteCommand(
        expectedText: String,
        retryCommandVMenuDiscovery: Bool,
        preparedCursorTextContext: CursorTextContextReader.PreparedContext?,
        latencyTraceToken: VoiceInkLatencyTrace.Token?,
        willAttempt: @escaping @MainActor () throws -> Void
    ) async -> PasteResult {
        guard !Task.isCancelled else { return .commandNotPosted }
        if let pasteCommandPosterForTesting {
            do { try willAttempt() } catch { return .commandNotPosted }
            return await pasteCommandPosterForTesting(retryCommandVMenuDiscovery)
        }

        if VoiceInkPasteMethod.current() == .appleScript {
            let didPost = pasteUsingAppleScript(willAttempt: willAttempt)
            if didPost {
                VoiceInkLatencyTrace.shared.event(
                    "paste_event_posted",
                    details: "method=appleScript",
                    token: latencyTraceToken
                )
            }
            return didPost ? .commandPosted : .commandNotPosted
        } else {
            return await pasteFromClipboard(
                expectedText: expectedText,
                retryCommandVMenuDiscovery: retryCommandVMenuDiscovery,
                preparedCursorTextContext: preparedCursorTextContext,
                latencyTraceToken: latencyTraceToken,
                willAttempt: willAttempt
            )
        }
    }

    @MainActor
    private static func scheduleClipboardRestore(
        _ savedContents: ClipboardSnapshot,
        expectedText: String,
        sessionID: String,
        on pasteboard: NSPasteboard,
        latencyTraceToken: VoiceInkLatencyTrace.Token?,
        expectedChangeCount: Int,
        delay: TimeInterval,
        settleImmediately: Bool = true
    ) {
        let restoration = ClipboardRestoration(board: pasteboard, contents: savedContents,
            text: expectedText, sessionID: sessionID, changeCount: expectedChangeCount, delay: delay)
        guard restoration.ownsClipboard else { return }
        clipboardRestorations[pasteboard.name] = restoration
        if delay <= 0, settleImmediately {
            settleRestoration(restoration)
        } else if delay > 0 {
            restoration.timer = Task { @MainActor in
                do {
                    let remaining = restoration.deadline - ProcessInfo.processInfo.systemUptime
                    if remaining > 0 { try await Task.sleep(for: .seconds(remaining)) }
                } catch { return }
                settleRestoration(restoration)
            }
        }
    }

    @MainActor
    private static func recordFailedRestoration(on board: NSPasteboard) {
        let failure = ClipboardRestoration(board: board, contents: [], text: "", sessionID: "",
            changeCount: board.changeCount, delay: 0)
        failure.state = .failed(board.changeCount)
        clipboardRestorations[board.name] = failure
        logger.error("An owned clipboard restoration failed; another paste requires a newer clipboard generation")
    }

    @MainActor
    private static func pasteboardItems(from snapshot: ClipboardSnapshot) throws -> [NSPasteboardItem] {
        try snapshot.map { itemSnapshot in
            let item = NSPasteboardItem()
            for (type, data) in itemSnapshot {
                guard item.setData(data, forType: type) else { throw WritingPasteError.clipboardRestorationFailed }
            }
            return item
        }
    }

    @MainActor
    private static func restoreClipboardSnapshot(_ snapshot: ClipboardSnapshot, on board: NSPasteboard, expectedChangeCount: Int) throws {
        let items = try pasteboardItems(from: snapshot)
        guard board.changeCount == expectedChangeCount else { throw WritingPasteError.clipboardChanged }
        let clearedChangeCount = board.clearContents()
        guard board.changeCount == clearedChangeCount else { throw WritingPasteError.clipboardChanged }
        let written = items.isEmpty || board.writeObjects(items)
        guard board.changeCount == clearedChangeCount else { throw WritingPasteError.clipboardChanged }
        guard written else { throw WritingPasteError.clipboardRestorationFailed }
        let readback = try snapshotClipboard(from: board)
        guard board.changeCount == clearedChangeCount else { throw WritingPasteError.clipboardChanged }
        guard readback.count == snapshot.count else { throw WritingPasteError.clipboardRestorationFailed }
        for (actual, expected) in zip(readback, snapshot) {
            guard actual.count == expected.count,
                  Dictionary(uniqueKeysWithValues: actual) == Dictionary(uniqueKeysWithValues: expected) else {
                throw WritingPasteError.clipboardRestorationFailed
            }
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
    private static func pasteUsingAppleScript(willAttempt: () throws -> Void) -> Bool {
        guard let script = layoutSwitchesToQWERTYOnCommand ? pasteScriptKeyCode : pasteScriptKeystroke else {
            logger.error("\(VoiceInkPasteDiagnostics.appleScriptPasteScriptUnavailableMessage, privacy: .public)")
            return false
        }

        do { try willAttempt() } catch { return false }
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
        expectedText: String,
        retryCommandVMenuDiscovery: Bool,
        preparedCursorTextContext: CursorTextContextReader.PreparedContext?,
        latencyTraceToken: VoiceInkLatencyTrace.Token?,
        willAttempt: @escaping @MainActor () throws -> Void
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

        guard !Task.isCancelled else { return .commandNotPosted }
        // AX menu actions do not synthesize modifiers, so they need no key-release delay.
        let menuAttempt = await CursorTextContextReader.pressFocusedCommandVMenuItem(
            retryIfUnavailable: retryCommandVMenuDiscovery,
            preparedContext: preparedCursorTextContext,
            latencyTraceToken: latencyTraceToken,
            willAttempt: willAttempt
        )
        let stableTarget: CursorTextContextReader.FocusedPasteTarget?
        switch menuAttempt {
        case .pressed(let targetProcessIdentifier):
            VoiceInkLatencyTrace.shared.event(
                "paste_event_posted",
                details: "method=accessibilityMenuCommandV targetPid=\(targetProcessIdentifier)",
                token: latencyTraceToken
            )
            return .commandPosted
        case .targetChanged(let targetProcessIdentifier):
            VoiceInkLatencyTrace.shared.event(
                "paste_event_delivery_uncertain",
                details: "method=accessibilityMenuCommandV reason=targetChanged targetPid=\(targetProcessIdentifier.map { String($0) } ?? "unknown")",
                token: latencyTraceToken
            )
            return .commandDeliveryUncertain
        case .unavailable(let target):
            stableTarget = target
        }
        guard !Task.isCancelled else { return .commandNotPosted }
        if retryCommandVMenuDiscovery {
            guard let stableTarget else { return .commandNotPosted }
            await wait(prePasteDelay)
            if let keyboardPaste = await CursorTextContextReader.postFocusedCommandVShortcut(
                target: stableTarget,
                expectedText: expectedText,
                latencyTraceToken: latencyTraceToken,
                willAttempt: willAttempt
            ) {
                switch keyboardPaste.disposition {
                case .delivered:
                    VoiceInkLatencyTrace.shared.event(
                        "paste_event_posted",
                        details: "method=globalHIDCommandV targetPid=\(keyboardPaste.processIdentifier) disposition=\(keyboardPaste.disposition.rawValue)",
                        token: latencyTraceToken
                    )
                    return .commandPosted
                case .deliveryUncertain:
                    VoiceInkLatencyTrace.shared.event(
                        "paste_event_delivery_uncertain",
                        details: "method=globalHIDCommandV targetPid=\(keyboardPaste.processIdentifier)",
                        token: latencyTraceToken
                    )
                    return .commandDeliveryUncertain
                }
            }
            guard !Task.isCancelled else { return .commandNotPosted }
            if let contextMenuPaste = await CursorTextContextReader.pressFocusedContextMenuPasteItem(
                target: stableTarget,
                expectedText: expectedText,
               latencyTraceToken: latencyTraceToken,
               willAttempt: willAttempt
            ) {
                if Task.isCancelled {
                    return .commandDeliveryUncertain
                }
                switch contextMenuPaste.disposition {
                case .delivered:
                    VoiceInkLatencyTrace.shared.event(
                        "paste_event_posted",
                        details: "method=accessibilityContextMenu targetPid=\(contextMenuPaste.processIdentifier) disposition=\(contextMenuPaste.disposition.rawValue)",
                        token: latencyTraceToken
                    )
                    return .commandPosted
                case .deliveryUncertain:
                    VoiceInkLatencyTrace.shared.event(
                        "paste_event_delivery_uncertain",
                        details: "method=accessibilityContextMenu targetPid=\(contextMenuPaste.processIdentifier)",
                        token: latencyTraceToken
                    )
                    return .commandDeliveryUncertain
                }
            }
            VoiceInkLatencyTrace.shared.event(
                "paste_event_not_posted",
                details: "reason=safeBrowserMethodUnavailable targetPid=\(stableTarget.processIdentifier)",
                token: latencyTraceToken
            )
            return .commandNotPosted
        }
        await wait(prePasteDelay)
        guard !Task.isCancelled else { return .commandNotPosted }
        let targetProcessIdentifier = CursorTextContextReader.focusedProcessIdentifierForPaste()
        // VoiceInk posts from the active login session, so share that session's
        // accumulated keyboard state instead of creating an isolated private state.
        let source = CGEventSource(stateID: .combinedSessionState)

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

        let events = [cmdDown, vDown, vUp, cmdUp]
        for (index, event) in events.enumerated() {
            if index < 2, Task.isCancelled {
                if index == 1 {
                    if let targetProcessIdentifier {
                        cmdUp.postToPid(targetProcessIdentifier)
                    } else {
                        cmdUp.post(tap: .cghidEventTap)
                    }
                }
                return .commandNotPosted
            }
            if index == 1 {
                do { try willAttempt() }
                catch {
                    if let targetProcessIdentifier { cmdUp.postToPid(targetProcessIdentifier) }
                    else { cmdUp.post(tap: .cghidEventTap) }
                    return .commandNotPosted
                }
            }
            if let targetProcessIdentifier {
                event.postToPid(targetProcessIdentifier)
            } else {
                event.post(tap: .cghidEventTap)
            }
            if index < events.count - 1 {
                await wait(pasteShortcutEventDelay)
            }
        }
        VoiceInkLatencyTrace.shared.event(
            "paste_event_posted",
            details: targetProcessIdentifier.map {
                "method=cgEvent source=combinedSession targetPid=\($0)"
            } ?? "method=cgEvent source=combinedSession target=global",
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
