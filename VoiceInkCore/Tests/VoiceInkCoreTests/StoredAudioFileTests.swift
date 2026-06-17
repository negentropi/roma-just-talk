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
}
