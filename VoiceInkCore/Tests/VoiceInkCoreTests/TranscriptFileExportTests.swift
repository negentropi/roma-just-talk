import Foundation
@testable import VoiceInkCore

final class TranscriptFileExportTests: XCTestCase {
    func testTranscriptFileExportPreservesMacOSFileExtensions() {
        XCTAssertEqual(VoiceInkTranscriptFileExport.plainTextFileExtension, "txt")
        XCTAssertEqual(VoiceInkTranscriptFileExport.markdownFileExtension, "md")
    }

    func testSuggestedBaseFilenameUsesFallbackForBlankOrPunctuationOnlyText() {
        XCTAssertEqual(
            VoiceInkTranscriptFileExport.suggestedBaseFilename(for: " \n\t "),
            "transcription"
        )
        XCTAssertEqual(
            VoiceInkTranscriptFileExport.suggestedBaseFilename(for: "!!!"),
            "transcription"
        )
    }

    func testSuggestedBaseFilenamePreservesMacOSWordSelectionPolicy() {
        XCTAssertEqual(
            VoiceInkTranscriptFileExport.suggestedBaseFilename(for: "One two three"),
            "one-two-three"
        )
        XCTAssertEqual(
            VoiceInkTranscriptFileExport.suggestedBaseFilename(for: "One two three four"),
            "one-two-three-four"
        )
        XCTAssertEqual(
            VoiceInkTranscriptFileExport.suggestedBaseFilename(for: "One two three four five six seven"),
            "one-two-three-four-five-six-seven"
        )
        XCTAssertEqual(
            VoiceInkTranscriptFileExport.suggestedBaseFilename(for: "One two three four five six seven eight nine"),
            "one-two-three-four-five-six-seven-eight"
        )
    }

    func testSuggestedBaseFilenameSanitizesAndLimitsLength() {
        XCTAssertEqual(
            VoiceInkTranscriptFileExport.suggestedBaseFilename(for: "Hello, ROMA!\nJust talk."),
            "hello-roma-just-talk"
        )

        let longName = VoiceInkTranscriptFileExport.suggestedBaseFilename(
            for: "Supercalifragilisticexpialidocious abcdefghijklmnopqrstuvwxyz extra words"
        )

        XCTAssertEqual(longName.count, 50)
        XCTAssertEqual(longName, "supercalifragilisticexpialidocious-abcdefghijklmno")
    }

    func testMarkdownContentPreservesMacOSBodyShape() {
        XCTAssertEqual(
            VoiceInkTranscriptFileExport.markdownContent(
                for: "Hello\nworld.",
                timestamp: "Jun 18, 2026 at 12:34"
            ),
            """
            # Transcription

            **Date:** Jun 18, 2026 at 12:34

            Hello
            world.
            """
        )
    }

    func testMarkdownContentFormatsTimestampInSharedCore() {
        let timeZone = TimeZone(secondsFromGMT: 0)!
        let date = DateComponents(
            calendar: Calendar(identifier: .gregorian),
            timeZone: timeZone,
            year: 2026,
            month: 6,
            day: 18,
            hour: 12,
            minute: 34
        ).date!

        XCTAssertEqual(
            VoiceInkTranscriptFileExport.markdownContent(
                for: "Shared export.",
                date: date,
                locale: Locale(identifier: "en_GB"),
                timeZone: timeZone
            ),
            """
            # Transcription

            **Date:** 18 Jun 2026 at 12:34

            Shared export.
            """
        )
    }

    func testCSVExportPresentationPreservesMacOSFilenameAndFailureCopy() {
        XCTAssertEqual(VoiceInkTranscriptionCSVExporter.defaultFilename, "VoiceInk-transcription.csv")
        XCTAssertEqual(
            VoiceInkTranscriptionCSVExporter.writeFailureDiagnosticMessage(errorDescription: "disk full"),
            "Error writing CSV file: disk full"
        )
    }

    func testCSVStringPreservesMacOSHeaderAndColumnOrder() {
        let csv = VoiceInkTranscriptionCSVExporter.csvString(for: [
            VoiceInkTranscriptionCSVRecord(
                originalText: "raw",
                enhancedText: "enhanced",
                enhancementModel: "gpt",
                promptName: "Assistant",
                transcriptionModel: "Whisper",
                powerModeName: "Writing",
                powerModeEmoji: "W",
                enhancementTime: 1.25,
                transcriptionTime: 2.5,
                timestamp: Date(timeIntervalSince1970: 0),
                duration: 3.75
            )
        ])

        XCTAssertTrue(csv.hasPrefix(VoiceInkTranscriptionCSVExporter.header + "\n"))
        XCTAssertTrue(csv.contains("raw,enhanced,gpt,Assistant,Whisper,W Writing,1.25,2.5,"))
        XCTAssertTrue(csv.hasSuffix(",3.75\n"))
    }

    func testCSVStringUsesMacOSOptionalFallbacks() {
        let csv = VoiceInkTranscriptionCSVExporter.csvString(for: [
            VoiceInkTranscriptionCSVRecord(
                originalText: "raw",
                timestamp: Date(timeIntervalSince1970: 0),
                duration: 0
            )
        ])

        XCTAssertTrue(csv.contains("raw,,,,,,0.0,0.0,"))
    }

    func testEscapeCSVStringPreservesExistingMacOSQuotingPolicy() {
        XCTAssertEqual(VoiceInkTranscriptionCSVExporter.escapeCSVString("plain"), "plain")
        XCTAssertEqual(VoiceInkTranscriptionCSVExporter.escapeCSVString("hello, world"), "\"hello, world\"")
        XCTAssertEqual(VoiceInkTranscriptionCSVExporter.escapeCSVString("hello\nworld"), "\"hello\nworld\"")
        XCTAssertEqual(VoiceInkTranscriptionCSVExporter.escapeCSVString("he said \"yes\""), "he said \"\"yes\"\"")
    }

    func testCSVStringUsesSharedPowerModeDisplayName() {
        let csv = VoiceInkTranscriptionCSVExporter.csvString(for: [
            VoiceInkTranscriptionCSVRecord(
                originalText: "raw",
                powerModeName: " Writing ",
                powerModeEmoji: " W ",
                timestamp: Date(timeIntervalSince1970: 0),
                duration: 0
            )
        ])

        XCTAssertTrue(csv.contains("W Writing"))
    }
}
