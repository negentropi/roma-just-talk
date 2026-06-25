import Foundation
@testable import VoiceInkCore

final class PerformanceAnalysisTests: XCTestCase {
    func testAnalyzeBuildsSummaryAndSortedModelStats() {
        let analysis = VoiceInkPerformanceAnalyzer.analyze(records: [
            Record(
                audioDuration: 10,
                transcriptionModelName: "fast",
                transcriptionDuration: 2,
                aiEnhancementModelName: "gpt",
                enhancementDuration: 1,
                enhancedText: "enhanced"
            ),
            Record(
                audioDuration: 20,
                transcriptionModelName: "fast",
                transcriptionDuration: 4,
                aiEnhancementModelName: "gpt",
                enhancementDuration: 3,
                enhancedText: nil
            ),
            Record(
                audioDuration: 20,
                transcriptionModelName: "slow",
                transcriptionDuration: 10,
                aiEnhancementModelName: nil,
                enhancementDuration: nil,
                enhancedText: nil
            ),
            Record(
                audioDuration: 5,
                transcriptionModelName: nil,
                transcriptionDuration: nil,
                aiEnhancementModelName: "gpt",
                enhancementDuration: nil,
                enhancedText: "ignored without duration"
            )
        ])

        XCTAssertEqual(analysis.totalTranscripts, 4)
        XCTAssertEqual(analysis.totalTranscriptsText, "4")
        XCTAssertEqual(analysis.totalWithTranscriptionData, 3)
        XCTAssertEqual(analysis.totalWithTranscriptionDataText, "3")
        XCTAssertEqual(analysis.totalAudioDuration, 55)
        XCTAssertEqual(analysis.totalEnhancedFiles, 1)
        XCTAssertEqual(analysis.totalEnhancedFilesText, "1")
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

    func testModelStatFormatsSharedPresentationText() {
        let stat = VoiceInkPerformanceModelStat(
            name: "fast",
            sampleCount: 1,
            totalProcessingTime: 2,
            avgProcessingTime: 2.34,
            avgAudioDuration: 10,
            speedFactor: 5.04
        )

        XCTAssertEqual(stat.speedFactorText, "5.0x")
        XCTAssertEqual(stat.speedFactorRealtimeText, "5.0x realtime")
        XCTAssertEqual(stat.realTimeComparisonText, "Faster than Real-time")
        XCTAssertEqual(stat.avgProcessingTimeCompactText, "2.34s")
        XCTAssertEqual(stat.avgProcessingTimeSpacedText, "2.34 s")

        let slowerStat = VoiceInkPerformanceModelStat(
            name: "slow",
            sampleCount: 1,
            totalProcessingTime: 10,
            avgProcessingTime: 10,
            avgAudioDuration: 5,
            speedFactor: 0.5
        )

        XCTAssertEqual(slowerStat.realTimeComparisonText, "Slower than Real-time")
    }

    func testSessionMetricSourceDefaultsPerformanceRecordFields() {
        let record = SessionBackedRecord(
            text: "raw",
            enhancedText: "enhanced",
            duration: 12,
            transcriptionDuration: 3,
            enhancementDuration: 2,
            transcriptionModelName: "fast-local",
            aiEnhancementModelName: "cleaner"
        )

        XCTAssertEqual(record.performanceAudioDuration, 12)
        XCTAssertEqual(record.performanceTranscriptionDuration, 3)
        XCTAssertEqual(record.performanceEnhancementDuration, 2)
        XCTAssertEqual(record.performanceEnhancedText, "enhanced")
        XCTAssertEqual(record.transcriptionModelName, "fast-local")
        XCTAssertEqual(record.aiEnhancementModelName, "cleaner")
    }

    func testPerformanceTimeFilterPreservesMacOSPanelStorageAndLabels() {
        XCTAssertEqual(VoiceInkPerformanceTimeFilter.userDefaultsKey, "modelPerfPanelFilter")
        XCTAssertEqual(VoiceInkPerformanceTimeFilter.defaultFilter, .last7Days)
        XCTAssertEqual(VoiceInkPerformanceTimeFilter.allCases, [.last7Days, .last30Days, .thisYear, .allTime])
        XCTAssertEqual(VoiceInkPerformanceTimeFilter.last7Days.label, "Last 7 Days")
        XCTAssertEqual(VoiceInkPerformanceTimeFilter.last30Days.label, "Last 30 Days")
        XCTAssertEqual(VoiceInkPerformanceTimeFilter.thisYear.label, "This Year")
        XCTAssertEqual(VoiceInkPerformanceTimeFilter.allTime.label, "All Time")
        XCTAssertEqual(VoiceInkPerformanceTimeFilter.storedFilter(rawValue: "Last 30 Days"), .last30Days)
        XCTAssertEqual(VoiceInkPerformanceTimeFilter.storedFilter(rawValue: "missing"), .last7Days)
        XCTAssertEqual(VoiceInkPerformanceTimeFilter.storedFilter(rawValue: nil), .last7Days)
    }

    func testPerformanceTimeFilterStartDatesPreserveMacOSPanelWindows() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: 2026,
            month: 6,
            day: 19,
            hour: 12,
            minute: 30
        ))!

        XCTAssertEqual(
            VoiceInkPerformanceTimeFilter.last7Days.startDate(now: now, calendar: calendar),
            now.addingTimeInterval(-7 * 24 * 3600)
        )
        XCTAssertEqual(
            VoiceInkPerformanceTimeFilter.last30Days.startDate(now: now, calendar: calendar),
            now.addingTimeInterval(-30 * 24 * 3600)
        )
        XCTAssertEqual(
            VoiceInkPerformanceTimeFilter.thisYear.startDate(now: now, calendar: calendar),
            calendar.date(from: DateComponents(timeZone: calendar.timeZone, year: 2026, month: 1, day: 1))
        )
        XCTAssertNil(VoiceInkPerformanceTimeFilter.allTime.startDate(now: now, calendar: calendar))
    }

    func testPerformancePresentationPreservesMacOSPanelCopyAndIcons() {
        XCTAssertEqual(VoiceInkPerformancePresentation.modelPerformancePanelTitle, "Model Performance")
        XCTAssertEqual(VoiceInkPerformancePresentation.performanceAnalysisPanelTitle, "Performance Analysis")
        XCTAssertEqual(VoiceInkPerformancePresentation.closeSystemImageName, "xmark")
        XCTAssertEqual(VoiceInkPerformancePresentation.emptyStateSystemImageName, "chart.bar.xaxis")
        XCTAssertEqual(VoiceInkPerformancePresentation.emptyStateTitle, "No data for this period")
        XCTAssertEqual(VoiceInkPerformancePresentation.summarySectionTitle, "Summary")
        XCTAssertEqual(VoiceInkPerformancePresentation.systemInformationSectionTitle, "System Information")
        XCTAssertEqual(VoiceInkPerformancePresentation.transcriptionModelsSectionTitle, "Transcription Models")
        XCTAssertEqual(VoiceInkPerformancePresentation.enhancementModelsSectionTitle, "Enhancement Models")
        XCTAssertEqual(VoiceInkPerformancePresentation.totalSummaryIconSystemName, "doc.text.fill")
        XCTAssertEqual(VoiceInkPerformancePresentation.totalSummaryLabel, "Total")
        XCTAssertEqual(VoiceInkPerformancePresentation.analyzableSummaryIconSystemName, "waveform.path.ecg")
        XCTAssertEqual(VoiceInkPerformancePresentation.analyzableSummaryLabel, "Analyzable")
        XCTAssertEqual(VoiceInkPerformancePresentation.enhancedSummaryIconSystemName, "sparkles")
        XCTAssertEqual(VoiceInkPerformancePresentation.enhancedSummaryLabel, "Enhanced")
        XCTAssertEqual(VoiceInkPerformancePresentation.deviceInfoLabel, "Device")
        XCTAssertEqual(VoiceInkPerformancePresentation.processorInfoLabel, "Processor")
        XCTAssertEqual(VoiceInkPerformancePresentation.memoryInfoLabel, "Memory")
        XCTAssertEqual(VoiceInkPerformancePresentation.averageAudioLabel, "Avg. Audio")
        XCTAssertEqual(VoiceInkPerformancePresentation.averageProcessingLabel, "Avg. Processing")
        XCTAssertEqual(VoiceInkPerformancePresentation.averageEnhancementTimeLabel, "Avg. Enhancement Time")
        XCTAssertEqual(VoiceInkPerformancePresentation.sessionSampleCountText(2), "2 sessions")
        XCTAssertEqual(VoiceInkPerformancePresentation.transcriptSampleCountText(3), "3 transcripts")
        XCTAssertEqual(VoiceInkPerformancePresentation.physicalMemoryText(byteCount: 1_073_741_824), "1 GB")
        XCTAssertEqual(VoiceInkPerformancePresentation.physicalMemoryText(byteCount: 17_179_869_184), "16 GB")
    }
}

private struct Record: VoiceInkPerformanceRecord {
    let audioDuration: TimeInterval
    let transcriptionModelName: String?
    let transcriptionDuration: TimeInterval?
    let aiEnhancementModelName: String?
    let enhancementDuration: TimeInterval?
    let enhancedText: String?

    init(
        audioDuration: TimeInterval,
        transcriptionModelName: String? = nil,
        transcriptionDuration: TimeInterval? = nil,
        aiEnhancementModelName: String? = nil,
        enhancementDuration: TimeInterval? = nil,
        enhancedText: String? = nil
    ) {
        self.audioDuration = audioDuration
        self.transcriptionModelName = transcriptionModelName
        self.transcriptionDuration = transcriptionDuration
        self.aiEnhancementModelName = aiEnhancementModelName
        self.enhancementDuration = enhancementDuration
        self.enhancedText = enhancedText
    }

    var performanceAudioDuration: TimeInterval { audioDuration }
    var performanceTranscriptionDuration: TimeInterval? { transcriptionDuration }
    var performanceEnhancementDuration: TimeInterval? { enhancementDuration }
    var performanceEnhancedText: String? { enhancedText }
}

private struct SessionBackedRecord: VoiceInkPerformanceRecord, VoiceInkSessionMetricSource {
    let text: String
    let enhancedText: String?
    let duration: TimeInterval
    let transcriptionDuration: TimeInterval?
    let enhancementDuration: TimeInterval?
    let transcriptionModelName: String?
    let aiEnhancementModelName: String?
}
