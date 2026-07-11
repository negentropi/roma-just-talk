import XCTest
import VoiceInkCore
@testable import roma_just_talk

final class IOSMetricsTests: XCTestCase {
    func testMetricsSnapshotFiltersRangeAndBuildsModelComparison() throws {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let recent = Transcription(
            text: "one two three four",
            duration: 4,
            enhancedText: "Enhanced",
            transcriptionModelName: "small",
            aiEnhancementModelName: "gpt-5",
            transcriptionDuration: 1,
            enhancementDuration: 0.5,
            transcriptionStatus: .completed
        )
        recent.timestamp = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -2, to: now))

        let old = Transcription(
            text: "old words",
            duration: 10,
            transcriptionModelName: "large",
            transcriptionDuration: 2,
            transcriptionStatus: .completed
        )
        old.timestamp = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -20, to: now))

        let snapshot = VoiceInkIOSMetricsSnapshot(
            records: [recent, old],
            filter: .last7Days,
            now: now
        )

        XCTAssertEqual(snapshot.records.map(\.id), [recent.id])
        XCTAssertEqual(snapshot.dashboardMetrics.summary.totalCount, 1)
        XCTAssertEqual(
            snapshot.dashboardMetrics.summary.totalWords,
            VoiceInkSessionMetricPolicy.values(for: recent).wordCount
        )
        XCTAssertEqual(snapshot.performance.totalEnhancedFiles, 1)
        XCTAssertEqual(snapshot.performance.transcriptionModels.map(\.name), ["small"])
        XCTAssertEqual(snapshot.performance.enhancementModels.map(\.name), ["gpt-5"])
    }

    func testAllTimeSnapshotKeepsEmptyStateDataCoherent() {
        let snapshot = VoiceInkIOSMetricsSnapshot(records: [], filter: .allTime)

        XCTAssertTrue(snapshot.records.isEmpty)
        XCTAssertEqual(snapshot.dashboardMetrics.summary.totalCount, 0)
        XCTAssertEqual(snapshot.dashboardMetrics.timeSaved, 0)
        XCTAssertTrue(snapshot.performance.transcriptionModels.isEmpty)
        XCTAssertTrue(snapshot.performance.enhancementModels.isEmpty)
    }
}
