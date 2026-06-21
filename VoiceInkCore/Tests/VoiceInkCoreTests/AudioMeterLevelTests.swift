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

    func testMacOSVisualizerGeometryPreservesExistingRecorderShape() {
        XCTAssertEqual(VoiceInkAudioMeterLevel.macOSVisualizerAnimationMinimumInterval, 0.016)
        XCTAssertEqual(VoiceInkAudioMeterLevel.macOSVisualizerBarCount, 15)
        XCTAssertEqual(VoiceInkAudioMeterLevel.macOSVisualizerBarWidth, 3)
        XCTAssertEqual(VoiceInkAudioMeterLevel.macOSVisualizerBarSpacing, 2)
        XCTAssertEqual(VoiceInkAudioMeterLevel.macOSVisualizerMinimumBarHeight, 4)
        XCTAssertEqual(VoiceInkAudioMeterLevel.macOSVisualizerMaximumBarHeight, 28)
        XCTAssertEqual(VoiceInkAudioMeterLevel.macOSVisualizerPhaseStep, 0.4)
        XCTAssertEqual(VoiceInkAudioMeterLevel.macOSVisualizerWaveFrequency, 8)
        XCTAssertEqual(VoiceInkAudioMeterLevel.macOSVisualizerAmplitudeExponent, 0.7)
        XCTAssertEqual(VoiceInkAudioMeterLevel.macOSVisualizerCenterBoostDropoff, 0.4)
    }

    func testMacOSVisualizerBarHeightPreservesExistingWaveAndCenterBoost() {
        XCTAssertEqual(
            VoiceInkAudioMeterLevel.macOSVisualizerBarHeight(
                forBarAt: 0,
                time: 0,
                averagePower: 1,
                isActive: true
            ),
            10.8571428571,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            VoiceInkAudioMeterLevel.macOSVisualizerBarHeight(
                forBarAt: 7,
                time: 0,
                averagePower: 1,
                isActive: true
            ),
            19.562147579,
            accuracy: 0.0001
        )
    }

    func testMacOSVisualizerBarHeightUsesMinimumForIdleOrInvalidBars() {
        XCTAssertEqual(
            VoiceInkAudioMeterLevel.macOSVisualizerBarHeight(
                forBarAt: 7,
                time: 0,
                averagePower: 1,
                isActive: false
            ),
            VoiceInkAudioMeterLevel.macOSVisualizerMinimumBarHeight
        )
        XCTAssertEqual(
            VoiceInkAudioMeterLevel.macOSVisualizerBarHeight(
                forBarAt: -1,
                time: 0,
                averagePower: 1,
                isActive: true
            ),
            VoiceInkAudioMeterLevel.macOSVisualizerMinimumBarHeight
        )
    }

    func testIOSVisualizerBarPolicyPreservesGeometryInputs() {
        XCTAssertEqual(VoiceInkAudioMeterLevel.iOSVisualizerBarCount, 8)
        XCTAssertEqual(VoiceInkAudioMeterLevel.iOSVisualizerBarSpacing, 3)
        XCTAssertEqual(VoiceInkAudioMeterLevel.iOSVisualizerBarMinimumWidth, 2)
        XCTAssertEqual(VoiceInkAudioMeterLevel.iOSVisualizerHorizontalPadding, 2)
        XCTAssertEqual(VoiceInkAudioMeterLevel.iOSVisualizerWidthInset, 16)
        XCTAssertEqual(VoiceInkAudioMeterLevel.iOSVisualizerFrameHeight, 48)
        XCTAssertEqual(VoiceInkAudioMeterLevel.iOSVisualizerMinimumBarHeight, 4)
        XCTAssertEqual(VoiceInkAudioMeterLevel.iOSVisualizerAnimationDuration, 0.12)
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

    func testIOSVisualizerBarWidthPreservesExistingLayoutMath() {
        XCTAssertEqual(
            VoiceInkAudioMeterLevel.iOSVisualizerBarWidth(containerWidth: 96),
            7,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            VoiceInkAudioMeterLevel.iOSVisualizerBarWidth(containerWidth: 24),
            VoiceInkAudioMeterLevel.iOSVisualizerBarMinimumWidth,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            VoiceInkAudioMeterLevel.iOSVisualizerBarWidth(containerWidth: 96, barCount: 0),
            VoiceInkAudioMeterLevel.iOSVisualizerBarMinimumWidth,
            accuracy: 0.0001
        )
    }

    func testIOSVisualizerBarHeightPreservesExistingLevelMapping() {
        let levels: [Float] = [0.2, 0.5, 1.0]

        XCTAssertEqual(
            VoiceInkAudioMeterLevel.iOSVisualizerBarHeight(
                forBarAt: 0,
                levels: levels,
                containerHeight: 48
            ),
            48,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            VoiceInkAudioMeterLevel.iOSVisualizerBarHeight(
                forBarAt: 1,
                levels: levels,
                containerHeight: 48
            ),
            26,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            VoiceInkAudioMeterLevel.iOSVisualizerBarHeight(
                forBarAt: 0,
                levels: [],
                containerHeight: 48
            ),
            VoiceInkAudioMeterLevel.iOSVisualizerMinimumBarHeight,
            accuracy: 0.0001
        )
    }
}
