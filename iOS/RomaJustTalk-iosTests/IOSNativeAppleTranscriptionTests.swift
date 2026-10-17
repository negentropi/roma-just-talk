import Foundation
import XCTest
import RomaCore
@testable import roma_just_talk

@MainActor
final class IOSNativeAppleTranscriptionTests: XCTestCase {
    func testProviderAvailabilityRequiresIOS26Capability() {
        let unavailable = RomaProviderAccessSnapshot(
            apiKeyState: RomaProviderAPIKeyState(),
            localWhisperModelAvailable: false,
            nativeAppleSpeechAvailable: false
        )
        XCTAssertFalse(unavailable.availableProviders(for: .transcription).contains(.nativeApple))

        let available = RomaProviderAccessSnapshot(
            apiKeyState: RomaProviderAPIKeyState(),
            localWhisperModelAvailable: false,
            nativeAppleSpeechAvailable: true
        )
        XCTAssertTrue(available.availableProviders(for: .transcription).contains(.nativeApple))
        XCTAssertFalse(available.availableProviders(for: .postProcessing).contains(.nativeApple))
    }

    func testProviderUsesNativeModelAndBCP47Languages() {
        XCTAssertEqual(
            RomaProviderKind.nativeApple.defaultModel(for: .transcription),
            RomaTranscriptionModelCatalog.nativeAppleModel.name
        )
        XCTAssertEqual(
            RomaLanguageCatalog.languages(for: RomaTranscriptionModelProvider.nativeApple)["en-US"],
            RomaLanguageCatalog.nativeApple["en-US"]
        )
        XCTAssertEqual(
            RomaProviderKind.nativeApple.transcriptionServiceKind,
            .nativeApple
        )
    }

    func testServiceFactoryRoutesNativeAppleSeparately() {
        let nativeService = NativeAppleServiceHarness()
        let factory = RomaAudioTranscriptionServiceFactory(
            localWhisperServiceFactory: { RomaUnsupportedAudioTranscriptionService() },
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
        } catch let error as RomaNativeAppleTranscriptionFailureKind {
            XCTAssertEqual(error, .invalidModel)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testIOSUnsupportedVersionErrorRemainsPlatformSpecific() {
        XCTAssertEqual(
            RomaNativeAppleTranscriptionFailureKind.unsupportedIOS.errorDescription,
            "SpeechAnalyzer requires iOS 26 or later."
        )
        XCTAssertEqual(
            RomaNativeAppleTranscriptionFailureKind.unsupportedOS.errorDescription,
            "SpeechAnalyzer requires macOS 26 or later."
        )
    }
}

private final class NativeAppleServiceHarness: RomaAudioTranscriptionService {
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
