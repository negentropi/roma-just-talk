import XCTest
import RomaCore

final class IOSHistoryCleanupTests: XCTestCase {
    func testScheduleRunsInitiallyAndAfterDailyInterval() {
        let now = Date(timeIntervalSince1970: 100_000)

        XCTAssertTrue(RomaHistoryCleanupSchedulePolicy.shouldRun(
            lastRunDate: nil,
            currentDate: now
        ))
        XCTAssertFalse(RomaHistoryCleanupSchedulePolicy.shouldRun(
            lastRunDate: now.addingTimeInterval(-60),
            currentDate: now
        ))
        XCTAssertTrue(RomaHistoryCleanupSchedulePolicy.shouldRun(
            lastRunDate: now.addingTimeInterval(-RomaAudioCleanupPreference.cleanupCheckInterval),
            currentDate: now
        ))
    }

    func testCleanupCandidatesExcludeRecentAndActiveRecords() {
        let cutoff = Date(timeIntervalSince1970: 1_000)
        let old = CleanupRecord(id: UUID(), timestamp: cutoff.addingTimeInterval(-1))
        let active = CleanupRecord(id: UUID(), timestamp: cutoff.addingTimeInterval(-2))
        let recent = CleanupRecord(id: UUID(), timestamp: cutoff)

        let candidates = RomaHistoryCleanupCandidatePolicy.eligibleRecords(
            [old, active, recent],
            cutoffDate: cutoff,
            activeIDs: [active.id],
            id: \.id,
            timestamp: \.timestamp
        )

        XCTAssertEqual(candidates.map(\.id), [old.id])
    }

    func testOrphanPolicyKeepsReferencedStandardizedFile() {
        let directory = URL(fileURLWithPath: "/tmp/records")
        let referenced = directory.appendingPathComponent("kept.wav")
        let orphan = directory.appendingPathComponent("orphan.wav")

        XCTAssertEqual(
            RomaOrphanAudioFilePolicy.orphanFiles(
                files: [referenced, orphan],
                referencedFiles: [referenced.standardizedFileURL]
            ),
            [orphan]
        )
    }
}

private struct CleanupRecord {
    let id: UUID
    let timestamp: Date
}
