import Foundation
@testable import VoiceInkCore

final class PostProcessingSkipPolicyTests: XCTestCase {
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
}
