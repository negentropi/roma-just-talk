import Foundation
@testable import VoiceInkCore

final class PerformanceAnalysisTests: XCTestCase {
    func testAnalyzeBuildsSummaryAndSortedModelStats() {
        let analysis = VoiceInkPerformanceAnalyzer.analyze(records: [
            Record(
                audioDuration: 10,
                transcriptionModelName: "fast",
                transcriptionDuration: 2,
                enhancementModelName: "gpt",
                enhancementDuration: 1,
                enhancedText: "enhanced"
            ),
            Record(
                audioDuration: 20,
                transcriptionModelName: "fast",
                transcriptionDuration: 4,
                enhancementModelName: "gpt",
                enhancementDuration: 3,
                enhancedText: nil
            ),
            Record(
                audioDuration: 20,
                transcriptionModelName: "slow",
                transcriptionDuration: 10,
                enhancementModelName: nil,
                enhancementDuration: nil,
                enhancedText: nil
            ),
            Record(
                audioDuration: 5,
                transcriptionModelName: nil,
                transcriptionDuration: nil,
                enhancementModelName: "gpt",
                enhancementDuration: nil,
                enhancedText: "ignored without duration"
            )
        ])

        XCTAssertEqual(analysis.totalTranscripts, 4)
        XCTAssertEqual(analysis.totalWithTranscriptionData, 3)
        XCTAssertEqual(analysis.totalAudioDuration, 55)
        XCTAssertEqual(analysis.totalEnhancedFiles, 1)
        XCTAssertEqual(analysis.transcriptionModels.map(\.name), ["fast", "slow"])
        XCTAssertEqual(analysis.transcriptionModels[0].sampleCount, 2)
        XCTAssertEqual(analysis.transcriptionModels[0].totalProcessingTime, 6)
        XCTAssertEqual(analysis.transcriptionModels[0].avgProcessingTime, 3)
        XCTAssertEqual(analysis.transcriptionModels[0].avgAudioDuration, 15)
        XCTAssertEqual(analysis.transcriptionModels[0].speedFactor, 5)
        XCTAssertEqual(analysis.enhancementModels.map(\.name), ["gpt"])
        XCTAssertEqual(analysis.enhancementModels[0].sampleCount, 2)
        XCTAssertEqual(analysis.enhancementModels[0].avgProcessingTime, 2)
    }

    func testStatsCanRequirePositiveDurationsForSessionMetricPanels() {
        let stats = VoiceInkPerformanceAnalyzer.transcriptionModelStats(
            from: [
                Record(audioDuration: 10, transcriptionModelName: "fast", transcriptionDuration: 2),
                Record(audioDuration: 10, transcriptionModelName: "zero", transcriptionDuration: 0),
                Record(audioDuration: 10, transcriptionModelName: "negative", transcriptionDuration: -1)
            ],
            requirePositiveDuration: true
        )

        XCTAssertEqual(stats.map(\.name), ["fast"])
    }

    func testDefaultStatsPreserveHistoricalAnalyzerNilOnlyFiltering() {
        let stats = VoiceInkPerformanceAnalyzer.transcriptionModelStats(from: [
            Record(audioDuration: 10, transcriptionModelName: "zero", transcriptionDuration: 0),
            Record(audioDuration: 10, transcriptionModelName: "missing", transcriptionDuration: nil)
        ])

        XCTAssertEqual(stats.map(\.name), ["zero"])
        XCTAssertEqual(stats[0].speedFactor, 0)
    }

    func testModelStatFormatsSpeedFactorForSharedPresentation() {
        let stat = VoiceInkPerformanceModelStat(
            name: "fast",
            sampleCount: 1,
            totalProcessingTime: 2,
            avgProcessingTime: 2,
            avgAudioDuration: 10,
            speedFactor: 5.04
        )

        XCTAssertEqual(stat.speedFactorText, "5.0x")
    }
}

private struct Record: VoiceInkPerformanceRecord {
    let audioDuration: TimeInterval
    let transcriptionModelName: String?
    let transcriptionDuration: TimeInterval?
    let enhancementModelName: String?
    let enhancementDuration: TimeInterval?
    let enhancedText: String?

    init(
        audioDuration: TimeInterval,
        transcriptionModelName: String? = nil,
        transcriptionDuration: TimeInterval? = nil,
        enhancementModelName: String? = nil,
        enhancementDuration: TimeInterval? = nil,
        enhancedText: String? = nil
    ) {
        self.audioDuration = audioDuration
        self.transcriptionModelName = transcriptionModelName
        self.transcriptionDuration = transcriptionDuration
        self.enhancementModelName = enhancementModelName
        self.enhancementDuration = enhancementDuration
        self.enhancedText = enhancedText
    }

    var performanceAudioDuration: TimeInterval { audioDuration }
    var performanceTranscriptionModelName: String? { transcriptionModelName }
    var performanceTranscriptionDuration: TimeInterval? { transcriptionDuration }
    var performanceEnhancementModelName: String? { enhancementModelName }
    var performanceEnhancementDuration: TimeInterval? { enhancementDuration }
    var performanceEnhancedText: String? { enhancedText }
}
