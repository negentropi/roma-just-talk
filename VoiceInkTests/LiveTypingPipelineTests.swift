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
    var focusedProcessIdentifier: pid_t = 1
    var canReceiveText = true
    let isSecureInputActive = false

    func textBeforeCursor() -> String? { (text as NSString).substring(to: caret) }

    func insertionPoint() -> CursorTextContextReader.InsertionPoint {
        CursorTextContextReader.InsertionPoint(processIdentifier: focusedProcessIdentifier, element: nil, caretLocation: caret)
    }

    /// Like a real field without Accessibility trust: insertion is unsupported and keystrokes are dropped.
    func insert(_ inserted: String) -> CursorTextContextReader.SelectedTextInsertionResult {
        guard canReceiveText else { return .unsupported }
        return paste(inserted)
    }

    /// What the normal paste path delivers, which does not depend on live typing's checks.
    func paste(_ inserted: String) -> CursorTextContextReader.SelectedTextInsertionResult {
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
        guard canReceiveText, caret >= length, (text as NSString).substring(with: range) == expected else { return .untouched }
        text = (text as NSString).replacingCharacters(in: range, with: replacement)
        caret = range.location + (replacement as NSString).length
        return .replaced
    }

    func typeKeystrokes(_ typed: String, isCancelled: () -> Bool) async {
        if canReceiveText { _ = paste(typed) }
    }
}

@MainActor private final class FailingSession: TranscriptionSession {
    private struct Failure: Error {}

    func prepare(model: any TranscriptionModel, latencyTraceToken: VoiceInkLatencyTrace.Token?) async throws -> ((Data) -> Void)? { nil }

    func transcribe(audioURL: URL) async throws -> String { throw Failure() }

    func cancel() {}
}
