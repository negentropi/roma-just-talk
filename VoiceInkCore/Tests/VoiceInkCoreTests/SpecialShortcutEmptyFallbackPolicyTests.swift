import Foundation
@testable import VoiceInkCore

final class SpecialShortcutEmptyFallbackPolicyTests: XCTestCase {
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
