import Foundation
import VoiceInkCore

final class DashboardMetricsTests: XCTestCase {
    func testValuesUseEnhancedTextForWordCountWhenEnhancementWasAttempted() {
        let values = VoiceInkSessionMetricPolicy.values(for: SessionMetricSource(
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
        let values = VoiceInkSessionMetricPolicy.values(for: SessionMetricSource(
            text: "raw words",
            enhancedText: "enhanced words count here",
            duration: 12,
            transcriptionDuration: 3,
            enhancementDuration: nil
        ))

        XCTAssertEqual(values.wordCount, 2)
    }

    func testValuesClampNonPositiveDurationsAndSkipSpeedFactor() {
        let values = VoiceInkSessionMetricPolicy.values(for: SessionMetricSource(
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
            source: SessionMetricSource(
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

    func testDashboardPresentationBuildsHeroPills() {
        let summary = VoiceInkDashboardMetricsSummary(
            totalCount: 1200,
            totalWords: 3456,
            totalDuration: 60
        )

        XCTAssertEqual(
            VoiceInkDashboardPresentation.heroPills(
                isSnapshotLoaded: true,
                summary: summary
            ),
            [
                VoiceInkDashboardHeroPillPresentation(
                    id: "sessions",
                    title: "Sessions",
                    value: "1,200"
                ),
                VoiceInkDashboardHeroPillPresentation(
                    id: "words",
                    title: "Words",
                    value: "3,456"
                )
            ]
        )

        XCTAssertEqual(
            VoiceInkDashboardPresentation
                .heroPills(isSnapshotLoaded: false, summary: summary)
                .map(\.value),
            Array(repeating: VoiceInkDashboardPresentation.metricValuePlaceholder, count: 2)
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

    func testNoteListSnapshotFiltersRawAndEnhancedTextPreservingDisplayedOrder() {
        let snapshot = VoiceInkNoteListSnapshot.make(
            from: [
                NoteListRecord(id: 1, rawText: "meeting recap", enhancedText: nil, wordCount: 5, audioDuration: 10, transcriptionModelName: nil, transcriptionDuration: nil),
                NoteListRecord(id: 2, rawText: "plain draft", enhancedText: "Needle in enhanced text", wordCount: 8, audioDuration: 12, transcriptionModelName: nil, transcriptionDuration: nil),
                NoteListRecord(id: 3, rawText: "needle in raw text", enhancedText: nil, wordCount: 13, audioDuration: 20, transcriptionModelName: nil, transcriptionDuration: nil)
            ],
            query: "needle",
            rawText: \.rawText,
            enhancedText: \.enhancedText
        )

        XCTAssertEqual(snapshot.displayedItems.map(\.id), [2, 3])
        XCTAssertFalse(snapshot.shouldShowEmptyState)
    }

    func testNoteListSnapshotSummaryUsesDisplayedRecordsOnly() {
        let snapshot = VoiceInkNoteListSnapshot.make(
            from: [
                NoteListRecord(id: 1, rawText: "hide", enhancedText: nil, wordCount: 200, audioDuration: 80, transcriptionModelName: "hidden", transcriptionDuration: 2),
                NoteListRecord(id: 2, rawText: "needle", enhancedText: nil, wordCount: 120, audioDuration: 60, transcriptionModelName: "slow", transcriptionDuration: 10),
                NoteListRecord(id: 3, rawText: "needle again", enhancedText: nil, wordCount: 80, audioDuration: 30, transcriptionModelName: "fast", transcriptionDuration: 3)
            ],
            query: "needle",
            rawText: \.rawText,
            enhancedText: \.enhancedText
        )

        XCTAssertEqual(
            snapshot.summaryPresentation.summary,
            VoiceInkDashboardMetricsSummary(totalCount: 2, totalWords: 200, totalDuration: 90)
        )
        XCTAssertEqual(snapshot.summaryPresentation.fastestModelText, "fast 10.0x realtime")
    }

    func testNoteListSnapshotExposesIOSNotesEmptyStateWhenNoRecordsMatch() {
        let snapshot = VoiceInkNoteListSnapshot.make(
            from: [
                NoteListRecord(id: 1, rawText: "meeting recap", enhancedText: nil, wordCount: 5, audioDuration: 10, transcriptionModelName: nil, transcriptionDuration: nil)
            ],
            query: "missing",
            rawText: \.rawText,
            enhancedText: \.enhancedText
        )

        XCTAssertTrue(snapshot.shouldShowEmptyState)
        XCTAssertEqual(snapshot.displayedItems, [])
        XCTAssertEqual(snapshot.emptyStatePresentation, VoiceInkHistoryPresentation.iOSNotesEmptyState)
        XCTAssertEqual(snapshot.summaryPresentation.countText, "0")
    }

    func testNoteListSnapshotBuildsOffsetDeletionPlanFromDisplayedRows() {
        let records = [
            NoteListRecord(id: 1, rawText: "needle first", enhancedText: nil, wordCount: 5, audioDuration: 10, transcriptionModelName: nil, transcriptionDuration: nil),
            NoteListRecord(id: 2, rawText: "hide", enhancedText: nil, wordCount: 8, audioDuration: 12, transcriptionModelName: nil, transcriptionDuration: nil),
            NoteListRecord(id: 3, rawText: "needle second", enhancedText: nil, wordCount: 13, audioDuration: 20, transcriptionModelName: nil, transcriptionDuration: nil)
        ]
        let snapshot = VoiceInkNoteListSnapshot.make(
            from: records,
            query: "needle",
            rawText: \.rawText,
            enhancedText: \.enhancedText
        )

        let deletionPlan = snapshot.offsetDeletionPlan(atOffsets: IndexSet(integer: 1), id: \.id)
        var deletedIDs: [Int] = []
        deletionPlan.applyRuntimeState { deletedIDs.append($0.id) }

        XCTAssertEqual(deletedIDs, [3])
        XCTAssertFalse(deletionPlan.deletesID(1))
        XCTAssertFalse(deletionPlan.deletesID(2))
        XCTAssertTrue(deletionPlan.deletesID(3))
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
        XCTAssertEqual(VoiceInkDashboardPromotionPresentation.dismissSystemImageName, "xmark.circle.fill")
        XCTAssertEqual(VoiceInkDashboardPromotionPresentation.upgradeCard.badgeDisplayText, "30% OFF")
        XCTAssertEqual(VoiceInkDashboardPromotionPresentation.affiliateCard.badgeDisplayText, "AFFILIATE 30%")

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

    func testAnalyzeBuildsSummaryAndSortedModelStats() {
        let analysis = VoiceInkPerformanceAnalyzer.analyze(records: [
            PerformanceAnalysisRecord(
                audioDuration: 10,
                transcriptionModelName: "fast",
                transcriptionDuration: 2,
                aiEnhancementModelName: "gpt",
                enhancementDuration: 1,
                enhancedText: "enhanced"
            ),
            PerformanceAnalysisRecord(
                audioDuration: 20,
                transcriptionModelName: "fast",
                transcriptionDuration: 4,
                aiEnhancementModelName: "gpt",
                enhancementDuration: 3,
                enhancedText: nil
            ),
            PerformanceAnalysisRecord(
                audioDuration: 20,
                transcriptionModelName: "slow",
                transcriptionDuration: 10,
                aiEnhancementModelName: nil,
                enhancementDuration: nil,
                enhancedText: nil
            ),
            PerformanceAnalysisRecord(
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
                PerformanceAnalysisRecord(audioDuration: 10, transcriptionModelName: "fast", transcriptionDuration: 2),
                PerformanceAnalysisRecord(audioDuration: 10, transcriptionModelName: "zero", transcriptionDuration: 0),
                PerformanceAnalysisRecord(audioDuration: 10, transcriptionModelName: "negative", transcriptionDuration: -1)
            ],
            requirePositiveDuration: true
        )

        XCTAssertEqual(stats.map(\.name), ["fast"])
    }

    func testDefaultStatsPreserveHistoricalAnalyzerNilOnlyFiltering() {
        let stats = VoiceInkPerformanceAnalyzer.transcriptionModelStats(from: [
            PerformanceAnalysisRecord(audioDuration: 10, transcriptionModelName: "zero", transcriptionDuration: 0),
            PerformanceAnalysisRecord(audioDuration: 10, transcriptionModelName: "missing", transcriptionDuration: nil)
        ])

        XCTAssertEqual(stats.map(\.name), ["zero"])
        XCTAssertEqual(stats[0].speedFactor, 0)
    }

    func testModelStatFormatsSharedPresentationText() {
        let stat = VoiceInkPerformanceAnalyzer.transcriptionModelStats(
            from: [
                PerformanceAnalysisRecord(
                    audioDuration: 11.7936,
                    transcriptionModelName: "fast",
                    transcriptionDuration: 2.34
                )
            ]
        )[0]

        XCTAssertEqual(stat.speedFactorText, "5.0x")
        XCTAssertEqual(stat.speedFactorRealtimeText, "5.0x realtime")
        XCTAssertEqual(stat.realTimeComparisonText, "Faster than Real-time")
        XCTAssertEqual(stat.avgProcessingTimeCompactText, "2.34s")
        XCTAssertEqual(stat.avgProcessingTimeSpacedText, "2.34 s")

        let slowerStat = VoiceInkPerformanceAnalyzer.transcriptionModelStats(
            from: [
                PerformanceAnalysisRecord(
                    audioDuration: 5,
                    transcriptionModelName: "slow",
                    transcriptionDuration: 10
                )
            ]
        )[0]

        XCTAssertEqual(slowerStat.realTimeComparisonText, "Slower than Real-time")
    }

    func testSessionMetricSourceDefaultsPerformanceRecordFields() {
        let record = PerformanceSessionBackedRecord(
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

    private func withTemporaryDefaults(_ test: (UserDefaults) -> Void) {
        let suiteName = "VoiceInkCore.DashboardMetricsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        test(defaults)
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

private struct SessionMetricSource: VoiceInkSessionMetricSource {
    let text: String
    let enhancedText: String?
    let duration: TimeInterval
    let transcriptionDuration: TimeInterval?
    let enhancementDuration: TimeInterval?
}

private struct NoteListRecord: Hashable, VoiceInkDashboardMetricRecord, VoiceInkPerformanceRecord {
    var id: Int = 0
    var rawText: String = ""
    var enhancedText: String? = nil
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

private struct PerformanceAnalysisRecord: VoiceInkPerformanceRecord {
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

private struct PerformanceSessionBackedRecord: VoiceInkPerformanceRecord, VoiceInkSessionMetricSource {
    let text: String
    let enhancedText: String?
    let duration: TimeInterval
    let transcriptionDuration: TimeInterval?
    let enhancementDuration: TimeInterval?
    let transcriptionModelName: String?
    let aiEnhancementModelName: String?
}
