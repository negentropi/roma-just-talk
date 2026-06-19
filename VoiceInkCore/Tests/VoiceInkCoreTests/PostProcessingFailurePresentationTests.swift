import Foundation
@testable import VoiceInkCore

final class PostProcessingFailurePresentationTests: XCTestCase {
    func testPostProcessingFailureTextPreservesExistingIOSRetryPrefix() {
        XCTAssertEqual(
            VoiceInkPostProcessingFailurePresentation.postProcessingFailureText(reason: "provider down"),
            "Post-processing failed: provider down"
        )
    }

    func testEnhancementFailureTextPreservesExistingMacOSPrefix() {
        XCTAssertEqual(
            VoiceInkPostProcessingFailurePresentation.enhancementFailureText(reason: "provider down"),
            "Enhancement failed: provider down"
        )
    }

    func testEnhancementUnavailableMessagePreservesMacOSGuardCopy() {
        XCTAssertEqual(
            VoiceInkPostProcessingFailurePresentation.enhancementUnavailableFallbackText,
            "AI Enhancement is not enabled or configured"
        )
        XCTAssertEqual(
            VoiceInkPostProcessingFailurePresentation.enhancementUnavailableMessage(
                isEnabled: false,
                isConfigured: true
            ),
            "AI Enhancement is not enabled or configured"
        )
        XCTAssertEqual(
            VoiceInkPostProcessingFailurePresentation.enhancementUnavailableMessage(
                isEnabled: true,
                isConfigured: false
            ),
            "AI Enhancement is not enabled or configured"
        )
        XCTAssertEqual(
            VoiceInkPostProcessingFailurePresentation.enhancementUnavailableMessage(
                isEnabled: false,
                isConfigured: false
            ),
            "AI Enhancement is not enabled or configured"
        )
        XCTAssertNil(
            VoiceInkPostProcessingFailurePresentation.enhancementUnavailableMessage(
                isEnabled: true,
                isConfigured: true
            )
        )
    }

    func testEnhancementFailureNotificationTitlePreservesEightyCharacterReasonLimit() {
        let reason = String(repeating: "a", count: 100)
        let title = VoiceInkPostProcessingFailurePresentation.enhancementFailureNotificationTitle(reason: reason)

        XCTAssertEqual(title, "Enhancement failed: \(String(repeating: "a", count: 80))")
    }

    func testEnhancementFailureNotificationTitleClampsNegativeReasonLimit() {
        XCTAssertEqual(
            VoiceInkPostProcessingFailurePresentation.enhancementFailureNotificationTitle(
                reason: "provider down",
                reasonLimit: -1
            ),
            "Enhancement failed: "
        )
    }
}
