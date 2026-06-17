import Foundation
@testable import VoiceInkCore

final class PostProcessingSkipPolicyTests: XCTestCase {
    func testCurrentConfigurationUsesSharedDefaultsWhenUnset() {
        withIsolatedDefaults { defaults in
            XCTAssertEqual(
                VoiceInkPostProcessingSkipConfiguration.current(in: defaults),
                VoiceInkPostProcessingSkipConfiguration(
                    isEnabled: VoiceInkPreferenceDefault.skipShortEnhancement,
                    wordThreshold: VoiceInkPreferenceDefault.shortEnhancementWordThreshold
                )
            )
        }
    }

    func testCurrentConfigurationReadsSharedStorageKeys() {
        withIsolatedDefaults { defaults in
            defaults.set(false, forKey: VoiceInkUserDefaultsKey.skipShortEnhancement)
            defaults.set(7, forKey: VoiceInkUserDefaultsKey.shortEnhancementWordThreshold)

            XCTAssertEqual(
                VoiceInkPostProcessingSkipConfiguration.current(in: defaults),
                VoiceInkPostProcessingSkipConfiguration(isEnabled: false, wordThreshold: 7)
            )
        }
    }

    func testDisabledPolicyNeverSkipsPostProcessing() {
        let configuration = VoiceInkPostProcessingSkipConfiguration(
            isEnabled: false,
            wordThreshold: 3
        )

        XCTAssertFalse(VoiceInkPostProcessingSkipPolicy.shouldSkipPostProcessing(
            transcript: "yes",
            configuration: configuration,
            promptTriggerForcesPostProcessing: false
        ))
    }

    func testEnabledPolicySkipsAtOrBelowThreshold() {
        let configuration = VoiceInkPostProcessingSkipConfiguration(
            isEnabled: true,
            wordThreshold: 3
        )

        XCTAssertTrue(VoiceInkPostProcessingSkipPolicy.shouldSkipPostProcessing(
            transcript: "yes thank you",
            configuration: configuration,
            promptTriggerForcesPostProcessing: false
        ))
    }

    func testEnabledPolicyKeepsPostProcessingAboveThreshold() {
        let configuration = VoiceInkPostProcessingSkipConfiguration(
            isEnabled: true,
            wordThreshold: 3
        )

        XCTAssertFalse(VoiceInkPostProcessingSkipPolicy.shouldSkipPostProcessing(
            transcript: "please summarize this longer note",
            configuration: configuration,
            promptTriggerForcesPostProcessing: false
        ))
    }

    func testPromptTriggerForcesPostProcessingForShortTranscript() {
        let configuration = VoiceInkPostProcessingSkipConfiguration(
            isEnabled: true,
            wordThreshold: 3
        )

        XCTAssertFalse(VoiceInkPostProcessingSkipPolicy.shouldSkipPostProcessing(
            transcript: "email john",
            configuration: configuration,
            promptTriggerForcesPostProcessing: true
        ))
    }

    func testNonPositiveThresholdFallsBackToExistingDefault() {
        let configuration = VoiceInkPostProcessingSkipConfiguration(
            isEnabled: true,
            wordThreshold: 0
        )

        XCTAssertEqual(
            configuration.wordThreshold,
            VoiceInkPreferenceDefault.shortEnhancementWordThreshold
        )
        XCTAssertTrue(VoiceInkPostProcessingSkipPolicy.shouldSkipPostProcessing(
            transcript: "yes thank you",
            configuration: configuration,
            promptTriggerForcesPostProcessing: false
        ))
    }

    private func withIsolatedDefaults(_ run: (UserDefaults) -> Void) {
        let suiteName = "VoiceInkCore.PostProcessingSkipPolicyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        run(defaults)
        defaults.removePersistentDomain(forName: suiteName)
    }
}
