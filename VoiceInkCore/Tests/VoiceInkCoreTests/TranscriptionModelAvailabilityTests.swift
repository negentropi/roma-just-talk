import Foundation
import VoiceInkCore

final class TranscriptionModelAvailabilityTests: XCTestCase {
    func testConfiguredAPIKeyRequirementUsesConfiguredKeyFact() {
        XCTAssertTrue(VoiceInkTranscriptionModelAvailabilityFacts(
            requirement: .configuredAPIKey,
            hasConfiguredAPIKey: true
        ).isUsable)

        XCTAssertFalse(VoiceInkTranscriptionModelAvailabilityFacts(
            requirement: .configuredAPIKey,
            hasConfiguredAPIKey: false
        ).isUsable)
    }

    func testCurrentOSRequirementUsesCurrentOSFact() {
        XCTAssertTrue(VoiceInkTranscriptionModelAvailabilityFacts(
            requirement: .currentOSSupport,
            isAvailableOnCurrentOS: true
        ).isUsable)

        XCTAssertFalse(VoiceInkTranscriptionModelAvailabilityFacts(
            requirement: .currentOSSupport,
            isAvailableOnCurrentOS: false
        ).isUsable)
    }

    func testLocalModelRequirementsUseDownloadedFacts() {
        XCTAssertTrue(VoiceInkTranscriptionModelAvailabilityFacts(
            requirement: .downloadedLocalWhisperModel,
            isLocalWhisperModelDownloaded: true
        ).isUsable)
        XCTAssertFalse(VoiceInkTranscriptionModelAvailabilityFacts(
            requirement: .downloadedLocalWhisperModel,
            isLocalWhisperModelDownloaded: false
        ).isUsable)

        XCTAssertTrue(VoiceInkTranscriptionModelAvailabilityFacts(
            requirement: .downloadedLocalFluidAudioModel,
            isLocalFluidAudioModelDownloaded: true
        ).isUsable)
        XCTAssertFalse(VoiceInkTranscriptionModelAvailabilityFacts(
            requirement: .downloadedLocalFluidAudioModel,
            isLocalFluidAudioModelDownloaded: false
        ).isUsable)
    }

    func testAlwaysAvailableAndUnavailableRequirementsStayExplicit() {
        XCTAssertTrue(VoiceInkTranscriptionModelAvailabilityFacts(requirement: .alwaysAvailable).isUsable)
        XCTAssertFalse(VoiceInkTranscriptionModelAvailabilityFacts(requirement: .unavailable).isUsable)
    }

    func testNativeAppleAvailabilityPresentationPreservesMacOSCopy() {
        XCTAssertEqual(
            VoiceInkNativeAppleTranscriptionAvailabilityPresentation.unsupportedSpeechAnalyzerErrorDescription,
            "SpeechAnalyzer requires macOS 26 or later."
        )
        XCTAssertEqual(
            VoiceInkNativeAppleTranscriptionAvailabilityPresentation.requiresMacOS26Title(modelDisplayName: "Apple Speech"),
            "Apple Speech requires macOS 26 or later"
        )
    }
}
