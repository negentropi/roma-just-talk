import SwiftData
import SwiftUI
import RomaCore

struct RomaIOSMetricsSnapshot {
    let records: [Transcription]
    let dashboardMetrics: RomaDashboardMetrics
    let performance: RomaPerformanceAnalysis

    init(
        records: [Transcription],
        filter: RomaPerformanceTimeFilter,
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        let startDate = filter.startDate(now: now, calendar: calendar)
        self.records = records.filter { record in
            startDate.map { record.timestamp >= $0 } ?? true
        }

        var accumulator = RomaDashboardMetricsAccumulator()
        for record in self.records {
            accumulator.add(record)
        }
        dashboardMetrics = RomaDashboardMetrics(
            summary: accumulator.summary(totalCount: self.records.count)
        )
        performance = RomaPerformanceAnalyzer.analyze(records: self.records)
    }
}

struct IOSMetricsView: View {
    @Query(sort: [SortDescriptor(\Transcription.timestamp, order: .reverse)]) private var notes: [Transcription]
    @AppStorage(RomaPerformanceTimeFilter.userDefaultsKey)
    private var storedFilterRawValue = RomaPerformanceTimeFilter.defaultFilter.rawValue

    private var selectedFilter: RomaPerformanceTimeFilter {
        RomaPerformanceTimeFilter.storedFilter(rawValue: storedFilterRawValue)
    }

    private var snapshot: RomaIOSMetricsSnapshot {
        RomaIOSMetricsSnapshot(records: notes, filter: selectedFilter)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Picker(
                    RomaPerformancePresentation.performanceAnalysisPanelTitle,
                    selection: Binding(
                        get: { selectedFilter },
                        set: { storedFilterRawValue = $0.rawValue }
                    )
                ) {
                    ForEach(RomaPerformanceTimeFilter.allCases) { filter in
                        Text(filter.label).tag(filter)
                    }
                }
                .pickerStyle(.menu)

                if snapshot.records.isEmpty {
                    ContentUnavailableView(
                        RomaPerformancePresentation.emptyStateTitle,
                        systemImage: RomaPerformancePresentation.emptyStateSystemImageName
                    )
                    .frame(maxWidth: .infinity, minHeight: 320)
                } else {
                    dashboardHero
                    metricGrid
                    performanceSummary
                    modelSection(
                        RomaPerformancePresentation.transcriptionModelsSectionTitle,
                        stats: snapshot.performance.transcriptionModels
                    )
                    modelSection(
                        RomaPerformancePresentation.enhancementModelsSectionTitle,
                        stats: snapshot.performance.enhancementModels
                    )
                }
            }
            .padding()
        }
        .navigationTitle(RomaDashboardPresentation.heroSectionTitle)
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemGroupedBackground))
    }

    private var dashboardHero: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(RomaDashboardPresentation.heroTitle(
                isSnapshotLoaded: true,
                timeSaved: snapshot.dashboardMetrics.timeSaved
            ))
            .font(.title.bold())

            Text(RomaDashboardPresentation.heroSubtitle(
                isSnapshotLoaded: true,
                totalCount: snapshot.dashboardMetrics.summary.totalCount,
                totalWords: snapshot.dashboardMetrics.summary.totalWords
            ))
            .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                ForEach(RomaDashboardPresentation.heroPills(
                    isSnapshotLoaded: true,
                    summary: snapshot.dashboardMetrics.summary
                )) { pill in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(pill.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(pill.value)
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private var metricGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 12)], spacing: 12) {
            ForEach(RomaDashboardPresentation.metricCards(
                isSnapshotLoaded: true,
                metrics: snapshot.dashboardMetrics
            )) { card in
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: card.iconSystemName)
                        .foregroundStyle(.blue)
                    Text(card.value)
                        .font(.title2.bold())
                    Text(card.title)
                        .font(.subheadline.weight(.medium))
                    Text(card.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private var performanceSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(RomaPerformancePresentation.summarySectionTitle)
                .font(.headline)
            LabeledContent(
                RomaPerformancePresentation.totalSummaryLabel,
                value: snapshot.performance.totalTranscriptsText
            )
            LabeledContent(
                RomaPerformancePresentation.analyzableSummaryLabel,
                value: snapshot.performance.totalWithTranscriptionDataText
            )
            LabeledContent(
                RomaPerformancePresentation.enhancedSummaryLabel,
                value: snapshot.performance.totalEnhancedFilesText
            )
            LabeledContent(
                "Audio",
                value: RomaDurationPresentation.positiveDuration(
                    snapshot.performance.totalAudioDuration,
                    style: .abbreviated,
                    fallback: "0s"
                )
            )
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func modelSection(
        _ title: String,
        stats: [RomaPerformanceModelStat]
    ) -> some View {
        if !stats.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.headline)
                ForEach(stats) { stat in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(stat.name)
                                .font(.subheadline.weight(.medium))
                            Text(RomaPerformancePresentation.transcriptSampleCountText(stat.sampleCount))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(stat.speedFactorRealtimeText)
                                .font(.subheadline.monospacedDigit())
                            Text(stat.avgProcessingTimeCompactText)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    if stat.id != stats.last?.id {
                        Divider()
                    }
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        }
    }
}
