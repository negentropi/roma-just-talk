import Foundation
import XCTest
import VoiceInkCore
@testable import VoiceInk_ios

@MainActor
final class IOSNativeAppleTranscriptionTests: XCTestCase {
    func testProviderAvailabilityRequiresIOS26Capability() {
        let unavailable = VoiceInkProviderAccessSnapshot(
            apiKeyState: VoiceInkProviderAPIKeyState(),
            localWhisperModelAvailable: false,
            nativeAppleSpeechAvailable: false
        )
        XCTAssertFalse(unavailable.availableProviders(for: .transcription).contains(.nativeApple))

        let available = VoiceInkProviderAccessSnapshot(
            apiKeyState: VoiceInkProviderAPIKeyState(),
            localWhisperModelAvailable: false,
            nativeAppleSpeechAvailable: true
        )
        XCTAssertTrue(available.availableProviders(for: .transcription).contains(.nativeApple))
        XCTAssertFalse(available.availableProviders(for: .postProcessing).contains(.nativeApple))
    }

    func testProviderUsesNativeModelAndBCP47Languages() {
        XCTAssertEqual(
            VoiceInkProviderKind.nativeApple.defaultModel(for: .transcription),
            VoiceInkTranscriptionModelCatalog.nativeAppleModel.name
        )
        XCTAssertEqual(
            VoiceInkLanguageCatalog.languages(for: VoiceInkTranscriptionModelProvider.nativeApple)["en-US"],
            VoiceInkLanguageCatalog.nativeApple["en-US"]
        )
        XCTAssertEqual(
            VoiceInkProviderKind.nativeApple.transcriptionServiceKind,
            .nativeApple
        )
    }

    func testServiceFactoryRoutesNativeAppleSeparately() {
        let nativeService = NativeAppleServiceHarness()
        let factory = VoiceInkAudioTranscriptionServiceFactory(
            localWhisperServiceFactory: { VoiceInkUnsupportedAudioTranscriptionService() },
            nativeAppleServiceFactory: { nativeService }
        )

        XCTAssertTrue(factory.service(for: .nativeApple) as AnyObject === nativeService)
    }

    func testNativeServiceRejectsWrongModelBeforeOpeningAudio() async {
        do {
            _ = try await IOSNativeAppleTranscriptionService().transcribeAudioFile(
                apiKey: "native-apple",
                model: "wrong-model",
                fileURL: URL(fileURLWithPath: "/missing.wav"),
                language: "en-US",
                prompt: nil,
                customVocabulary: []
            )
            XCTFail("The iOS Native Apple adapter must reject a mismatched model")
        } catch let error as VoiceInkNativeAppleTranscriptionFailureKind {
            XCTAssertEqual(error, .invalidModel)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testIOSUnsupportedVersionErrorRemainsPlatformSpecific() {
        XCTAssertEqual(
            VoiceInkNativeAppleTranscriptionFailureKind.unsupportedIOS.errorDescription,
            "SpeechAnalyzer requires iOS 26 or later."
        )
        XCTAssertEqual(
            VoiceInkNativeAppleTranscriptionFailureKind.unsupportedOS.errorDescription,
            "SpeechAnalyzer requires macOS 26 or later."
        )
    }
}

private final class NativeAppleServiceHarness: VoiceInkAudioTranscriptionService {
    func transcribeAudioFile(
        apiKey: String,
        model: String,
        fileURL: URL,
        language: String?,
        prompt: String?,
        customVocabulary: [String]
    ) async throws -> String {
        "native"
    }
}
