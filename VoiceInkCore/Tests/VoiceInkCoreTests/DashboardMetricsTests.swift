import Foundation
@testable import VoiceInkCore

final class DashboardMetricsTests: XCTestCase {
    func testAccumulatorBuildsSummaryFromMetricRecords() {
        var accumulator = VoiceInkDashboardMetricsAccumulator()

        accumulator.add(Record(wordCount: 120, audioDuration: 60))
        accumulator.add(Record(wordCount: 80, audioDuration: 30))

        XCTAssertEqual(
            accumulator.summary(totalCount: 3),
            VoiceInkDashboardMetricsSummary(
                totalCount: 3,
                totalWords: 200,
                totalDuration: 90
            )
        )
    }

    func testMetricSourceRecordGetsDashboardValuesFromSessionMetricPolicy() {
        var accumulator = VoiceInkDashboardMetricsAccumulator()

        accumulator.add(SourceRecord(
            text: "raw words",
            enhancedText: "enhanced words win",
            duration: -4,
            transcriptionDuration: nil,
            enhancementDuration: 2
        ))

        XCTAssertEqual(
            accumulator.summary(totalCount: 1),
            VoiceInkDashboardMetricsSummary(
                totalCount: 1,
                totalWords: 3,
                totalDuration: 0
            )
        )
    }

    func testDerivedMetricsPreserveDashboardDefaults() {
        let metrics = VoiceInkDashboardMetrics(summary: VoiceInkDashboardMetricsSummary(
            totalCount: 2,
            totalWords: 70,
            totalDuration: 60
        ))

        XCTAssertEqual(metrics.estimatedTypingTime, 120)
        XCTAssertEqual(metrics.timeSaved, 60)
        XCTAssertEqual(metrics.averageWordsPerMinute, 70)
        XCTAssertEqual(metrics.averageWordsPerMinuteDisplayText, "70.0")
        XCTAssertEqual(metrics.totalKeystrokesSaved, 350)
    }

    func testTimeSavedAndAverageWordsPerMinuteHandleZeroAndOverTypingTime() {
        let zeroDuration = VoiceInkDashboardMetrics(summary: VoiceInkDashboardMetricsSummary(
            totalCount: 1,
            totalWords: 70,
            totalDuration: 0
        ))
        XCTAssertEqual(zeroDuration.averageWordsPerMinute, 0)
        XCTAssertNil(zeroDuration.averageWordsPerMinuteDisplayText)
        XCTAssertEqual(zeroDuration.timeSaved, 120)

        let slowerThanTyping = VoiceInkDashboardMetrics(summary: VoiceInkDashboardMetricsSummary(
            totalCount: 1,
            totalWords: 35,
            totalDuration: 120
        ))
        XCTAssertEqual(slowerThanTyping.timeSaved, 0)
    }

    func testDerivedMetricsCanOverrideTypingAndKeystrokeAssumptions() {
        let metrics = VoiceInkDashboardMetrics(
            summary: VoiceInkDashboardMetricsSummary(totalCount: 1, totalWords: 100, totalDuration: 60),
            averageTypingWordsPerMinute: 50,
            keystrokesPerWord: 4
        )

        XCTAssertEqual(metrics.estimatedTypingTime, 120)
        XCTAssertEqual(metrics.timeSaved, 60)
        XCTAssertEqual(metrics.totalKeystrokesSaved, 400)
    }

    func testAverageWordsPerMinuteDisplayTextRoundsToOneDecimalPlace() {
        let metrics = VoiceInkDashboardMetrics(summary: VoiceInkDashboardMetricsSummary(
            totalCount: 1,
            totalWords: 10,
            totalDuration: 12
        ))

        XCTAssertEqual(metrics.averageWordsPerMinuteDisplayText, "50.0")
    }

    func testDashboardPresentationPreservesMacOSDashboardCopy() {
        XCTAssertEqual(VoiceInkDashboardPresentation.metricValuePlaceholder, "–")
        XCTAssertEqual(VoiceInkDashboardPresentation.emptyStateSystemImageName, "waveform")
        XCTAssertEqual(VoiceInkDashboardPresentation.emptyStateTitle, "No sessions yet")
        XCTAssertEqual(VoiceInkDashboardPresentation.emptyStateMessage, "Start a recording; your dictation rhythm will show here.")
        XCTAssertEqual(VoiceInkDashboardPresentation.heroSectionTitle, "Dashboard")
        XCTAssertEqual(VoiceInkDashboardPresentation.readyTitle, "Ready when you are")
        XCTAssertEqual(VoiceInkDashboardPresentation.usageSummaryPendingSubtitle, "Your usage summary will appear here.")
        XCTAssertEqual(VoiceInkDashboardPresentation.firstRecordingSubtitle, "Your first roma-just-talk recording starts the timeline.")
        XCTAssertEqual(VoiceInkDashboardPresentation.timeSavedFallbackTitle, "Time savings coming soon")
        XCTAssertEqual(VoiceInkDashboardPresentation.sessionsPillTitle, "Sessions")
        XCTAssertEqual(VoiceInkDashboardPresentation.wordsPillTitle, "Words")
        XCTAssertEqual(VoiceInkDashboardPresentation.modelPerformanceButtonTitle, "Model Performance")
        XCTAssertEqual(VoiceInkDashboardPresentation.modelPerformanceSystemImageName, "gauge")
        XCTAssertEqual(VoiceInkDashboardPresentation.modelPerformanceHelpText, "View transcription and enhancement model performance")
    }

    func testDashboardPresentationBuildsHeroTitleAndSubtitle() {
        XCTAssertEqual(
            VoiceInkDashboardPresentation.heroTitle(isSnapshotLoaded: false, timeSaved: 120),
            "Ready when you are"
        )
        XCTAssertEqual(
            VoiceInkDashboardPresentation.heroTitle(isSnapshotLoaded: true, timeSaved: 0),
            "Time savings coming soon"
        )
        XCTAssertEqual(
            VoiceInkDashboardPresentation.heroTitle(isSnapshotLoaded: true, timeSaved: 65),
            "1 minute, 5 seconds"
        )
        XCTAssertEqual(
            VoiceInkDashboardPresentation.heroSubtitle(
                isSnapshotLoaded: false,
                totalCount: 0,
                formattedWordCount: "0"
            ),
            "Your usage summary will appear here."
        )
        XCTAssertEqual(
            VoiceInkDashboardPresentation.heroSubtitle(
                isSnapshotLoaded: true,
                totalCount: 0,
                formattedWordCount: "0"
            ),
            "Your first roma-just-talk recording starts the timeline."
        )
        XCTAssertEqual(
            VoiceInkDashboardPresentation.heroSubtitle(
                isSnapshotLoaded: true,
                totalCount: 1,
                formattedWordCount: "320"
            ),
            "Dictated 320 words across 1 session."
        )
        XCTAssertEqual(
            VoiceInkDashboardPresentation.heroSubtitle(
                isSnapshotLoaded: true,
                totalCount: 2,
                formattedWordCount: "1,200"
            ),
            "Dictated 1,200 words across 2 sessions."
        )
        XCTAssertEqual(
            VoiceInkDashboardPresentation.heroSubtitle(
                isSnapshotLoaded: true,
                totalCount: 2,
                totalWords: 1200
            ),
            "Dictated 1,200 words across 2 sessions."
        )
    }

    func testDashboardPresentationBuildsMacOSMetricCards() {
        let metrics = VoiceInkDashboardMetrics(summary: VoiceInkDashboardMetricsSummary(
            totalCount: 2,
            totalWords: 70,
            totalDuration: 60
        ))

        XCTAssertEqual(
            VoiceInkDashboardPresentation.metricCards(isSnapshotLoaded: true, metrics: metrics),
            [
                VoiceInkDashboardMetricCardPresentation(
                    id: "sessions-recorded",
                    iconSystemName: "mic.fill",
                    title: "Sessions Recorded",
                    value: "2",
                    detail: "recordings completed"
                ),
                VoiceInkDashboardMetricCardPresentation(
                    id: "words-dictated",
                    iconSystemName: "text.alignleft",
                    title: "Words Dictated",
                    value: "70",
                    detail: "words generated"
                ),
                VoiceInkDashboardMetricCardPresentation(
                    id: "words-per-minute",
                    iconSystemName: "speedometer",
                    title: "Words Per Minute",
                    value: "70.0",
                    detail: "dictation pace"
                ),
                VoiceInkDashboardMetricCardPresentation(
                    id: "keystrokes-saved",
                    iconSystemName: "keyboard.fill",
                    title: "Keystrokes Saved",
                    value: "350",
                    detail: "fewer keystrokes"
                )
            ]
        )

        XCTAssertEqual(
            VoiceInkDashboardPresentation
                .metricCards(isSnapshotLoaded: false, metrics: metrics)
                .map(\.value),
            Array(repeating: VoiceInkDashboardPresentation.metricValuePlaceholder, count: 4)
        )
    }

    func testNoteListSummaryPresentationBuildsIOSHeaderText() {
        let presentation = VoiceInkNoteListSummaryPresentation.make(from: [
            NoteListRecord(
                wordCount: 120,
                audioDuration: 60,
                transcriptionModelName: "slow",
                transcriptionDuration: 10
            ),
            NoteListRecord(
                wordCount: 80,
                audioDuration: 30,
                transcriptionModelName: "fast",
                transcriptionDuration: 3
            ),
            NoteListRecord(
                wordCount: 10,
                audioDuration: 5,
                transcriptionModelName: nil,
                transcriptionDuration: nil
            )
        ])

        XCTAssertEqual(
            presentation.summary,
            VoiceInkDashboardMetricsSummary(totalCount: 3, totalWords: 210, totalDuration: 95)
        )
        XCTAssertEqual(presentation.countText, "3")
        XCTAssertEqual(presentation.dashboardText, "210 words - 1:35 audio")
        XCTAssertEqual(presentation.fastestModelText, "fast 10.0x realtime")
    }

    func testNoteListSummaryPresentationOmitsFastestModelWhenNoTimedModelExists() {
        let presentation = VoiceInkNoteListSummaryPresentation.make(from: [
            NoteListRecord(
                wordCount: 5,
                audioDuration: 12,
                transcriptionModelName: "zero",
                transcriptionDuration: 0
            ),
            NoteListRecord(
                wordCount: 7,
                audioDuration: 18,
                transcriptionModelName: nil,
                transcriptionDuration: nil
            )
        ])

        XCTAssertEqual(presentation.dashboardText, "12 words - 0:30 audio")
        XCTAssertNil(presentation.fastestModelText)
    }

    func testNoteListPresentationPreservesIOSChromeCopy() {
        XCTAssertEqual(VoiceInkNoteListPresentation.sectionTitle, "Recent")
        XCTAssertEqual(VoiceInkNoteListPresentation.settingsSystemImageName, "gearshape")
        XCTAssertEqual(VoiceInkNoteListPresentation.startRecordingButtonTitle, "Start Recording")
        XCTAssertEqual(VoiceInkNoteListPresentation.startRecordingSystemImageName, "mic.fill")
    }

    func testDashboardPromotionPresentationPreservesMacOSCopyURLsAndDismissalKey() {
        XCTAssertEqual(
            VoiceInkDashboardPromotionPresentation.affiliateDismissedKey,
            "VoiceInkAffiliatePromotionDismissed"
        )
        XCTAssertFalse(VoiceInkDashboardPromotionPresentation.defaultIsAffiliateDismissed)
        XCTAssertEqual(
            VoiceInkDashboardPromotionPresentation.socialShareURL.absoluteString,
            "https://tryvoiceink.com/social-share"
        )
        XCTAssertEqual(
            VoiceInkDashboardPromotionPresentation.affiliateURL.absoluteString,
            "https://tryvoiceink.com/affiliate"
        )
        XCTAssertEqual(VoiceInkDashboardPromotionPresentation.dismissHelpText, "Dismiss this promotion")

        XCTAssertEqual(
            VoiceInkDashboardPromotionPresentation.upgradeCard,
            VoiceInkDashboardPromotionCardPresentation(
                id: .upgrade,
                badge: "30% OFF",
                title: "Unlock VoiceInk Pro For Less",
                message: "Share VoiceInk on your socials, and instantly unlock a 30% discount on VoiceInk Pro.",
                actionTitle: "Share & Unlock",
                actionSystemImageName: "arrow.up.right",
                actionURL: VoiceInkDashboardPromotionPresentation.socialShareURL
            )
        )
        XCTAssertEqual(
            VoiceInkDashboardPromotionPresentation.affiliateCard,
            VoiceInkDashboardPromotionCardPresentation(
                id: .affiliate,
                badge: "AFFILIATE 30%",
                title: "Earn With The VoiceInk Affiliate Program",
                message: "Share VoiceInk with friends or your audience and receive 30% on every referral that upgrades.",
                actionTitle: "Explore Affiliate",
                actionSystemImageName: "arrow.up.right",
                actionURL: VoiceInkDashboardPromotionPresentation.affiliateURL,
                dismissHelpText: "Dismiss this promotion"
            )
        )
    }

    func testDashboardPromotionPolicyMatchesMacOSLicenseVisibilityRules() {
        XCTAssertEqual(
            VoiceInkDashboardPromotionPresentation.cards(
                for: .trial(daysRemaining: 4),
                isAffiliateDismissed: false
            ),
            []
        )
        XCTAssertEqual(
            VoiceInkDashboardPromotionPresentation.cards(
                for: .trial(daysRemaining: 3),
                isAffiliateDismissed: false
            ),
            [VoiceInkDashboardPromotionPresentation.upgradeCard]
        )
        XCTAssertEqual(
            VoiceInkDashboardPromotionPresentation.cards(
                for: .trialExpired,
                isAffiliateDismissed: true
            ),
            [VoiceInkDashboardPromotionPresentation.upgradeCard]
        )
        XCTAssertEqual(
            VoiceInkDashboardPromotionPresentation.cards(
                for: .licensed,
                isAffiliateDismissed: false
            ),
            [VoiceInkDashboardPromotionPresentation.affiliateCard]
        )
        XCTAssertEqual(
            VoiceInkDashboardPromotionPresentation.cards(
                for: .licensed,
                isAffiliateDismissed: true
            ),
            []
        )
    }
}

private struct Record: VoiceInkDashboardMetricRecord {
    let wordCount: Int
    let audioDuration: TimeInterval

    var dashboardWordCount: Int { wordCount }
    var dashboardAudioDuration: TimeInterval { audioDuration }
}

private struct SourceRecord: VoiceInkDashboardMetricRecord, VoiceInkSessionMetricSource {
    let text: String
    let enhancedText: String?
    let duration: TimeInterval
    let transcriptionDuration: TimeInterval?
    let enhancementDuration: TimeInterval?
}

private struct NoteListRecord: VoiceInkDashboardMetricRecord, VoiceInkPerformanceRecord {
    let wordCount: Int
    let audioDuration: TimeInterval
    let transcriptionModelName: String?
    let transcriptionDuration: TimeInterval?

    var dashboardWordCount: Int { wordCount }
    var dashboardAudioDuration: TimeInterval { audioDuration }
    var performanceAudioDuration: TimeInterval { audioDuration }
    var performanceTranscriptionDuration: TimeInterval? { transcriptionDuration }
    let aiEnhancementModelName: String? = nil
    let performanceEnhancementDuration: TimeInterval? = nil
    let performanceEnhancedText: String? = nil
}
