import Foundation
import VoiceInkCore

final class TranscriptionRecordTests: XCTestCase {
    func testApplyCompletedRunResultStoresCompletedRecordState() {
        let record = StubMutableTranscriptionRecord()
        let result = VoiceInkTranscriptionRunResult(
            cleanedText: "clean",
            finalText: "enhanced",
            transcriptionModelName: "whisper-large-v3",
            aiEnhancementModelName: "gemini-2.5-flash",
            transcriptionDuration: 3,
            enhancementDuration: 2,
            postProcessingError: "Post-processing failed: timeout",
            postProcessingSucceeded: false
        )

        record.applyCompletedRunResult(result)

        XCTAssertEqual(record.text, "clean")
        XCTAssertEqual(record.enhancedText, "enhanced")
        XCTAssertEqual(record.transcriptionModelName, "whisper-large-v3")
        XCTAssertEqual(record.aiEnhancementModelName, "gemini-2.5-flash")
        XCTAssertEqual(record.transcriptionDuration, 3)
        XCTAssertEqual(record.enhancementDuration, 2)
        XCTAssertEqual(record.transcriptionStatus, .completed)
        XCTAssertEqual(record.transcriptionError, "Post-processing failed: timeout")
    }

    func testApplyCompletedRunResultClearsOldEnhancementAndErrorWhenAbsent() {
        let record = StubMutableTranscriptionRecord(
            enhancedText: "old enhancement",
            aiEnhancementModelName: "old model",
            transcriptionError: "old error"
        )
        let result = VoiceInkTranscriptionRunResult(
            cleanedText: "clean",
            finalText: "clean",
            transcriptionModelName: "whisper-large-v3",
            aiEnhancementModelName: nil,
            transcriptionDuration: nil,
            enhancementDuration: nil,
            postProcessingError: nil,
            postProcessingSucceeded: false
        )

        record.applyCompletedRunResult(result)

        XCTAssertEqual(record.text, "clean")
        XCTAssertNil(record.enhancedText)
        XCTAssertEqual(record.transcriptionModelName, "whisper-large-v3")
        XCTAssertNil(record.aiEnhancementModelName)
        XCTAssertNil(record.transcriptionDuration)
        XCTAssertNil(record.enhancementDuration)
        XCTAssertEqual(record.transcriptionStatus, .completed)
        XCTAssertNil(record.transcriptionError)
    }

    func testMarkTranscriptionFailedOnlyStoresFailureState() {
        let record = StubMutableTranscriptionRecord(
            text: "draft",
            enhancedText: "enhanced",
            transcriptionModelName: "whisper-large-v3",
            aiEnhancementModelName: "gemini-2.5-flash"
        )

        record.markTranscriptionFailed("Audio file not found")

        XCTAssertEqual(record.text, "draft")
        XCTAssertEqual(record.enhancedText, "enhanced")
        XCTAssertEqual(record.transcriptionModelName, "whisper-large-v3")
        XCTAssertEqual(record.aiEnhancementModelName, "gemini-2.5-flash")
        XCTAssertEqual(record.transcriptionStatus, .failed)
        XCTAssertEqual(record.transcriptionError, "Audio file not found")
    }
}

private final class StubMutableTranscriptionRecord: VoiceInkMutableTranscriptionRecord {
    var text: String
    var enhancedText: String?
    var transcriptionModelName: String?
    var aiEnhancementModelName: String?
    var transcriptionDuration: TimeInterval?
    var enhancementDuration: TimeInterval?
    var transcriptionStatus: VoiceInkTranscriptionStatus
    var transcriptionError: String?

    init(
        text: String = "",
        enhancedText: String? = nil,
        transcriptionModelName: String? = nil,
        aiEnhancementModelName: String? = nil,
        transcriptionDuration: TimeInterval? = nil,
        enhancementDuration: TimeInterval? = nil,
        transcriptionStatus: VoiceInkTranscriptionStatus = .pending,
        transcriptionError: String? = nil
    ) {
        self.text = text
        self.enhancedText = enhancedText
        self.transcriptionModelName = transcriptionModelName
        self.aiEnhancementModelName = aiEnhancementModelName
        self.transcriptionDuration = transcriptionDuration
        self.enhancementDuration = enhancementDuration
        self.transcriptionStatus = transcriptionStatus
        self.transcriptionError = transcriptionError
    }
}
