import AppKit
import Carbon
import os
import VoiceInkCore

/// Types dictated words into the focused field while the recording shortcut is held, so they appear
/// where the user is looking instead of all at once on release.
///
/// A word is typed once the last few live passes agree on it. On release, `releaseInsertion` lines the
/// typed chunks up with the final transcript, replaces any typed tail the final pass changed, and
/// returns the rest to insert.
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

    private enum Phase {
        case undecided
        case typing
        /// No new words are queued. Already queued ones still run unless `isCancelled`.
        case stopped
    }

    private enum InsertionOutcome {
        case insertedAtCaret
        /// The text landed but the caret may not be after it, so later text could land in the wrong place.
        case insertedCaretUnknown
    }

    /// One insertion: the raw transcript words and the exact text put into the field for them.
    private struct TypedChunk {
        let rawWords: [String]
        let insertedText: String
    }

    private var phase = Phase.undecided
    private var isCancelled = false
    private var isHalted = false
    private var isCaretUncertain = false
    private var recentPasses: [[String]] = []
    private var queuedWords: [String] = []
    /// Only chunks that were inserted, in order, so their words are a prefix of `queuedWords`.
    private var typedChunks: [TypedChunk] = []
    private var pendingInsertion: Task<Void, Never>?
    private let canStartTyping: @MainActor () -> Bool
    private let cleanText: @MainActor (String) -> String
    private let logger = Logger(subsystem: VoiceInkAppIdentity.loggingSubsystem, category: "LiveTranscriptTyper")

    init(
        canStartTyping: @escaping @MainActor () -> Bool,
        cleanText: @escaping @MainActor (String) -> String
    ) {
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
        guard stable.count > queuedWords.count else { return }
        guard stable.starts(with: queuedWords) else {
            halt("the live transcript revised words already typed")
            return
        }
        let newWords = Array(stable.dropFirst(queuedWords.count))
        queuedWords = stable

        let previous = pendingInsertion
        pendingInsertion = Task { @MainActor in
            await previous?.value
            await self.insertChunk(newWords)
        }
    }

    /// Stops queuing, waits for queued insertions, and reports whether anything was typed.
    func finish() async -> Bool {
        phase = .stopped
        await pendingInsertion?.value
        return !typedChunks.isEmpty
    }

    /// Drops every queued insertion and stops a keystroke run in progress.
    func cancel() {
        phase = .stopped
        isCancelled = true
    }

    /// Brings the field in line with the final transcript after `finish()`.
    func releaseInsertion(finalRawText: String) -> ReleaseInsertion {
        let finalWords = VoiceInkLiveTyping.words(finalRawText)
        let (keptChunkCount, remainingWords) = VoiceInkLiveTyping.reconcile(
            typedChunks: typedChunks.map(\.rawWords),
            finalWords: finalWords
        )
        let remainder = cleanText(remainingWords.joined(separator: " ")).trimmingCharacters(in: .whitespacesAndNewlines)
        let changedTail = typedChunks.dropFirst(keptChunkCount).map(\.insertedText).joined()

        if changedTail.isEmpty {
            guard !remainder.isEmpty else { return .insert("") }
            guard !isCaretUncertain else { return unreconciled("the caret position after live typing is unknown") }
            return .insert(Self.insertionText(remainder, continuing: typedChunks.contains { !$0.insertedText.isEmpty }))
        }

        guard !isCaretUncertain else { return unreconciled("the caret position after live typing is unknown") }
        // Keep the tail's leading space so the corrected words stay separated from what precedes them.
        let leadingSpace = String(changedTail.prefix { $0.isWhitespace })
        switch CursorTextContextReader.replaceTextBeforeCaret(changedTail, with: remainder.isEmpty ? "" : leadingSpace + remainder) {
        case .replaced:
            logger.notice("Corrected \(self.typedChunks.count - keptChunkCount, privacy: .public) live-typed chunks on release")
            return .insert("")
        case .uncertain:
            return unreconciled("correcting live-typed words left unexpected text")
        case .untouched:
            break
        }

        // Fields that cannot be edited in place: accept typed words that differ only in case or
        // punctuation and append what follows them.
        let typedRawText = typedChunks.flatMap(\.rawWords).joined(separator: " ")
        guard let fallback = VoiceInkLiveTyping.untypedRemainder(finalRawText: finalRawText, typedRawText: typedRawText) else {
            return unreconciled("the final transcript does not continue the live-typed words")
        }
        let cleanedFallback = cleanText(fallback).trimmingCharacters(in: .whitespacesAndNewlines)
        return .insert(cleanedFallback.isEmpty ? "" : " " + cleanedFallback)
    }

    private func unreconciled(_ reason: String) -> ReleaseInsertion {
        logger.error("Live-typed text left as typed: \(reason, privacy: .public)")
        return .unreconciled
    }

    private func insertChunk(_ rawWords: [String]) async {
        guard !isCancelled, !isHalted else { return }
        guard !ShortcutMonitor.isSecureEventInputEnabled() else {
            halt("secure input is active")
            return
        }
        let cleaned = cleanText(rawWords.joined(separator: " ")).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            typedChunks.append(TypedChunk(rawWords: rawWords, insertedText: ""))
            return
        }

        let text = Self.insertionText(cleaned, continuing: typedChunks.contains { !$0.insertedText.isEmpty })
        let outcome = await insert(text)
        typedChunks.append(TypedChunk(rawWords: rawWords, insertedText: text))
        if outcome == .insertedCaretUnknown {
            isCaretUncertain = true
            halt("the caret position after insertion is unknown")
        }
    }

    private func halt(_ reason: String) {
        isHalted = true
        logger.notice("Live typing stopped: \(reason, privacy: .public)")
    }

    /// The first insertion adapts spacing and capitalization to the text before the cursor;
    /// later ones continue the dictation after a space.
    private static func insertionText(_ cleaned: String, continuing: Bool) -> String {
        continuing ? " " + cleaned : CursorPaster.preparedTextForPaste(cleaned)
    }

    private func insert(_ text: String) async -> InsertionOutcome {
        switch CursorTextContextReader.insertSelectedText(text, preparedContext: nil) {
        case .inserted, .insertedViaValue:
            return .insertedAtCaret
        case .insertedWithoutSelection, .insertedViaValueWithoutSelection:
            return .insertedCaretUnknown
        case .unsupported, .notApplied:
            await typeKeystrokes(text)
            return .insertedAtCaret
        }
    }

    /// Posts the text as Unicode keystrokes. Avoids the clipboard so each chunk does not
    /// overwrite and restore the user's clipboard while they are still speaking.
    private func typeKeystrokes(_ text: String) async {
        // A private source keeps the physically held Shift key out of the typed events.
        let source = CGEventSource(stateID: .privateState)
        let targetProcessIdentifier = CursorTextContextReader.focusedProcessIdentifierForPaste()
        for chunk in Self.utf16Chunks(text, maximumLength: 20) {
            guard !isCancelled else { return }
            for isKeyDown in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: isKeyDown) else { return }
                chunk.withUnsafeBufferPointer { buffer in
                    event.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
                }
                event.flags = []
                event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventTag)
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
