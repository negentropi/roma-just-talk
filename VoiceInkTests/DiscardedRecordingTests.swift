import AVFoundation
import Foundation
import SwiftData
import Testing
import VoiceInkCore
@testable import VoiceInk

// Recorder preferences are shared with the pipeline and Power Mode fixtures in this serialized suite.
extension VoiceInkTests {
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
        let stored = try #require(rows.first)
        #expect(stored.hasStoredAudioFile())
    }

    @Test @MainActor func lipOnlyCancellationPreservesOnlyUserRequestedHistory() async throws {
        for reason in [RecordingCancellation.userRequested, .accidentalShortcut] {
            let fixture = try RecordingFixture(mode: .lips)
            fixture.beginRecording()

            await fixture.engine.cancelRecording(reason)

            let rows = try fixture.context.fetch(FetchDescriptor<Transcription>())
            if reason == .userRequested {
                let stored = try #require(rows.first)
                #expect(rows.count == 1)
                #expect(stored.transcriptionState == .canceled)
                #expect(stored.audioFileURL == nil)
            } else {
                #expect(rows.isEmpty)
            }
            #expect(fixture.audioURL == nil)
            #expect(try fixture.context.fetchCount(FetchDescriptor<SessionMetric>()) == 0)
            #expect(fixture.engine.recordingState == .idle)
            await fixture.engine.shutDown()
        }
    }

    @Test(.timeLimit(.minutes(1)), arguments: RecordingSessionEndAction.allCases)
    @MainActor func lipOnlySessionEndDoesNotCreateHistory(action: RecordingSessionEndAction) async throws {
        let defaults = UserDefaults.standard
        let keys = [VoiceInkLipDictationPreference.enabledKey, VoiceInkLipDictationPreference.lipOnlyKey]
        let saved = keys.map { ($0, defaults.object(forKey: $0)) }
        defer {
            for (key, value) in saved {
                if let value { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }
        VoiceInkLipDictationPreference.saveIsEnabled(true)
        VoiceInkLipDictationPreference.saveLipOnly(true)
        let fixture = try RecordingFixture(mode: .lips)
        fixture.beginRecording()

        switch action {
        case .masterOff:
            VoiceInkLipDictationPreference.saveIsEnabled(false)
            NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: defaults)
            #expect(fixture.engine.recordingCancellationForTesting == .sessionEnded)
            #expect(await fixture.engine.waitUntilRecordingIsIdle())
        case .reset:
            await fixture.engine.resetRecordingSession()
        case .shutdown:
            await fixture.engine.shutDown()
        }

        #expect(try fixture.transcriptionCount() == 0, "Unexpected history after \(action)")
        #expect(try fixture.context.fetchCount(FetchDescriptor<SessionMetric>()) == 0)
        #expect(fixture.audioURL == nil)
        #expect(fixture.engine.recordingState == .idle)
        await fixture.engine.shutDown()
    }

    // A failed startup keeps audio only if a row references it. An explicit cancel inserts its
    // row before awaiting the duration, so that unsaved row must already count as a reference.
    @Test @MainActor func unsavedCanceledRowCountsAsAudioReference() throws {
        let fixture = try RecordingFixture()
        let storedURL: String? = try #require(fixture.audioURL).absoluteString
        fixture.context.insert(Transcription(text: "", duration: 0, audioFileURL: storedURL))

        let referencing = FetchDescriptor<Transcription>(predicate: #Predicate { $0.audioFileURL == storedURL })
        #expect(try fixture.context.fetchCount(referencing) == 1)
    }

    @Test @MainActor func emptyTranscriptionLeavesNoHistoryRowAudioOrMetric() async throws {
        let fixture = try RecordingFixture()
        fixture.beginRecording(session: GatedTextSession(text: " \n ", released: true))

        await fixture.engine.toggleRecord()

        #expect(try fixture.transcriptionCount() == 0)
        #expect(try fixture.context.fetchCount(FetchDescriptor<SessionMetric>()) == 0)
        #expect(!fixture.audioExists)
        #expect(fixture.engine.recordingState == .idle)
    }

    @Test @MainActor func accidentalShortcutCancelDuringTranscriptionLeavesNoHistoryRowOrAudio() async throws {
        let fixture = try RecordingFixture()
        let session = GatedTextSession(text: "hello", released: false)
        fixture.beginRecording(session: session)

        let stop = Task { await fixture.engine.toggleRecord() }
        await session.waitUntilTranscribing()
        await fixture.engine.cancelRecording(.accidentalShortcut)
        session.release()
        await stop.value

        #expect(try fixture.transcriptionCount() == 0)
        #expect(!fixture.audioExists)
    }

    @Test @MainActor func accidentalShortcutCancelDuringStartupStartsNoCapture() async throws {
        let gate = SelectionDrainGate()
        defer { gate.release() }
        let qwen = QwenModelManager(runtimeResult: .failure(FixtureError.unusedRuntime)) { await gate.drain() }
        let fixture = try RecordingFixture(qwenModelManager: qwen)
        fixture.models.currentTranscriptionModel = QwenModel()
        // Hold startup inside session preparation, where a quick Shift+Control chord lands.
        qwen.recordingSelectionChanged(isSelected: false)
        await gate.waitUntilEntered()

        let start = Task { await fixture.engine.toggleRecord() }
        let startupFile = try #require(await fixture.engine.recordedFileOnceStarting())
        defer { try? FileManager.default.removeItem(at: startupFile) }
        let cancel = Task { await fixture.engine.cancelRecording(.accidentalShortcut) }
        #expect(await fixture.engine.waitForRecordingCancellation(.accidentalShortcut))
        gate.release()
        await start.value
        await cancel.value
        let leakedSession = fixture.engine.currentSession
        await fixture.engine.recorder.stopRecording()

        #expect(!FileManager.default.fileExists(atPath: startupFile.path))
        #expect(leakedSession == nil)
        #expect(fixture.engine.recordingState == .idle)
        #expect(try fixture.transcriptionCount() == 0)
    }

    @Test(.timeLimit(.minutes(1)))
    @MainActor func userCanceledStartupOwnsAudioBeforeAwaitingDrain() async throws {
        let gate = SelectionDrainGate()
        defer { gate.release() }
        let qwen = QwenModelManager(runtimeResult: .failure(FixtureError.unusedRuntime)) { await gate.drain() }
        let fixture = try RecordingFixture(qwenModelManager: qwen)
        fixture.models.currentTranscriptionModel = QwenModel()
        qwen.recordingSelectionChanged(isSelected: false)
        await gate.waitUntilEntered()

        let start = Task { await fixture.engine.toggleRecord() }
        let startupFile = try #require(await fixture.engine.recordedFileOnceStarting())
        defer { try? FileManager.default.removeItem(at: startupFile) }
        try FileManager.default.copyItem(at: #require(fixture.audioURL), to: startupFile)
        let cancel = Task { await fixture.engine.cancelRecording(.userRequested) }
        #expect(await fixture.engine.waitForRecordingCancellation(.userRequested))
        let pending = try fixture.context.fetch(FetchDescriptor<Transcription>())
        #expect(pending.map(\.audioFileURL) == [startupFile.absoluteString])
        #expect(pending.map(\.transcriptionState) == [.canceled])

        gate.release()
        await start.value
        await cancel.value

        let rows = try fixture.context.fetch(FetchDescriptor<Transcription>())
        #expect(rows.map(\.transcriptionState) == [.canceled])
        let stored = try #require(rows.first)
        #expect(stored.hasStoredAudioFile())
        #expect(fixture.engine.recordingState == .idle)
    }

    @Test(.timeLimit(.minutes(1)))
    @MainActor func deletedStartupCancellationIsNotRecreatedAfterDrain() async throws {
        let gate = SelectionDrainGate()
        defer { gate.release() }
        let qwen = QwenModelManager(runtimeResult: .failure(FixtureError.unusedRuntime)) { await gate.drain() }
        let fixture = try RecordingFixture(qwenModelManager: qwen)
        fixture.models.currentTranscriptionModel = QwenModel()
        qwen.recordingSelectionChanged(isSelected: false)
        await gate.waitUntilEntered()

        let start = Task { await fixture.engine.toggleRecord() }
        let startupFile = try #require(await fixture.engine.recordedFileOnceStarting())
        defer { try? FileManager.default.removeItem(at: startupFile) }
        try FileManager.default.copyItem(at: #require(fixture.audioURL), to: startupFile)
        let cancel = Task { await fixture.engine.cancelRecording(.userRequested) }
        #expect(await fixture.engine.waitForRecordingCancellation(.userRequested))
        let pending = try #require(try fixture.context.fetch(FetchDescriptor<Transcription>()).first)
        let storedAudio = pending.audioFileURL
        let pendingIdentity = ObjectIdentifier(pending)
        let creations = TranscriptionNotificationCounter()
        let observer = NotificationCenter.default.addObserver(forName: .transcriptionCreated, object: nil, queue: nil) { notification in
            guard let transcription = notification.object as? Transcription,
                  ObjectIdentifier(transcription) == pendingIdentity else { return }
            creations.count += 1
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        fixture.context.delete(pending)
        try fixture.context.save()
        VoiceInkStoredAudioFile.deleteExistingFileReportingFailure(for: storedAudio) { Issue.record($0) }

        gate.release()
        await start.value
        await cancel.value

        #expect(try fixture.transcriptionCount() == 0)
        #expect(creations.count == 0)
        #expect(!FileManager.default.fileExists(atPath: startupFile.path))
        #expect(fixture.engine.recordingState == .idle)
    }

    @Test @MainActor func emptyResultBehindNewerRowAnnouncesDeletionAndLeavesSelection() async throws {
        let fixture = try RecordingFixture()
        let session = GatedTextSession(text: "", released: false)
        fixture.beginRecording(session: session)
        let stop = Task { await fixture.engine.toggleRecord() }
        await session.waitUntilTranscribing()
        let pending = try #require(try fixture.context.fetch(FetchDescriptor<Transcription>()).first)
        // A newer row (e.g. an imported file) lands while the selected pending row transcribes.
        let newer = Transcription(text: "imported", duration: 1, transcriptionStatus: .completed)
        fixture.context.insert(newer)
        try fixture.context.save()
        let deletions = TranscriptionNotificationCounter()
        let observer = NotificationCenter.default.addObserver(forName: .transcriptionDeleted, object: nil, queue: nil) { _ in
            deletions.count += 1
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        session.release()
        await stop.value

        var latest = FetchDescriptor<Transcription>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        latest.fetchLimit = 1
        #expect(try fixture.context.fetch(latest).map(\.id) == [newer.id])
        #expect(deletions.count == 1)
        #expect(TranscriptionHistoryQuery.liveSelection([pending, newer], in: fixture.context) == [newer])
    }
}

extension VoiceInkTests {
    @Test @MainActor func historySelectionDropsOlderRowDeletedByAnotherContext() throws {
        let fixture = try RecordingFixture()
        let older = Transcription(text: "older", duration: 1, transcriptionStatus: .completed)
        let newest = Transcription(text: "newest", duration: 1, transcriptionStatus: .completed)
        fixture.context.insert(older)
        fixture.context.insert(newest)
        try fixture.context.save()

        // Auto-cleanup deletes on a background context; the newest row stays put.
        let cleanup = ModelContext(fixture.context.container)
        let olderID = older.id
        try cleanup.delete(model: Transcription.self, where: #Predicate { $0.id == olderID })
        try cleanup.save()

        #expect(TranscriptionHistoryQuery.liveSelection([older, newest], in: fixture.context) == [newest])
    }
}

@MainActor private final class RecordingFixture {
    let context: ModelContext
    let models: TranscriptionModelManager
    let engine: VoiceInkEngine
    let audioURL: URL?
    private let mode: VoiceInkDictationMode
    private let qwenModelManager: QwenModelManager?

    init(qwenModelManager: QwenModelManager? = nil, mode: VoiceInkDictationMode = .voice) throws {
        self.mode = mode
        let schema = Schema([Transcription.self, VocabularyWord.self, WordReplacement.self, SessionMetric.self])
        // Mirror the app's named stores; the host app binds SessionMetric to "stats" process-wide.
        let container = try ModelContainer(for: schema, configurations: [
            ModelConfiguration("default", schema: Schema([Transcription.self]), isStoredInMemoryOnly: true),
            ModelConfiguration("dictionary", schema: Schema([VocabularyWord.self, WordReplacement.self]), isStoredInMemoryOnly: true),
            ModelConfiguration("stats", schema: Schema([SessionMetric.self]), isStoredInMemoryOnly: true),
        ])
        context = ModelContext(container)
        self.qwenModelManager = qwenModelManager
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let whisper = WhisperModelManager(modelsDirectory: directory.appendingPathComponent("models"))
        models = TranscriptionModelManager(
            whisperModelManager: whisper,
            fluidAudioModelManager: FluidAudioModelManager(),
            qwenModelManager: qwenModelManager
        )
        models.currentTranscriptionModel = TranscriptionModelRegistry.defaultMacOSFluidAudioModel
        engine = VoiceInkEngine(modelContext: context, whisperModelManager: whisper,
            transcriptionModelManager: models, qwenRuntimeResult: .failure(FixtureError.unusedRuntime))
        if mode.usesMicrophone {
            let url = directory.appendingPathComponent("recording.wav")
            audioURL = url
            try Self.writeSilence(to: url)
        } else {
            audioURL = nil
        }
    }

    var audioExists: Bool { audioURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false }

    func transcriptionCount() throws -> Int {
        try context.fetchCount(FetchDescriptor<Transcription>())
    }

    func beginRecording(session: TranscriptionSession? = nil) {
        engine.installCapturedRecordingForTesting(
            audioURL: audioURL,
            model: mode.usesMicrophone ? models.currentTranscriptionModel : nil,
            session: session,
            mode: mode
        )
    }

    private static func writeSilence(to url: URL) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000)!
        buffer.frameLength = 16_000
        try file.write(from: buffer)
    }
}

private extension VoiceInkEngine {
    func waitUntilRecordingIsIdle() async -> Bool {
        for _ in 0..<500 {
            if recordingState == .idle { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    func waitForRecordingCancellation(_ cancellation: RecordingCancellation) async -> Bool {
        for _ in 0..<500 {
            if recordingCancellationForTesting == cancellation { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    func recordedFileOnceStarting() async -> URL? {
        for _ in 0..<500 {
            if recordingState == .starting, let recordedFile { return recordedFile }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return nil
    }
}

private enum FixtureError: Error { case unusedRuntime }

enum RecordingSessionEndAction: CaseIterable, Sendable {
    case masterOff, reset, shutdown
}

private final class TranscriptionNotificationCounter: @unchecked Sendable { var count = 0 }

@MainActor private final class GatedTextSession: TranscriptionSession {
    private let text: String
    private var released: Bool
    private var gate: CheckedContinuation<Void, Never>?
    private var entered: CheckedContinuation<Void, Never>?
    private var isTranscribing = false

    init(text: String, released: Bool) {
        self.text = text
        self.released = released
    }

    func prepare(model: any TranscriptionModel, latencyTraceToken: VoiceInkLatencyTrace.Token?) async throws -> ((Data) -> Void)? { nil }

    func transcribe(audioURL: URL) async throws -> String {
        isTranscribing = true
        entered?.resume(); entered = nil
        if !released { await withCheckedContinuation { gate = $0 } }
        return text
    }

    func cancel() { release() }

    func release() { released = true; gate?.resume(); gate = nil }

    func waitUntilTranscribing() async {
        if isTranscribing { return }
        await withCheckedContinuation { entered = $0 }
    }
}

@MainActor private final class SelectionDrainGate {
    private var entered: CheckedContinuation<Void, Never>?
    private var held: CheckedContinuation<Void, Never>?
    private var released = false
    private var calls = 0

    func drain() async {
        calls += 1
        entered?.resume(); entered = nil
        if !released { await withCheckedContinuation { held = $0 } }
    }

    func waitUntilEntered() async {
        if calls > 0 { return }
        await withCheckedContinuation { entered = $0 }
    }

    func release() { released = true; held?.resume(); held = nil }
}
