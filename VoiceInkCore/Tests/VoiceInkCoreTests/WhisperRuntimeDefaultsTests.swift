import Foundation
@testable import VoiceInkCore

final class WhisperRuntimeDefaultsTests: XCTestCase {
    func testThreadCountKeepsExistingBounds() {
        XCTAssertEqual(VoiceInkWhisperRuntimeDefaults.threadCount(processorCount: 1), 1)
        XCTAssertEqual(VoiceInkWhisperRuntimeDefaults.threadCount(processorCount: 4), 2)
        XCTAssertEqual(VoiceInkWhisperRuntimeDefaults.threadCount(processorCount: 12), 8)
    }

    func testRuntimeConstantsMatchExistingWhisperWrappers() {
        XCTAssertTrue(VoiceInkWhisperRuntimeDefaults.printRealtime)
        XCTAssertFalse(VoiceInkWhisperRuntimeDefaults.printProgress)
        XCTAssertTrue(VoiceInkWhisperRuntimeDefaults.printTimestamps)
        XCTAssertFalse(VoiceInkWhisperRuntimeDefaults.printSpecial)
        XCTAssertFalse(VoiceInkWhisperRuntimeDefaults.translate)
        XCTAssertEqual(VoiceInkWhisperRuntimeDefaults.offsetMilliseconds, 0)
        XCTAssertTrue(VoiceInkWhisperRuntimeDefaults.noContext)
        XCTAssertFalse(VoiceInkWhisperRuntimeDefaults.singleSegment)
        XCTAssertEqual(VoiceInkWhisperRuntimeDefaults.transcriptionTemperature, 0.2)
        XCTAssertEqual(VoiceInkWhisperRuntimeDefaults.audioLevelingTargetPeak, 12_000)
        XCTAssertEqual(VoiceInkWhisperRuntimeDefaults.audioLevelingNoiseFloorPeak, 32)
        XCTAssertEqual(VoiceInkWhisperRuntimeDefaults.audioLevelingMaxGain, 16)
        XCTAssertEqual(VoiceInkWhisperRuntimeDefaults.vadThreshold, 0.50)
        XCTAssertEqual(VoiceInkWhisperRuntimeDefaults.vadMinSpeechDurationMs, 250)
        XCTAssertEqual(VoiceInkWhisperRuntimeDefaults.vadMinSilenceDurationMs, 100)
        XCTAssertEqual(VoiceInkWhisperRuntimeDefaults.vadSpeechPadMs, 30)
        XCTAssertEqual(VoiceInkWhisperRuntimeDefaults.vadSamplesOverlap, 0.1)
    }

    func testRuntimeDiagnosticsPreserveExistingWhisperWrapperLogText() {
        XCTAssertEqual(VoiceInkWhisperRuntimeDiagnostics.logCategory, "WhisperContext")
        XCTAssertEqual(VoiceInkWhisperRuntimeDiagnostics.simulatorCPUModeMessage, "Running on the simulator, using CPU")
        XCTAssertEqual(VoiceInkWhisperRuntimeDiagnostics.metalFlashAttentionMessage, "Flash attention enabled for Metal")
        XCTAssertEqual(VoiceInkWhisperRuntimeDiagnostics.vadBundleModelLoadedMessage, "VAD model loaded from bundle resources")
    }

    func testContextRuntimePlanPreservesSimulatorAndDeviceInitializationPolicy() {
        XCTAssertEqual(
            VoiceInkWhisperContextRuntimePlan.current(environment: .simulator),
            VoiceInkWhisperContextRuntimePlan(
                useGPU: false,
                flashAttention: nil,
                diagnosticMessage: VoiceInkWhisperRuntimeDiagnostics.simulatorCPUModeMessage
            )
        )
        XCTAssertEqual(
            VoiceInkWhisperContextRuntimePlan.current(environment: .device),
            VoiceInkWhisperContextRuntimePlan(
                useGPU: nil,
                flashAttention: true,
                diagnosticMessage: VoiceInkWhisperRuntimeDiagnostics.metalFlashAttentionMessage
            )
        )
    }

    func testVADRuntimeConfigurationRequiresEnabledPreferenceAndModelPath() {
        XCTAssertEqual(
            VoiceInkWhisperVADRuntimeConfiguration.current(modelPath: "/tmp/vad.bin", isEnabled: true),
            VoiceInkWhisperVADRuntimeConfiguration(modelPath: "/tmp/vad.bin")
        )
        XCTAssertNil(VoiceInkWhisperVADRuntimeConfiguration.current(modelPath: "/tmp/vad.bin", isEnabled: false))
        XCTAssertNil(VoiceInkWhisperVADRuntimeConfiguration.current(modelPath: nil, isEnabled: true))
        XCTAssertNil(VoiceInkWhisperVADRuntimeConfiguration.current(modelPath: "", isEnabled: true))
    }

    func testRuntimeOptionsPreserveExistingWhisperCppFlags() {
        XCTAssertEqual(
            VoiceInkWhisperRuntimeOptions(),
            VoiceInkWhisperRuntimeOptions(
                printRealtime: true,
                printProgress: false,
                printTimestamps: true,
                printSpecial: false,
                translate: false,
                offsetMilliseconds: 0,
                noContext: true,
                singleSegment: false
            )
        )
    }

    func testRuntimeConfigurationBuildsSharedWhisperInputs() {
        withTemporaryDefaults { defaults in
            VoiceInkVADPreference.saveIsEnabled(true, to: defaults)

            let configuration = VoiceInkWhisperRuntimeConfiguration.current(
                language: "ja",
                prompt: "Use Japanese punctuation.",
                vadModelPath: "/tmp/vad.bin",
                defaults: defaults,
                processorCount: 6
            )

            XCTAssertEqual(configuration.language, "ja")
            XCTAssertEqual(configuration.prompt, "Use Japanese punctuation.")
            XCTAssertEqual(configuration.options, VoiceInkWhisperRuntimeOptions())
            XCTAssertEqual(configuration.threadCount, 4)
            XCTAssertEqual(configuration.temperature, VoiceInkWhisperRuntimeDefaults.transcriptionTemperature)
            XCTAssertEqual(configuration.vad?.modelPath, "/tmp/vad.bin")
            XCTAssertEqual(configuration.vad?.threshold, VoiceInkWhisperRuntimeDefaults.vadThreshold)
            XCTAssertEqual(configuration.vad?.minSpeechDurationMs, VoiceInkWhisperRuntimeDefaults.vadMinSpeechDurationMs)
            XCTAssertEqual(configuration.vad?.minSilenceDurationMs, VoiceInkWhisperRuntimeDefaults.vadMinSilenceDurationMs)
            XCTAssertEqual(configuration.vad?.maxSpeechDurationSeconds, VoiceInkWhisperRuntimeDefaults.vadMaxSpeechDurationSeconds)
            XCTAssertEqual(configuration.vad?.speechPadMs, VoiceInkWhisperRuntimeDefaults.vadSpeechPadMs)
            XCTAssertEqual(configuration.vad?.samplesOverlap, VoiceInkWhisperRuntimeDefaults.vadSamplesOverlap)
        }
    }

    func testRuntimeConfigurationNormalizesWhisperRequestLanguage() {
        XCTAssertEqual(
            VoiceInkWhisperRuntimeConfiguration.current(language: " fr ").language,
            "fr"
        )
        XCTAssertNil(VoiceInkWhisperRuntimeConfiguration.current(language: "auto").language)
        XCTAssertNil(VoiceInkWhisperRuntimeConfiguration.current(language: "  ").language)
        XCTAssertNil(VoiceInkWhisperRuntimeConfiguration.current(language: nil).language)
    }

    func testRuntimeConfigurationDisablesVADWhenPreferenceIsOff() {
        withTemporaryDefaults { defaults in
            VoiceInkVADPreference.saveIsEnabled(false, to: defaults)

            let configuration = VoiceInkWhisperRuntimeConfiguration.current(
                vadModelPath: "/tmp/vad.bin",
                defaults: defaults
            )

            XCTAssertNil(configuration.vad)
        }
    }

    func testRuntimeInvocationPlanKeepsWhisperCStringInputsAlive() {
        let plan = VoiceInkWhisperRuntimeInvocationPlan(
            configuration: VoiceInkWhisperRuntimeConfiguration(
                language: "ja",
                prompt: "Use Japanese punctuation.",
                vad: VoiceInkWhisperVADRuntimeConfiguration(modelPath: "/tmp/vad.bin")
            )
        )

        let strings = plan.withUnsafeCStringPointers { languagePointer, promptPointer, vadModelPathPointer in
            [
                languagePointer.map { String(cString: $0) },
                promptPointer.map { String(cString: $0) },
                vadModelPathPointer.map { String(cString: $0) }
            ]
        }

        let expectedStrings: [String?] = ["ja", "Use Japanese punctuation.", "/tmp/vad.bin"]
        XCTAssertEqual(strings, expectedStrings)
    }

    func testRuntimeInvocationPlanOmitsDisabledWhisperInputs() {
        let plan = VoiceInkWhisperRuntimeInvocationPlan(
            configuration: VoiceInkWhisperRuntimeConfiguration(
                language: nil,
                prompt: nil,
                vad: nil
            )
        )

        let hasPointers = plan.withUnsafeCStringPointers { languagePointer, promptPointer, vadModelPathPointer in
            [
                languagePointer != nil,
                promptPointer != nil,
                vadModelPathPointer != nil
            ]
        }

        XCTAssertEqual(hasPointers, [false, false, false])
    }

    func testLocalWhisperFailurePolicyPreservesMacOSMapping() {
        XCTAssertEqual(
            errorName(VoiceInkLocalWhisperFailurePolicy.error(for: .modelUnavailable, platform: .macOS)),
            "modelLoadFailed"
        )
        XCTAssertEqual(
            errorName(VoiceInkLocalWhisperFailurePolicy.error(for: .modelLoadFailed, platform: .macOS)),
            "modelLoadFailed"
        )
        XCTAssertEqual(
            errorName(VoiceInkLocalWhisperFailurePolicy.error(for: .audioProcessingFailed, platform: .macOS)),
            "audioProcessingFailed"
        )
        XCTAssertEqual(
            errorName(VoiceInkLocalWhisperFailurePolicy.error(for: .transcriptionFailed, platform: .macOS)),
            "whisperCoreFailed"
        )
    }

    func testLocalWhisperFailurePolicyPreservesIOSMapping() {
        XCTAssertEqual(
            errorName(VoiceInkLocalWhisperFailurePolicy.error(for: .modelUnavailable, platform: .iOS)),
            "localModelUnavailable"
        )
        XCTAssertEqual(
            errorName(VoiceInkLocalWhisperFailurePolicy.error(for: .modelLoadFailed, platform: .iOS)),
            "localModelLoadFailed"
        )
        XCTAssertEqual(
            errorName(VoiceInkLocalWhisperFailurePolicy.error(for: .audioProcessingFailed, platform: .iOS)),
            "audioProcessingFailed"
        )
        XCTAssertEqual(
            errorName(VoiceInkLocalWhisperFailurePolicy.error(for: .transcriptionFailed, platform: .iOS)),
            "whisperTranscriptionFailed"
        )
    }

    private func withTemporaryDefaults(_ test: (UserDefaults) -> Void) {
        let suiteName = "VoiceInkCore.WhisperRuntimeDefaultsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        test(defaults)
    }

    private func errorName(_ error: VoiceInkEngineError) -> String {
        String(describing: error)
    }
}
