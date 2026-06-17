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
}
