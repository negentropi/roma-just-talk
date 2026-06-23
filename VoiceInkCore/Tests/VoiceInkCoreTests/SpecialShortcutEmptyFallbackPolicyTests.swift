import Foundation
@testable import VoiceInkCore

final class SpecialShortcutEmptyFallbackPolicyTests: XCTestCase {
    func testRecordingShortcutTimingPolicyPreservesMacOSThresholds() {
        XCTAssertEqual(VoiceInkRecordingShortcutTimingPolicy.pressCooldown, 0.08)
        XCTAssertEqual(VoiceInkRecordingShortcutTimingPolicy.hybridPushToTalkThreshold, 0.5)
    }

    func testRecordingShortcutTimingPolicyDetectsPressCooldown() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)

        XCTAssertFalse(
            VoiceInkRecordingShortcutTimingPolicy.isPressWithinCooldown(
                lastPressTime: nil,
                now: now
            )
        )
        XCTAssertTrue(
            VoiceInkRecordingShortcutTimingPolicy.isPressWithinCooldown(
                lastPressTime: now.addingTimeInterval(-0.079),
                now: now
            )
        )
        XCTAssertFalse(
            VoiceInkRecordingShortcutTimingPolicy.isPressWithinCooldown(
                lastPressTime: now.addingTimeInterval(-0.08),
                now: now
            )
        )
    }

    func testRecordingShortcutTimingPolicyHybridStopRequiresThresholdAndRecordingState() {
        XCTAssertFalse(
            VoiceInkRecordingShortcutTimingPolicy.shouldStopHybridRecording(
                pressDuration: 0.499,
                recordingState: .recording
            )
        )
        XCTAssertTrue(
            VoiceInkRecordingShortcutTimingPolicy.shouldStopHybridRecording(
                pressDuration: 0.5,
                recordingState: .recording
            )
        )
        XCTAssertFalse(
            VoiceInkRecordingShortcutTimingPolicy.shouldStopHybridRecording(
                pressDuration: 0.5,
                recordingState: .idle
            )
        )
    }

    func testRecordingShortcutTimingPolicyConvertsSleepDelaySafely() {
        XCTAssertEqual(
            VoiceInkRecordingShortcutTimingPolicy.sleepNanoseconds(delaySeconds: 0.25),
            250_000_000
        )
        XCTAssertEqual(
            VoiceInkRecordingShortcutTimingPolicy.sleepNanoseconds(delaySeconds: -1),
            0
        )
        XCTAssertEqual(
            VoiceInkRecordingShortcutTimingPolicy.sleepNanoseconds(delaySeconds: .infinity),
            0
        )
        XCTAssertEqual(
            VoiceInkRecordingShortcutTimingPolicy.sleepNanoseconds(delaySeconds: .greatestFiniteMagnitude),
            UInt64.max
        )
    }

    func testShortPressSchedulesEmptyTapFallbackOnlyBelowThreshold() {
        XCTAssertTrue(
            VoiceInkSpecialShortcutEmptyFallbackPolicy.shouldScheduleFallback(pressDuration: 0.319)
        )
        XCTAssertFalse(
            VoiceInkSpecialShortcutEmptyFallbackPolicy.shouldScheduleFallback(pressDuration: 0.32)
        )
        XCTAssertFalse(
            VoiceInkSpecialShortcutEmptyFallbackPolicy.shouldScheduleFallback(pressDuration: 0.5)
        )
    }

    func testConsumeFallbackRequiresFreshCompletedEmptyTranscription() {
        let createdAt = Date(timeIntervalSinceReferenceDate: 1_000)
        let now = createdAt.addingTimeInterval(29.9)

        XCTAssertTrue(
            VoiceInkSpecialShortcutEmptyFallbackPolicy.shouldConsumeFallback(
                createdAt: createdAt,
                now: now,
                transcriptionStatus: .completed,
                rawText: " \n ",
                enhancedText: nil
            )
        )
        XCTAssertTrue(
            VoiceInkSpecialShortcutEmptyFallbackPolicy.shouldConsumeFallback(
                createdAt: createdAt,
                now: now,
                transcriptionStatus: .completed,
                rawText: "",
                enhancedText: "  "
            )
        )
    }

    func testConsumeFallbackRejectsStalePendingOrNonEmptyTranscriptions() {
        let createdAt = Date(timeIntervalSinceReferenceDate: 1_000)

        XCTAssertFalse(
            VoiceInkSpecialShortcutEmptyFallbackPolicy.shouldConsumeFallback(
                createdAt: createdAt,
                now: createdAt.addingTimeInterval(30.1),
                transcriptionStatus: .completed,
                rawText: "",
                enhancedText: nil
            )
        )
        XCTAssertFalse(
            VoiceInkSpecialShortcutEmptyFallbackPolicy.shouldConsumeFallback(
                createdAt: createdAt,
                now: createdAt,
                transcriptionStatus: .pending,
                rawText: "",
                enhancedText: nil
            )
        )
        XCTAssertFalse(
            VoiceInkSpecialShortcutEmptyFallbackPolicy.shouldConsumeFallback(
                createdAt: createdAt,
                now: createdAt,
                transcriptionStatus: nil,
                rawText: "",
                enhancedText: nil
            )
        )
        XCTAssertFalse(
            VoiceInkSpecialShortcutEmptyFallbackPolicy.shouldConsumeFallback(
                createdAt: createdAt,
                now: createdAt,
                transcriptionStatus: .completed,
                rawText: "hello",
                enhancedText: nil
            )
        )
        XCTAssertFalse(
            VoiceInkSpecialShortcutEmptyFallbackPolicy.shouldConsumeFallback(
                createdAt: createdAt,
                now: createdAt,
                transcriptionStatus: .completed,
                rawText: "",
                enhancedText: "hello"
            )
        )
    }
}
