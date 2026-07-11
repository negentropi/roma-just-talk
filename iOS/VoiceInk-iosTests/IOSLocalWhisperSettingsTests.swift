import Foundation
import XCTest
import VoiceInkCore

final class IOSLocalWhisperSettingsTests: XCTestCase {
    func testVADPreferenceControlsIOSWhisperRuntimeParameters() throws {
        let suiteName = "IOSLocalWhisperSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        VoiceInkVADPreference.saveIsEnabled(false, to: defaults)
        let disabled = VoiceInkWhisperRuntimeConfiguration.current(
            vadModelPath: "/bundle/ggml-silero.bin",
            defaults: defaults,
            processorCount: 8
        )
        var disabledParameters = WhisperParametersHarness()
        disabled.apply(
            to: &disabledParameters,
            makeVADParameters: WhisperVADParametersHarness.init
        )

        XCTAssertNil(disabled.vad)
        XCTAssertFalse(disabledParameters.vad)

        VoiceInkVADPreference.saveIsEnabled(true, to: defaults)
        let enabled = VoiceInkWhisperRuntimeConfiguration.current(
            vadModelPath: "/bundle/ggml-silero.bin",
            defaults: defaults,
            processorCount: 8
        )
        var enabledParameters = WhisperParametersHarness()
        enabled.apply(
            to: &enabledParameters,
            makeVADParameters: WhisperVADParametersHarness.init
        )

        XCTAssertEqual(enabled.vad?.modelPath, "/bundle/ggml-silero.bin")
        XCTAssertTrue(enabledParameters.vad)
        XCTAssertEqual(
            enabledParameters.vad_params.threshold,
            VoiceInkWhisperRuntimeDefaults.vadThreshold
        )
        XCTAssertEqual(
            enabledParameters.vad_params.min_speech_duration_ms,
            VoiceInkWhisperRuntimeDefaults.vadMinSpeechDurationMs
        )
        XCTAssertEqual(
            enabledParameters.vad_params.min_silence_duration_ms,
            VoiceInkWhisperRuntimeDefaults.vadMinSilenceDurationMs
        )
    }

    func testEnabledVADRequiresBundledModelPath() throws {
        let suiteName = "IOSLocalWhisperSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        VoiceInkVADPreference.saveIsEnabled(true, to: defaults)

        XCTAssertNil(VoiceInkWhisperRuntimeConfiguration.current(
            vadModelPath: nil,
            defaults: defaults
        ).vad)
        XCTAssertNil(VoiceInkWhisperRuntimeConfiguration.current(
            vadModelPath: "",
            defaults: defaults
        ).vad)
    }
}

private struct WhisperVADParametersHarness: VoiceInkWhisperRuntimeVADParameterSink {
    var threshold: Float = 0
    var min_speech_duration_ms: Int32 = 0
    var min_silence_duration_ms: Int32 = 0
    var max_speech_duration_s: Float = 0
    var speech_pad_ms: Int32 = 0
    var samples_overlap: Float = 0
}

private struct WhisperParametersHarness: VoiceInkWhisperRuntimeFullParameterSink {
    var print_realtime = false
    var print_progress = false
    var print_timestamps = false
    var print_special = false
    var translate = false
    var n_threads: Int32 = 0
    var offset_ms: Int32 = 0
    var no_context = false
    var single_segment = false
    var temperature: Float = 0
    var vad = false
    var vad_params = WhisperVADParametersHarness()
}
