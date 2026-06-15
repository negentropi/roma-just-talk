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

    var count: Int {
        chunks.count
    }

    var bytes: Int {
        byteCount
    }

    private mutating func trimIfNeeded() {
        while byteCount > maxBytes, !chunks.isEmpty {
            byteCount -= chunks.removeFirst().count
        }
    }
}

@MainActor
final class RollingBufferPreloadCoordinator {
    typealias CurrentModelProvider = @MainActor () -> (any TranscriptionModel)?
    typealias DetectorProvider = @Sendable () async -> (any SpeechActivityDetecting)?
    typealias SessionFactory = @MainActor (any TranscriptionModel, @escaping (String) -> Void) -> TranscriptionSession

    private enum State {
        case idle
        case starting
        case active
        case claimed
    }

    private struct Plan {
        let model: any TranscriptionModel
    }

    private let currentModelProvider: CurrentModelProvider
    private let detectorProvider: DetectorProvider
    private let sessionFactory: SessionFactory
    private let powerStateProvider: any RollingBufferPowerStateProviding
    private let source = RollingBufferChunkSource()
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "RollingBufferPreload")

    private var observeTask: Task<Void, Never>?
    private var detector: (any SpeechActivityDetecting)?
    private var detectorLoadTask: Task<(any SpeechActivityDetecting)?, Never>?
    private var detectorLoadAttempted = false
    private var state: State = .idle
    private var recordingInProgress = false
    private var leadInBuffer: RollingChunkBuffer
    private var vadWindow = Data()
    private var currentSession: TranscriptionSession?
    private var currentCallback: ((Data) -> Void)?
    private var currentModelName: String?
    private var speechDetectedAt: Date?
    private var preloadStartedAt: Date?
    private var observedChunks = 0
    private var observedBytes = 0
    private var preloadedChunks = 0
    private var preloadedBytes = 0
    private var vadWindowsChecked = 0

    private let vadWindowBytes = 8_000 // 250 ms at 16 kHz, 16-bit mono.

    init(
        serviceRegistry: TranscriptionServiceRegistry,
        transcriptionModelManager: TranscriptionModelManager,
        powerStateProvider: any RollingBufferPowerStateProviding = IOKitRollingBufferPowerStateProvider(),
        detectorProvider: @escaping DetectorProvider = {
            await SileroSpeechActivityDetector.makeDefault()
        }
    ) {
        self.currentModelProvider = { [weak transcriptionModelManager] in
            transcriptionModelManager?.currentTranscriptionModel
        }
        self.detectorProvider = detectorProvider
        self.sessionFactory = { model, partialTranscriptHandler in
            serviceRegistry.createSession(
                for: model,
                onPartialTranscript: partialTranscriptHandler,
                forceStreaming: true
            )
        }
        self.powerStateProvider = powerStateProvider
        self.leadInBuffer = RollingChunkBuffer(
            maxBytes: Self.bytes(forDuration: RollingBufferPreloadSettings.defaultBufferDurationSeconds)
        )
    }

    init(
        currentModelProvider: @escaping CurrentModelProvider,
        powerStateProvider: any RollingBufferPowerStateProviding,
        detectorProvider: @escaping DetectorProvider,
        sessionFactory: @escaping SessionFactory
    ) {
        self.currentModelProvider = currentModelProvider
        self.detectorProvider = detectorProvider
        self.sessionFactory = sessionFactory
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

    func processRollingChunkForTesting(_ chunk: Data) async {
        await processRollingChunk(chunk)
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
        let triggerElapsed = speechDetectedAt.map { Date().timeIntervalSince($0) } ?? -1
        let startupElapsed = preloadStartedAt.map { Date().timeIntervalSince($0) } ?? -1
        logger.notice("Claimed rolling preload session model=\(model.displayName, privacy: .public) triggerElapsed=\(triggerElapsed, format: .fixed(precision: 3), privacy: .public)s startupElapsed=\(startupElapsed, format: .fixed(precision: 3), privacy: .public)s preloadedChunks=\(self.preloadedChunks, privacy: .public) preloadedBytes=\(self.preloadedBytes, privacy: .public)")
        return RollingBufferPreloadedSession(session: session, audioChunkHandler: callback)
    }

    func cancelUnclaimedPreload(reason: String) {
        guard currentSession != nil || state == .starting || state == .active else { return }
        logger.notice("Canceling unclaimed rolling preload reason=\(reason, privacy: .public) state=\(String(describing: self.state), privacy: .public) preloadedChunks=\(self.preloadedChunks, privacy: .public) preloadedBytes=\(self.preloadedBytes, privacy: .public)")
        resetPreloadState(cancelSession: true, keepLeadIn: false)
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
        detectorLoadAttempted = false
        resetPreloadState(cancelSession: true, keepLeadIn: false)
    }

    private func processRollingChunk(_ chunk: Data) async {
        guard !chunk.isEmpty else { return }
        observedChunks += 1
        observedBytes += chunk.count

        let configuration = RollingBufferPreloadSettings.configuration()
        leadInBuffer.updateMaxBytes(Self.bytes(forDuration: configuration.bufferDurationSeconds))

        if recordingInProgress, state != .active {
            return
        }

        if let currentModelName,
           currentModelName != currentModelProvider()?.name {
            resetPreloadState(cancelSession: true, keepLeadIn: false)
        }

        leadInBuffer.append(chunk)

        if state == .active {
            currentCallback?(chunk)
            preloadedChunks += 1
            preloadedBytes += chunk.count
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
        vadWindowsChecked += 1

        guard let detector = await detectorForCurrentSettings(),
              detector.containsSpeech(inPCM16LEData: window) else {
            return
        }

        speechDetectedAt = Date()
        logger.notice("Rolling preload VAD trigger model=\(plan.model.displayName, privacy: .public) leadInChunks=\(self.leadInBuffer.count, privacy: .public) leadInBytes=\(self.leadInBuffer.bytes, privacy: .public) observedChunks=\(self.observedChunks, privacy: .public) observedBytes=\(self.observedBytes, privacy: .public) vadWindows=\(self.vadWindowsChecked, privacy: .public)")
        await startPreload(with: plan, leadInChunks: leadInBuffer.snapshot())
    }

    private func currentPlan(configuration: RollingBufferPreloadConfiguration) -> Plan? {
        guard let model = currentModelProvider() else { return nil }
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

    private func detectorForCurrentSettings() async -> (any SpeechActivityDetecting)? {
        if let detector {
            return detector
        }
        if detectorLoadAttempted {
            return nil
        }

        if let detectorLoadTask {
            let loaded = await detectorLoadTask.value
            detectorLoadAttempted = true
            detector = loaded
            return loaded
        }

        let detectorProvider = detectorProvider
        let task = Task {
            await detectorProvider()
        }
        detectorLoadTask = task
        let loaded = await task.value
        detectorLoadTask = nil
        detectorLoadAttempted = true
        detector = loaded
        return loaded
    }

    private func startPreload(with plan: Plan, leadInChunks: [Data]) async {
        guard state == .idle else { return }
        state = .starting
        currentModelName = plan.model.name
        preloadStartedAt = Date()

        let session = sessionFactory(
            plan.model,
            { partial in
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
                preloadedChunks += 1
                preloadedBytes += chunk.count
            }
            state = .active
            let startupElapsed = preloadStartedAt.map { Date().timeIntervalSince($0) } ?? -1
            logger.notice("Started rolling preload model=\(plan.model.displayName, privacy: .public) startupElapsed=\(startupElapsed, format: .fixed(precision: 3), privacy: .public)s leadInChunks=\(leadInChunks.count, privacy: .public) leadInBytes=\(leadInChunks.reduce(0) { $0 + $1.count }, privacy: .public)")
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
        speechDetectedAt = nil
        preloadStartedAt = nil
        observedChunks = 0
        observedBytes = 0
        preloadedChunks = 0
        preloadedBytes = 0
        vadWindowsChecked = 0
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
