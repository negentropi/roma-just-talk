import Foundation
import SwiftData
import Testing
import VoiceInkCore
@testable import VoiceInk

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

    @MainActor private func makeFixture(
        finalText: String = "",
        session: TranscriptionSession? = nil
    ) throws -> (RecordingFixture, InMemoryTextField, @MainActor () -> Void) {
        let fixture = try RecordingFixture()
        let field = InMemoryTextField()
        let defaults = UserDefaults.standard
        let trailingSpace = defaults.object(forKey: VoiceInkAppendTrailingSpacePreference.userDefaultsKey)
        defaults.set(false, forKey: VoiceInkAppendTrailingSpacePreference.userDefaultsKey)
        // The release remainder goes through the normal paste path; route it into the same field.
        CursorPaster.configureAccessibilityTextInserterForTesting { text, _ in field.insert(text) }
        let restore: @MainActor () -> Void = {
            CursorPaster.configureAccessibilityTextInserterForTesting()
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

@MainActor private final class InMemoryTextField: LiveTypingField {
    private(set) var text = ""
    private var caret = 0
    let isSecureInputActive = false

    func textBeforeCursor() -> String? { (text as NSString).substring(to: caret) }

    func insertionPoint() -> CursorTextContextReader.InsertionPoint {
        CursorTextContextReader.InsertionPoint(processIdentifier: 1, element: nil, caretLocation: caret)
    }

    func insert(_ inserted: String) -> CursorTextContextReader.SelectedTextInsertionResult {
        text = (text as NSString).replacingCharacters(in: NSRange(location: caret, length: 0), with: inserted)
        caret += (inserted as NSString).length
        return .inserted
    }

    func replaceTextBeforeCaret(
        _ expected: String,
        with replacement: String
    ) -> CursorTextContextReader.TextReplacementResult {
        let length = (expected as NSString).length
        let range = NSRange(location: caret - length, length: length)
        guard caret >= length, (text as NSString).substring(with: range) == expected else { return .untouched }
        text = (text as NSString).replacingCharacters(in: range, with: replacement)
        caret = range.location + (replacement as NSString).length
        return .replaced
    }

    func typeKeystrokes(_ typed: String, isCancelled: () -> Bool) async { _ = insert(typed) }
}

@MainActor private final class FailingSession: TranscriptionSession {
    private struct Failure: Error {}

    func prepare(model: any TranscriptionModel, latencyTraceToken: VoiceInkLatencyTrace.Token?) async throws -> ((Data) -> Void)? { nil }

    func transcribe(audioURL: URL) async throws -> String { throw Failure() }

    func cancel() {}
}
