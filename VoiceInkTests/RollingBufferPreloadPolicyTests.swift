import Foundation
import Testing
@testable import VoiceInk

private struct TestTranscriptionModel: TranscriptionModel {
    let id = UUID()
    let name: String
    let displayName: String
    let description: String
    let provider: ModelProvider
    let isMultilingualModel = true
    let supportsStreaming: Bool
    let supportedLanguages: [String: String] = [:]
}

struct RollingBufferPreloadPolicyTests {
    @Test func defaultsUseAutoWithCloudRuleOffAndLowBatteryRuleOnAtFortyPercent() {
        let defaults = temporaryDefaults()
        defer { removeTemporaryDefaults(defaults) }

        let configuration = RollingBufferPreloadSettings.configuration(in: defaults)

        #expect(configuration.mode == .auto)
        #expect(configuration.autoDisablesCloudModels == false)
        #expect(configuration.autoDisablesLowBatteryLocalModels == true)
        #expect(configuration.lowBatteryThresholdPercent == 40)
        #expect(configuration.bufferDurationSeconds == 3.0)
        #expect(configuration.preRunFinalization)
    }

    @Test func autoAllowsLocalPreloadExceptBelowBatteryThreshold() {
        let defaults = temporaryDefaults()
        defer { removeTemporaryDefaults(defaults) }
        let model = streamingModel(provider: .fluidAudio)

        defaults.set(RollingBufferPreloadMode.auto.rawValue, forKey: RollingBufferPreloadSettings.modeKey)
        defaults.set(true, forKey: RollingBufferPreloadSettings.autoDisableLowBatteryLocalModelsKey)
        defaults.set(40, forKey: RollingBufferPreloadSettings.lowBatteryThresholdPercentKey)

        #expect(!RollingBufferPreloadPolicy(defaults: defaults, powerState: .init(isOnBattery: true, batteryLevelPercent: 39))
            .allowsPreload(for: model, perModelEnabled: true))
        #expect(RollingBufferPreloadPolicy(defaults: defaults, powerState: .init(isOnBattery: true, batteryLevelPercent: 40))
            .allowsPreload(for: model, perModelEnabled: true))
        #expect(RollingBufferPreloadPolicy(defaults: defaults, powerState: .init(isOnBattery: false, batteryLevelPercent: 10))
            .allowsPreload(for: model, perModelEnabled: true))
    }

    @Test func autoCloudRuleIsOptIn() {
        let defaults = temporaryDefaults()
        defer { removeTemporaryDefaults(defaults) }
        let model = streamingModel(provider: .deepgram)

        defaults.set(RollingBufferPreloadMode.auto.rawValue, forKey: RollingBufferPreloadSettings.modeKey)
        defaults.set(false, forKey: RollingBufferPreloadSettings.autoDisableCloudModelsKey)

        #expect(RollingBufferPreloadPolicy(defaults: defaults, powerState: .init(isOnBattery: true, batteryLevelPercent: 20))
            .allowsPreload(for: model, perModelEnabled: true))

        defaults.set(true, forKey: RollingBufferPreloadSettings.autoDisableCloudModelsKey)

        #expect(!RollingBufferPreloadPolicy(defaults: defaults, powerState: .init(isOnBattery: false, batteryLevelPercent: nil))
            .allowsPreload(for: model, perModelEnabled: true))
    }

    @Test func manualModesStillHonorPerModelOptOutAndStreamingCapability() {
        let defaults = temporaryDefaults()
        defer { removeTemporaryDefaults(defaults) }
        let streaming = streamingModel(provider: .fluidAudio)
        let batchOnly = TestTranscriptionModel(
            name: "batch-only",
            displayName: "Batch Only",
            description: "No streaming",
            provider: .whisper,
            supportsStreaming: false
        )

        defaults.set(RollingBufferPreloadMode.on.rawValue, forKey: RollingBufferPreloadSettings.modeKey)

        let policy = RollingBufferPreloadPolicy(defaults: defaults, powerState: .init(isOnBattery: true, batteryLevelPercent: 1))
        #expect(policy.allowsPreload(for: streaming, perModelEnabled: true))
        #expect(!policy.allowsPreload(for: streaming, perModelEnabled: false))
        #expect(!policy.allowsPreload(for: batchOnly, perModelEnabled: true))

        defaults.set(RollingBufferPreloadMode.off.rawValue, forKey: RollingBufferPreloadSettings.modeKey)
        #expect(!RollingBufferPreloadPolicy(defaults: defaults, powerState: .init(isOnBattery: false, batteryLevelPercent: nil))
            .allowsPreload(for: streaming, perModelEnabled: true))
    }

    @Test func bufferDurationIsClampedButAllowsDecimalSeconds() {
        let defaults = temporaryDefaults()
        defer { removeTemporaryDefaults(defaults) }

        defaults.set(4.25, forKey: RollingBufferPreloadSettings.bufferDurationSecondsKey)
        #expect(RollingBufferPreloadSettings.configuration(in: defaults).bufferDurationSeconds == 4.25)

        defaults.set(0.1, forKey: RollingBufferPreloadSettings.bufferDurationSecondsKey)
        #expect(RollingBufferPreloadSettings.configuration(in: defaults).bufferDurationSeconds == 0.25)

        defaults.set(90.0, forKey: RollingBufferPreloadSettings.bufferDurationSecondsKey)
        #expect(RollingBufferPreloadSettings.configuration(in: defaults).bufferDurationSeconds == 30.0)
    }

    @Test func batchVadToggleDoesNotDisableRollingPreloadPolicy() {
        let defaults = temporaryDefaults()
        defer { removeTemporaryDefaults(defaults) }
        let model = streamingModel(provider: .fluidAudio)

        defaults.set(false, forKey: "IsVADEnabled")
        defaults.set(RollingBufferVADSettings.sileroModelName, forKey: RollingBufferVADSettings.modelKey)
        defaults.set(RollingBufferPreloadMode.on.rawValue, forKey: RollingBufferPreloadSettings.modeKey)

        #expect(RollingBufferVADSettings.usesSilero(in: defaults))
        #expect(RollingBufferPreloadPolicy(defaults: defaults, powerState: .init(isOnBattery: false, batteryLevelPercent: nil))
            .allowsPreload(for: model, perModelEnabled: true))
    }

    private func temporaryDefaults() -> UserDefaults {
        let suiteName = "VoiceInkTests.RollingBufferPreloadPolicy.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(suiteName, forKey: "_temporaryDefaultsSuiteName")
        return defaults
    }

    private func removeTemporaryDefaults(_ defaults: UserDefaults) {
        guard let suiteName = defaults.string(forKey: "_temporaryDefaultsSuiteName") else { return }
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func streamingModel(provider: ModelProvider) -> TestTranscriptionModel {
        TestTranscriptionModel(
            name: "\(provider.rawValue)-streaming",
            displayName: "\(provider.rawValue) Streaming",
            description: "Streaming test model",
            provider: provider,
            supportsStreaming: true
        )
    }
}
