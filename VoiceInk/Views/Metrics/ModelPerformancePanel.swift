import SwiftUI
import SwiftData
import VoiceInkCore

// MARK: - Panel shell (owns filter state)

struct ModelPerformancePanel: View {
    @AppStorage(VoiceInkPerformanceTimeFilter.userDefaultsKey)
    private var filterRaw: String = VoiceInkPerformanceTimeFilter.defaultFilter.rawValue
    let onClose: () -> Void

    private var filter: VoiceInkPerformanceTimeFilter {
        VoiceInkPerformanceTimeFilter.storedFilter(rawValue: filterRaw)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color(NSColor.windowBackgroundColor))
                .overlay(Divider().opacity(0.5), alignment: .bottom)
                .zIndex(1)

            ModelPerformancePanelContent(filter: filter)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Model Performance")
                .font(.headline.weight(.semibold))
            Spacer()
            Picker("", selection: Binding(get: { filter }, set: { filterRaw = $0.rawValue })) {
                ForEach(VoiceInkPerformanceTimeFilter.allCases) { f in
                    Text(f.label).tag(f)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(6)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Content (owns @Query, reacts to filter)

private struct ModelPerformancePanelContent: View {
    @Query private var metrics: [SessionMetric]

    init(filter: VoiceInkPerformanceTimeFilter) {
        if let start = filter.startDate() {
            _metrics = Query(filter: #Predicate<SessionMetric> { $0.timestamp >= start })
        } else {
            _metrics = Query()
        }
    }

    private var modelStats: [VoiceInkPerformanceModelStat] {
        VoiceInkPerformanceAnalyzer.transcriptionModelStats(from: metrics, requirePositiveDuration: true)
    }

    private var enhancementStats: [VoiceInkPerformanceModelStat] {
        VoiceInkPerformanceAnalyzer.enhancementModelStats(from: metrics, requirePositiveDuration: true)
    }

    private let gridColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        if modelStats.isEmpty && enhancementStats.isEmpty {
            emptyState
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !modelStats.isEmpty {
                        modelsSection
                    }
                    if !enhancementStats.isEmpty {
                        enhancementSection
                    }
                }
                .padding(16)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 32, weight: .light))
                .foregroundColor(.secondary)
            Text("No data for this period")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Models grid

    private var modelsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Transcription Models")
            LazyVGrid(columns: gridColumns, spacing: 12) {
                ForEach(modelStats) { stat in
                    modelTile(stat)
                }
            }
        }
    }

    private func modelTile(_ stat: VoiceInkPerformanceModelStat) -> some View {
        VStack(spacing: 10) {
            VStack(spacing: 2) {
                Text(stat.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("\(stat.sampleCount) sessions")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 3) {
                Text(stat.speedFactorText)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.mint)
                Text(stat.realTimeComparisonText)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Divider().padding(.horizontal, 8)

            HStack(spacing: 0) {
                VStack(spacing: 2) {
                    Text(VoiceInkDurationPresentation.abbreviatedMinutesSeconds(stat.avgAudioDuration))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.indigo)
                    Text("Avg. Audio")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)

                Rectangle()
                    .fill(Color(NSColor.separatorColor))
                    .frame(width: 1, height: 24)

                VStack(spacing: 2) {
                    Text(stat.avgProcessingTimeCompactText)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.teal)
                    Text("Avg. Processing")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(14)
        .background(MetricCardBackground(color: .mint))
        .cornerRadius(12)
    }

    // MARK: - Enhancement Models

    private var enhancementSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Enhancement Models")
            LazyVGrid(columns: gridColumns, spacing: 12) {
                ForEach(enhancementStats) { stat in
                    enhancementTile(stat)
                }
            }
        }
    }

    private func enhancementTile(_ stat: VoiceInkPerformanceModelStat) -> some View {
        VStack(spacing: 10) {
            VStack(spacing: 2) {
                Text(stat.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("\(stat.sampleCount) sessions")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 3) {
                Text(stat.avgProcessingTimeCompactText)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.indigo)
                Text("Avg. Enhancement Time")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .padding(14)
        .background(MetricCardBackground(color: .indigo))
        .cornerRadius(12)
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.secondary)
            .textCase(.uppercase)
            .tracking(0.5)
    }

}
