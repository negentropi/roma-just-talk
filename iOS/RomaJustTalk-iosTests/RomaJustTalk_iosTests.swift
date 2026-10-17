import XCTest
import RomaCore
@testable import roma_just_talk

final class RomaIOSTests: XCTestCase {
    func testTranscriptionFeedsSharedDashboardMetrics() throws {
        let note = Transcription(
            text: "raw words ignored",
            duration: 5,
            enhancedText: "enhanced words count here",
            transcriptionDuration: 2,
            enhancementDuration: 1
        )

        var accumulator = RomaDashboardMetricsAccumulator()
        accumulator.add(note)

        XCTAssertEqual(
            accumulator.summary(totalCount: 1),
            RomaDashboardMetricsSummary(
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

        let analysis = RomaPerformanceAnalyzer.analyze(records: [note])

        XCTAssertEqual(analysis.totalTranscripts, 1)
        XCTAssertEqual(analysis.totalWithTranscriptionData, 1)
        XCTAssertEqual(analysis.totalAudioDuration, 12)
        XCTAssertEqual(analysis.totalEnhancedFiles, 1)

        XCTAssertEqual(analysis.transcriptionModels.count, 1)
        let transcriptionModel = try XCTUnwrap(analysis.transcriptionModels.first)
        XCTAssertEqual(transcriptionModel.name, "fast-local")
        XCTAssertEqual(transcriptionModel.sampleCount, 1)
        XCTAssertEqual(transcriptionModel.totalProcessingTime, 3)
        XCTAssertEqual(transcriptionModel.avgProcessingTime, 3)
        XCTAssertEqual(transcriptionModel.avgAudioDuration, 12)
        XCTAssertEqual(transcriptionModel.speedFactor, 4)

        XCTAssertEqual(analysis.enhancementModels.count, 1)
        let enhancementModel = try XCTUnwrap(analysis.enhancementModels.first)
        XCTAssertEqual(enhancementModel.name, "cleaner")
        XCTAssertEqual(enhancementModel.sampleCount, 1)
        XCTAssertEqual(enhancementModel.totalProcessingTime, 2)
        XCTAssertEqual(enhancementModel.avgProcessingTime, 2)
        XCTAssertEqual(enhancementModel.avgAudioDuration, 12)
        XCTAssertEqual(enhancementModel.speedFactor, 6)
    }

    func testAppGroupRecordingBridgeKeepsFreshRecordingState() throws {
        let defaults = try makeIsolatedDefaults()
        let timestamp = Date(timeIntervalSince1970: 100)
        var notifications: [String] = []

        apply(
            RomaAppGroupRecordingStatePolicy.recordingStateMutationPlan(
                isRecording: true,
                now: timestamp
            ),
            to: defaults,
            notifications: &notifications
        )
        let readPlan = RomaAppGroupRecordingBridge.recordingStateReadPlan(
            in: defaults,
            now: timestamp.addingTimeInterval(RomaAppGroupRecordingStatePolicy.staleRecordingInterval)
        )
        let state = readPlan.applyRuntimeState { mutationPlan in
            apply(
                mutationPlan,
                to: defaults,
                notifications: &notifications
            )
        }

        XCTAssertEqual(state, RomaAppGroupRecordingState(isRecording: true, shouldClearStaleState: false))
        XCTAssertEqual(notifications, [RomaAppIdentity.iOSRecordingStateChangedDarwinNotificationName])
    }

    func testAppGroupRecordingBridgeMarksStaleRecordingStateForClearing() throws {
        let defaults = try makeIsolatedDefaults()
        let timestamp = Date(timeIntervalSince1970: 100)
        let staleReadTime = timestamp.addingTimeInterval(
            RomaAppGroupRecordingStatePolicy.staleRecordingInterval + 1
        )
        var notifications: [String] = []

        apply(
            RomaAppGroupRecordingStatePolicy.recordingStateMutationPlan(
                isRecording: true,
                now: timestamp
            ),
            to: defaults,
            notifications: &notifications
        )
        let readPlan = RomaAppGroupRecordingBridge.recordingStateReadPlan(
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

        XCTAssertEqual(state, RomaAppGroupRecordingState(isRecording: false, shouldClearStaleState: true))
        XCTAssertFalse(defaults.bool(forKey: RomaAppGroupRecordingStatePolicy.UserDefaultsKey.isRecording))
        XCTAssertEqual(
            defaults.double(forKey: RomaAppGroupRecordingStatePolicy.UserDefaultsKey.lastRecordingTimestamp),
            staleReadTime.timeIntervalSince1970
        )
        XCTAssertEqual(notifications, [
            RomaAppIdentity.iOSRecordingStateChangedDarwinNotificationName,
            RomaAppIdentity.iOSRecordingStateChangedDarwinNotificationName
        ])
    }

    func testAppGroupRecordingBridgeStopRequestRefreshesTimestampWithoutChangingRecordingFlag() throws {
        let defaults = try makeIsolatedDefaults()
        let recordingStart = Date(timeIntervalSince1970: 100)
        let stopRequest = Date(timeIntervalSince1970: 110)
        var notifications: [String] = []

        apply(
            RomaAppGroupRecordingStatePolicy.recordingStateMutationPlan(
                isRecording: true,
                now: recordingStart
            ),
            to: defaults,
            notifications: &notifications
        )
        apply(
            RomaAppGroupRecordingStatePolicy.stopRequestedMutationPlan(now: stopRequest),
            to: defaults,
            notifications: &notifications
        )

        XCTAssertTrue(defaults.bool(forKey: RomaAppGroupRecordingStatePolicy.UserDefaultsKey.isRecording))
        XCTAssertEqual(
            defaults.double(forKey: RomaAppGroupRecordingStatePolicy.UserDefaultsKey.lastRecordingTimestamp),
            stopRequest.timeIntervalSince1970
        )
        XCTAssertEqual(notifications, [
            RomaAppIdentity.iOSRecordingStateChangedDarwinNotificationName,
            RomaAppIdentity.iOSStopRecordingDarwinNotificationName
        ])
    }

    private func apply(
        _ mutationPlan: RomaAppGroupRecordingStateMutationPlan,
        to defaults: UserDefaults,
        notifications: inout [String]
    ) {
        mutationPlan.applyRuntimeState(
            applyWritePlan: {
                RomaAppGroupRecordingBridge.apply($0, to: defaults)
            },
            postDarwinNotification: {
                notifications.append($0)
            }
        )
    }

    private func makeIsolatedDefaults() throws -> UserDefaults {
        let suiteName = "RomaIOSTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }
}
