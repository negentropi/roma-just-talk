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

    func testAvailabilityReturnsMissingPathForBlankOrUnresolvableStoredValue() {
        XCTAssertEqual(VoiceInkStoredAudioFile.availability(for: "  "), .missingPath)
        XCTAssertEqual(VoiceInkStoredAudioFile.availability(for: "voiceink-recording.m4a"), .missingPath)
    }

    func testAvailabilityReturnsMissingFileForResolvedMissingFile() {
        let recordingsDirectory = URL(fileURLWithPath: "/tmp/Recordings", isDirectory: true)
        let expectedURL = VoiceInkStoredAudioFile.fileURL(forFilename: "missing-recording.m4a", in: recordingsDirectory)

        XCTAssertEqual(
            VoiceInkStoredAudioFile.availability(
                for: "missing-recording.m4a",
                relativeTo: recordingsDirectory
            ),
            .missingFile(expectedURL)
        )
    }

    func testAvailabilityReturnsAvailableResolvedFileWhenItExists() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInkCore.StoredAudioFileTests.\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let recordingsDirectory = try VoiceInkStoredAudioFile.createRecordingsDirectory(in: baseDirectory)
        let fileURL = VoiceInkStoredAudioFile.fileURL(forFilename: "voiceink-recording.m4a", in: recordingsDirectory)
        try Data().write(to: fileURL)

        XCTAssertEqual(
            VoiceInkStoredAudioFile.availability(
                for: "voiceink-recording.m4a",
                relativeTo: recordingsDirectory
            ),
            .available(fileURL)
        )
    }

    func testAvailabilityPresentationKeepsExistingIOSMissingAudioText() {
        XCTAssertEqual(VoiceInkStoredAudioAvailability.available(URL(fileURLWithPath: "/tmp/a.wav")).unavailableTitle, nil)
        XCTAssertEqual(VoiceInkStoredAudioAvailability.available(URL(fileURLWithPath: "/tmp/a.wav")).unavailableDetail, nil)
        XCTAssertEqual(VoiceInkStoredAudioAvailability.missingFile(URL(fileURLWithPath: "/tmp/missing.wav")).unavailableTitle, "Audio Unavailable")
        XCTAssertEqual(VoiceInkStoredAudioAvailability.missingFile(URL(fileURLWithPath: "/tmp/missing.wav")).unavailableDetail, "File not found")
        XCTAssertEqual(VoiceInkStoredAudioAvailability.missingPath.unavailableTitle, "Audio Unavailable")
        XCTAssertEqual(VoiceInkStoredAudioAvailability.missingPath.unavailableDetail, "Path missing")
    }

    func testAvailabilityAudioSectionVisibilityPreservesMissingAudioIntent() {
        XCTAssertTrue(VoiceInkStoredAudioAvailability.available(URL(fileURLWithPath: "/tmp/a.wav")).shouldShowAudioSection(duration: 0))
        XCTAssertTrue(VoiceInkStoredAudioAvailability.missingFile(URL(fileURLWithPath: "/tmp/missing.wav")).shouldShowAudioSection(duration: 0))
        XCTAssertTrue(VoiceInkStoredAudioAvailability.missingPath.shouldShowAudioSection(duration: 1))
        XCTAssertFalse(VoiceInkStoredAudioAvailability.missingPath.shouldShowAudioSection(duration: 0))
        XCTAssertFalse(VoiceInkStoredAudioAvailability.missingPath.shouldShowAudioSection(duration: -1))
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
        XCTAssertEqual(record.storedAudioAvailability(), .available(fileURL))
        XCTAssertEqual(try record.deleteExistingAudioFile()?.path, fileURL.path)
        XCTAssertFalse(record.hasStoredAudioFile())
    }

    func testStoredAudioRecordDeleteAndClearOnlyClearsReferenceWhenFileWasDeleted() throws {
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

        XCTAssertEqual(try record.deleteExistingAudioFileAndClearReference()?.path, fileURL.path)
        XCTAssertNil(record.audioFileURL)
        XCTAssertNil(try record.deleteExistingAudioFileAndClearReference())

        record.audioFileURL = "missing-recording.m4a"
        XCTAssertNil(try record.deleteExistingAudioFileAndClearReference())
        XCTAssertEqual(record.audioFileURL, "missing-recording.m4a")
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
