import Foundation
import XCTest
import VoiceInkCore
@testable import roma_just_talk

final class IOSRecordingAppIntentTests: XCTestCase {
    func testRequestStoreConsumesEachRequestOnce() {
        let suiteName = "IOSRecordingAppIntentTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        IOSRecordingAppIntentRequestStore.submit(
            .start,
            defaults: defaults,
            notificationCenter: NotificationCenter()
        )

        XCTAssertEqual(IOSRecordingAppIntentRequestStore.consume(defaults: defaults), .start)
        XCTAssertNil(IOSRecordingAppIntentRequestStore.consume(defaults: defaults))
    }

    func testStartOnlyRunsFromIdle() {
        XCTAssertEqual(
            IOSRecordingAppIntentPolicy.runtimeAction(for: .start, recordingState: .idle),
            .start
        )
        XCTAssertEqual(
            IOSRecordingAppIntentPolicy.runtimeAction(for: .start, recordingState: .recording),
            .ignore
        )
    }

    func testStopAndCancelRequireActiveRecording() {
        XCTAssertEqual(
            IOSRecordingAppIntentPolicy.runtimeAction(for: .stop, recordingState: .recording),
            .stop
        )
        XCTAssertEqual(
            IOSRecordingAppIntentPolicy.runtimeAction(for: .cancel, recordingState: .recording),
            .cancel
        )
        XCTAssertEqual(
            IOSRecordingAppIntentPolicy.runtimeAction(for: .stop, recordingState: .idle),
            .ignore
        )
        XCTAssertEqual(
            IOSRecordingAppIntentPolicy.runtimeAction(for: .cancel, recordingState: .transcribing),
            .ignore
        )
    }
}
