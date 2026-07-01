import Foundation
@testable import VoiceInkCore

final class VoiceInkEngineErrorTests: XCTestCase {
    func testPrefersLocalizedErrorDescription() {
        XCTAssertEqual(
            VoiceInkErrorDescription.text(for: StubDescribedError(message: "provider down")),
            "provider down"
        )
    }

    func testFallsBackToLocalizedDescription() {
        let error = StubUndescribedError()

        XCTAssertEqual(
            VoiceInkErrorDescription.text(for: error),
            error.localizedDescription
        )
    }

    func testMacOSErrorDescriptionsStayStable() {
        XCTAssertEqual(
            VoiceInkEngineError.modelLoadFailed.errorDescription,
            "Failed to load the transcription model."
        )
        XCTAssertEqual(
            VoiceInkEngineError.transcriptionFailed.errorDescription,
            "Failed to transcribe the audio."
        )
        XCTAssertEqual(
            VoiceInkEngineError.whisperCoreFailed.errorDescription,
            "The core transcription engine failed."
        )
        XCTAssertEqual(
            VoiceInkEngineError.unzipFailed.errorDescription,
            "Failed to unzip the downloaded Core ML model."
        )
        XCTAssertEqual(
            VoiceInkEngineError.unknownError.errorDescription,
            "An unknown error occurred."
        )
    }

    func testIOSLocalWhisperDescriptionsStayStable() {
        XCTAssertEqual(
            VoiceInkEngineError.localModelUnavailable.errorDescription,
            "No local Whisper model is available. Please download a model first."
        )
        XCTAssertEqual(
            VoiceInkEngineError.localModelLoadFailed.errorDescription,
            "Failed to load the Whisper model."
        )
        XCTAssertEqual(
            VoiceInkEngineError.audioProcessingFailed.errorDescription,
            "Failed to process audio file for transcription."
        )
        XCTAssertEqual(
            VoiceInkEngineError.whisperTranscriptionFailed.errorDescription,
            "Whisper transcription failed."
        )
        XCTAssertEqual(
            VoiceInkEngineError.audioFileNotFound.errorDescription,
            "Audio file not found"
        )
        XCTAssertEqual(
            VoiceInkEngineError.noTranscriptionModelSelected.errorDescription,
            "No transcription model selected"
        )
    }
}

private struct StubDescribedError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}

private struct StubUndescribedError: LocalizedError {
    var errorDescription: String? {
        nil
    }
}
