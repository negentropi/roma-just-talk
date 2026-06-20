import XCTest
import VoiceInkCore
@testable import VoiceInk_ios

final class VoiceInkIOSTests: XCTestCase {
    func testRecordDeepLinkRoundTripsThroughSharedShellURL() throws {
        let url = VoiceInkAppDeepLink.record.url

        XCTAssertEqual(url, VoiceInkAppIdentity.iOSRecordDeepLinkURL)
        XCTAssertEqual(url.scheme, VoiceInkAppIdentity.iOSRecordDeepLinkScheme)
        XCTAssertEqual(url.host, VoiceInkAppIdentity.iOSRecordDeepLinkHost)
        XCTAssertEqual(VoiceInkAppDeepLink(url: url), .record)
        XCTAssertNil(VoiceInkAppDeepLink(url: try XCTUnwrap(URL(string: "voiceink://settings"))))
    }

    func testKeyboardRecordingButtonPresentationUsesSharedDisplayNameForFallback() {
        XCTAssertEqual(
            VoiceInkKeyboardRecordingButtonPresentation.openAppFallback.title,
            " Open \(VoiceInkAppIdentity.displayName)"
        )
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

    func testTranscriptionFeedsSharedDashboardMetrics() throws {
        let note = Transcription(
            text: "raw words ignored",
            duration: 5,
            enhancedText: "enhanced words count here",
            transcriptionDuration: 2,
            enhancementDuration: 1
        )

        var accumulator = VoiceInkDashboardMetricsAccumulator()
        accumulator.add(note)

        XCTAssertEqual(
            accumulator.summary(totalCount: 1),
            VoiceInkDashboardMetricsSummary(
                totalCount: 1,
                totalWords: 4,
                totalDuration: 5
            )
        )
    }

    func testTranscriptionFeedsSharedPerformanceAnalyzer() throws {
        let note = Transcription(
            text: "raw",
            duration: 12,
            enhancedText: "enhanced",
            transcriptionModelName: "fast-local",
            aiEnhancementModelName: "cleaner",
            transcriptionDuration: 3,
            enhancementDuration: 2
        )

        let analysis = VoiceInkPerformanceAnalyzer.analyze(records: [note])

        XCTAssertEqual(analysis.totalTranscripts, 1)
        XCTAssertEqual(analysis.totalWithTranscriptionData, 1)
        XCTAssertEqual(analysis.totalAudioDuration, 12)
        XCTAssertEqual(analysis.totalEnhancedFiles, 1)
        XCTAssertEqual(
            analysis.transcriptionModels,
            [
                VoiceInkPerformanceModelStat(
                    name: "fast-local",
                    sampleCount: 1,
                    totalProcessingTime: 3,
                    avgProcessingTime: 3,
                    avgAudioDuration: 12,
                    speedFactor: 4
                )
            ]
        )
        XCTAssertEqual(
            analysis.enhancementModels,
            [
                VoiceInkPerformanceModelStat(
                    name: "cleaner",
                    sampleCount: 1,
                    totalProcessingTime: 2,
                    avgProcessingTime: 2,
                    avgAudioDuration: 12,
                    speedFactor: 6
                )
            ]
        )
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

    func testAppGroupRecordingBridgeKeepsFreshRecordingState() throws {
        let defaults = try makeIsolatedDefaults()
        let timestamp = Date(timeIntervalSince1970: 100)

        VoiceInkAppGroupRecordingBridge.writeRecordingState(true, to: defaults, now: timestamp)
        let state = VoiceInkAppGroupRecordingBridge.recordingState(
            in: defaults,
            now: timestamp.addingTimeInterval(VoiceInkAppGroupRecordingBridge.staleRecordingInterval)
        )

        XCTAssertEqual(state, VoiceInkAppGroupRecordingState(isRecording: true, shouldClearStaleState: false))
    }

    func testAppGroupRecordingBridgeMarksStaleRecordingStateForClearing() throws {
        let defaults = try makeIsolatedDefaults()
        let timestamp = Date(timeIntervalSince1970: 100)

        VoiceInkAppGroupRecordingBridge.writeRecordingState(true, to: defaults, now: timestamp)
        let state = VoiceInkAppGroupRecordingBridge.recordingState(
            in: defaults,
            now: timestamp.addingTimeInterval(VoiceInkAppGroupRecordingBridge.staleRecordingInterval + 1)
        )

        XCTAssertEqual(state, VoiceInkAppGroupRecordingState(isRecording: false, shouldClearStaleState: true))
    }

    func testAppGroupRecordingBridgeStopRequestRefreshesTimestampWithoutChangingRecordingFlag() throws {
        let defaults = try makeIsolatedDefaults()
        let recordingStart = Date(timeIntervalSince1970: 100)
        let stopRequest = Date(timeIntervalSince1970: 110)

        VoiceInkAppGroupRecordingBridge.writeRecordingState(true, to: defaults, now: recordingStart)
        VoiceInkAppGroupRecordingBridge.markStopRequested(in: defaults, now: stopRequest)

        XCTAssertTrue(defaults.bool(forKey: VoiceInkAppGroupRecordingBridge.UserDefaultsKey.isRecording))
        XCTAssertEqual(
            defaults.double(forKey: VoiceInkAppGroupRecordingBridge.UserDefaultsKey.lastRecordingTimestamp),
            stopRequest.timeIntervalSince1970
        )
    }

    private func makeIsolatedDefaults() throws -> UserDefaults {
        let suiteName = "VoiceInkIOSTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }
}
