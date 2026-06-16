import Foundation
import Testing
@testable import VoiceInk

private struct TestPreloadModel: TranscriptionModel {
    let id = UUID()
    let name: String
    let displayName: String
    let description = "Streaming preload test model"
    let provider: ModelProvider
    let isMultilingualModel = true
    let supportsStreaming: Bool
    let supportedLanguages: [String: String] = [:]
}

private struct FixedPowerStateProvider: RollingBufferPowerStateProviding {
    let state: RollingBufferPowerState

    func currentPowerState() -> RollingBufferPowerState {
        state
    }
}

private final class CountingPowerStateProvider: RollingBufferPowerStateProviding, @unchecked Sendable {
    private let lock = NSLock()
    private let state: RollingBufferPowerState
    private var callCountValue = 0

    init(state: RollingBufferPowerState) {
        self.state = state
    }

    func currentPowerState() -> RollingBufferPowerState {
        lock.lock()
        callCountValue += 1
        lock.unlock()
        return state
    }

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return callCountValue
    }
}

private struct FakeSpeechDetector: SpeechActivityDetecting {
    let containsSpeech: Bool

    func containsSpeech(inPCM16LEData data: Data) -> Bool {
        containsSpeech
    }
}

private final class LockedDataChunks: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Data] = []

    func append(_ data: Data) {
        lock.lock()
        values.append(data)
        lock.unlock()
    }

    func snapshot() -> [Data] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}

@MainActor
private final class FakeTranscriptionSession: TranscriptionSession {
    let chunks = LockedDataChunks()
    private(set) var preparedModelName: String?
    private(set) var cancelCount = 0

    func prepare(model: any TranscriptionModel) async throws -> ((Data) -> Void)? {
        preparedModelName = model.name
        return { [chunks] data in
            chunks.append(data)
        }
    }

    func transcribe(audioURL: URL) async throws -> String {
        "fake transcript"
    }

    func cancel() {
        cancelCount += 1
    }
}

@MainActor
private final class DelayedFakeTranscriptionSession: TranscriptionSession {
    let chunks = LockedDataChunks()
    private var prepareStartedContinuation: CheckedContinuation<Void, Never>?
    private var prepareContinuation: CheckedContinuation<Void, Never>?
    private var didStartPrepare = false
    private(set) var preparedModelName: String?
    private(set) var cancelCount = 0

    func prepare(model: any TranscriptionModel) async throws -> ((Data) -> Void)? {
        preparedModelName = model.name
        didStartPrepare = true
        prepareStartedContinuation?.resume()
        prepareStartedContinuation = nil

        await withCheckedContinuation { continuation in
            prepareContinuation = continuation
        }

        return { [chunks] data in
            chunks.append(data)
        }
    }

    func waitForPrepareToStart() async {
        guard !didStartPrepare else { return }
        await withCheckedContinuation { continuation in
            prepareStartedContinuation = continuation
        }
    }

    func finishPrepare() {
        prepareContinuation?.resume()
        prepareContinuation = nil
    }

    func transcribe(audioURL: URL) async throws -> String {
        "fake transcript"
    }

    func cancel() {
        cancelCount += 1
    }
}

struct RollingBufferPreloadCoordinatorTests {
    @MainActor
    @Test func startingPreloadClaimWaitStaysUnderQuickReleaseBudget() {
        #expect(RollingBufferPreloadCoordinator.startingPreloadClaimWaitNanoseconds <= 150_000_000)
    }

    @MainActor
    @Test func vadTriggerStartsPreloadAndClaimTransfersLeadIn() async {
        let model = streamingModel()
        let session = FakeTranscriptionSession()

        await withStandardRollingDefaults(for: model) { defaults in
            setPreloadDefaults(defaults, model: model, preRunFinalization: true)
        } run: {
            let coordinator = makeCoordinator(model: model, session: session)
            let speechWindow = Data(repeating: 1, count: 8_000)

            await coordinator.processRollingChunkForTesting(speechWindow)

            let claimed = await coordinator.claimPreloadedSession(for: model)
            #expect(claimed != nil)
            #expect(claimed?.audioData.count == 8_000)
            #expect(session.preparedModelName == model.name)
            #expect(session.chunks.snapshot().map(\.count) == [8_000])

            claimed?.audioChunkHandler(Data(repeating: 2, count: 1_024))
            #expect(session.chunks.snapshot().map(\.count) == [8_000, 1_024])
        }
    }

    @MainActor
    @Test func leadInBufferKeepsLatestBytesWhenSingleChunkExceedsDuration() async {
        let model = streamingModel()
        let session = FakeTranscriptionSession()

        await withStandardRollingDefaults(for: model) { defaults in
            setPreloadDefaults(defaults, model: model, preRunFinalization: true)
            defaults.set(0.25, forKey: RollingBufferPreloadSettings.bufferDurationSecondsKey)
        } run: {
            let coordinator = makeCoordinator(model: model, session: session)
            let chunk = Data(repeating: 1, count: 4_000) + Data(repeating: 2, count: 8_000)

            await coordinator.processRollingChunkForTesting(chunk)

            #expect(session.chunks.snapshot().map(\.count) == [8_000])
            #expect(session.chunks.snapshot().first == Data(repeating: 2, count: 8_000))
        }
    }

    @MainActor
    @Test func preloadFeedsChunksThatArriveDuringSessionPrepareAfterRecordingStart() async {
        let model = streamingModel()
        let session = DelayedFakeTranscriptionSession()

        await withStandardRollingDefaults(for: model) { defaults in
            setPreloadDefaults(defaults, model: model, preRunFinalization: true)
        } run: {
            let coordinator = makeCoordinator(model: model, session: session)
            let triggerChunk = Data(repeating: 1, count: 8_000)
            let prepareWindowChunk = Data(repeating: 2, count: 1_024)

            let triggerTask = Task {
                await coordinator.processRollingChunkForTesting(triggerChunk)
            }

            await session.waitForPrepareToStart()
            coordinator.prepareForRecordingStart()
            await coordinator.processRollingChunkForTesting(prepareWindowChunk)
            session.finishPrepare()
            await triggerTask.value

            let claimed = await coordinator.claimPreloadedSession(for: model)

            #expect(claimed != nil)
            #expect(session.preparedModelName == model.name)
            #expect(session.chunks.snapshot().map(\.count) == [8_000, 1_024])
        }
    }

    @MainActor
    @Test func staleStartingPreloadDoesNotBecomeClaimableAfterLanguageChange() async {
        let model = streamingModel()
        let session = DelayedFakeTranscriptionSession()
        var selectedLanguage = "en"

        await withStandardRollingDefaults(for: model) { defaults in
            setPreloadDefaults(defaults, model: model, preRunFinalization: true)
        } run: {
            let coordinator = makeCoordinator(
                model: model,
                session: session,
                currentLanguageProvider: { selectedLanguage }
            )

            let triggerTask = Task {
                await coordinator.processRollingChunkForTesting(Data(repeating: 1, count: 8_000))
            }

            await session.waitForPrepareToStart()
            selectedLanguage = "de"

            let staleClaim = await coordinator.claimPreloadedSession(for: model)
            session.finishPrepare()
            await triggerTask.value
            let laterClaim = await coordinator.claimPreloadedSession(for: model)

            #expect(staleClaim == nil)
            #expect(laterClaim == nil)
            #expect(session.cancelCount == 1)
        }
    }

    @MainActor
    @Test func activePreloadFeedsChunksThatArriveBeforeRecordingSessionClaim() async {
        let model = streamingModel()
        let session = FakeTranscriptionSession()

        await withStandardRollingDefaults(for: model) { defaults in
            setPreloadDefaults(defaults, model: model, preRunFinalization: true)
        } run: {
            let coordinator = makeCoordinator(model: model, session: session)
            let triggerChunk = Data(repeating: 1, count: 8_000)
            let recordingStartChunk = Data(repeating: 2, count: 1_024)

            await coordinator.processRollingChunkForTesting(triggerChunk)
            coordinator.prepareForRecordingStart()
            await coordinator.processRollingChunkForTesting(recordingStartChunk)

            let claimed = await coordinator.claimPreloadedSession(for: model)

            #expect(claimed != nil)
            #expect(session.preparedModelName == model.name)
            #expect(session.chunks.snapshot().map(\.count) == [8_000, 1_024])
        }
    }

    @MainActor
    @Test func claimCancelsPreloadStartedForPreviousLanguage() async {
        let model = streamingModel()
        let session = FakeTranscriptionSession()
        var selectedLanguage = "en"

        await withStandardRollingDefaults(for: model) { defaults in
            setPreloadDefaults(defaults, model: model, preRunFinalization: true)
        } run: {
            let coordinator = makeCoordinator(
                model: model,
                session: session,
                currentLanguageProvider: { selectedLanguage }
            )

            await coordinator.processRollingChunkForTesting(Data(repeating: 1, count: 8_000))
            selectedLanguage = "de"

            let claimed = await coordinator.claimPreloadedSession(for: model)

            #expect(claimed == nil)
            #expect(session.cancelCount == 1)
        }
    }

    @MainActor
    @Test func fallbackCancelStopsUnclaimedPreload() async {
        let model = streamingModel()
        let session = FakeTranscriptionSession()

        await withStandardRollingDefaults(for: model) { defaults in
            setPreloadDefaults(defaults, model: model, preRunFinalization: true)
        } run: {
            let coordinator = makeCoordinator(model: model, session: session)

            await coordinator.processRollingChunkForTesting(Data(repeating: 1, count: 8_000))
            #expect(session.chunks.snapshot().count == 1)

            coordinator.cancelUnclaimedPreload(reason: "test-fallback")

            #expect(session.cancelCount == 1)
            let claimed = await coordinator.claimPreloadedSession(for: model)
            #expect(claimed == nil)
        }
    }

    @MainActor
    @Test func preRunFinalizationOffPreventsPreRunSessionWork() async {
        let model = streamingModel()
        let session = FakeTranscriptionSession()

        await withStandardRollingDefaults(for: model) { defaults in
            setPreloadDefaults(defaults, model: model, preRunFinalization: false)
        } run: {
            let coordinator = makeCoordinator(model: model, session: session)

            await coordinator.processRollingChunkForTesting(Data(repeating: 1, count: 8_000))

            #expect(session.preparedModelName == nil)
            #expect(session.chunks.snapshot().isEmpty)
            let claimed = await coordinator.claimPreloadedSession(for: model)
            #expect(claimed == nil)
        }
    }

    @MainActor
    @Test func settingsChangeRefreshesCachedFinalizationPolicy() async {
        let model = streamingModel()
        let session = FakeTranscriptionSession()

        await withStandardRollingDefaults(for: model) { defaults in
            setPreloadDefaults(defaults, model: model, preRunFinalization: true)
        } run: {
            let coordinator = makeCoordinator(model: model, session: session)

            UserDefaults.standard.set(false, forKey: RollingBufferPreloadSettings.preRunFinalizationKey)
            coordinator.settingsDidChange()

            await coordinator.processRollingChunkForTesting(Data(repeating: 1, count: 8_000))

            #expect(session.preparedModelName == nil)
            #expect(session.chunks.snapshot().isEmpty)
            let claimed = await coordinator.claimPreloadedSession(for: model)
            #expect(claimed == nil)
        }
    }

    @MainActor
    @Test func policyPlanIsNotEvaluatedBeforeVadWindowFills() async {
        let model = streamingModel()
        let session = FakeTranscriptionSession()
        let powerStateProvider = CountingPowerStateProvider(
            state: RollingBufferPowerState(isOnBattery: false, batteryLevelPercent: nil)
        )

        await withStandardRollingDefaults(for: model) { defaults in
            setPreloadDefaults(defaults, model: model, preRunFinalization: true)
            defaults.set(RollingBufferPreloadMode.auto.rawValue, forKey: RollingBufferPreloadSettings.modeKey)
        } run: {
            let coordinator = makeCoordinator(
                model: model,
                session: session,
                powerStateProvider: powerStateProvider,
                detector: FakeSpeechDetector(containsSpeech: true)
            )

            await coordinator.processRollingChunkForTesting(Data(repeating: 1, count: 1_024))
            await coordinator.processRollingChunkForTesting(Data(repeating: 1, count: 1_024))

            #expect(powerStateProvider.callCount == 0)
            #expect(session.chunks.snapshot().isEmpty)
        }
    }

    @MainActor
    @Test func autoCloudOptOutBlocksPreloadBeforeDetectorWork() async {
        let model = streamingModel(provider: .deepgram)
        let session = FakeTranscriptionSession()
        let detectorLoadCount = LockedCounter()

        await withStandardRollingDefaults(for: model) { defaults in
            setPreloadDefaults(defaults, model: model, preRunFinalization: true)
            defaults.set(RollingBufferPreloadMode.auto.rawValue, forKey: RollingBufferPreloadSettings.modeKey)
            defaults.set(true, forKey: RollingBufferPreloadSettings.autoDisableCloudModelsKey)
        } run: {
            let coordinator = makeCoordinator(
                model: model,
                session: session,
                detectorProvider: {
                    detectorLoadCount.increment()
                    return FakeSpeechDetector(containsSpeech: true)
                }
            )

            await coordinator.processRollingChunkForTesting(Data(repeating: 1, count: 8_000))

            #expect(detectorLoadCount.value == 0)
            #expect(session.preparedModelName == nil)
            #expect(session.chunks.snapshot().isEmpty)
        }
    }

    @MainActor
    @Test func powerStateIsNotPolledForNonSpeechVadWindows() async {
        let model = streamingModel()
        let session = FakeTranscriptionSession()
        let powerStateProvider = CountingPowerStateProvider(
            state: RollingBufferPowerState(isOnBattery: false, batteryLevelPercent: nil)
        )

        await withStandardRollingDefaults(for: model) { defaults in
            setPreloadDefaults(defaults, model: model, preRunFinalization: true)
            defaults.set(RollingBufferPreloadMode.auto.rawValue, forKey: RollingBufferPreloadSettings.modeKey)
        } run: {
            let coordinator = makeCoordinator(
                model: model,
                session: session,
                powerStateProvider: powerStateProvider,
                detector: FakeSpeechDetector(containsSpeech: false)
            )

            await coordinator.processRollingChunkForTesting(Data(repeating: 1, count: 8_000))
            await coordinator.processRollingChunkForTesting(Data(repeating: 1, count: 8_000))

            #expect(powerStateProvider.callCount == 0)
            #expect(session.chunks.snapshot().isEmpty)
        }
    }

    @MainActor
    @Test func lowBatteryAutoPolicyIsEvaluatedAfterSpeechDetection() async {
        let model = streamingModel()
        let session = FakeTranscriptionSession()
        let powerStateProvider = CountingPowerStateProvider(
            state: RollingBufferPowerState(isOnBattery: true, batteryLevelPercent: 10)
        )

        await withStandardRollingDefaults(for: model) { defaults in
            setPreloadDefaults(defaults, model: model, preRunFinalization: true)
            defaults.set(RollingBufferPreloadMode.auto.rawValue, forKey: RollingBufferPreloadSettings.modeKey)
            defaults.set(true, forKey: RollingBufferPreloadSettings.autoDisableLowBatteryLocalModelsKey)
            defaults.set(40, forKey: RollingBufferPreloadSettings.lowBatteryThresholdPercentKey)
        } run: {
            let coordinator = makeCoordinator(
                model: model,
                session: session,
                powerStateProvider: powerStateProvider,
                detector: FakeSpeechDetector(containsSpeech: true)
            )

            await coordinator.processRollingChunkForTesting(Data(repeating: 1, count: 8_000))

            #expect(powerStateProvider.callCount == 1)
            #expect(session.chunks.snapshot().isEmpty)
        }
    }

    @MainActor
    @Test func manualOnDoesNotPollPowerState() async {
        let model = streamingModel()
        let session = FakeTranscriptionSession()
        let powerStateProvider = CountingPowerStateProvider(
            state: RollingBufferPowerState(isOnBattery: true, batteryLevelPercent: 1)
        )

        await withStandardRollingDefaults(for: model) { defaults in
            setPreloadDefaults(defaults, model: model, preRunFinalization: true)
        } run: {
            let coordinator = makeCoordinator(
                model: model,
                session: session,
                powerStateProvider: powerStateProvider,
                detector: FakeSpeechDetector(containsSpeech: false)
            )

            await coordinator.processRollingChunkForTesting(Data(repeating: 1, count: 8_000))

            #expect(powerStateProvider.callCount == 0)
            #expect(session.chunks.snapshot().isEmpty)
        }
    }

    @MainActor
    private func makeCoordinator(
        model: TestPreloadModel,
        session: FakeTranscriptionSession,
        currentLanguageProvider: @escaping RollingBufferPreloadCoordinator.CurrentLanguageProvider = { "en" },
        powerStateProvider: any RollingBufferPowerStateProviding = FixedPowerStateProvider(
            state: RollingBufferPowerState(isOnBattery: false, batteryLevelPercent: nil)
        ),
        detector: any SpeechActivityDetecting = FakeSpeechDetector(containsSpeech: true),
        detectorProvider: RollingBufferPreloadCoordinator.DetectorProvider? = nil
    ) -> RollingBufferPreloadCoordinator {
        RollingBufferPreloadCoordinator(
            currentModelProvider: { model },
            currentLanguageProvider: currentLanguageProvider,
            powerStateProvider: powerStateProvider,
            detectorProvider: detectorProvider ?? { detector },
            sessionFactory: { _, _ in session }
        )
    }

    private func streamingModel(provider: ModelProvider = .fluidAudio) -> TestPreloadModel {
        TestPreloadModel(
            name: "test-preload-\(UUID().uuidString)",
            displayName: "Test Preload",
            provider: provider,
            supportsStreaming: true
        )
    }

    @MainActor
    private func makeCoordinator(
        model: TestPreloadModel,
        session: DelayedFakeTranscriptionSession,
        currentLanguageProvider: @escaping RollingBufferPreloadCoordinator.CurrentLanguageProvider = { "en" },
        powerStateProvider: any RollingBufferPowerStateProviding = FixedPowerStateProvider(
            state: RollingBufferPowerState(isOnBattery: false, batteryLevelPercent: nil)
        ),
        detector: any SpeechActivityDetecting = FakeSpeechDetector(containsSpeech: true)
    ) -> RollingBufferPreloadCoordinator {
        RollingBufferPreloadCoordinator(
            currentModelProvider: { model },
            currentLanguageProvider: currentLanguageProvider,
            powerStateProvider: powerStateProvider,
            detectorProvider: { detector },
            sessionFactory: { _, _ in session }
        )
    }

    private func setPreloadDefaults(
        _ defaults: UserDefaults,
        model: TestPreloadModel,
        preRunFinalization: Bool
    ) {
        defaults.set(RollingBufferPreloadMode.on.rawValue, forKey: RollingBufferPreloadSettings.modeKey)
        defaults.set(3.0, forKey: RollingBufferPreloadSettings.bufferDurationSecondsKey)
        defaults.set(preRunFinalization, forKey: RollingBufferPreloadSettings.preRunFinalizationKey)
        defaults.set(true, forKey: RollingBufferPreloadSettings.perModelPreloadEnabledKey(forModelName: model.name))
    }

    private func withStandardRollingDefaults(
        for model: TestPreloadModel,
        configure: (UserDefaults) -> Void,
        run: () async -> Void
    ) async {
        let defaults = UserDefaults.standard
        let keys = [
            RollingBufferPreloadSettings.modeKey,
            RollingBufferPreloadSettings.autoDisableCloudModelsKey,
            RollingBufferPreloadSettings.autoDisableLowBatteryLocalModelsKey,
            RollingBufferPreloadSettings.lowBatteryThresholdPercentKey,
            RollingBufferPreloadSettings.bufferDurationSecondsKey,
            RollingBufferPreloadSettings.preRunFinalizationKey,
            RollingBufferPreloadSettings.perModelPreloadEnabledKey(forModelName: model.name)
        ]
        let savedValues: [(String, Any?)] = keys.map { key in
            (key, defaults.object(forKey: key))
        }

        for key in keys {
            defaults.removeObject(forKey: key)
        }
        configure(defaults)

        defer {
            for (key, value) in savedValues {
                if let value {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }

        await run()
    }
}
