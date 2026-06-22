import Foundation
@testable import VoiceInkCore

final class SessionMetricPolicyTests: XCTestCase {
    func testValuesUseEnhancedTextForWordCountWhenEnhancementWasAttempted() {
        let values = VoiceInkSessionMetricPolicy.values(for: Source(
            text: "raw words",
            enhancedText: "enhanced words count here",
            duration: 12,
            transcriptionDuration: 3,
            enhancementDuration: 2
        ))

        XCTAssertEqual(values.wordCount, 4)
        XCTAssertEqual(values.audioDuration, 12)
        XCTAssertEqual(values.transcriptionDuration, 3)
        XCTAssertEqual(values.speedFactor, 4)
        XCTAssertEqual(values.enhancementDuration, 2)
    }

    func testValuesUseRawTextWhenEnhancementDurationIsMissing() {
        let values = VoiceInkSessionMetricPolicy.values(for: Source(
            text: "raw words",
            enhancedText: "enhanced words count here",
            duration: 12,
            transcriptionDuration: 3,
            enhancementDuration: nil
        ))

        XCTAssertEqual(values.wordCount, 2)
    }

    func testValuesClampNonPositiveDurationsAndSkipSpeedFactor() {
        let values = VoiceInkSessionMetricPolicy.values(for: Source(
            text: "raw words",
            enhancedText: "enhanced words",
            duration: -4,
            transcriptionDuration: 0,
            enhancementDuration: -1
        ))

        XCTAssertEqual(values.audioDuration, 0)
        XCTAssertNil(values.transcriptionDuration)
        XCTAssertNil(values.speedFactor)
        XCTAssertNil(values.enhancementDuration)
    }

    func testRecorderDraftPreservesSourceAndMetricFields() {
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000456")!
        let timestamp = Date(timeIntervalSince1970: 1_234)

        let draft = VoiceInkSessionMetricPolicy.recorderDraft(
            transcriptionId: id,
            timestamp: timestamp,
            source: Source(
                text: "raw words",
                enhancedText: "enhanced words count",
                duration: 12,
                transcriptionDuration: 3,
                enhancementDuration: 2
            ),
            transcriptionModelName: "Whisper",
            powerModeName: "Focus",
            aiEnhancementModelName: "GPT"
        )

        XCTAssertEqual(draft.transcriptionId, id)
        XCTAssertEqual(draft.timestamp, timestamp)
        XCTAssertEqual(draft.source, "recorder")
        XCTAssertEqual(draft.wordCount, 3)
        XCTAssertEqual(draft.audioDuration, 12)
        XCTAssertEqual(draft.transcriptionModelName, "Whisper")
        XCTAssertEqual(draft.transcriptionDuration, 3)
        XCTAssertEqual(draft.speedFactor, 4)
        XCTAssertEqual(draft.powerModeName, "Focus")
        XCTAssertEqual(draft.aiEnhancementModelName, "GPT")
        XCTAssertEqual(draft.enhancementDuration, 2)
        XCTAssertEqual(VoiceInkSessionMetricPolicy.completedTranscriptionStatusRawValue, "completed")
    }

    func testMigrationPreferencePreservesCompletionStorageKey() {
        withTemporaryDefaults { defaults in
            XCTAssertEqual(VoiceInkSessionMetricMigrationPreference.completionKey, "HasCompletedStatsMigration")
            XCTAssertFalse(VoiceInkSessionMetricMigrationPreference.isCompleted(in: defaults))

            VoiceInkSessionMetricMigrationPreference.markCompleted(in: defaults)

            XCTAssertTrue(VoiceInkSessionMetricMigrationPreference.isCompleted(in: defaults))
            XCTAssertTrue(defaults.bool(forKey: "HasCompletedStatsMigration"))
        }
    }

    private func withTemporaryDefaults(_ test: (UserDefaults) -> Void) {
        let suiteName = "VoiceInkCore.SessionMetricPolicyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        test(defaults)
    }
}

private struct Source: VoiceInkSessionMetricSource {
    let text: String
    let enhancedText: String?
    let duration: TimeInterval
    let transcriptionDuration: TimeInterval?
    let enhancementDuration: TimeInterval?
}
