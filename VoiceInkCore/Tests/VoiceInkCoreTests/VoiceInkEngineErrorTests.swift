@testable import VoiceInkCore

final class VoiceInkEngineErrorTests: XCTestCase {
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
    }
}
