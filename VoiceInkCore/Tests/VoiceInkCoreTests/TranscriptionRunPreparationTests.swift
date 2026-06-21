import Foundation
@testable import VoiceInkCore

final class TranscriptionRunPreparationTests: XCTestCase {
    func testPrepareRawTextFiltersThenPreparesTranscriptText() {
        let configuration = VoiceInkTranscriptionCleanupConfiguration(
            punctuationMode: .removeTrailingPeriod,
            shouldFormatParagraphs: false,
            shouldLowercase: true,
            shouldRemoveFillerWords: true,
            fillerWords: ["um"]
        )

        let prepared = VoiceInkTranscriptionRunPreparation.prepareRawText(
            "Um Hello.",
            cleanupConfiguration: configuration
        ) { text in
            text.replacingOccurrences(of: "Hello", with: "ROMA")
        }

        XCTAssertEqual(prepared.filteredText, "Hello.")
        XCTAssertEqual(prepared.textForWordReplacement, "Hello.")
        XCTAssertEqual(prepared.wordReplacedText, "ROMA.")
        XCTAssertEqual(prepared.cleanedText, "roma")
    }

    func testPrepareRawTextCanPreserveParagraphWhitespaceForRunProcessor() {
        let configuration = VoiceInkTranscriptionCleanupConfiguration(
            shouldFormatParagraphs: false,
            shouldLowercase: false,
            shouldRemoveFillerWords: false
        )

        let prepared = VoiceInkTranscriptionRunPreparation.prepareRawText(
            "First line.\n\nSecond line.",
            cleanupConfiguration: configuration,
            whitespacePolicy: .preserveParagraphs,
            normalizeParagraphSpacingBeforeFormatting: true
        )

        XCTAssertEqual(prepared.filteredText, "First line.\n\nSecond line.")
        XCTAssertEqual(prepared.cleanedText, "First line.\n\nSecond line.")
    }

    func testPostProcessingSkipCanUseCleanedOrWordReplacedText() {
        let prepared = VoiceInkTranscriptionRunPreparedText(
            filteredText: "raw",
            preparedText: VoiceInkPreparedTranscriptionText(
                textForWordReplacement: "raw",
                wordReplacedText: "one two three four",
                cleanedText: "one"
            )
        )
        let configuration = VoiceInkPostProcessingSkipConfiguration(
            isEnabled: true,
            wordThreshold: 3
        )

        XCTAssertTrue(prepared.shouldSkipPostProcessing(configuration: configuration))
        XCTAssertFalse(prepared.shouldSkipPostProcessing(
            configuration: configuration,
            transcriptRole: .wordReplacedText
        ))
    }

    func testPromptTriggerKeepsPostProcessingForShortTranscript() {
        let prepared = VoiceInkTranscriptionRunPreparation.prepareFilteredText(
            "one",
            cleanupConfiguration: .disabled
        )
        let configuration = VoiceInkPostProcessingSkipConfiguration(
            isEnabled: true,
            wordThreshold: 3
        )

        XCTAssertFalse(prepared.shouldSkipPostProcessing(
            configuration: configuration,
            promptTriggerForcesPostProcessing: true
        ))
    }

    func testAudioFileTextPlanFiltersPreparesAndSelectsEnhancementText() {
        let configuration = VoiceInkTranscriptionCleanupConfiguration(
            punctuationMode: .removeTrailingPeriod,
            shouldFormatParagraphs: false,
            shouldLowercase: true,
            shouldRemoveFillerWords: true,
            fillerWords: ["um"]
        )

        let plan = VoiceInkTranscriptionRunPreparation.prepareAudioFileText(
            "Um Hello.",
            cleanupConfiguration: configuration
        ) { text in
            text.replacingOccurrences(of: "Hello", with: "ROMA")
        }

        XCTAssertEqual(plan.textForEnhancement, "ROMA.")
        XCTAssertEqual(plan.cleanedText, "roma")
    }

    func testAudioFileTextPlanSkipUsesEnhancementTextAndPromptTrigger() {
        let configuration = VoiceInkPostProcessingSkipConfiguration(
            isEnabled: true,
            wordThreshold: 3
        )
        let longEnhancementPlan = VoiceInkAudioFileTranscriptionTextPlan(
            textForEnhancement: "one two three four",
            cleanedText: "one"
        )
        let shortEnhancementPlan = VoiceInkAudioFileTranscriptionTextPlan(
            textForEnhancement: "one",
            cleanedText: "one two three four"
        )

        XCTAssertFalse(longEnhancementPlan.shouldSkipEnhancement(configuration: configuration))
        XCTAssertTrue(shortEnhancementPlan.shouldSkipEnhancement(configuration: configuration))
        XCTAssertFalse(shortEnhancementPlan.shouldSkipEnhancement(
            configuration: configuration,
            promptTriggerForcesEnhancement: true
        ))
        XCTAssertFalse(shortEnhancementPlan.shouldSkipEnhancement(configuration: nil))
    }
}
