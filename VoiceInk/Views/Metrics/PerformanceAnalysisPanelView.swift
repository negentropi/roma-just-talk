import SwiftUI
import VoiceInkCore

/// Compact panel-optimized performance analysis view for sliding panels and sidebars.
struct PerformanceAnalysisPanelView: View {
    let transcriptions: [Transcription]
    let onClose: () -> Void
    private let analysis: VoiceInkPerformanceAnalysis

    init(transcriptions: [Transcription], onClose: @escaping () -> Void) {
        self.transcriptions = transcriptions
        self.onClose = onClose
        self.analysis = VoiceInkPerformanceAnalyzer.analyze(records: transcriptions)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color(NSColor.windowBackgroundColor))
                .overlay(Divider().opacity(0.5), alignment: .bottom)
                .zIndex(1)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    summarySection
                    systemInfoSection

                    if !analysis.transcriptionModels.isEmpty {
                        transcriptionModelsSection
                    }

                    if !analysis.enhancementModels.isEmpty {
                        enhancementModelsSection
                    }
                }
                .padding(16)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Text(VoiceInkPerformancePresentation.performanceAnalysisPanelTitle)
                .font(.headline)
                .fontWeight(.semibold)
            Spacer()
            Button(action: onClose) {
                Image(systemName: VoiceInkPerformancePresentation.closeSystemImageName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(6)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Summary

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(VoiceInkPerformancePresentation.summarySectionTitle)

            HStack(spacing: 10) {
                summaryPill(
                    icon: VoiceInkPerformancePresentation.totalSummaryIconSystemName,
                    value: "\(analysis.totalTranscripts)",
                    label: VoiceInkPerformancePresentation.totalSummaryLabel,
                    color: .indigo
                )
                summaryPill(
                    icon: VoiceInkPerformancePresentation.analyzableSummaryIconSystemName,
                    value: "\(analysis.totalWithTranscriptionData)",
                    label: VoiceInkPerformancePresentation.analyzableSummaryLabel,
                    color: .teal
                )
                summaryPill(
                    icon: VoiceInkPerformancePresentation.enhancedSummaryIconSystemName,
                    value: "\(analysis.totalEnhancedFiles)",
                    label: VoiceInkPerformancePresentation.enhancedSummaryLabel,
                    color: .mint
                )
            }
        }
    }

    private func summaryPill(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(color)
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(MetricCardBackground(color: color))
        .cornerRadius(10)
    }

    // MARK: - System Info

    private var systemInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(VoiceInkPerformancePresentation.systemInformationSectionTitle)

            VStack(spacing: 0) {
                infoRow(label: VoiceInkPerformancePresentation.deviceInfoLabel, value: PerformanceAnalyzer.getMacModel())
                Divider().padding(.horizontal, 10)
                infoRow(label: VoiceInkPerformancePresentation.processorInfoLabel, value: PerformanceAnalyzer.getCPUInfo())
                Divider().padding(.horizontal, 10)
                infoRow(label: VoiceInkPerformancePresentation.memoryInfoLabel, value: PerformanceAnalyzer.getMemoryInfo())
            }
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color(NSColor.quaternaryLabelColor).opacity(0.3), lineWidth: 1)
                    )
            )
            .cornerRadius(10)
        }
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            Spacer(minLength: 4)
            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Transcription Models

    private let gridColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    private var transcriptionModelsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(VoiceInkPerformancePresentation.transcriptionModelsSectionTitle)

            LazyVGrid(columns: gridColumns, spacing: 12) {
                ForEach(analysis.transcriptionModels) { modelStat in
                    transcriptionModelTile(modelStat)
                }
            }
        }
    }

    private func transcriptionModelTile(_ modelStat: VoiceInkPerformanceModelStat) -> some View {
        VStack(spacing: 10) {
            // Model name + count
            VStack(spacing: 2) {
                Text(modelStat.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(VoiceInkPerformancePresentation.transcriptSampleCountText(modelStat.sampleCount))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)

            // Hero metric
            VStack(spacing: 3) {
                Text(modelStat.speedFactorText)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.mint)
                Text(modelStat.realTimeComparisonText)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Divider()
                .padding(.horizontal, 8)

            // Secondary metrics
            HStack(spacing: 0) {
                VStack(spacing: 2) {
                    Text(VoiceInkDurationPresentation.abbreviatedMinutesSeconds(modelStat.avgAudioDuration))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.indigo)
                    Text(VoiceInkPerformancePresentation.averageAudioLabel)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)

                Rectangle()
                    .fill(Color(NSColor.separatorColor))
                    .frame(width: 1, height: 24)

                VStack(spacing: 2) {
                    Text(modelStat.avgProcessingTimeCompactText)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.teal)
                    Text(VoiceInkPerformancePresentation.averageProcessingLabel)
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

    private var enhancementModelsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(VoiceInkPerformancePresentation.enhancementModelsSectionTitle)

            LazyVGrid(columns: gridColumns, spacing: 12) {
                ForEach(analysis.enhancementModels) { modelStat in
                    enhancementModelTile(modelStat)
                }
            }
        }
    }

    private func enhancementModelTile(_ modelStat: VoiceInkPerformanceModelStat) -> some View {
        VStack(spacing: 10) {
            // Model name + count
            VStack(spacing: 2) {
                Text(modelStat.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(VoiceInkPerformancePresentation.transcriptSampleCountText(modelStat.sampleCount))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)

            // Hero metric
            VStack(spacing: 3) {
                Text(modelStat.avgProcessingTimeSpacedText)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.indigo)
                Text(VoiceInkPerformancePresentation.averageEnhancementTimeLabel)
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
