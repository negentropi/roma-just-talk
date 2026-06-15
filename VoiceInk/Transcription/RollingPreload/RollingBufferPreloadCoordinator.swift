import Foundation
import os

struct RollingBufferPreloadedSession {
    let session: TranscriptionSession
    let audioChunkHandler: (Data) -> Void
}

private final class RollingBufferChunkSource: @unchecked Sendable {
    let stream: AsyncStream<Data>
    private let continuation: AsyncStream<Data>.Continuation

    init() {
        let (stream, continuation) = AsyncStream.makeStream(
            of: Data.self,
            bufferingPolicy: .bufferingNewest(400)
        )
        self.stream = stream
        self.continuation = continuation
    }

    deinit {
        continuation.finish()
    }

    func send(_ data: Data) {
        continuation.yield(data)
    }
}

private struct RollingChunkBuffer {
    private var chunks: [Data] = []
    private var byteCount = 0
    private var maxBytes: Int

    init(maxBytes: Int) {
        self.maxBytes = max(0, maxBytes)
    }

    mutating func updateMaxBytes(_ newMaxBytes: Int) {
        maxBytes = max(0, newMaxBytes)
        trimIfNeeded()
    }

    mutating func append(_ chunk: Data) {
        guard !chunk.isEmpty, maxBytes > 0 else { return }
        chunks.append(chunk)
        byteCount += chunk.count
        trimIfNeeded()
    }

    mutating func removeAll(keepingCapacity: Bool = true) {
        chunks.removeAll(keepingCapacity: keepingCapacity)
        byteCount = 0
    }

    func snapshot() -> [Data] {
        chunks
    }

    private mutating func trimIfNeeded() {
        while byteCount > maxBytes, !chunks.isEmpty {
            byteCount -= chunks.removeFirst().count
        }
    }
}

@MainActor
final class RollingBufferPreloadCoordinator {
    private enum State {
        case idle
        case starting
        case active
        case claimed
    }

    private struct Plan {
        let model: any TranscriptionModel
    }

    private let serviceRegistry: TranscriptionServiceRegistry
    private weak var transcriptionModelManager: TranscriptionModelManager?
    private let powerStateProvider: any RollingBufferPowerStateProviding
    private let source = RollingBufferChunkSource()
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "RollingBufferPreload")

    private var observeTask: Task<Void, Never>?
    private var detector: SileroSpeechActivityDetector?
    private var detectorLoadTask: Task<SileroSpeechActivityDetector?, Never>?
    private var state: State = .idle
    private var recordingInProgress = false
    private var leadInBuffer: RollingChunkBuffer
    private var vadWindow = Data()
    private var currentSession: TranscriptionSession?
    private var currentCallback: ((Data) -> Void)?
    private var currentModelName: String?

    private let vadWindowBytes = 8_000 // 250 ms at 16 kHz, 16-bit mono.

    init(
        serviceRegistry: TranscriptionServiceRegistry,
        transcriptionModelManager: TranscriptionModelManager,
        powerStateProvider: any RollingBufferPowerStateProviding = IOKitRollingBufferPowerStateProvider()
    ) {
        self.serviceRegistry = serviceRegistry
        self.transcriptionModelManager = transcriptionModelManager
        self.powerStateProvider = powerStateProvider
        self.leadInBuffer = RollingChunkBuffer(
            maxBytes: Self.bytes(forDuration: RollingBufferPreloadSettings.defaultBufferDurationSeconds)
        )
    }

    var audioChunkHandler: (Data) -> Void {
        let source = source
        return { data in
            source.send(data)
        }
    }

    func start() {
        guard observeTask == nil else { return }
        let stream = source.stream
        observeTask = Task { [weak self] in
            for await chunk in stream {
                await self?.processRollingChunk(chunk)
            }
        }
    }

    func prepareForRecordingStart() {
        recordingInProgress = true
        if state != .active {
            resetPreloadState(cancelSession: true, keepLeadIn: true)
        }
    }

    func claimPreloadedSession(for model: any TranscriptionModel) -> RollingBufferPreloadedSession? {
        guard state == .active,
              currentModelName == model.name,
              RollingBufferPreloadSettings.configuration().preRunFinalization,
              let session = currentSession,
              let callback = currentCallback else {
            return nil
        }

        state = .claimed
        currentSession = nil
        currentCallback = nil
        currentModelName = nil
        vadWindow.removeAll(keepingCapacity: true)
        leadInBuffer.removeAll()
        logger.notice("Claimed rolling preload session for \(model.displayName, privacy: .public)")
        return RollingBufferPreloadedSession(session: session, audioChunkHandler: callback)
    }

    func recordingSessionDidFinish() {
        recordingInProgress = false
        resetPreloadState(cancelSession: state != .claimed, keepLeadIn: false)
        state = .idle
    }

    func settingsDidChange() {
        detectorLoadTask?.cancel()
        detectorLoadTask = nil
        detector = nil
        resetPreloadState(cancelSession: true, keepLeadIn: false)
    }

    private func processRollingChunk(_ chunk: Data) async {
        guard !chunk.isEmpty else { return }

        let configuration = RollingBufferPreloadSettings.configuration()
        leadInBuffer.updateMaxBytes(Self.bytes(forDuration: configuration.bufferDurationSeconds))

        if recordingInProgress, state != .active {
            return
        }

        if currentModelName != transcriptionModelManager?.currentTranscriptionModel?.name {
            resetPreloadState(cancelSession: true, keepLeadIn: false)
        }

        leadInBuffer.append(chunk)

        if state == .active {
            currentCallback?(chunk)
            return
        }

        guard state == .idle,
              let plan = currentPlan(configuration: configuration) else {
            return
        }

        vadWindow.append(chunk)
        guard vadWindow.count >= vadWindowBytes else { return }
        let window = vadWindow
        vadWindow.removeAll(keepingCapacity: true)

        guard let detector = await detectorForCurrentSettings(),
              detector.containsSpeech(inPCM16LEData: window) else {
            return
        }

        await startPreload(with: plan, leadInChunks: leadInBuffer.snapshot())
    }

    private func currentPlan(configuration: RollingBufferPreloadConfiguration) -> Plan? {
        guard let model = transcriptionModelManager?.currentTranscriptionModel else { return nil }
        let perModelEnabled = RollingBufferPreloadSettings.perModelPreloadEnabled(for: model)
        let powerState = powerStateProvider.currentPowerState()
        let allowed = RollingBufferPreloadPolicy(
            configuration: configuration,
            powerState: powerState
        ).allowsPreload(
            for: model,
            perModelEnabled: perModelEnabled
        )

        guard allowed else { return nil }
        return Plan(model: model)
    }

    private func detectorForCurrentSettings() async -> SileroSpeechActivityDetector? {
        if let detector {
            return detector
        }

        if let detectorLoadTask {
            let loaded = await detectorLoadTask.value
            detector = loaded
            return loaded
        }

        let task = Task {
            await SileroSpeechActivityDetector.makeDefault()
        }
        detectorLoadTask = task
        let loaded = await task.value
        detectorLoadTask = nil
        detector = loaded
        return loaded
    }

    private func startPreload(with plan: Plan, leadInChunks: [Data]) async {
        guard state == .idle else { return }
        state = .starting
        currentModelName = plan.model.name

        let session = serviceRegistry.createSession(
            for: plan.model,
            onPartialTranscript: { partial in
                Task { @MainActor in
                    NotificationCenter.default.post(
                        name: .rollingBufferPreloadPartialTranscript,
                        object: nil,
                        userInfo: ["text": partial]
                    )
                }
            }
        )

        do {
            guard let callback = try await session.prepare(model: plan.model) else {
                state = .idle
                currentModelName = nil
                return
            }

            currentSession = session
            currentCallback = callback
            for chunk in leadInChunks {
                callback(chunk)
            }
            state = .active
            logger.notice("Started rolling preload for \(plan.model.displayName, privacy: .public) leadInChunks=\(leadInChunks.count, privacy: .public)")
        } catch {
            logger.error("Rolling preload failed to start: \(error.localizedDescription, privacy: .public)")
            session.cancel()
            resetPreloadState(cancelSession: false, keepLeadIn: true)
        }
    }

    private func resetPreloadState(cancelSession: Bool, keepLeadIn: Bool) {
        if cancelSession {
            currentSession?.cancel()
        }
        currentSession = nil
        currentCallback = nil
        currentModelName = nil
        vadWindow.removeAll(keepingCapacity: true)
        if !keepLeadIn {
            leadInBuffer.removeAll()
        }
        if state != .claimed {
            state = .idle
        }
    }

    private static func bytes(forDuration seconds: Double) -> Int {
        Int((seconds * 16_000 * Double(MemoryLayout<Int16>.size)).rounded())
    }
}
