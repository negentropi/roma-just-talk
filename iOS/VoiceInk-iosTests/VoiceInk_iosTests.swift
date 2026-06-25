import XCTest
import VoiceInkCore
@testable import VoiceInk_ios

final class VoiceInkIOSTests: XCTestCase {
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
        var notifications: [String] = []

        apply(
            VoiceInkAppGroupRecordingStatePolicy.recordingStateMutationPlan(
                isRecording: true,
                now: timestamp
            ),
            to: defaults,
            notifications: &notifications
        )
        let readPlan = VoiceInkAppGroupRecordingBridge.recordingStateReadPlan(
            in: defaults,
            now: timestamp.addingTimeInterval(VoiceInkAppGroupRecordingStatePolicy.staleRecordingInterval)
        )
        let state = readPlan.applyRuntimeState { mutationPlan in
            apply(
                mutationPlan,
                to: defaults,
                notifications: &notifications
            )
        }

        XCTAssertEqual(state, VoiceInkAppGroupRecordingState(isRecording: true, shouldClearStaleState: false))
        XCTAssertEqual(notifications, [VoiceInkAppIdentity.iOSRecordingStateChangedDarwinNotificationName])
    }

    func testAppGroupRecordingBridgeMarksStaleRecordingStateForClearing() throws {
        let defaults = try makeIsolatedDefaults()
        let timestamp = Date(timeIntervalSince1970: 100)
        let staleReadTime = timestamp.addingTimeInterval(
            VoiceInkAppGroupRecordingStatePolicy.staleRecordingInterval + 1
        )
        var notifications: [String] = []

        apply(
            VoiceInkAppGroupRecordingStatePolicy.recordingStateMutationPlan(
                isRecording: true,
                now: timestamp
            ),
            to: defaults,
            notifications: &notifications
        )
        let readPlan = VoiceInkAppGroupRecordingBridge.recordingStateReadPlan(
            in: defaults,
            now: staleReadTime
        )

        let state = readPlan.applyRuntimeState { mutationPlan in
            apply(
                mutationPlan,
                to: defaults,
                notifications: &notifications
            )
        }

        XCTAssertEqual(state, VoiceInkAppGroupRecordingState(isRecording: false, shouldClearStaleState: true))
        XCTAssertFalse(defaults.bool(forKey: VoiceInkAppGroupRecordingStatePolicy.UserDefaultsKey.isRecording))
        XCTAssertEqual(
            defaults.double(forKey: VoiceInkAppGroupRecordingStatePolicy.UserDefaultsKey.lastRecordingTimestamp),
            staleReadTime.timeIntervalSince1970
        )
        XCTAssertEqual(notifications, [
            VoiceInkAppIdentity.iOSRecordingStateChangedDarwinNotificationName,
            VoiceInkAppIdentity.iOSRecordingStateChangedDarwinNotificationName
        ])
    }

    func testAppGroupRecordingBridgeStopRequestRefreshesTimestampWithoutChangingRecordingFlag() throws {
        let defaults = try makeIsolatedDefaults()
        let recordingStart = Date(timeIntervalSince1970: 100)
        let stopRequest = Date(timeIntervalSince1970: 110)
        var notifications: [String] = []

        apply(
            VoiceInkAppGroupRecordingStatePolicy.recordingStateMutationPlan(
                isRecording: true,
                now: recordingStart
            ),
            to: defaults,
            notifications: &notifications
        )
        apply(
            VoiceInkAppGroupRecordingStatePolicy.stopRequestedMutationPlan(now: stopRequest),
            to: defaults,
            notifications: &notifications
        )

        XCTAssertTrue(defaults.bool(forKey: VoiceInkAppGroupRecordingStatePolicy.UserDefaultsKey.isRecording))
        XCTAssertEqual(
            defaults.double(forKey: VoiceInkAppGroupRecordingStatePolicy.UserDefaultsKey.lastRecordingTimestamp),
            stopRequest.timeIntervalSince1970
        )
        XCTAssertEqual(notifications, [
            VoiceInkAppIdentity.iOSRecordingStateChangedDarwinNotificationName,
            VoiceInkAppIdentity.iOSStopRecordingDarwinNotificationName
        ])
    }

    private func apply(
        _ mutationPlan: VoiceInkAppGroupRecordingStateMutationPlan,
        to defaults: UserDefaults,
        notifications: inout [String]
    ) {
        mutationPlan.applyRuntimeState(
            applyWritePlan: {
                VoiceInkAppGroupRecordingBridge.apply($0, to: defaults)
            },
            postDarwinNotification: {
                notifications.append($0)
            }
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
