import Foundation
@testable import VoiceInkCore

final class StoredAudioFileTests: XCTestCase {
    func testRecordingsDirectoryNameMatchesExistingStoragePath() {
        XCTAssertEqual(VoiceInkStoredAudioFile.recordingsDirectoryName, "Recordings")
    }

    func testRecordingsDirectoryBuildsUnderBaseDirectory() {
        let baseDirectory = URL(fileURLWithPath: "/tmp/VoiceInk", isDirectory: true)

        XCTAssertEqual(
            VoiceInkStoredAudioFile.recordingsDirectory(in: baseDirectory).path,
            "/tmp/VoiceInk/Recordings"
        )
    }

    func testCreateRecordingsDirectoryCreatesDirectoryUnderBaseDirectory() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInkCore.StoredAudioFileTests.\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let directory = try VoiceInkStoredAudioFile.createRecordingsDirectory(in: baseDirectory)

        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
        XCTAssertEqual(directory.lastPathComponent, "Recordings")
    }

    func testFileURLBuildsUnderRecordingsDirectory() {
        let recordingsDirectory = URL(fileURLWithPath: "/tmp/VoiceInk/Recordings", isDirectory: true)

        XCTAssertEqual(
            VoiceInkStoredAudioFile.fileURL(forFilename: "recording.wav", in: recordingsDirectory).path,
            "/tmp/VoiceInk/Recordings/recording.wav"
        )
    }

    func testRecordingFileURLUsesMacOSUUIDWAVName() {
        let recordingsDirectory = URL(fileURLWithPath: "/tmp/VoiceInk/Recordings", isDirectory: true)
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!

        XCTAssertEqual(
            VoiceInkStoredAudioFile.recordingFileURL(in: recordingsDirectory, id: id).lastPathComponent,
            "00000000-0000-0000-0000-000000000123.wav"
        )
    }

    func testTimestampedRecordingFileURLPreservesIOSName() {
        let recordingsDirectory = URL(fileURLWithPath: "/tmp/VoiceInk/Recordings", isDirectory: true)
        let date = Date(timeIntervalSince1970: 1_234.9)

        XCTAssertEqual(
            VoiceInkStoredAudioFile.timestampedRecordingFileURL(in: recordingsDirectory, date: date).lastPathComponent,
            "recording_1234.wav"
        )
    }

    func testImportedTranscriptionFileURLPreservesMacOSName() {
        let recordingsDirectory = URL(fileURLWithPath: "/tmp/VoiceInk/Recordings", isDirectory: true)
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000456")!

        XCTAssertEqual(
            VoiceInkStoredAudioFile.importedTranscriptionFileURL(in: recordingsDirectory, id: id).lastPathComponent,
            "transcribed_00000000-0000-0000-0000-000000000456.wav"
        )
    }

    func testRetranscriptionFileURLPreservesMacOSName() {
        let recordingsDirectory = URL(fileURLWithPath: "/tmp/VoiceInk/Recordings", isDirectory: true)
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000789")!

        XCTAssertEqual(
            VoiceInkStoredAudioFile.retranscriptionFileURL(in: recordingsDirectory, id: id).lastPathComponent,
            "retranscribed_00000000-0000-0000-0000-000000000789.wav"
        )
    }

    func testResolvesFileURLString() {
        let fileURL = URL(fileURLWithPath: "/tmp/voiceink-recording.m4a")

        XCTAssertEqual(
            VoiceInkStoredAudioFile.resolvedURL(for: fileURL.absoluteString)?.path,
            fileURL.path
        )
    }

    func testResolvesAbsolutePath() {
        XCTAssertEqual(
            VoiceInkStoredAudioFile.resolvedURL(for: "/tmp/voiceink-recording.m4a")?.path,
            "/tmp/voiceink-recording.m4a"
        )
    }

    func testResolvesRelativeFilenameAgainstRecordingsDirectory() {
        let recordingsDirectory = URL(fileURLWithPath: "/tmp/Recordings", isDirectory: true)

        XCTAssertEqual(
            VoiceInkStoredAudioFile
                .resolvedURL(for: "voiceink-recording.m4a", relativeTo: recordingsDirectory)?
                .path,
            "/tmp/Recordings/voiceink-recording.m4a"
        )
    }

    func testRejectsBlankAndRelativeValueWithoutDirectory() {
        XCTAssertNil(VoiceInkStoredAudioFile.resolvedURL(for: "  "))
        XCTAssertNil(VoiceInkStoredAudioFile.resolvedURL(for: "voiceink-recording.m4a"))
    }

    func testExistingURLReturnsNilForMissingFile() {
        let recordingsDirectory = URL(fileURLWithPath: "/tmp/Recordings", isDirectory: true)

        XCTAssertNil(
            VoiceInkStoredAudioFile.existingURL(
                for: "missing-recording.m4a",
                relativeTo: recordingsDirectory
            )
        )
    }

    func testExistingURLReturnsResolvedFileWhenItExists() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInkCore.StoredAudioFileTests.\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let recordingsDirectory = try VoiceInkStoredAudioFile.createRecordingsDirectory(in: baseDirectory)
        let fileURL = VoiceInkStoredAudioFile.fileURL(forFilename: "voiceink-recording.m4a", in: recordingsDirectory)
        try Data().write(to: fileURL)

        XCTAssertEqual(
            VoiceInkStoredAudioFile.existingURL(
                for: "voiceink-recording.m4a",
                relativeTo: recordingsDirectory
            )?.path,
            fileURL.path
        )
    }

    func testDeleteExistingFileRemovesResolvedFileAndReturnsURL() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInkCore.StoredAudioFileTests.\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let recordingsDirectory = try VoiceInkStoredAudioFile.createRecordingsDirectory(in: baseDirectory)
        let fileURL = VoiceInkStoredAudioFile.fileURL(forFilename: "voiceink-recording.m4a", in: recordingsDirectory)
        try Data().write(to: fileURL)

        let deletedURL = try VoiceInkStoredAudioFile.deleteExistingFile(
            for: "voiceink-recording.m4a",
            relativeTo: recordingsDirectory
        )

        XCTAssertEqual(deletedURL?.path, fileURL.path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testDeleteExistingFileReturnsNilForMissingFile() throws {
        let recordingsDirectory = URL(fileURLWithPath: "/tmp/Recordings", isDirectory: true)

        let deletedURL = try VoiceInkStoredAudioFile.deleteExistingFile(
            for: "missing-recording.m4a",
            relativeTo: recordingsDirectory
        )

        XCTAssertNil(deletedURL)
    }

    func testStoredAudioRecordUsesDefaultRecordingsDirectory() {
        let recordingsDirectory = URL(fileURLWithPath: "/tmp/VoiceInk/Recordings", isDirectory: true)
        let record = StubStoredAudioRecord(
            audioFileURL: "voiceink-recording.m4a",
            storedAudioRecordingsDirectory: recordingsDirectory
        )

        XCTAssertEqual(
            record.resolvedAudioFileURL()?.path,
            "/tmp/VoiceInk/Recordings/voiceink-recording.m4a"
        )
    }

    func testStoredAudioRecordAllowsExplicitRecordingsDirectoryOverride() {
        let defaultDirectory = URL(fileURLWithPath: "/tmp/default/Recordings", isDirectory: true)
        let overrideDirectory = URL(fileURLWithPath: "/tmp/override/Recordings", isDirectory: true)
        let record = StubStoredAudioRecord(
            audioFileURL: "voiceink-recording.m4a",
            storedAudioRecordingsDirectory: defaultDirectory
        )

        XCTAssertEqual(
            record.resolvedAudioFileURL(relativeTo: overrideDirectory)?.path,
            "/tmp/override/Recordings/voiceink-recording.m4a"
        )
    }

    func testStoredAudioRecordDeleteUsesResolvedRecordFile() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInkCore.StoredAudioFileTests.\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let recordingsDirectory = try VoiceInkStoredAudioFile.createRecordingsDirectory(in: baseDirectory)
        let fileURL = VoiceInkStoredAudioFile.fileURL(forFilename: "voiceink-recording.m4a", in: recordingsDirectory)
        try Data().write(to: fileURL)
        let record = StubStoredAudioRecord(
            audioFileURL: "voiceink-recording.m4a",
            storedAudioRecordingsDirectory: recordingsDirectory
        )

        XCTAssertTrue(record.hasStoredAudioFile())
        XCTAssertEqual(try record.deleteExistingAudioFile()?.path, fileURL.path)
        XCTAssertFalse(record.hasStoredAudioFile())
    }
}

private final class StubStoredAudioRecord: VoiceInkStoredAudioRecord {
    var audioFileURL: String?
    let storedAudioRecordingsDirectory: URL?

    init(audioFileURL: String?, storedAudioRecordingsDirectory: URL?) {
        self.audioFileURL = audioFileURL
        self.storedAudioRecordingsDirectory = storedAudioRecordingsDirectory
    }
}
