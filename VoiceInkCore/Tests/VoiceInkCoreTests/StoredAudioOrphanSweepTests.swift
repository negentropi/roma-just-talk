import Foundation
import VoiceInkCore

final class StoredAudioOrphanSweepTests: XCTestCase {
    func testSweepSparesACopyOfOldAudioWhoseRecordIsNotSavedYet() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInkCore.StoredAudioOrphanSweepTests.\(UUID().uuidString)", isDirectory: true)
        let recordings = directory.appendingPathComponent("Recordings", isDirectory: true)
        try FileManager.default.createDirectory(at: recordings, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let lastWeek = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        let source = recordings.appendingPathComponent("old.caf")
        try Data("old audio".utf8).write(to: source)
        try FileManager.default.setAttributes([.modificationDate: lastWeek], ofItemAtPath: source.path)
        let staleOrphan = recordings.appendingPathComponent("stale.wav")
        try Data("orphan".utf8).write(to: staleOrphan)
        try FileManager.default.setAttributes([.modificationDate: lastWeek], ofItemAtPath: staleOrphan.path)

        let copy = VoiceInkStoredAudioFile.retranscriptionFileURL(in: recordings, fileExtension: "caf")
        try VoiceInkStoredAudioFile.copyForUnsavedRecord(from: source, to: copy)

        let orphans = try VoiceInkStoredAudioFile.orphanedFiles(
            in: recordings,
            referencedFileNames: [source.lastPathComponent]
        ).map(\.lastPathComponent)

        XCTAssertEqual(orphans, [staleOrphan.lastPathComponent], "in-flight copy survives; stale orphan goes")
    }
}
