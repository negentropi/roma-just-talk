import Foundation
import XCTest
import RomaCore
@testable import roma_just_talk

final class IOSLocalWhisperSettingsTests: XCTestCase {
    func testVADPreferenceControlsIOSWhisperRuntimeParameters() throws {
        let suiteName = "IOSLocalWhisperSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        RomaVADPreference.saveIsEnabled(false, to: defaults)
        let disabled = RomaWhisperRuntimeConfiguration.current(
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

        RomaVADPreference.saveIsEnabled(true, to: defaults)
        let enabled = RomaWhisperRuntimeConfiguration.current(
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
            RomaWhisperRuntimeDefaults.vadThreshold
        )
        XCTAssertEqual(
            enabledParameters.vad_params.min_speech_duration_ms,
            RomaWhisperRuntimeDefaults.vadMinSpeechDurationMs
        )
        XCTAssertEqual(
            enabledParameters.vad_params.min_silence_duration_ms,
            RomaWhisperRuntimeDefaults.vadMinSilenceDurationMs
        )
    }

    func testEnabledVADRequiresBundledModelPath() throws {
        let suiteName = "IOSLocalWhisperSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        RomaVADPreference.saveIsEnabled(true, to: defaults)

        XCTAssertNil(RomaWhisperRuntimeConfiguration.current(
            vadModelPath: nil,
            defaults: defaults
        ).vad)
        XCTAssertNil(RomaWhisperRuntimeConfiguration.current(
            vadModelPath: "",
            defaults: defaults
        ).vad)
    }

    func testRetainedContextCacheReusesAndReleasesByModelPath() async throws {
        let harness = RetainedContextHarness()
        let cache = IOSRetainedContextCache<String>(
            factory: { await harness.create(path: $0) },
            release: { await harness.release(context: $0) }
        )

        async let first = cache.context(forModelPath: "/models/base.bin")
        async let second = cache.context(forModelPath: "/models/base.bin")
        let firstContext = try await first
        let secondContext = try await second

        XCTAssertEqual(firstContext, secondContext)
        let baseCreateCount = await harness.createCount(for: "/models/base.bin")
        XCTAssertEqual(baseCreateCount, 1)

        let replacement = try await cache.context(
            forModelPath: "/models/small.bin"
        )
        XCTAssertEqual(replacement, "context:/models/small.bin")
        let releasedAfterReplacement = await harness.releasedContexts()
        XCTAssertEqual(releasedAfterReplacement, [firstContext])

        await cache.releaseRetainedContext()
        let allReleased = await harness.releasedContexts()
        XCTAssertEqual(allReleased, [firstContext, replacement])
        let retainedPath = await cache.retainedModelPath()
        XCTAssertNil(retainedPath)
    }

    func testPrewarmPreferenceAndGeneratedSampleUseSharedPolicy() throws {
        let suiteName = "IOSLocalWhisperSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertTrue(RomaModelRuntimePreference.shouldPrewarmModelOnWake(
            from: defaults
        ))
        RomaModelRuntimePreference.saveShouldPrewarmModelOnWake(
            false,
            to: defaults
        )
        XCTAssertFalse(RomaModelRuntimePreference.shouldPrewarmModelOnWake(
            from: defaults
        ))
        XCTAssertEqual(
            RomaModelPrewarmSamplePolicy.generatedSilenceSampleCount,
            16_000
        )
    }

    func testPerLanguagePromptFeedsIOSRunSettings() throws {
        let suiteName = "IOSLocalWhisperSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let mode = Mode(
            name: "Local",
            transcriptionProvider: .localWhisper,
            transcriptionModel: "ggml-base"
        )

        RomaTranscriptionLanguagePreference.saveSelectedLanguage("fr", to: defaults)
        RomaLocalWhisperPromptCatalog.saveCustomPrompt(
            "Bonjour Roma Just Talk.",
            for: "fr",
            to: defaults
        )
        RomaTranscriptionPromptPreference.savePrompt("Stale English prompt", to: defaults)

        let runSettings = RomaIOSAppSettingsRunSnapshot(
            modes: [mode],
            selectedModeId: mode.id,
            selectedTranscriptionLanguage: "fr",
            wordReplacementRules: [],
            customVocabulary: []
        ).transcriptionRunSettings(defaults: defaults)

        XCTAssertEqual(runSettings.transcriptionLanguage, "fr")
        XCTAssertEqual(runSettings.transcriptionPrompt, "Bonjour Roma Just Talk.")
    }

    func testKeyboardDeliveryAppliesTrailingSpacePreference() throws {
        let suiteName = "IOSLocalWhisperSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        RomaAppendTrailingSpacePreference.saveIsEnabled(false, to: defaults)
        XCTAssertEqual(
            IOSKeyboardDictationDeliveryText.text("Hello", defaults: defaults),
            "Hello"
        )

        RomaAppendTrailingSpacePreference.saveIsEnabled(true, to: defaults)
        XCTAssertEqual(
            IOSKeyboardDictationDeliveryText.text("Hello", defaults: defaults),
            "Hello "
        )
    }

    func testKeyboardAutoSendPreferenceAndDeliveryPlan() throws {
        let suiteName = "IOSLocalWhisperSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertFalse(RomaIOSKeyboardAutoSendPreference.isEnabled(from: defaults))
        RomaIOSKeyboardAutoSendPreference.saveIsEnabled(true, to: defaults)
        XCTAssertTrue(RomaIOSKeyboardAutoSendPreference.isEnabled(from: defaults))
        XCTAssertEqual(
            RomaIOSKeyboardDeliveryPolicy.plan(
                text: "Hello",
                shouldLowercase: false,
                shouldInsertReturn: true,
                beforeCursor: nil
            ),
            RomaIOSKeyboardDeliveryPlan(text: "Hello", shouldInsertReturn: true)
        )
        XCTAssertEqual(RomaIOSKeyboardDeliveryPolicy.returnText, "\n")
    }
}

private actor RetainedContextHarness {
    private var createCounts: [String: Int] = [:]
    private var released: [String] = []

    func create(path: String) -> String {
        createCounts[path, default: 0] += 1
        return "context:\(path)"
    }

    func release(context: String) {
        released.append(context)
    }

    func createCount(for path: String) -> Int {
        createCounts[path, default: 0]
    }

    func releasedContexts() -> [String] {
        released
    }
}

private struct WhisperVADParametersHarness: RomaWhisperRuntimeVADParameterSink {
    var threshold: Float = 0
    var min_speech_duration_ms: Int32 = 0
    var min_silence_duration_ms: Int32 = 0
    var max_speech_duration_s: Float = 0
    var speech_pad_ms: Int32 = 0
    var samples_overlap: Float = 0
}

private struct WhisperParametersHarness: RomaWhisperRuntimeFullParameterSink {
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
