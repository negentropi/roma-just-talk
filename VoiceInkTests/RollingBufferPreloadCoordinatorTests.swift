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

struct RollingBufferPreloadCoordinatorTests {
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

            let claimed = coordinator.claimPreloadedSession(for: model)
            #expect(claimed != nil)
            #expect(session.preparedModelName == model.name)
            #expect(session.chunks.snapshot().map(\.count) == [8_000])

            claimed?.audioChunkHandler(Data(repeating: 2, count: 1_024))
            #expect(session.chunks.snapshot().map(\.count) == [8_000, 1_024])
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
            #expect(coordinator.claimPreloadedSession(for: model) == nil)
        }
    }

    @MainActor
    @Test func preRunFinalizationOffPreventsClaimingWarmSession() async {
        let model = streamingModel()
        let session = FakeTranscriptionSession()

        await withStandardRollingDefaults(for: model) { defaults in
            setPreloadDefaults(defaults, model: model, preRunFinalization: false)
        } run: {
            let coordinator = makeCoordinator(model: model, session: session)

            await coordinator.processRollingChunkForTesting(Data(repeating: 1, count: 8_000))

            #expect(session.chunks.snapshot().count == 1)
            #expect(coordinator.claimPreloadedSession(for: model) == nil)

            coordinator.cancelUnclaimedPreload(reason: "test-finalization-off")
            #expect(session.cancelCount == 1)
        }
    }

    @MainActor
    private func makeCoordinator(
        model: TestPreloadModel,
        session: FakeTranscriptionSession,
        detector: any SpeechActivityDetecting = FakeSpeechDetector(containsSpeech: true)
    ) -> RollingBufferPreloadCoordinator {
        RollingBufferPreloadCoordinator(
            currentModelProvider: { model },
            powerStateProvider: FixedPowerStateProvider(
                state: RollingBufferPowerState(isOnBattery: false, batteryLevelPercent: nil)
            ),
            detectorProvider: { detector },
            sessionFactory: { _, _ in session }
        )
    }

    private func streamingModel() -> TestPreloadModel {
        TestPreloadModel(
            name: "test-preload-\(UUID().uuidString)",
            displayName: "Test Preload",
            provider: .fluidAudio,
            supportsStreaming: true
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
        defaults.set(true, forKey: "rolling-buffer-preload-enabled-\(model.name)")
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
            "rolling-buffer-preload-enabled-\(model.name)"
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
