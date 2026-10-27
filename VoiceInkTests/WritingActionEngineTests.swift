import Foundation
import SwiftData
import Testing
import VoiceInkCore
@testable import VoiceInk

@Suite(.serialized)
struct WritingActionEngineTests {
    @Test @MainActor func permissionWaitReservesOneRecordingStart() async throws {
        let fixture = try WritingEngineFixture()
        let gate = WritingPermissionGate()
        fixture.engine.recordPermissionRequestForTesting = { await gate.request() }
        let first = Task { await fixture.engine.toggleRecord() }
        await gate.waitUntilEntered()
        #expect(fixture.engine.recordingState == .starting)
        var secondFinished = false
        let second = Task {
            await fixture.engine.toggleRecord()
            secondFinished = true
        }
        for _ in 0..<200 {
            if secondFinished || gate.calls > 1 { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        gate.releaseAll(granted: false)
        await first.value
        await second.value
        #expect(gate.calls == 1)
        #expect(fixture.engine.recordingState == .idle)
        #expect(fixture.engine.recordedFile == nil)
    }

    @Test @MainActor func oldStartupFailureDoesNotClearANewerRecordingStart() async throws {
        let fixture = try WritingEngineFixture()
        let gate = WritingPreparationGate()
        fixture.engine.recordPermissionRequestForTesting = { true }
        fixture.engine.recordingStartupPreparationForTesting = { try await gate.prepare() }
        let first = Task { await fixture.engine.toggleRecord() }
        await gate.waitUntilEntered(count: 1)
        await fixture.engine.cancelRecording()
        let second = Task { await fixture.engine.toggleRecord() }
        await gate.waitUntilEntered(count: 2)
        gate.fail(index: 0)
        await first.value
        #expect(fixture.engine.recordingState == .starting)
        #expect(gate.calls == 2)
        gate.fail(index: 1)
        await second.value
        #expect(fixture.engine.recordingState == .idle)
        #expect(fixture.engine.recordedFile == nil)
    }
}

private enum WritingEngineFixtureError: Error { case unusedRuntime, preparationFailed }

@MainActor private final class WritingEngineFixture {
    let engine: VoiceInkEngine
    private let whisper: WhisperModelManager
    private let fluid: FluidAudioModelManager
    private let models: TranscriptionModelManager

    init() throws {
        let schema = Schema([Transcription.self, VocabularyWord.self, WordReplacement.self, SessionMetric.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        whisper = WhisperModelManager(modelsDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        fluid = FluidAudioModelManager()
        models = TranscriptionModelManager(whisperModelManager: whisper, fluidAudioModelManager: fluid)
        models.currentTranscriptionModel = TranscriptionModelRegistry.defaultMacOSFluidAudioModel
        engine = VoiceInkEngine(
            modelContext: ModelContext(container),
            whisperModelManager: whisper,
            transcriptionModelManager: models,
            qwenRuntimeResult: .failure(WritingEngineFixtureError.unusedRuntime)
        )
    }
}

@MainActor private final class WritingPermissionGate {
    private var waiters: [CheckedContinuation<Bool, Never>] = []
    private var observer: CheckedContinuation<Void, Never>?
    private var releasedResult: Bool?
    private(set) var calls = 0
    func request() async -> Bool {
        calls += 1
        if let releasedResult { return releasedResult }
        observer?.resume(); observer = nil
        return await withCheckedContinuation { waiters.append($0) }
    }
    func waitUntilEntered() async {
        if calls > 0 { return }
        let timeout = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            observer?.resume(); observer = nil
        }
        await withCheckedContinuation { observer = $0 }
        timeout.cancel()
    }
    func releaseAll(granted: Bool) {
        releasedResult = granted
        let pending = waiters
        waiters = []
        pending.forEach { $0.resume(returning: granted) }
    }
}

@MainActor private final class WritingPreparationGate {
    private var pending: [Int: CheckedContinuation<Void, Error>] = [:]
    private var observer: CheckedContinuation<Void, Never>?
    private(set) var calls = 0
    func prepare() async throws {
        let index = calls
        calls += 1
        observer?.resume(); observer = nil
        try await withCheckedThrowingContinuation { pending[index] = $0 }
    }
    func waitUntilEntered(count: Int) async {
        while calls < count {
            let timeout = Task {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                observer?.resume(); observer = nil
            }
            await withCheckedContinuation { observer = $0 }
            timeout.cancel()
            if calls < count { Issue.record("Recording startup did not reach the deferred preparation"); return }
        }
    }
    func fail(index: Int) { pending.removeValue(forKey: index)?.resume(throwing: WritingEngineFixtureError.preparationFailed) }
}
