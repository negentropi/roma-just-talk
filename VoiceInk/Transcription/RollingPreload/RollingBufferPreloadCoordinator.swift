import Foundation
import os
import VoiceInkCore

struct RollingBufferPreloadedSession {
    let session: TranscriptionSession
    let audioChunkHandler: (Data) -> Void
    let language: String?
    let audioData: Data
}

struct RollingBufferAudioSnapshot {
    let audioData: Data
    let language: String?
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

@MainActor
final class RollingBufferPreloadCoordinator {
    typealias CurrentModelProvider = @MainActor () -> (any TranscriptionModel)?
    typealias CurrentLanguageProvider = @MainActor () -> String?
    typealias DetectorProvider = @Sendable () async -> (any SpeechActivityDetecting)?
    typealias SessionFactory = @MainActor (any TranscriptionModel, @escaping (String) -> Void) -> TranscriptionSession
    static let startingPreloadClaimWaitNanoseconds: UInt64 = 150_000_000
    static let unclaimedPreloadSilenceSeconds = 1.0
    static let unclaimedPreloadGraceSeconds = 2.0

    private enum State {
        case idle
        case starting
        case active
        case claimed
    }

    private struct Plan {
        let model: any TranscriptionModel
        let language: String?
    }

    private let currentModelProvider: CurrentModelProvider
    private let currentLanguageProvider: CurrentLanguageProvider
    private let detectorProvider: DetectorProvider
    private let sessionFactory: SessionFactory
    private let powerStateProvider: any RollingBufferPowerStateProviding
    private let source = RollingBufferChunkSource()
    private let logger = Logger(subsystem: VoiceInkAppIdentity.loggingSubsystem, category: "RollingBufferPreload")

    private var observeTask: Task<Void, Never>?
    private var detector: (any SpeechActivityDetecting)?
    private var detectorLoadTask: Task<(any SpeechActivityDetecting)?, Never>?
    private var detectorLoadAttempted = false
    private var configuration = VoiceInkRollingBufferPreloadSettings.configuration()
    private var cachedPlan: Plan?
    private var cachedPlanModelName: String?
    private var cachedPlanLanguage: String?
    private var cachedPlanExpiresAt = Date.distantPast
    private var state: State = .idle
    private var recordingInProgress = false
    private var leadInBuffer: VoiceInkRollingAudioBuffer
    private var vadWindow = Data()
    private var currentSession: TranscriptionSession?
    private var currentCallback: ((Data) -> Void)?
    private var currentModelName: String?
    private var currentLanguage: String?
    private var speechDetectedAt: Date?
    private var preloadStartedAt: Date?
    private var observedChunks = 0
    private var observedBytes = 0
    private var preloadedChunks = 0
    private var preloadedBytes = 0
    private var activeSilenceBytes = 0
    private var vadWindowsChecked = 0
    private var startingPreloadWaiters: [CheckedContinuation<Void, Never>] = []

    private let vadWindowBytes = 8_000 // 250 ms at 16 kHz, 16-bit mono.
    private let planRefreshInterval: TimeInterval = 30

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
        self.currentLanguageProvider = {
            VoiceInkTranscriptionLanguagePreference.storedLanguage()
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
        self.leadInBuffer = VoiceInkRollingAudioBuffer(
            maxBytes: VoiceInkPCM16Audio.byteCount(
                forMono16kDuration: VoiceInkRollingBufferPreloadSettings.defaultBufferDurationSeconds
            )
        )
    }

    init(
        currentModelProvider: @escaping CurrentModelProvider,
        currentLanguageProvider: @escaping CurrentLanguageProvider = {
            VoiceInkTranscriptionLanguagePreference.storedLanguage()
        },
        powerStateProvider: any RollingBufferPowerStateProviding,
        detectorProvider: @escaping DetectorProvider,
        sessionFactory: @escaping SessionFactory
    ) {
        self.currentModelProvider = currentModelProvider
        self.currentLanguageProvider = currentLanguageProvider
        self.detectorProvider = detectorProvider
        self.sessionFactory = sessionFactory
        self.powerStateProvider = powerStateProvider
        self.leadInBuffer = VoiceInkRollingAudioBuffer(
            maxBytes: VoiceInkPCM16Audio.byteCount(
                forMono16kDuration: VoiceInkRollingBufferPreloadSettings.defaultBufferDurationSeconds
            )
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
        prewarmDetectorIfEligible()
    }

    func processRollingChunkForTesting(_ chunk: Data) async {
        await processRollingChunk(chunk)
    }

    func prepareForRecordingStart() {
        recordingInProgress = true
        if state != .active && state != .starting {
            resetPreloadState(cancelSession: true, keepLeadIn: true)
        }
    }

    func claimPreloadedSession(for model: any TranscriptionModel) async -> RollingBufferPreloadedSession? {
        let selectedLanguage = currentLanguageProvider()
        guard currentModelName == model.name,
              currentLanguage == selectedLanguage,
              configuration.preRunFinalization else {
            if currentSession != nil || state == .starting || state == .active {
                resetPreloadState(cancelSession: true, keepLeadIn: true)
            }
            return nil
        }

        if state == .starting {
            await waitForStartingPreload()
        }

        guard state == .active,
              let session = currentSession,
              let callback = currentCallback else {
            return nil
        }

        let audioData = leadInBuffer.dataSnapshot()

        state = .claimed
        currentSession = nil
        currentCallback = nil
        currentModelName = nil
        currentLanguage = nil
        vadWindow.removeAll(keepingCapacity: true)
        leadInBuffer.removeAll()
        let triggerElapsed = speechDetectedAt.map { Date().timeIntervalSince($0) } ?? -1
        let startupElapsed = preloadStartedAt.map { Date().timeIntervalSince($0) } ?? -1
        logger.notice("Claimed rolling preload session model=\(model.displayName, privacy: .public) triggerElapsed=\(triggerElapsed, format: .fixed(precision: 3), privacy: .public)s startupElapsed=\(startupElapsed, format: .fixed(precision: 3), privacy: .public)s preloadedChunks=\(self.preloadedChunks, privacy: .public) preloadedBytes=\(self.preloadedBytes, privacy: .public)")
        return RollingBufferPreloadedSession(
            session: session,
            audioChunkHandler: callback,
            language: selectedLanguage,
            audioData: audioData
        )
    }

    func claimBufferedAudioSnapshot() -> RollingBufferAudioSnapshot? {
        let audioData = leadInBuffer.dataSnapshot()
        guard !audioData.isEmpty else { return nil }

        let selectedLanguage = currentLanguageProvider()
        state = .claimed
        resetPreloadState(cancelSession: true, keepLeadIn: false)
        logger.notice("Claimed rolling buffer audio snapshot bytes=\(audioData.count, privacy: .public)")
        return RollingBufferAudioSnapshot(
            audioData: audioData,
            language: selectedLanguage
        )
    }

    func cancelUnclaimedPreload(reason: String) {
        guard currentSession != nil || state == .starting || state == .active else { return }
        logger.notice("Canceling unclaimed rolling preload reason=\(reason, privacy: .public) state=\(String(describing: self.state), privacy: .public) preloadedChunks=\(self.preloadedChunks, privacy: .public) preloadedBytes=\(self.preloadedBytes, privacy: .public)")
        resetPreloadState(cancelSession: true, keepLeadIn: false)
    }

    func recordingSessionDidFinish() {
        let shouldKeepLeadIn = state == .claimed && !recordingInProgress
        recordingInProgress = false
        resetPreloadState(cancelSession: state != .claimed, keepLeadIn: shouldKeepLeadIn)
        state = .idle
    }

    func settingsDidChange() {
        configuration = VoiceInkRollingBufferPreloadSettings.configuration()
        invalidateCachedPlan()
        detectorLoadTask?.cancel()
        detectorLoadTask = nil
        detector = nil
        detectorLoadAttempted = false
        resetPreloadState(cancelSession: true, keepLeadIn: false)
        prewarmDetectorIfEligible()
    }

    private func processRollingChunk(_ chunk: Data) async {
        guard !chunk.isEmpty else { return }
        observedChunks += 1
        observedBytes += chunk.count

        leadInBuffer.updateMaxBytes(
            VoiceInkPCM16Audio.byteCount(forMono16kDuration: configuration.bufferDurationSeconds)
        )

        let selectedModelName = currentModelProvider()?.name
        let selectedLanguage = currentLanguageProvider()
        if let currentModelName,
           currentModelName != selectedModelName || currentLanguage != selectedLanguage {
            resetPreloadState(cancelSession: true, keepLeadIn: false)
        }

        if !recordingInProgress || state == .starting || state == .active {
            leadInBuffer.append(chunk)
        }

        if recordingInProgress, state != .active {
            return
        }

        if state == .active {
            if !recordingInProgress,
               let staleReason = staleUnclaimedPreloadReason(afterAdding: chunk) {
                logger.notice("Canceling stale unclaimed rolling preload reason=\(staleReason, privacy: .public) preloadedChunks=\(self.preloadedChunks, privacy: .public) preloadedBytes=\(self.preloadedBytes, privacy: .public) bufferDuration=\(self.configuration.bufferDurationSeconds, format: .fixed(precision: 2), privacy: .public)s")
                resetPreloadState(cancelSession: true, keepLeadIn: true)
                return
            }
            currentCallback?(chunk)
            preloadedChunks += 1
            preloadedBytes += chunk.count
            return
        }

        guard state == .idle,
              let currentModel = currentModelProvider() else {
            return
        }

        vadWindow.append(chunk)
        guard vadWindow.count >= vadWindowBytes else { return }
        let window = vadWindow
        vadWindow.removeAll(keepingCapacity: true)
        vadWindowsChecked += 1

        guard let plan = currentPlan(
            for: currentModel,
            language: selectedLanguage,
            configuration: configuration
        ) else {
            return
        }

        guard let detector = await detectorForCurrentSettings(),
              detector.containsSpeech(inPCM16LEData: window) else {
            return
        }

        speechDetectedAt = Date()
        logger.notice("Rolling preload VAD trigger model=\(plan.model.displayName, privacy: .public) leadInChunks=\(self.leadInBuffer.count, privacy: .public) leadInBytes=\(self.leadInBuffer.bytes, privacy: .public) observedChunks=\(self.observedChunks, privacy: .public) observedBytes=\(self.observedBytes, privacy: .public) vadWindows=\(self.vadWindowsChecked, privacy: .public)")
        await startPreload(with: plan)
    }

    private func currentPlan(
        for model: any TranscriptionModel,
        language: String?,
        configuration: VoiceInkRollingBufferPreloadConfiguration
    ) -> Plan? {
        let now = Date()
        if cachedPlanModelName == model.name,
           cachedPlanLanguage == language,
           now < cachedPlanExpiresAt {
            return cachedPlan
        }

        if configuration.mode == .off || !configuration.preRunFinalization || !model.supportsStreaming {
            return cachePlan(nil, for: model.name, language: language, now: now)
        }

        let perModelEnabled = VoiceInkRollingBufferPreloadSettings.perModelPreloadEnabled(for: model)
        guard perModelEnabled else {
            return cachePlan(nil, for: model.name, language: language, now: now)
        }

        if !allowsPreloadBeforeDetector(
            for: model,
            configuration: configuration,
            perModelEnabled: perModelEnabled
        ) {
            return cachePlan(nil, for: model.name, language: language, now: now)
        }

        return cachePlan(Plan(model: model, language: language), for: model.name, language: language, now: now)
    }

    private func allowsPreloadBeforeDetector(
        for model: any TranscriptionModel,
        configuration: VoiceInkRollingBufferPreloadConfiguration,
        perModelEnabled: Bool
    ) -> Bool {
        let snapshot = model.rollingBufferPreloadSnapshot
        switch configuration.mode {
        case .on:
            return true
        case .off:
            return false
        case .auto:
            if configuration.autoDisablesCloudModels, snapshot.isCloudTranscriptionProvider {
                return false
            }

            guard configuration.autoDisablesLowBatteryLocalModels,
                  snapshot.isLocalTranscriptionProvider else {
                return true
            }
        }

        return VoiceInkRollingBufferPreloadPolicy(
            configuration: configuration,
            powerState: powerStateProvider.currentPowerState()
        ).allowsPreload(
            for: snapshot,
            perModelEnabled: perModelEnabled
        )
    }

    private func staleUnclaimedPreloadReason(afterAdding chunk: Data) -> String? {
        vadWindow.append(chunk)
        if vadWindow.count >= vadWindowBytes {
            let window = vadWindow
            vadWindow.removeAll(keepingCapacity: true)
            if detector?.containsSpeech(inPCM16LEData: window) == true {
                activeSilenceBytes = 0
            } else if detector != nil {
                activeSilenceBytes += window.count
            }
        }

        if activeSilenceBytes >= VoiceInkPCM16Audio.byteCount(
            forMono16kDuration: Self.unclaimedPreloadSilenceSeconds
        ) {
            return "silence"
        }

        if preloadedBytes >= VoiceInkPCM16Audio.byteCount(
            forMono16kDuration: configuration.bufferDurationSeconds + Self.unclaimedPreloadGraceSeconds
        ) {
            return "max-duration"
        }

        return nil
    }

    private func cachePlan(_ plan: Plan?, for modelName: String, language: String?, now: Date) -> Plan? {
        cachedPlan = plan
        cachedPlanModelName = modelName
        cachedPlanLanguage = language
        cachedPlanExpiresAt = now.addingTimeInterval(planRefreshInterval)
        return plan
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

        let task = beginDetectorLoad()
        let loaded = await task.value
        detectorLoadTask = nil
        detectorLoadAttempted = true
        detector = loaded
        return loaded
    }

    private func prewarmDetectorIfEligible() {
        guard detector == nil,
              detectorLoadTask == nil,
              !detectorLoadAttempted,
              let currentModel = currentModelProvider(),
              currentPlan(
                for: currentModel,
                language: currentLanguageProvider(),
                configuration: configuration
              ) != nil else {
            return
        }

        _ = beginDetectorLoad()
    }

    private func beginDetectorLoad() -> Task<(any SpeechActivityDetecting)?, Never> {
        if let detectorLoadTask {
            return detectorLoadTask
        }

        let detectorProvider = detectorProvider
        let task = Task {
            await detectorProvider()
        }
        detectorLoadTask = task
        return task
    }

    private func startPreload(with plan: Plan) async {
        guard state == .idle else { return }
        state = .starting
        currentModelName = plan.model.name
        currentLanguage = plan.language
        preloadStartedAt = Date()

        let session = sessionFactory(
            plan.model,
            { partial in
                Task { @MainActor in
                    NotificationCenter.default.post(
                        name: .rollingBufferPreloadPartialTranscript,
                        object: nil,
                        userInfo: VoiceInkRollingBufferPreloadPartialTranscriptRequest.userInfo(text: partial)
                    )
                }
            }
        )

        do {
            guard let callback = try await session.prepare(model: plan.model) else {
                state = .idle
                currentModelName = nil
                currentLanguage = nil
                resumeStartingPreloadWaiters()
                return
            }

            guard state == .starting,
                  currentModelName == plan.model.name,
                  currentLanguage == plan.language else {
                session.cancel()
                resumeStartingPreloadWaiters()
                return
            }

            currentSession = session
            currentCallback = callback
            let bufferedChunks = leadInBuffer.chunksSnapshot()
            for chunk in bufferedChunks {
                callback(chunk)
                preloadedChunks += 1
                preloadedBytes += chunk.count
            }
            state = .active
            resumeStartingPreloadWaiters()
            let startupElapsed = preloadStartedAt.map { Date().timeIntervalSince($0) } ?? -1
            logger.notice("Started rolling preload model=\(plan.model.displayName, privacy: .public) startupElapsed=\(startupElapsed, format: .fixed(precision: 3), privacy: .public)s leadInChunks=\(bufferedChunks.count, privacy: .public) leadInBytes=\(bufferedChunks.reduce(0) { $0 + $1.count }, privacy: .public)")
        } catch {
            logger.error("Rolling preload failed to start: \(error.localizedDescription, privacy: .public)")
            session.cancel()
            resetPreloadState(cancelSession: false, keepLeadIn: true)
        }
    }

    private func waitForStartingPreload() async {
        guard state == .starting else { return }

        let timeoutTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: Self.startingPreloadClaimWaitNanoseconds)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.resumeStartingPreloadWaiters()
        }

        await withCheckedContinuation { continuation in
            if state == .starting {
                startingPreloadWaiters.append(continuation)
            } else {
                continuation.resume()
            }
        }
        timeoutTask.cancel()
    }

    private func resumeStartingPreloadWaiters() {
        guard !startingPreloadWaiters.isEmpty else { return }
        let waiters = startingPreloadWaiters
        startingPreloadWaiters.removeAll(keepingCapacity: true)
        for waiter in waiters {
            waiter.resume()
        }
    }

    private func resetPreloadState(cancelSession: Bool, keepLeadIn: Bool) {
        if cancelSession {
            currentSession?.cancel()
        }
        currentSession = nil
        currentCallback = nil
        currentModelName = nil
        currentLanguage = nil
        speechDetectedAt = nil
        preloadStartedAt = nil
        observedChunks = 0
        observedBytes = 0
        preloadedChunks = 0
        preloadedBytes = 0
        activeSilenceBytes = 0
        vadWindowsChecked = 0
        vadWindow.removeAll(keepingCapacity: true)
        if !keepLeadIn {
            leadInBuffer.removeAll()
        }
        if state != .claimed {
            state = .idle
        }
        resumeStartingPreloadWaiters()
    }

    private func invalidateCachedPlan() {
        cachedPlan = nil
        cachedPlanModelName = nil
        cachedPlanLanguage = nil
        cachedPlanExpiresAt = .distantPast
    }

}
