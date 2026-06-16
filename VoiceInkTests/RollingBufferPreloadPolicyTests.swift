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

    @Test func runtimeDiagnosticsKeepLatestQuickReleaseClaim() {
        let diagnostics = RollingBufferPreloadRuntimeDiagnostics()

        #expect(diagnostics.currentQuickReleaseClaim().displaySummary == "None")

        diagnostics.recordQuickReleaseClaim(
            strategy: .bufferedAudioSnapshot,
            reason: "test",
            audioBytes: 1_024,
            elapsedSeconds: 0.012,
            at: Date(timeIntervalSince1970: 0)
        )
        diagnostics.recordQuickReleaseTiming(
            stage: .transcriptionReady,
            elapsedSeconds: 0.111,
            at: Date(timeIntervalSince1970: 1)
        )
        diagnostics.recordQuickReleaseTiming(
            stage: .pasteCompleted,
            elapsedSeconds: 0.222,
            at: Date(timeIntervalSince1970: 2)
        )
        diagnostics.recordQuickReleaseTiming(
            stage: .pipelineReturned,
            elapsedSeconds: 0.333,
            at: Date(timeIntervalSince1970: 3)
        )
        diagnostics.recordQuickReleaseTiming(
            stage: .idle,
            elapsedSeconds: 0.444,
            at: Date(timeIntervalSince1970: 4)
        )
        diagnostics.recordQuickReleaseTiming(
            stage: .sessionFinished,
            elapsedSeconds: 0.555,
            at: Date(timeIntervalSince1970: 5)
        )

        let claim = diagnostics.currentQuickReleaseClaim()
        #expect(claim.strategy == .bufferedAudioSnapshot)
        #expect(claim.reason == "test")
        #expect(claim.audioBytes == 1_024)
        #expect(claim.claimElapsedSeconds == 0.012)
        #expect(claim.transcriptionReadySeconds == 0.111)
        #expect(claim.pasteCompletedSeconds == 0.222)
        #expect(claim.pipelineReturnedSeconds == 0.333)
        #expect(claim.idleSeconds == 0.444)
        #expect(claim.sessionFinishedSeconds == 0.555)
        #expect(claim.displaySummary.contains("Buffered Audio Snapshot"))
        #expect(claim.displaySummary.contains("test"))
        #expect(claim.displaySummary.contains("paste 0.222s"))
        #expect(claim.displaySummary.contains("idle 0.444s"))
        #expect(claim.exportSummary.contains("transcription=0.111s"))
        #expect(claim.exportSummary.contains("returned=0.333s"))
        #expect(claim.exportSummary.contains("idle=0.444s"))
        #expect(claim.exportSummary.contains("session-finished=0.555s"))
        #expect(claim.exportSummary.contains(claim.displaySummary))
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
