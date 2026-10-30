import AppKit
import Foundation
import Observation
import SwiftData
import Testing
import VoiceInkCore
@testable import VoiceInk

extension VoiceInkTests {
    #if DEBUG
    @Test(.timeLimit(.minutes(1)), arguments: PipelinePreparationBoundary.allCases)
    @MainActor func canceledPipelineCannotPasteAfterPreparation(
        boundary: PipelinePreparationBoundary
    ) async throws {
        let fixture = try PipelineFixture(insertDirectly: false)
        defer { fixture.restore() }
        let transcription = fixture.insertTranscription()
        let barrier = PipelinePreparationBarrier()
        defer { barrier.release() }
        switch boundary {
        case .cursorContext:
            fixture.pipeline.cursorContextPreparedForTesting = { await barrier.hold() }
        case .pasteAuthorization:
            // Skip the cursor await so cancellation lands at authorization.
            UserDefaults.standard.set(true, forKey: VoiceInkUserDefaultsKey.lowercaseTranscription)
            fixture.pipeline.pasteAuthorizationPreparedForTesting = { await barrier.hold() }
        }

        let completed = AsyncStream<Void>.makeStream()
        defer { completed.continuation.finish() }
        withObservationTracking {
            _ = transcription.transcriptionState
        } onChange: {
            completed.continuation.yield(())
            completed.continuation.finish()
        }
        var cancellationRequested = false
        var cancelCount = 0
        var dismissCount = 0
        let clipboardChangeCount = NSPasteboard.general.changeCount
        let run = Task { @MainActor in
            await fixture.pipeline.run(
                transcription: transcription,
                modelDisplayName: "Camera recognition",
                recognize: { "Camera history survives" },
                captureDuration: { 2.5 },
                latencyTraceToken: nil,
                onStateChange: { _ in },
                shouldCancel: { cancellationRequested },
                onCancel: { cancelCount += 1 },
                onDismiss: { dismissCount += 1 }
            )
        }
        for await _ in completed.stream { break }
        #expect(await barrier.waitUntilHeld())
        #expect(transcription.transcriptionState == .completed)
        cancellationRequested = true
        barrier.release()
        await run.value

        let stored = try #require(fixture.readTranscriptions().first)
        #expect(stored.transcriptionState == .canceled)
        #expect(stored.audioFileURL == nil)
        #expect(stored.duration == 2.5)
        #expect(cancelCount == 1)
        #expect(dismissCount == 0)
        #expect(fixture.insertedTexts.isEmpty)
        #expect(fixture.pasteCommandCount == 0)
        #expect(NSPasteboard.general.changeCount == clipboardChangeCount)
        #expect(try fixture.readMetrics().isEmpty)
    }
    #endif

    @Test(arguments: [false, true])
    @MainActor func pipelineStoresCaptureDurationAndSharedTextWithoutRequiringAudio(
        hasAudioFile: Bool
    ) async throws {
        let fixture = try PipelineFixture()
        defer { fixture.restore() }
        let audioFileURL = hasAudioFile ? "file:///recordings/voice.wav" : nil
        let transcription = fixture.insertTranscription(audioFileURL: audioFileURL)
        fixture.container.mainContext.insert(
            WordReplacement(originalText: "caption", replacementText: "camera")
        )
        DictionaryService.invalidateWordReplacementCache()
        var events: [String] = []
        await fixture.pipeline.run(
            transcription: transcription,
            modelDisplayName: "Capture recognition",
            recognize: {
                events.append("recognized")
                return "caption history survives"
            },
            captureDuration: {
                events.append("duration")
                return 2.5
            },
            latencyTraceToken: nil,
            onStateChange: { _ in },
            shouldCancel: { false },
            onCancel: { Issue.record("Completed recognition was canceled") },
            onDismiss: { events.append("dismissed") }
        )

        let stored = try #require(fixture.readTranscriptions().first)
        let metric = try #require(fixture.readMetrics().first)
        #expect(stored.transcriptionState == .completed)
        #expect(stored.text == "camera history survives")
        #expect(stored.audioFileURL == audioFileURL)
        #expect(stored.duration == 2.5)
        #expect(stored.transcriptionModelName == "Capture recognition")
        #expect(stored.transcriptionDuration != nil)
        #expect(metric.transcriptionId == stored.id)
        #expect(metric.transcriptionModelName == "Capture recognition")
        #expect(metric.audioDuration == 2.5)
        #expect(metric.wordCount == 3)
        #expect(fixture.insertedTexts.count == 1)
        #expect(fixture.pasteCommandCount == 0)
        #expect(events == ["recognized", "dismissed", "duration"])
    }

    @Test(arguments: [false, true])
    @MainActor func pipelinePreservesKnownDurationWithoutReadingCapture(canceled: Bool) async throws {
        let fixture = try PipelineFixture()
        defer { fixture.restore() }
        let transcription = fixture.insertTranscription(duration: 4.5)
        var didRecognize = false
        await fixture.pipeline.run(
            transcription: transcription,
            modelDisplayName: "Camera recognition",
            recognize: {
                didRecognize = true
                return "camera history survives"
            },
            captureDuration: {
                Issue.record("A record with a known duration read the capture again")
                return 99
            },
            latencyTraceToken: nil,
            onStateChange: { _ in },
            shouldCancel: { canceled },
            onCancel: {},
            onDismiss: {}
        )

        let stored = try #require(fixture.readTranscriptions().first)
        #expect(stored.duration == 4.5)
        #expect(stored.transcriptionState == (canceled ? .canceled : .completed))
        #expect(stored.audioFileURL == nil)
        #expect(didRecognize == !canceled)
        #expect(try fixture.readMetrics().count == (canceled ? 0 : 1))
    }

    @Test @MainActor func failedRecognitionDoesNotReadCaptureDurationOrPaste() async throws {
        let fixture = try PipelineFixture()
        defer { fixture.restore() }
        let transcription = fixture.insertTranscription()
        var didDismiss = false
        await fixture.pipeline.run(
            transcription: transcription,
            modelDisplayName: "Camera recognition",
            recognize: { throw PipelineRecognitionFailure.unavailable },
            captureDuration: {
                Issue.record("Failed recognition read the capture duration")
                return 99
            },
            latencyTraceToken: nil,
            onStateChange: { _ in },
            shouldCancel: { false },
            onCancel: { Issue.record("Failed recognition was canceled") },
            onDismiss: { didDismiss = true }
        )

        let stored = try #require(fixture.readTranscriptions().first)
        #expect(stored.transcriptionState == .failed)
        #expect(stored.duration == 0)
        #expect(stored.audioFileURL == nil)
        #expect(didDismiss)
        #expect(fixture.insertedTexts.isEmpty)
        #expect(fixture.pasteCommandCount == 0)
        #expect(try fixture.readMetrics().isEmpty)
    }
}

enum PipelinePreparationBoundary: CaseIterable, Sendable {
    case cursorContext
    case pasteAuthorization
}

private enum PipelineRecognitionFailure: Error {
    case unavailable
}

@MainActor
private final class PipelinePreparationBarrier {
    private let entered = AsyncStream<Void>.makeStream()
    private let resumed = AsyncStream<Void>.makeStream()

    func hold() async {
        entered.continuation.yield(())
        entered.continuation.finish()
        for await _ in resumed.stream { break }
    }

    func waitUntilHeld() async -> Bool {
        for await _ in entered.stream { return true }
        return false
    }

    func release() {
        resumed.continuation.yield(())
        resumed.continuation.finish()
    }
}

@MainActor
private final class PipelineFixture {
    let container: ModelContainer
    let pipeline: TranscriptionPipeline
    var insertedTexts: [String] = []
    var pasteCommandCount = 0
    private let readContext: ModelContext
    private let savedDefaults: [(String, Any?)]
    private let clipboard: [[(NSPasteboard.PasteboardType, Data)]]
    private let clipboardChangeCount: Int
    private let activeConfiguration: PowerModeConfig?

    init(insertDirectly: Bool = true) throws {
        let schema = Schema([Transcription.self, SessionMetric.self, WordReplacement.self])
        container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        readContext = ModelContext(container)
        pipeline = TranscriptionPipeline(modelContext: container.mainContext, enhancementService: nil)
        let values: [(String, Any)] = [
            (VoiceInkUserDefaultsKey.lowercaseTranscription, false),
            (VoiceInkUserDefaultsKey.removeFillerWords, false),
            (VoiceInkUserDefaultsKey.isTextFormattingEnabled, false),
            (VoiceInkUserDefaultsKey.appendTrailingSpace, false),
            (PunctuationCleanupMode.userDefaultsKey, PunctuationCleanupMode.keep.rawValue),
            (VoiceInkPasteMethod.userDefaultsKey, VoiceInkPasteMethod.standard.rawValue),
            (VoiceInkRecordingFeedbackPreference.isSoundFeedbackEnabledKey, false),
            ("restoreClipboardAfterPaste", false)
        ]
        savedDefaults = values.map { ($0.0, UserDefaults.standard.object(forKey: $0.0)) }
        clipboard = (NSPasteboard.general.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
        clipboardChangeCount = NSPasteboard.general.changeCount
        activeConfiguration = PowerModeManager.shared.activeConfiguration
        PowerModeManager.shared.activeConfiguration = nil
        for (key, value) in values { UserDefaults.standard.set(value, forKey: key) }
        DictionaryService.invalidateWordReplacementCache()
        SpecialShortcutEmptyTranscriptionFallback.resetForTesting()
        CursorPaster.configureAccessibilityTextInserterForTesting { [weak self] text, _ in
            guard insertDirectly else { return .notApplied }
            self?.insertedTexts.append(text)
            return .inserted
        }
        CursorPaster.configurePasteCommandPosterForTesting { [weak self] _ in
            self?.pasteCommandCount += 1
            return .commandNotPosted
        }
    }

    func insertTranscription(duration: TimeInterval = 0, audioFileURL: String? = nil) -> Transcription {
        let transcription = Transcription(text: "", duration: duration, audioFileURL: audioFileURL)
        container.mainContext.insert(transcription)
        return transcription
    }

    func readTranscriptions() throws -> [Transcription] {
        try readContext.fetch(FetchDescriptor<Transcription>())
    }

    func readMetrics() throws -> [SessionMetric] {
        try readContext.fetch(FetchDescriptor<SessionMetric>())
    }

    func restore() {
        CursorPaster.configureAccessibilityTextInserterForTesting()
        CursorPaster.configurePasteCommandPosterForTesting()
        DictionaryService.invalidateWordReplacementCache()
        PowerModeManager.shared.activeConfiguration = activeConfiguration
        for (key, value) in savedDefaults {
            if let value {
                UserDefaults.standard.set(value, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        if NSPasteboard.general.changeCount != clipboardChangeCount {
            let items = clipboard.map { representations in
                let item = NSPasteboardItem()
                for (type, data) in representations { item.setData(data, forType: type) }
                return item
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects(items)
        }
    }
}
