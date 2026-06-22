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

    func testNativeAppleTranscriptionPolicyPreservesMacOSErrorCopy() {
        XCTAssertEqual(
            VoiceInkNativeAppleTranscriptionPolicy.errorDescription(for: .unsupportedOS),
            "SpeechAnalyzer requires macOS 26 or later."
        )
        XCTAssertEqual(
            VoiceInkNativeAppleTranscriptionPolicy.errorDescription(for: .transcriptionFailed),
            "Transcription failed using SpeechAnalyzer."
        )
        XCTAssertEqual(
            VoiceInkNativeAppleTranscriptionPolicy.errorDescription(for: .localeNotSupported),
            "The selected language is not supported by SpeechAnalyzer."
        )
        XCTAssertEqual(
            VoiceInkNativeAppleTranscriptionPolicy.errorDescription(for: .invalidModel),
            "Invalid model type provided for Native Apple transcription."
        )
        XCTAssertEqual(
            VoiceInkNativeAppleTranscriptionPolicy.errorDescription(for: .assetDownloadRequired(displayName: "English")),
            "Download required for English."
        )
        XCTAssertEqual(
            VoiceInkNativeAppleTranscriptionPolicy.errorDescription(for: .resultStreamTimedOut),
            "Apple Speech did not finish returning transcription results."
        )
    }

    func testNativeAppleFailureKindIsSharedThrowableLocalizedError() {
        let unsupportedError: Error = VoiceInkNativeAppleTranscriptionFailureKind.unsupportedOS
        XCTAssertEqual(
            VoiceInkErrorDescription.text(for: unsupportedError),
            "SpeechAnalyzer requires macOS 26 or later."
        )

        let assetError: Error = VoiceInkNativeAppleTranscriptionFailureKind.assetDownloadRequired(displayName: "English")
        XCTAssertEqual(
            VoiceInkErrorDescription.text(for: assetError),
            "Download required for English."
        )
    }

    func testNativeAppleTranscriptionPolicyPreservesSelectionAndTimeoutCopy() {
        XCTAssertEqual(
            VoiceInkNativeAppleTranscriptionPolicy.requiresMacOS26Title(modelDisplayName: "Apple Speech"),
            "Apple Speech requires macOS 26 or later"
        )
        XCTAssertEqual(VoiceInkNativeAppleTranscriptionPolicy.resultStreamTimeout(forAudioDuration: 0), 20.0)
        XCTAssertEqual(VoiceInkNativeAppleTranscriptionPolicy.resultStreamTimeout(forAudioDuration: 2.0), 20.0)
        XCTAssertEqual(VoiceInkNativeAppleTranscriptionPolicy.resultStreamTimeout(forAudioDuration: 5.0), 30.0)
    }
}
