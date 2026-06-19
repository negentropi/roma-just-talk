import Foundation
@testable import VoiceInkCore

final class AudioMeterLevelTests: XCTestCase {
    func testVisualizerAccessibilityLabelPreservesIOSCopy() {
        XCTAssertEqual(VoiceInkAudioMeterLevel.visualizerAccessibilityLabel, "Audio level visualizer")
    }

    func testNormalizedLevelClampsBelowAndAboveVisibleDecibelRange() {
        XCTAssertEqual(VoiceInkAudioMeterLevel.normalizedLevel(forDecibels: -80), 0)
        XCTAssertEqual(VoiceInkAudioMeterLevel.normalizedLevel(forDecibels: 0), 1)
        XCTAssertEqual(VoiceInkAudioMeterLevel.normalizedLevel(forDecibels: 12), 1)
    }

    func testNormalizedLevelPreservesExistingMinusSixtyToZeroDecibelMapping() {
        XCTAssertEqual(VoiceInkAudioMeterLevel.normalizedLevel(forDecibels: -60), 0)
        XCTAssertEqual(VoiceInkAudioMeterLevel.normalizedLevel(forDecibels: -30), 0.5, accuracy: 0.0001)
        XCTAssertEqual(VoiceInkAudioMeterLevel.normalizedLevel(forDecibels: -15), 0.75, accuracy: 0.0001)
    }

    func testSmoothedLevelPreservesMacOSExponentialMovingAverageWeights() {
        XCTAssertEqual(
            VoiceInkAudioMeterLevel.smoothedLevel(previous: 0.25, current: 0.75),
            0.45,
            accuracy: 0.0001
        )
    }

    func testSmoothedLevelClampsCustomPreviousWeight() {
        XCTAssertEqual(
            VoiceInkAudioMeterLevel.smoothedLevel(previous: 0.25, current: 0.75, previousWeight: -1),
            0.75,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            VoiceInkAudioMeterLevel.smoothedLevel(previous: 0.25, current: 0.75, previousWeight: 2),
            0.25,
            accuracy: 0.0001
        )
    }

    func testBoundedHistoryKeepsMostRecentLevels() {
        let history = VoiceInkAudioMeterLevel.boundedHistory(
            appending: 4,
            to: [1, 2, 3],
            limit: 3
        )

        XCTAssertEqual(history, [2, 3, 4])
    }

    func testBoundedHistoryRejectsNonPositiveLimit() {
        XCTAssertEqual(
            VoiceInkAudioMeterLevel.boundedHistory(appending: 1, to: [0], limit: 0),
            []
        )
    }

    func testUpdateCadencesPreservePlatformAudioMeterBehavior() {
        XCTAssertEqual(VoiceInkAudioMeterLevel.macOSUpdateIntervalMilliseconds, 17)
        XCTAssertEqual(VoiceInkAudioMeterLevel.iOSUpdateInterval, 0.1)
    }
}
