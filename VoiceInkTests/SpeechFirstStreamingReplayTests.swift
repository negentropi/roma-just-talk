import Foundation
import Testing
import VoiceInkCore
@testable import VoiceInk

@Suite(.serialized)
struct SpeechFirstStreamingReplayTests {
    @Test @MainActor
    func speechBeforeKeyDownDrainsBeforeCommitAndProducesPaste() async throws {
        let outcome = try await replay(committedText: "So for example, I can speak longer too.")

        #expect(outcome.audioLeadMilliseconds == 1_100)
        #expect(!outcome.didCommitBeforeBlockedSendResumed)
        #expect(outcome.provider.receivedChunks == outcome.expectedChunks)
        #expect(outcome.provider.didCommit)
        #expect(outcome.provider.didDisconnect)

        let prepared = VoiceInkTranscriptionRunPreparation.prepareRawTextForEnhancement(
            outcome.transcript,
            cleanupConfiguration: VoiceInkTranscriptionCleanupConfiguration()
        )
        #expect(VoiceInkTranscriptionPasteOutputPolicy.shouldPaste(prepared.cleanedText))

        let cursorPlan = VoiceInkTranscriptionPasteOutputPolicy.cursorPasteTextPlan(
            prepared.cleanedText,
            shouldLowercase: false
        )
        let pastedText = VoiceInkTranscriptionPasteOutputPolicy.finalPastedText(
            cursorPlan.text(beforeCursor: ""),
            appendTrailingSpace: true,
            isTrialExpired: false
        )
        #expect(pastedText == "So for example, I can speak longer too. ")
    }

    @Test @MainActor
    func blankCommittedResultStopsBeforePasteDecision() async throws {
        let outcome = try await replay(committedText: " \n\t ")

        #expect(outcome.provider.receivedChunks == outcome.expectedChunks)
        #expect(outcome.provider.didCommit)
        #expect(outcome.transcript.isEmpty)
        #expect(!VoiceInkTranscriptionPasteOutputPolicy.shouldPaste(outcome.transcript))
        #expect(!VoiceInkTranscriptionPasteOutputPolicy.shouldPaste(" \n\t "))
    }

    @MainActor
    private func replay(committedText: String) async throws -> SpeechFirstReplayOutcome {
        let fixture = SpeechFirstPCMFixture()
        let preRoll = VoiceInkPCM16PreRollBuffer(
            sampleRate: VoiceInkPCM16Audio.mono16kSampleRateHz,
            durationSeconds: VoiceInkAudioPreRollPolicy.durationSeconds
        )
        fixture.preKeySamples.withUnsafeBufferPointer { samples in
            guard let baseAddress = samples.baseAddress else { return }
            preRoll.append(baseAddress, sampleCount: samples.count)
        }

        let streamingChunkByteCount = VoiceInkPCM16Audio.byteCount(
            forMono16kDuration: VoiceInkAudioPreRollPolicy.streamingChunkDurationSeconds
        )
        let preRollChunks = VoiceInkPCM16Audio.monoPCM16Chunks(
            from: preRoll.snapshotData(),
            maxByteCount: streamingChunkByteCount
        )
        let liveChunks = VoiceInkPCM16Audio.monoPCM16Chunks(
            from: fixture.livePCM,
            maxByteCount: streamingChunkByteCount
        )
        let expectedChunks = preRollChunks + liveChunks
        let provider = SpeechFirstReplayProvider(
            expectedChunks: expectedChunks,
            blockedChunkIndex: expectedChunks.count,
            committedText: committedText
        )
        let streamingService = StreamingTranscriptionService(
            streamingAdapterKind: .cloud,
            finalCommitTimeoutNanoseconds: 1_000_000_000,
            providerFactory: { _ in provider }
        )
        let session = StreamingTranscriptionSession(
            streamingService: streamingService,
            fallbackService: UnexpectedReplayFallbackService()
        )

        let sendAudio = try await session.prepare(
            model: SpeechFirstReplayModel(),
            latencyTraceToken: nil
        )
        #expect(sendAudio != nil)
        guard let sendAudio else {
            throw SpeechFirstReplayError.missingAudioCallback
        }

        preRollChunks.forEach(sendAudio)
        liveChunks.forEach(sendAudio)

        let transcribeTask = Task { @MainActor in
            try await session.transcribe(
                audioURL: URL(fileURLWithPath: "/tmp/voiceink-speech-first-replay.wav")
            )
        }
        let blocked = await eventually {
            await provider.isBlockedSending
        }
        #expect(blocked)
        let didCommitBeforeBlockedSendResumed = await provider.didCommit
        await provider.resumeBlockedSend()

        let transcript = try await transcribeTask.value
        return SpeechFirstReplayOutcome(
            audioLeadMilliseconds: fixture.audioLeadMilliseconds,
            transcript: transcript,
            expectedChunks: expectedChunks,
            provider: await provider.snapshot(),
            didCommitBeforeBlockedSendResumed: didCommitBeforeBlockedSendResumed
        )
    }

    private func eventually(_ predicate: () async -> Bool) async -> Bool {
        for _ in 0..<10_000 {
            if await predicate() {
                return true
            }
            await Task.yield()
        }
        return await predicate()
    }
}

private struct SpeechFirstPCMFixture {
    let preKeySamples: [Int16]
    let livePCM: Data

    var audioLeadMilliseconds: Int {
        Int(
            (Double(preKeySamples.count)
                / Double(VoiceInkPCM16Audio.mono16kSampleRateHz)
                * 1_000)
                .rounded()
        )
    }

    init() {
        preKeySamples = Self.samples(
            count: VoiceInkPCM16Audio.sampleCount(forMono16kDuration: 1.1),
            amplitude: 2_000
        )
        livePCM = Self.pcmData(
            Self.samples(
                count: VoiceInkPCM16Audio.sampleCount(forMono16kDuration: 1.5),
                amplitude: 3_000
            )
        )
    }

    private static func samples(count: Int, amplitude: Int16) -> [Int16] {
        (0..<count).map { index in
            index.isMultiple(of: 2) ? amplitude : -amplitude
        }
    }

    private static func pcmData(_ samples: [Int16]) -> Data {
        samples.withUnsafeBytes { Data($0) }
    }
}

private struct SpeechFirstReplayModel: TranscriptionModel {
    let id = UUID()
    let name = "speech-first-replay"
    let displayName = "Speech-first replay"
    let description = "Deterministic streaming replay"
    let provider: VoiceInkMacOSTranscriptionModelProvider = .cartesia
    let isMultilingualModel = true
    let supportedLanguages: [String: String] = [:]
    let supportsStreaming = true
}

private struct UnexpectedReplayFallbackService: TranscriptionService {
    func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String {
        throw SpeechFirstReplayError.unexpectedBatchFallback
    }
}

private actor SpeechFirstReplayProvider: StreamingTranscriptionProvider {
    nonisolated let transcriptionEvents: AsyncStream<VoiceInkStreamingTranscriptionEvent>

    private let continuation: AsyncStream<VoiceInkStreamingTranscriptionEvent>.Continuation
    private let expectedChunks: [Data]
    private let blockedChunkIndex: Int
    private let committedText: String
    private var receivedChunks: [Data] = []
    private var blockedSendContinuation: CheckedContinuation<Void, Never>?
    private var releaseWasRequested = false
    private(set) var isBlockedSending = false
    private(set) var didCommit = false
    private var didDisconnect = false

    init(expectedChunks: [Data], blockedChunkIndex: Int, committedText: String) {
        self.expectedChunks = expectedChunks
        self.blockedChunkIndex = blockedChunkIndex
        self.committedText = committedText
        (transcriptionEvents, continuation) = AsyncStream.makeStream(
            of: VoiceInkStreamingTranscriptionEvent.self
        )
    }

    func connect(model: any TranscriptionModel, language: String?) async throws {
        continuation.yield(.sessionStarted)
    }

    func sendAudioChunk(_ data: Data) async throws {
        receivedChunks.append(data)
        guard receivedChunks.count == blockedChunkIndex else { return }

        isBlockedSending = true
        if !releaseWasRequested {
            await withCheckedContinuation { continuation in
                blockedSendContinuation = continuation
            }
        }
        isBlockedSending = false
    }

    func commit() async throws {
        guard receivedChunks == expectedChunks else {
            throw SpeechFirstReplayError.audioDeliveryMismatch
        }
        didCommit = true
        continuation.yield(.committed(text: committedText))
    }

    func disconnect() async {
        didDisconnect = true
        continuation.finish()
    }

    func resumeBlockedSend() {
        releaseWasRequested = true
        blockedSendContinuation?.resume()
        blockedSendContinuation = nil
    }

    func snapshot() -> SpeechFirstReplayProviderSnapshot {
        SpeechFirstReplayProviderSnapshot(
            receivedChunks: receivedChunks,
            didCommit: didCommit,
            didDisconnect: didDisconnect
        )
    }
}

private struct SpeechFirstReplayOutcome {
    let audioLeadMilliseconds: Int
    let transcript: String
    let expectedChunks: [Data]
    let provider: SpeechFirstReplayProviderSnapshot
    let didCommitBeforeBlockedSendResumed: Bool
}

private struct SpeechFirstReplayProviderSnapshot: Sendable {
    let receivedChunks: [Data]
    let didCommit: Bool
    let didDisconnect: Bool
}

private enum SpeechFirstReplayError: Error {
    case missingAudioCallback
    case audioDeliveryMismatch
    case unexpectedBatchFallback
}
