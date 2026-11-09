import Foundation
import SwiftData
import Testing
import VoiceInkCore
@testable import VoiceInk

/// Suites that set CursorPaster's process-wide test hooks run one at a time, even across files;
/// `.serialized` on a single suite only orders its own tests.
@Suite(.serialized)
struct CursorPasterHookTests {}

extension CursorPasterHookTests {
/// Drives the real engine and pipeline with live typing into an in-memory field and checks that
/// release leaves the field holding exactly what History saves.
@Suite(.serialized)
struct LiveTypingPipelineTests {
    @Test @MainActor func emptyFinalTranscriptRemovesLiveTypedText() async throws {
        let (fixture, field, restore) = try makeFixture(finalText: " \n ")
        defer { restore() }
        speak("Hello there friend", into: fixture)
        await fixture.engine.toggleRecord()

        #expect(field.text == "")
        #expect(try fixture.transcriptionCount() == 0)
    }

    @Test @MainActor func fieldMatchesHistoryIncludingSingleNewlines() async throws {
        // Paragraph formatting rewraps text; with it off, History keeps a single newline as spoken.
        let defaults = UserDefaults.standard
        let formatting = defaults.object(forKey: VoiceInkUserDefaultsKey.isTextFormattingEnabled)
        defaults.set(false, forKey: VoiceInkUserDefaultsKey.isTextFormattingEnabled)
        defer { defaults.set(formatting, forKey: VoiceInkUserDefaultsKey.isTextFormattingEnabled) }
        let (fixture, field, restore) = try makeFixture(finalText: "First line.\nSecond line.")
        defer { restore() }
        speak("First line. Second", into: fixture)
        await fixture.engine.toggleRecord()

        let saved = try #require(try fixture.context.fetch(FetchDescriptor<Transcription>()).first?.text)
        #expect(saved.contains("\n"))
        #expect(field.text == saved)
    }

    @Test @MainActor func failedTranscriptionWarnsAndLeavesLiveTypedWordsWithoutPastingAgain() async throws {
        let (fixture, field, restore) = try makeFixture(session: FailingSession())
        defer { restore() }
        var warnings: [String] = []
        NotificationManager.showNotificationForTesting = { title, type in
            if type == .warning { warnings.append(title) }
        }
        defer { NotificationManager.showNotificationForTesting = nil }
        speak("Hello there friend", into: fixture)
        await fixture.engine.toggleRecord()

        #expect(field.text == "Hello there")
        #expect(warnings.contains { $0.hasPrefix("Live typing could not finish cleanly") })
    }

    @Test @MainActor func focusMovedBeforeReleaseWritesNothingMoreAndWarns() async throws {
        let (fixture, field, restore) = try makeFixture(finalText: "Hello there friend.")
        defer { restore() }
        var warnings: [String] = []
        NotificationManager.showNotificationForTesting = { title, type in
            if type == .warning { warnings.append(title) }
        }
        defer { NotificationManager.showNotificationForTesting = nil }
        speak("Hello there friend", into: fixture)
        // Let the queued insertion land, then the user clicks into another app.
        _ = await fixture.engine.liveTranscriptTyper?.finish()
        field.focusedProcessIdentifier = 2
        await fixture.engine.toggleRecord()

        #expect(field.text == "Hello there")
        #expect(warnings.contains { $0.hasPrefix("Live typing could not finish cleanly") })
    }

    @Test @MainActor func fieldThatCannotReceiveTextFallsBackToOneNormalPaste() async throws {
        let (fixture, field, restore) = try makeFixture(finalText: "Hello there friend.")
        defer { restore() }
        field.canReceiveText = false
        var normalPastes = 0
        CursorPaster.configureAccessibilityTextInserterForTesting { text, _ in
            normalPastes += 1
            return field.paste(text)
        }
        defer { CursorPaster.configureAccessibilityTextInserterForTesting() }
        speak("Hello there friend", into: fixture)
        await fixture.engine.toggleRecord()

        #expect(field.text == "Hello there friend.")
        #expect(normalPastes == 1)
    }

    @Test @MainActor func losingTheFieldAfterTypingStartedWarnsInsteadOfReportingDelivery() async throws {
        let (fixture, field, restore) = try makeFixture(finalText: "Hello there friend.")
        defer { restore() }
        var warnings: [String] = []
        NotificationManager.showNotificationForTesting = { title, type in
            if type == .warning { warnings.append(title) }
        }
        defer { NotificationManager.showNotificationForTesting = nil }
        speak("Hello there friend", into: fixture)
        _ = await fixture.engine.liveTranscriptTyper?.finish()
        // Accessibility permission is revoked before release; keystrokes would now be dropped.
        field.canReceiveText = false
        await fixture.engine.toggleRecord()

        #expect(field.text == "Hello there")
        #expect(warnings.contains { $0.hasPrefix("Live typing could not finish cleanly") })
    }

    @Test @MainActor func losingTheFieldWarnsEvenWhenNothingIsLeftToType() async throws {
        let (fixture, field, restore) = try makeFixture(finalText: "Hello there")
        defer { restore() }
        var warnings: [String] = []
        NotificationManager.showNotificationForTesting = { title, type in
            if type == .warning { warnings.append(title) }
        }
        defer { NotificationManager.showNotificationForTesting = nil }
        speak("Hello there friend", into: fixture)
        _ = await fixture.engine.liveTranscriptTyper?.finish()
        field.canReceiveText = false
        await fixture.engine.toggleRecord()

        #expect(field.text == "Hello there")
        #expect(warnings.contains { $0.hasPrefix("Live typing could not finish cleanly") })
    }

    @Test @MainActor func webEditorEndsWithTheFinalTranscriptWhenItRevisesTypedWords() async throws {
        let (fixture, field, restore) = try makeFixture(finalText: "I think it's just the logic of it.")
        defer { restore() }
        field.supportsAccessibilityEditing = false
        speak("I think it's you just", into: fixture)
        _ = await fixture.engine.liveTranscriptTyper?.finish()
        #expect(field.text == "I think it's you")
        await fixture.engine.toggleRecord()

        let saved = try #require(try fixture.context.fetch(FetchDescriptor<Transcription>()).first?.text)
        #expect(field.text == saved)
    }

    @Test @MainActor func aWebEditorStoringNoBreakSpacesStillFinishesWithoutAWarning() async throws {
        let (fixture, field, restore) = try makeFixture(finalText: "I think it's just the logic of it.")
        defer { restore() }
        field.supportsAccessibilityEditing = false
        field.storesSpacesAsNoBreakSpaces = true
        var warnings: [String] = []
        NotificationManager.showNotificationForTesting = { title, type in
            if type == .warning { warnings.append(title) }
        }
        defer { NotificationManager.showNotificationForTesting = nil }
        speak("I think it's you just", into: fixture)
        await fixture.engine.toggleRecord()

        let saved = try #require(try fixture.context.fetch(FetchDescriptor<Transcription>()).first?.text)
        #expect(field.text.replacingOccurrences(of: "\u{00A0}", with: " ") == saved)
        #expect(warnings.isEmpty)
    }

    @Test @MainActor func aCorrectionCountsOnlyOnceAllItsKeysLanded() async throws {
        // "there" to "here": the old text already ends with the new word, and mid-way through the
        // Backspaces the caret passes the offset where the correction will end.
        let (fixture, field, restore) = try makeFixture(finalText: "Hello here you are.")
        defer { restore() }
        field.supportsAccessibilityEditing = false
        field.handlesKeystrokesOneReadAtATime = true
        speak("Hello there you", into: fixture)
        speak("Hello here you", into: fixture)
        speak("Hello here you are", into: fixture)
        _ = await fixture.engine.liveTranscriptTyper?.finish()
        field.handleAllPendingKeys()

        #expect(field.text == "Hello here you")
    }

    @Test @MainActor func aRevisedWordIsCorrectedAndTypingContinues() async throws {
        let (fixture, field, restore) = try makeFixture(finalText: "Hello their friend is here.")
        defer { restore() }
        field.supportsAccessibilityEditing = false
        speak("Hello there friend", into: fixture)
        speak("Hello their friend is here", into: fixture)
        _ = await fixture.engine.liveTranscriptTyper?.finish()

        #expect(field.text == "Hello their friend is")
    }

    @Test @MainActor func aDeclinedCorrectionLeavesTheFieldAndWarns() async throws {
        let (fixture, field, restore) = try makeFixture(finalText: "Hello their friend.")
        defer { restore() }
        field.supportsAccessibilityEditing = false
        var warnings: [String] = []
        NotificationManager.showNotificationForTesting = { title, type in
            if type == .warning { warnings.append(title) }
        }
        defer { NotificationManager.showNotificationForTesting = nil }
        speak("Hello there friend", into: fixture)
        _ = await fixture.engine.liveTranscriptTyper?.finish()
        field.appRewrites("there", as: "THERE")
        await fixture.engine.toggleRecord()

        #expect(field.text == "Hello THERE")
        #expect(warnings.contains { $0.hasPrefix("Live typing could not finish cleanly") })
    }

    @Test @MainActor func aCorrectionDeclinedForRecentUserInputLeavesTheFieldAndWarns() async throws {
        let (fixture, field, restore) = try makeFixture(finalText: "Hello their friend.")
        defer { restore() }
        field.supportsAccessibilityEditing = false
        var warnings: [String] = []
        NotificationManager.showNotificationForTesting = { title, type in
            if type == .warning { warnings.append(title) }
        }
        defer { NotificationManager.showNotificationForTesting = nil }
        speak("Hello there friend", into: fixture)
        _ = await fixture.engine.liveTranscriptTyper?.finish()
        field.userInputIsRecent = true
        await fixture.engine.toggleRecord()

        #expect(field.text == "Hello there")
        #expect(warnings.contains { $0.hasPrefix("Live typing could not finish cleanly") })
    }

    @Test @MainActor func selectedTextSurvivesAnEmptyFinalTranscript() async throws {
        let (fixture, field, restore) = try makeFixture(finalText: " \n ")
        defer { restore() }
        field.select("Keep this draft")
        speak("Hello there friend", into: fixture)
        await fixture.engine.toggleRecord()

        #expect(field.text == "Keep this draft")
    }

    @MainActor private func makeFixture(
        finalText: String = "",
        session: TranscriptionSession? = nil
    ) throws -> (RecordingFixture, InMemoryTextField, @MainActor () -> Void) {
        let fixture = try RecordingFixture()
        let field = InMemoryTextField()
        let defaults = UserDefaults.standard
        let trailingSpace = defaults.object(forKey: VoiceInkAppendTrailingSpacePreference.userDefaultsKey)
        defaults.set(false, forKey: VoiceInkAppendTrailingSpacePreference.userDefaultsKey)
        let restore: @MainActor () -> Void = {
            defaults.set(trailingSpace, forKey: VoiceInkAppendTrailingSpacePreference.userDefaultsKey)
        }
        fixture.beginRecording(session: session ?? GatedTextSession(text: finalText, released: true))
        fixture.engine.liveTranscriptTyper = fixture.engine.makeLiveTranscriptTyper(field: field)
        return (fixture, field, restore)
    }

    /// Reports the same running transcript for enough live passes that all but its last word are typed.
    @MainActor private func speak(_ transcript: String, into fixture: RecordingFixture) {
        for _ in 0..<VoiceInkLiveTyping.stabilityPasses {
            fixture.engine.liveTranscriptTyper?.update(liveTranscript: transcript)
        }
    }
}
}

@MainActor private final class InMemoryTextField: LiveTypingField {
    private(set) var text = ""
    private var caret = 0
    private var selectionLength = 0
    var focusedProcessIdentifier: pid_t = 1
    var canReceiveText = true
    /// False for a web editor: Accessibility cannot edit it, only keystrokes reach it.
    var supportsAccessibilityEditing = true
    /// Like a contenteditable editor, which stores typed spaces as no-break spaces.
    var storesSpacesAsNoBreakSpaces = false
    let isSecureInputActive = false

    func textBeforeCursor() -> String? { (text as NSString).substring(to: caret) }

    /// Keystroke corrections queued but not yet handled by the "app". Each read of the field returns
    /// the current state and then lets the app handle one more key, like a busy editor catching up.
    var handlesKeystrokesOneReadAtATime = false
    private var pendingKeys: [Character?] = []

    private func handleOnePendingKey() {
        guard !pendingKeys.isEmpty else { return }
        if let character = pendingKeys.removeFirst() {
            _ = paste(String(character))
        } else {
            let before = (text as NSString).substring(to: caret)
            let kept = String(before.dropLast())
            text = kept + (text as NSString).substring(from: caret)
            caret = (kept as NSString).length
        }
    }

    func handleAllPendingKeys() { while !pendingKeys.isEmpty { handleOnePendingKey() } }

    func insertionPoint() -> CursorTextContextReader.InsertionPoint {
        defer { handleOnePendingKey() }
        return CursorTextContextReader.InsertionPoint(
            processIdentifier: focusedProcessIdentifier,
            element: nil,
            caretLocation: selectionLength == 0 ? caret : nil,
            hasSelection: selectionLength > 0
        )
    }

    /// Like a real field without Accessibility trust: insertion is unsupported and keystrokes are dropped.
    func insert(_ inserted: String) -> CursorTextContextReader.SelectedTextInsertionResult {
        guard canReceiveText else { return .unsupported }
        return paste(inserted)
    }

    /// Fills the field with `selected` and selects all of it, like a user about to dictate over it.
    func select(_ selected: String) {
        text = selected
        caret = 0
        selectionLength = (selected as NSString).length
    }

    /// What the normal paste path delivers, which does not depend on live typing's checks.
    /// Like a real text field, inserting replaces the selection.
    func paste(_ inserted: String) -> CursorTextContextReader.SelectedTextInsertionResult {
        let inserted = storesSpacesAsNoBreakSpaces ? inserted.replacingOccurrences(of: " ", with: "\u{00A0}") : inserted
        text = (text as NSString).replacingCharacters(in: NSRange(location: caret, length: selectionLength), with: inserted)
        caret += (inserted as NSString).length
        selectionLength = 0
        return .inserted
    }

    func replaceTextBeforeCaret(
        _ expected: String,
        with replacement: String
    ) -> CursorTextContextReader.TextReplacementResult {
        guard supportsAccessibilityEditing else { return .unsupported }
        let length = (expected as NSString).length
        let range = NSRange(location: caret - length, length: length)
        guard canReceiveText, caret >= length, (text as NSString).substring(with: range) == expected else { return .untouched }
        text = (text as NSString).replacingCharacters(in: range, with: replacement)
        caret = range.location + (replacement as NSString).length
        return .replaced
    }

    func typeKeystrokes(_ typed: String, isCancelled: () -> Bool) async {
        if canReceiveText { _ = paste(typed) }
    }

    func textBeforeCaret(length: Int) -> String? {
        defer { handleOnePendingKey() }
        guard selectionLength == 0, length <= caret else { return nil }
        return (text as NSString).substring(with: NSRange(location: caret - length, length: length))
    }

    /// True when the user just clicked or typed, so a keystroke correction must not run yet.
    var userInputIsRecent = false

    func replaceByKeystrokes(
        at expected: CursorTextContextReader.InsertionPoint,
        deleting: String,
        typing: String,
        isCancelled: () -> Bool
    ) async -> KeystrokeReplacement {
        guard canReceiveText, !userInputIsRecent, insertionPoint().continues(expected),
              let typed = textBeforeCaret(length: (deleting as NSString).length),
              VoiceInkLiveTyping.sameTypedText(typed, deleting) else { return .declined }
        if handlesKeystrokesOneReadAtATime {
            pendingKeys += Array(repeating: nil, count: deleting.count) + typing.map { Optional($0) }
            return .sent
        }
        let length = (deleting as NSString).length
        text = (text as NSString).replacingCharacters(in: NSRange(location: caret - length, length: length), with: "")
        caret -= length
        _ = paste(typing)
        return .sent
    }

    /// The target app rewrites text before the caret without moving it, like autocorrect.
    func appRewrites(_ old: String, as new: String) {
        precondition((old as NSString).length == (new as NSString).length)
        text = text.replacingOccurrences(of: old, with: new)
    }
}

@MainActor private final class FailingSession: TranscriptionSession {
    private struct Failure: Error {}

    func prepare(model: any TranscriptionModel, latencyTraceToken: VoiceInkLatencyTrace.Token?) async throws -> ((Data) -> Void)? { nil }

    func transcribe(audioURL: URL) async throws -> String { throw Failure() }

    func cancel() {}
}
