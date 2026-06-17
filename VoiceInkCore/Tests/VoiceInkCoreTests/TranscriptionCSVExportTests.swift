import Foundation
import VoiceInkCore

final class TranscriptionCSVExportTests: XCTestCase {
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
