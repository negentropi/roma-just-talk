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

    func testIOSVisualizerBarPolicyPreservesGeometryInputs() {
        XCTAssertEqual(VoiceInkAudioMeterLevel.iOSVisualizerBarCount, 8)
        XCTAssertEqual(VoiceInkAudioMeterLevel.iOSVisualizerMinimumBarHeight, 4)
    }

    func testIOSVisualizerLevelSamplesRecentHistoryAndClampsLevels() {
        let levels: [Float] = [0.2, 0.5, 1.4, -0.3]

        XCTAssertEqual(
            VoiceInkAudioMeterLevel.visualizerLevel(forBarAt: 0, levels: levels, barCount: 4),
            0
        )
        XCTAssertEqual(
            VoiceInkAudioMeterLevel.visualizerLevel(forBarAt: 1, levels: levels, barCount: 4),
            1
        )
        XCTAssertEqual(
            VoiceInkAudioMeterLevel.visualizerLevel(forBarAt: 2, levels: levels, barCount: 4),
            0.5
        )
        XCTAssertEqual(
            VoiceInkAudioMeterLevel.visualizerLevel(forBarAt: 3, levels: levels, barCount: 4),
            0.2
        )
    }

    func testIOSVisualizerLevelHandlesEmptyHistoryAndNonPositiveBarCount() {
        XCTAssertEqual(VoiceInkAudioMeterLevel.visualizerLevel(forBarAt: 0, levels: []), 0)
        XCTAssertEqual(
            VoiceInkAudioMeterLevel.visualizerLevel(forBarAt: 0, levels: [0.5], barCount: 0),
            0
        )
        XCTAssertEqual(
            VoiceInkAudioMeterLevel.visualizerLevel(forBarAt: -1, levels: [0.5], barCount: 1),
            0
        )
    }
}
