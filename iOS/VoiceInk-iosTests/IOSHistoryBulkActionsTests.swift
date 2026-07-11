import XCTest
import VoiceInkCore
@testable import roma_just_talk

final class IOSHistoryBulkActionsTests: XCTestCase {
    func testCSVExportMapsIOSHistoryMetadataThroughSharedExporter() {
        let note = Transcription(
            text: "Raw, text",
            duration: 4,
            enhancedText: "Enhanced text",
            transcriptionModelName: "small",
            aiEnhancementModelName: "gpt-5",
            promptName: "Email",
            transcriptionDuration: 1.5,
            enhancementDuration: 0.5,
            transcriptionStatus: .completed
        )
        note.timestamp = Date(timeIntervalSince1970: 1_700_000_000)

        let csv = VoiceInkIOSCSVExport(transcriptions: [note]).csvString

        XCTAssertTrue(csv.hasPrefix(VoiceInkTranscriptionCSVExporter.header + "\n"))
        XCTAssertTrue(csv.contains("\"Raw, text\""))
        XCTAssertTrue(csv.contains("Enhanced text,gpt-5,Email,small"))
        XCTAssertTrue(csv.contains(",0.5,1.5,"))
    }

    func testBulkDeletionPlanKeepsUnselectedIDs() {
        let first = UUID()
        let second = UUID()
        let third = UUID()
        let plan = VoiceInkHistoryDeletionPolicy.selectedItemsDeletionPlan(
            selectedItems: [first, third],
            id: { $0 }
        )
        var deleted: [UUID] = []

        plan.applyRuntimeState { deleted.append($0) }

        XCTAssertEqual(Set(deleted), [first, third])
        XCTAssertFalse(plan.deletesID(second))
        XCTAssertTrue(plan.remainingSelection.isEmpty)
    }
}
