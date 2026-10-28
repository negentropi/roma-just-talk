import AVFoundation
import Foundation
import SwiftData
import Testing
import VoiceInkCore
@testable import VoiceInk

@Suite(.serialized)
struct DiscardedRecordingTests {
    @Test @MainActor func accidentalShortcutCancelLeavesNoHistoryRowOrAudio() async throws {
        let fixture = try RecordingFixture()
        fixture.beginRecording()

        await fixture.engine.cancelRecording(.accidentalShortcut)

        #expect(try fixture.transcriptionCount() == 0)
        #expect(!fixture.audioExists)
    }

    @Test @MainActor func explicitCancelStaysInHistoryWithAudio() async throws {
        let fixture = try RecordingFixture()
        fixture.beginRecording()

        await fixture.engine.cancelRecording(.userRequested)

        let rows = try fixture.context.fetch(FetchDescriptor<Transcription>())
        #expect(rows.map(\.transcriptionState) == [.canceled])
        #expect(fixture.audioExists)
    }

    @Test @MainActor func emptyTranscriptionLeavesNoHistoryRowAudioOrMetric() async throws {
        let fixture = try RecordingFixture()
        fixture.beginRecording(session: FixedTextSession(text: " \n "))

        await fixture.engine.toggleRecord()

        #expect(try fixture.transcriptionCount() == 0)
        #expect(try fixture.context.fetchCount(FetchDescriptor<SessionMetric>()) == 0)
        #expect(!fixture.audioExists)
        #expect(fixture.engine.recordingState == .idle)
    }
}

@MainActor private final class RecordingFixture {
    let context: ModelContext
    let engine: VoiceInkEngine
    let audioURL: URL

    init() throws {
        let schema = Schema([Transcription.self, VocabularyWord.self, WordReplacement.self, SessionMetric.self])
        // Mirror the app's named stores; the host app binds SessionMetric to "stats" process-wide.
        let container = try ModelContainer(for: schema, configurations: [
            ModelConfiguration("default", schema: Schema([Transcription.self]), isStoredInMemoryOnly: true),
            ModelConfiguration("dictionary", schema: Schema([VocabularyWord.self, WordReplacement.self]), isStoredInMemoryOnly: true),
            ModelConfiguration("stats", schema: Schema([SessionMetric.self]), isStoredInMemoryOnly: true),
        ])
        context = ModelContext(container)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let whisper = WhisperModelManager(modelsDirectory: directory.appendingPathComponent("models"))
        let models = TranscriptionModelManager(whisperModelManager: whisper, fluidAudioModelManager: FluidAudioModelManager())
        models.currentTranscriptionModel = TranscriptionModelRegistry.defaultMacOSFluidAudioModel
        engine = VoiceInkEngine(modelContext: context, whisperModelManager: whisper,
            transcriptionModelManager: models, qwenRuntimeResult: .failure(FixtureError.unusedRuntime))
        audioURL = directory.appendingPathComponent("recording.wav")
        try Self.writeSilence(to: audioURL)
    }

    var audioExists: Bool { FileManager.default.fileExists(atPath: audioURL.path) }

    func transcriptionCount() throws -> Int {
        try context.fetchCount(FetchDescriptor<Transcription>())
    }

    func beginRecording(session: TranscriptionSession? = nil) {
        engine.recordedFile = audioURL
        engine.currentSession = session
        engine.recordingState = .recording
    }

    private static func writeSilence(to url: URL) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000)!
        buffer.frameLength = 16_000
        try file.write(from: buffer)
    }
}

private enum FixtureError: Error { case unusedRuntime }

@MainActor private final class FixedTextSession: TranscriptionSession {
    private let text: String
    init(text: String) { self.text = text }
    func prepare(model: any TranscriptionModel, latencyTraceToken: VoiceInkLatencyTrace.Token?) async throws -> ((Data) -> Void)? { nil }
    func transcribe(audioURL: URL) async throws -> String { text }
    func cancel() {}
}
