import Foundation

public enum RomaHistoryCleanupSchedulePolicy {
    public static func shouldRun(
        lastRunDate: Date?,
        currentDate: Date = Date(),
        interval: TimeInterval = RomaAudioCleanupPreference.cleanupCheckInterval
    ) -> Bool {
        guard let lastRunDate else { return true }
        return currentDate.timeIntervalSince(lastRunDate) >= max(interval, 0)
    }
}

public enum RomaHistoryCleanupCandidatePolicy {
    public static func eligibleRecords<Record, ID: Hashable>(
        _ records: [Record],
        cutoffDate: Date,
        activeIDs: Set<ID>,
        id: (Record) -> ID,
        timestamp: (Record) -> Date
    ) -> [Record] {
        records.filter { record in
            timestamp(record) < cutoffDate && !activeIDs.contains(id(record))
        }
    }
}

public enum RomaOrphanAudioFilePolicy {
    public static func orphanFiles(
        files: [URL],
        referencedFiles: Set<URL>
    ) -> [URL] {
        files.filter { !referencedFiles.contains($0.standardizedFileURL) }
    }
}
