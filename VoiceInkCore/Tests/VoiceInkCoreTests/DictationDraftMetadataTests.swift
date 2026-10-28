import Foundation
import VoiceInkCore

final class DictationDraftMetadataTests: XCTestCase {
    func testAudioDraftCarriesExactRecognitionWithoutEnhancement() {
        for (profile, style) in [(VoiceInkDictationProfile.custom, VoiceInkClarityStyle.formal), (.none, .natural)] {
            let draft = VoiceInkAudioFileTranscriptionDraft.completed(context: capturedContext(profile: profile, style: style))

            XCTAssertEqual(draft.text, "Prepared text.")
            XCTAssertEqual(draft.duration, 3.5)
            XCTAssertEqual(draft.audioFileURL, "file:///fixture.wav")
            XCTAssertEqual(draft.transcriptionModelName, "Fixture recognizer")
            XCTAssertEqual(draft.transcriptionDuration, 0.75)
            XCTAssertEqual(draft.powerModeName, "Focus")
            XCTAssertEqual(draft.powerModeEmoji, "🧪")
            XCTAssertEqual(draft.transcriptionStatus, .completed)
            XCTAssertNil(draft.enhancedText)
            XCTAssertNil(draft.aiEnhancementModelName)
            XCTAssertNil(draft.processingFailureReason)
            assertCapturedMetadata(draft, profile: profile, style: style)
        }
    }

    func testAudioDraftPreservesMetadataAndSameOutputEnhancementSuccess() {
        let enhancement = VoiceInkAIEnhancementResult(
            text: "Prepared text.", duration: 1.25, modelName: "Fixture polisher", promptName: "Fixed cleanup",
            requestSystemMessage: "fixed system", requestUserMessage: "literal request\r\ne\u{301} 🧪"
        )
        let draft = VoiceInkAudioFileTranscriptionDraft.completed(
            context: capturedContext(), enhancementOutcome: .succeeded(enhancement)
        )

        XCTAssertEqual(draft.text, "Prepared text.")
        XCTAssertEqual(draft.enhancedText, "Prepared text.")
        XCTAssertEqual(draft.aiEnhancementModelName, "Fixture polisher")
        XCTAssertEqual(draft.promptName, "Fixed cleanup")
        XCTAssertEqual(draft.enhancementDuration, 1.25)
        XCTAssertEqual(draft.aiRequestSystemMessage, "fixed system")
        XCTAssertEqual(draft.aiRequestUserMessage, "literal request\r\ne\u{301} 🧪")
        XCTAssertNil(draft.processingFailureReason)
        assertCapturedMetadata(draft)
    }

    func testAudioDraftKeepsExplicitProcessingFailureSeparateFromEnhancementFailure() {
        let processingFailure = "Library snapshot failed.\r\nCafe\u{301} 🧪"
        for policy in [VoiceInkEnhancementFailureDraftPolicy.storeFailureText, .omitEnhancedText] {
            let draft = VoiceInkAudioFileTranscriptionDraft.completed(
                context: capturedContext(),
                enhancementOutcome: .failed(reason: "provider timeout", policy: policy),
                processingFailureReason: processingFailure
            )

            XCTAssertEqual(draft.text, "Prepared text.")
            XCTAssertEqual(draft.enhancedText, policy == .storeFailureText ? "Enhancement failed: provider timeout" : nil)
            XCTAssertEqual(draft.processingFailureReason.map { Array($0.utf8) }, Optional(Array(processingFailure.utf8)))
            XCTAssertEqual(draft.processingFailureReason.map { Array($0.utf16) }, Optional(Array(processingFailure.utf16)))
            XCTAssertNil(draft.aiEnhancementModelName)
            XCTAssertNil(draft.promptName)
            XCTAssertNil(draft.enhancementDuration)
            XCTAssertNil(draft.aiRequestSystemMessage)
            XCTAssertNil(draft.aiRequestUserMessage)
            XCTAssertEqual(draft.transcriptionStatus, .completed)
            assertCapturedMetadata(draft)
        }
    }

    func testLegacyDraftAndAudioCompletionDefaultsKeepMetadataAbsent() async {
        let direct = VoiceInkCompletedTranscriptionDraft(
            cleanedText: "Legacy text", duration: 2, audioFileURL: nil,
            transcriptionModelName: "Legacy recognizer", transcriptionDuration: 0.5
        )
        XCTAssertEqual(direct.text, "Legacy text")
        XCTAssertNil(direct.enhancedText)
        XCTAssertEqual(direct.transcriptionStatus, .completed)
        assertNoCapturedMetadata(direct)

        let context = VoiceInkAudioFileTranscriptionDraftContext(
            cleanedText: "Legacy text", duration: 2, audioFileURL: nil,
            transcriptionModelName: "Legacy recognizer", transcriptionDuration: 0.5
        )
        var didEnhance = false
        let result = await VoiceInkAudioFileTranscriptionDraft.completionResult(
            context: context, enhancementRequest: nil, enhancementFailurePolicy: .storeFailureText
        ) { _ in
            didEnhance = true
            return VoiceInkAIEnhancementResult(
                text: "Unexpected", duration: 1, modelName: "Unexpected", promptName: nil,
                requestSystemMessage: nil, requestUserMessage: nil
            )
        }

        XCTAssertFalse(didEnhance)
        XCTAssertEqual(result.draft, direct)
        XCTAssertNil(result.enhancementFailureReason)
        assertNoCapturedMetadata(result.draft)
    }

    func testLegacyCompletionFailureDoesNotInventProcessingFailure() async {
        for policy in [VoiceInkEnhancementFailureDraftPolicy.storeFailureText, .omitEnhancedText] {
            let result = await VoiceInkAudioFileTranscriptionDraft.completionResult(
                context: capturedContext(),
                enhancementRequest: VoiceInkTranscriptionEnhancementRequest(text: "Prepared text."),
                enhancementFailurePolicy: policy
            ) { request in
                XCTAssertEqual(request.text, "Prepared text.")
                throw NSError(domain: "DictationDraftMetadataTests", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "provider timeout"])
            }

            XCTAssertEqual(result.enhancementFailureReason, "provider timeout")
            XCTAssertEqual(result.draft.text, "Prepared text.")
            XCTAssertEqual(result.draft.enhancedText, policy == .storeFailureText ? "Enhancement failed: provider timeout" : nil)
            XCTAssertNil(result.draft.aiEnhancementModelName)
            XCTAssertNil(result.draft.aiRequestSystemMessage)
            XCTAssertNil(result.draft.processingFailureReason)
            assertCapturedMetadata(result.draft)
        }
    }

    func testExplicitProcessingFailureWithoutEnhancementDoesNotInventRequestMetadata() {
        let context = VoiceInkAudioFileTranscriptionDraftContext(
            cleanedText: rawRecognition, duration: 3.5, audioFileURL: "file:///fixture.wav",
            transcriptionModelName: "Fixture recognizer", transcriptionDuration: 0.75,
            recognitionText: rawRecognition, dictationProfile: .custom, clarityStyle: .formal
        )
        let draft = VoiceInkAudioFileTranscriptionDraft.completed(
            context: context, processingFailureReason: "Provider not configured"
        )

        XCTAssertEqual(Array(draft.text.utf8), Array(rawRecognition.utf8))
        XCTAssertEqual(Array(draft.text.utf16), Array(rawRecognition.utf16))
        XCTAssertEqual(draft.processingFailureReason, "Provider not configured")
        XCTAssertNil(draft.enhancedText)
        XCTAssertNil(draft.aiEnhancementModelName)
        XCTAssertNil(draft.promptName)
        XCTAssertNil(draft.enhancementDuration)
        XCTAssertNil(draft.aiRequestSystemMessage)
        XCTAssertNil(draft.aiRequestUserMessage)
        assertCapturedMetadata(draft)
    }

    func testLegacyCompletionCancellationKeepsItsExistingOutcome() async {
        let result = await VoiceInkAudioFileTranscriptionDraft.completionResult(
            context: capturedContext(),
            enhancementRequest: VoiceInkTranscriptionEnhancementRequest(text: "Prepared text."),
            enhancementFailurePolicy: .omitEnhancedText
        ) { _ in
            throw CancellationError()
        }

        XCTAssertEqual(result.draft.text, "Prepared text.")
        XCTAssertEqual(result.draft.transcriptionStatus, .completed)
        XCTAssertNil(result.draft.enhancedText)
        XCTAssertFalse(result.enhancementFailureReason?.isEmpty ?? true)
        XCTAssertNil(result.draft.processingFailureReason)
        assertCapturedMetadata(result.draft)
    }

    private let rawRecognition = " Um, Cafe\u{301} 🧪 \"literal\"\r\nSecond line\n"

    private func capturedContext(
        profile: VoiceInkDictationProfile = .custom,
        style: VoiceInkClarityStyle = .formal
    ) -> VoiceInkAudioFileTranscriptionDraftContext {
        VoiceInkAudioFileTranscriptionDraftContext(
            cleanedText: "Prepared text.", duration: 3.5, audioFileURL: "file:///fixture.wav",
            transcriptionModelName: "Fixture recognizer", transcriptionDuration: 0.75,
            powerModeName: "Focus", powerModeEmoji: "🧪",
            recognitionText: rawRecognition, dictationProfile: profile, clarityStyle: style
        )
    }

    private func assertCapturedMetadata(
        _ draft: VoiceInkCompletedTranscriptionDraft,
        profile: VoiceInkDictationProfile = .custom,
        style: VoiceInkClarityStyle = .formal
    ) {
        XCTAssertEqual(draft.recognitionText.map { Array($0.utf8) }, Optional(Array(rawRecognition.utf8)))
        XCTAssertEqual(draft.recognitionText.map { Array($0.utf16) }, Optional(Array(rawRecognition.utf16)))
        XCTAssertEqual(draft.dictationProfile, profile)
        XCTAssertEqual(draft.clarityStyle, style)
    }

    private func assertNoCapturedMetadata(_ draft: VoiceInkCompletedTranscriptionDraft) {
        XCTAssertNil(draft.recognitionText)
        XCTAssertNil(draft.dictationProfile)
        XCTAssertNil(draft.clarityStyle)
        XCTAssertNil(draft.processingFailureReason)
    }
}
