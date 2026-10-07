import Foundation
import SwiftData

enum ModelProvider { case fluidAudio, cartesia }
protocol TranscriptionModel {
    var name: String { get }
    var displayName: String { get }
    var provider: ModelProvider { get }
}
struct ProofModel: TranscriptionModel {
    let name = "proof"
    let displayName = "Proof"
    let provider = ModelProvider.cartesia
}
protocol TranscriptionService {
    func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String
}
enum VoiceInkEngineError: Error { case transcriptionFailed }
final class FluidAudioTranscriptionService {}
final class FluidAudioStreamingProvider: StreamingTranscriptionProvider {
    let transcriptionEvents = AsyncStream<StreamingTranscriptionEvent> { $0.finish() }
    init(fluidAudioService: FluidAudioTranscriptionService) { fatalError("unused proof provider") }
    func connect(model: any TranscriptionModel, language: String?) async throws {}
    func sendAudioChunk(_ data: Data) async throws {}
    func commit() async throws {}
    func disconnect() async {}
}

@MainActor enum CloudProviderRegistry {
    static var mock: ProofProvider!
    static func provider(for: ModelProvider) -> ProofCloudProvider? { ProofCloudProvider() }
}
struct ProofCloudProvider {
    @MainActor func makeStreamingProvider(modelContext: ModelContext) -> StreamingTranscriptionProvider? { CloudProviderRegistry.mock }
}

final class ProofProvider: StreamingTranscriptionProvider, @unchecked Sendable {
    let transcriptionEvents: AsyncStream<StreamingTranscriptionEvent>
    private let events: AsyncStream<StreamingTranscriptionEvent>.Continuation
    private let lock = NSLock()
    private var sendReceipt: CheckedContinuation<Void, Error>?
    private var sentData: Data?
    init() {
        (transcriptionEvents, events) = AsyncStream.makeStream()
    }
    func connect(model: any TranscriptionModel, language: String?) async throws { events.yield(.sessionStarted) }
    func sendAudioChunk(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { receipt in
            lock.lock()
            sentData = data
            sendReceipt = receipt
            lock.unlock()
        }
    }
    func completeSend() {
        lock.lock()
        let receipt = sendReceipt
        sendReceipt = nil
        lock.unlock()
        receipt?.resume()
    }
    func receivedAudio() -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return sentData
    }
    func commit() async throws {}
    func disconnect() async { events.finish() }
    func closeUnexpectedly() { events.finish() }
}

struct ProofFallback: TranscriptionService {
    func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String { "saved audio fallback" }
}

@main struct StreamingRegression {
    @MainActor static func main() async throws {
        let container = try ModelContainer(for: Schema([]), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let provider = ProofProvider()
        CloudProviderRegistry.mock = provider
        let service = StreamingTranscriptionService(modelContext: container.mainContext)
        var failures = 0
        service.onFailure = { _ in failures += 1 }
        let session = StreamingTranscriptionSession(streamingService: service, fallbackService: ProofFallback())
        var prepared = false
        let pcm = Data(repeating: 0, count: 3200)
        session.audioChunkCallback?(pcm)
        let preparation = Task { @MainActor in
            try await session.prepare(model: ProofModel())
            prepared = true
        }
        try await Task.sleep(for: .milliseconds(250))
        guard !prepared else {
            print("RED resume-only connect incorrectly marked the production session prepared before any successful PCM send")
            Foundation.exit(1)
        }
        assert(provider.receivedAudio() == pcm, "real callback forwards exact recorded PCM before preparation completes")
        provider.completeSend()
        try await preparation.value
        assert(prepared, "successful actual audio send completes production session preparation")
        provider.closeUnexpectedly()
        try await Task.sleep(for: .milliseconds(250))
        assert(failures == 1, "unexpected provider stream closure reports failure exactly once")
        session.cancel()
        let canceledProvider = ProofProvider()
        CloudProviderRegistry.mock = canceledProvider
        let canceledService = StreamingTranscriptionService(modelContext: container.mainContext)
        let canceledSession = StreamingTranscriptionSession(streamingService: canceledService, fallbackService: ProofFallback())
        canceledSession.audioChunkCallback?(pcm)
        let canceledPreparation = Task { @MainActor in try await canceledSession.prepare(model: ProofModel()) }
        try await Task.sleep(for: .milliseconds(100))
        canceledSession.cancel()
        do {
            try await canceledPreparation.value
            fatalError("canceled preparation advertised readiness")
        } catch is CancellationError {}
        canceledProvider.completeSend()
        try await Task.sleep(for: .milliseconds(100))
        assert(!canceledService.isActive, "late audio send cannot revive canceled streaming session")
        print("GREEN production streaming session waits for successful recorded PCM send, reports unexpected stream closure, and rejects late canceled send")
    }
}
