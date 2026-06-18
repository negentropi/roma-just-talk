import XCTest
import VoiceInkCore
@testable import VoiceInk_ios

final class VoiceInkIOSTests: XCTestCase {
    func testRecordDeepLinkRoundTripsThroughSharedShellURL() throws {
        let url = VoiceInkAppDeepLink.record.url

        XCTAssertEqual(url.absoluteString, "voiceink://record")
        XCTAssertEqual(VoiceInkAppDeepLink(url: url), .record)
        XCTAssertNil(VoiceInkAppDeepLink(url: try XCTUnwrap(URL(string: "voiceink://settings"))))
    }

    func testStorageDirectoryAdaptersUseSharedCorePolicies() {
        let documentsDirectory = VoiceInkIOSStorageDirectories.documentsDirectory

        XCTAssertEqual(
            VoiceInkIOSStorageDirectories.recordingsDirectory,
            VoiceInkStoredAudioFile.recordingsDirectory(in: documentsDirectory)
        )
        XCTAssertEqual(
            VoiceInkIOSStorageDirectories.modelsDirectory,
            VoiceInkWhisperModelFiles.modelsDirectory(in: documentsDirectory)
        )
    }

    func testDefaultModeUsesSharedCoreLocalWhisperPolicy() throws {
        let defaultSelection = Mode.defaultModesAndSelection()
        let mode = try XCTUnwrap(defaultSelection.modes.first)

        XCTAssertEqual(defaultSelection.modes.count, 1)
        XCTAssertEqual(defaultSelection.selectedModeId, mode.id)
        XCTAssertEqual(mode.transcriptionProvider, .localWhisper)
        XCTAssertEqual(mode.transcriptionModel, VoiceInkTranscriptionModelCatalog.localBaseModel)
        XCTAssertFalse(mode.isPostProcessingEnabled)
    }

    func testRetryServiceMarksNoteFailedWhenRetranscriptionFails() async throws {
        let audioFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")
        try Data([0]).write(to: audioFileURL)
        defer { try? FileManager.default.removeItem(at: audioFileURL) }

        let note = Transcription(
            text: "old text",
            duration: 1,
            audioFileURL: audioFileURL.path,
            transcriptionStatus: .pending
        )
        let service = TranscriptionRetryService { _ in
            throw VoiceInkEngineError.transcriptionFailed
        }

        do {
            _ = try await service.retranscribe(note: note)
            XCTFail("Retranscription should throw")
        } catch {
            XCTAssertEqual(note.text, "old text")
            XCTAssertEqual(note.transcriptionStatus, .failed)
            XCTAssertEqual(note.transcriptionError, VoiceInkEngineError.transcriptionFailed.errorDescription)
        }
    }
}
