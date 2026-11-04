import AppKit
import Carbon
import os
import VoiceInkCore

/// Types dictated words into the focused field while the recording shortcut is held, so they appear
/// where the user is looking instead of all at once on release.
///
/// Invariant: `typedRegion`, the text this typer put into the field, ends at the caret and equals the
/// cleaned, cursor-adapted transcript of `typedWords`. Each change types only the difference: new text
/// is appended, and a changed tail (a dictionary replacement spanning words, a corrected word) is
/// replaced in place. Release applies the same rule to the final transcript, so the field ends up with
/// exactly the text History saves.
@MainActor
final class LiveTranscriptTyper {
    /// Marks keystrokes this class posts so the shortcut monitor does not read them as a key chord.
    nonisolated static let syntheticEventTag: Int64 = 0x524A_5454_5950 // "RJTTYP"

    enum ReleaseInsertion: Equatable {
        /// Text to insert at the caret; empty when the field already holds the whole transcript.
        case insert(String)
        /// The field could not be brought in line with the transcript; History keeps the full text.
        case unreconciled
    }

    private enum InsertionOutcome {
        case insertedAtCaret
        /// Posted as keystrokes, which the target app handles asynchronously.
        case typedAsKeystrokes
        /// The text landed but the caret may not be after it.
        case caretUnknown
    }

    private enum Phase {
        case undecided
        case typing
        /// No new words are queued. Already queued ones still run unless `isCancelled`.
        case stopped
    }

    private var phase = Phase.undecided
    private var isCancelled = false
    private var isHalted = false
    /// Set when the field may no longer end with `typedRegion` at the caret: the user moved focus or
    /// the caret, or an insertion could not be confirmed. Nothing more is inserted after that.
    private var isPlacementUncertain = false
    private var recentPasses: [[String]] = []
    private var queuedWords: [String] = []
    private var typedWords: [String] = []
    /// True once anything was sent to the field, confirmed or not, so release never re-pastes it.
    private var hasTouchedField = false
    private var typedRegion = ""
    /// Text before the cursor when typing began, so cursor-adapted capitalization and spacing stay
    /// the same every time the region is recomputed.
    private var textBeforeTyping: String?
    private var lastInsertionPoint: CursorTextContextReader.InsertionPoint?
    private var pendingInsertion: Task<Void, Never>?
    private let field: LiveTypingField
    private let canStartTyping: @MainActor () -> Bool
    private let cleanText: @MainActor (String) -> String
    private let logger = Logger(subsystem: VoiceInkAppIdentity.loggingSubsystem, category: "LiveTranscriptTyper")

    init(
        field: LiveTypingField = FocusedTextField(),
        canStartTyping: @escaping @MainActor () -> Bool,
        cleanText: @escaping @MainActor (String) -> String
    ) {
        self.field = field
        self.canStartTyping = canStartTyping
        self.cleanText = cleanText
    }

    /// Takes the running transcript of the current recording after each live pass.
    func update(liveTranscript: String) {
        if phase == .undecided {
            // Decided at the first live text, after Power Mode has applied its per-app settings.
            phase = canStartTyping() ? .typing : .stopped
            logger.notice("Live typing \(self.phase == .typing ? "started" : "declined", privacy: .public)")
        }
        guard phase == .typing, !isHalted else { return }

        let latest = VoiceInkLiveTyping.words(liveTranscript)
        // A shorter transcript that agrees is fine (a commit can report only committed words);
        // a changed word that was already queued is a revision live typing cannot follow.
        guard zip(latest, queuedWords).allSatisfy({ $0 == $1 }) else {
            halt("the live transcript revised words already typed")
            return
        }
        recentPasses.append(latest)
        if recentPasses.count > VoiceInkLiveTyping.stabilityPasses { recentPasses.removeFirst() }
        guard recentPasses.count == VoiceInkLiveTyping.stabilityPasses else { return }

        let stable = VoiceInkLiveTyping.stableWords(acrossPasses: recentPasses)
        guard stable.count > queuedWords.count, stable.starts(with: queuedWords) else { return }
        queuedWords = stable

        let previous = pendingInsertion
        pendingInsertion = Task { @MainActor in
            await previous?.value
            await self.type(words: stable)
        }
    }

    /// Stops queuing, waits for queued insertions, and reports whether anything may have been typed.
    func finish() async -> Bool {
        phase = .stopped
        await pendingInsertion?.value
        return hasTouchedField
    }

    /// Drops every queued insertion and stops a keystroke run in progress.
    func cancel() {
        phase = .stopped
        isCancelled = true
    }

    /// Brings the field in line with the final transcript after `finish()`.
    func releaseInsertion(finalRawText: String) -> ReleaseInsertion {
        // Checked even when nothing is left to type: the trailing space and auto-send go to the caret too.
        guard !isPlacementUncertain, isAtLastInsertionPoint() else {
            return unreconciled("the field or caret changed during live typing")
        }
        // From the raw text, as History cleans it, so single newlines survive.
        let desired = region(for: finalRawText)
        guard desired != typedRegion else { return .insert("") }

        let edit = VoiceInkLiveTyping.edit(from: typedRegion, to: desired)
        if edit.removedSuffix.isEmpty { return .insert(edit.insertedText) }
        switch field.replaceTextBeforeCaret(edit.removedSuffix, with: edit.insertedText) {
        case .replaced:
            logger.notice("Corrected live-typed text on release")
            return .insert("")
        case .uncertain:
            return unreconciled("correcting live-typed text left unexpected text")
        case .untouched:
            // The field cannot be edited in place, so it would not match History.
            return unreconciled("live-typed text differs from the transcript and cannot be corrected")
        }
    }

    private func unreconciled(_ reason: String) -> ReleaseInsertion {
        logger.error("Live-typed text left as typed: \(reason, privacy: .public)")
        return .unreconciled
    }

    /// The text the field should hold for a raw transcript: cleaned as a whole, then adapted to the
    /// text that preceded the cursor when typing began.
    private func region(for rawText: String) -> String {
        let cleaned = cleanText(rawText).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return "" }
        return VoiceInkTranscriptionPasteOutputPolicy.cursorPasteTextPlan(cleaned).text(beforeCursor: textBeforeTyping)
    }

    private func type(words: [String]) async {
        guard !isCancelled, !isHalted else { return }
        guard !field.isSecureInputActive else {
            halt("secure input is active")
            return
        }
        if typedWords.isEmpty {
            textBeforeTyping = field.textBeforeCursor()
        } else if !isAtLastInsertionPoint() {
            stopUncertain("the field or caret changed during live typing")
            return
        }

        let desired = region(for: words.joined(separator: " "))
        let edit = VoiceInkLiveTyping.edit(from: typedRegion, to: desired)
        let before = field.insertionPoint()
        var outcome = InsertionOutcome.insertedAtCaret
        if !edit.removedSuffix.isEmpty || !edit.insertedText.isEmpty { hasTouchedField = true }
        if !edit.removedSuffix.isEmpty {
            switch field.replaceTextBeforeCaret(edit.removedSuffix, with: edit.insertedText) {
            case .replaced:
                break
            case .untouched:
                // The field still ends with the old region; release appends after it.
                halt("typed text could not be corrected in place")
                return
            case .uncertain:
                stopUncertain("correcting typed text left unexpected text")
                return
            }
        } else if !edit.insertedText.isEmpty {
            outcome = await insert(edit.insertedText)
            guard outcome != .caretUnknown else {
                stopUncertain("the caret position after insertion is unknown")
                return
            }
        }
        typedWords = words
        typedRegion = desired

        let delta = (edit.insertedText as NSString).length - (edit.removedSuffix as NSString).length
        let expectedCaret = before.caretLocation.map { $0 + delta }
        // Keystrokes are handled asynchronously, so give the app a moment to move the caret.
        let after = outcome == .typedAsKeystrokes
            ? await settledInsertionPoint(expectedCaret: expectedCaret)
            : field.insertionPoint()
        lastInsertionPoint = after
        guard after.continues(before.withoutCaret()) else {
            stopUncertain("focus moved while typing")
            return
        }
        if let expectedCaret, after.caretLocation != expectedCaret {
            stopUncertain("the caret did not end after the typed text")
        }
    }

    private func settledInsertionPoint(expectedCaret: Int?) async -> CursorTextContextReader.InsertionPoint {
        var point = field.insertionPoint()
        for _ in 0..<20 where expectedCaret != nil && point.caretLocation != expectedCaret {
            try? await Task.sleep(nanoseconds: 10_000_000)
            point = field.insertionPoint()
        }
        return point
    }

    private func isAtLastInsertionPoint() -> Bool {
        guard let lastInsertionPoint else { return true }
        return field.insertionPoint().continues(lastInsertionPoint)
    }

    private func halt(_ reason: String) {
        isHalted = true
        logger.notice("Live typing stopped: \(reason, privacy: .public)")
    }

    private func stopUncertain(_ reason: String) {
        isPlacementUncertain = true
        halt(reason)
    }

    private func insert(_ text: String) async -> InsertionOutcome {
        switch field.insert(text) {
        case .inserted, .insertedViaValue:
            return .insertedAtCaret
        case .insertedWithoutSelection, .insertedViaValueWithoutSelection,
             // An unobserved Accessibility write may still land, so typing it again could duplicate it.
             .notApplied:
            return .caretUnknown
        case .unsupported:
            await field.typeKeystrokes(text) { [weak self] in self?.isCancelled ?? true }
            return .typedAsKeystrokes
        }
    }
}

/// Where live typing puts text. `FocusedTextField` is the focused field of the frontmost app.
@MainActor
protocol LiveTypingField {
    var isSecureInputActive: Bool { get }
    func textBeforeCursor() -> String?
    func insertionPoint() -> CursorTextContextReader.InsertionPoint
    func insert(_ text: String) -> CursorTextContextReader.SelectedTextInsertionResult
    func replaceTextBeforeCaret(_ expected: String, with replacement: String) -> CursorTextContextReader.TextReplacementResult
    func typeKeystrokes(_ text: String, isCancelled: () -> Bool) async
}

@MainActor
struct FocusedTextField: LiveTypingField {
    var isSecureInputActive: Bool { ShortcutMonitor.isSecureEventInputEnabled() }

    func textBeforeCursor() -> String? { CursorTextContextReader.textBeforeCursor() }

    func insertionPoint() -> CursorTextContextReader.InsertionPoint { CursorTextContextReader.focusedInsertionPoint() }

    func insert(_ text: String) -> CursorTextContextReader.SelectedTextInsertionResult {
        CursorTextContextReader.insertSelectedText(text, preparedContext: nil)
    }

    func replaceTextBeforeCaret(_ expected: String, with replacement: String) -> CursorTextContextReader.TextReplacementResult {
        CursorTextContextReader.replaceTextBeforeCaret(expected, with: replacement)
    }

    /// Posts the text as Unicode keystrokes. Avoids the clipboard so each insertion does not
    /// overwrite and restore the user's clipboard while they are still speaking.
    func typeKeystrokes(_ text: String, isCancelled: () -> Bool) async {
        // A private source keeps the physically held Shift key out of the typed events.
        let source = CGEventSource(stateID: .privateState)
        let targetProcessIdentifier = CursorTextContextReader.focusedProcessIdentifierForPaste()
        for chunk in Self.utf16Chunks(text, maximumLength: 20) {
            guard !isCancelled() else { return }
            for isKeyDown in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: isKeyDown) else { return }
                chunk.withUnsafeBufferPointer { buffer in
                    event.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
                }
                event.flags = []
                event.setIntegerValueField(.eventSourceUserData, value: LiveTranscriptTyper.syntheticEventTag)
                if let targetProcessIdentifier {
                    event.postToPid(targetProcessIdentifier)
                } else {
                    event.post(tap: .cghidEventTap)
                }
            }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
    }

    /// Splits on character boundaries so a surrogate pair or emoji is never cut in half.
    private static func utf16Chunks(_ text: String, maximumLength: Int) -> [[UniChar]] {
        var chunks: [[UniChar]] = []
        var current: [UniChar] = []
        for character in text {
            let units = Array(String(character).utf16)
            if current.count + units.count > maximumLength, !current.isEmpty {
                chunks.append(current)
                current = []
            }
            current.append(contentsOf: units)
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }
}
