import SwiftUI
import VoiceInkCore

// MARK: - Shared Analysis Logic

enum PanelMode {
    case info
    case analysis
}

struct PerformanceAnalyzer {
    static func analyze(transcriptions: [Transcription]) -> VoiceInkPerformanceAnalysis {
        VoiceInkPerformanceAnalyzer.analyze(records: transcriptions)
    }

    static func getMacModel() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &machine, &size, nil, 0)
        return String(cString: machine)
    }

    static func getCPUInfo() -> String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0)
        return String(cString: buffer)
    }

    static func getMemoryInfo() -> String {
        let totalMemory = ProcessInfo.processInfo.physicalMemory
        return ByteCountFormatter.string(fromByteCount: Int64(totalMemory), countStyle: .memory)
    }
}

// MARK: - Sheet View (existing)

struct PerformanceAnalysisView: View {
    @Environment(\.dismiss) private var dismiss
    let transcriptions: [Transcription]
    private let analysis: VoiceInkPerformanceAnalysis

    private let columns: [GridItem] = [
        GridItem(.adaptive(minimum: 250), spacing: 16)
    ]

    init(transcriptions: [Transcription]) {
        self.transcriptions = transcriptions
        self.analysis = PerformanceAnalyzer.analyze(transcriptions: transcriptions)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    summarySection
                    
                    systemInfoSection
                    
                    if !analysis.transcriptionModels.isEmpty {
                        transcriptionPerformanceSection
                    }
                    
                    if !analysis.enhancementModels.isEmpty {
                        enhancementPerformanceSection
                    }
                }
                .padding()
            }
        }
        .frame(minWidth: 550, idealWidth: 600, maxWidth: 700, minHeight: 600, idealHeight: 750, maxHeight: 900)
        .background(Color(.windowBackgroundColor))
    }

    private var header: some View {
        HStack {
            Text("Performance Analysis")
                .font(.title2)
                .fontWeight(.bold)
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
        }
    }

    private var summarySection: some View {
        HStack(spacing: 12) {
            SummaryCard(
                icon: "doc.text.fill", 
                value: "\(analysis.totalTranscripts)", 
                label: "Total Transcripts",
                color: .indigo
            )
            SummaryCard(
                icon: "waveform.path.ecg", 
                value: "\(analysis.totalWithTranscriptionData)", 
                label: "Analyzable",
                color: .teal
            )
            SummaryCard(
                icon: "sparkles", 
                value: "\(analysis.totalEnhancedFiles)", 
                label: "Enhanced",
                color: .mint
            )
        }
    }

    private var systemInfoSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("System Information")
                .font(.system(.title2, design: .default, weight: .bold))
                .foregroundColor(.primary)

            HStack(spacing: 12) {
                SystemInfoCard(label: "Device", value: PerformanceAnalyzer.getMacModel())
                SystemInfoCard(label: "Processor", value: PerformanceAnalyzer.getCPUInfo())
                SystemInfoCard(label: "Memory", value: PerformanceAnalyzer.getMemoryInfo())
            }
        }
    }

    private var transcriptionPerformanceSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Transcription Models")
                .font(.system(.title2, design: .default, weight: .bold))
                .foregroundColor(.primary)

            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(analysis.transcriptionModels) { modelStat in
                    TranscriptionModelCard(modelStat: modelStat)
                }
            }
        }
    }

    private var enhancementPerformanceSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Enhancement Models")
                .font(.system(.title2, design: .default, weight: .bold))
                .foregroundColor(.primary)

            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(analysis.enhancementModels) { modelStat in
                    EnhancementModelCard(modelStat: modelStat)
                }
            }
        }
    }
    
}

// MARK: - Subviews

struct SummaryCard: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(color)
            
            Text(value)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundColor(.primary)
            
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 100)
        .background(MetricCardBackground(color: color))
        .cornerRadius(12)
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.headline)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.body)
                .foregroundColor(.primary)
        }
    }
}

struct SystemInfoCard: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            
            Text(value)
                .font(.system(.body, design: .default, weight: .semibold))
                .foregroundColor(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .background(MetricCardBackground(color: .secondary))
        .cornerRadius(12)
    }
}

struct TranscriptionModelCard: View {
    let modelStat: VoiceInkPerformanceModelStat

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Model name and transcript count
            HStack(alignment: .firstTextBaseline) {
                Text(modelStat.name)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Spacer()
                
                Text("\(modelStat.sampleCount) transcripts")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Divider()

            VStack(spacing: 16) {
                // Main metric: Speed Factor
                VStack {
                    Text(modelStat.speedFactorText)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.mint)
                    Text("Faster than Real-time")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                
                Divider()

                // Secondary metrics
                HStack {
                    MetricDisplay(
                        title: "Avg. Audio",
                        value: VoiceInkDurationPresentation.abbreviatedMinutesSeconds(modelStat.avgAudioDuration),
                        color: .indigo
                    )
                    Spacer()
                    MetricDisplay(
                        title: "Avg. Process Time",
                        value: modelStat.avgProcessingTimeSpacedText,
                        color: .teal
                    )
                }
            }
        }
        .padding(16)
        .background(MetricCardBackground(color: .mint))
        .cornerRadius(12)
    }
    
}

struct EnhancementModelCard: View {
    let modelStat: VoiceInkPerformanceModelStat

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Model name and transcript count
            HStack(alignment: .firstTextBaseline) {
                Text(modelStat.name)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Spacer()
                
                Text("\(modelStat.sampleCount) transcripts")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            VStack(alignment: .center) {
                Text(modelStat.avgProcessingTimeSpacedText)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.indigo)
                Text("Avg. Enhancement Time")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(16)
        .background(MetricCardBackground(color: .indigo))
        .cornerRadius(12)
    }
}

struct MetricCardBackground: View {
    let color: Color
    
    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(.regularMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(color.opacity(0.08))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color(NSColor.separatorColor).opacity(0.35), lineWidth: 1)
            }
    }
}

struct MetricDisplay: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
            
            Text(value)
                .font(.system(.body, design: .monospaced, weight: .semibold))
                .foregroundColor(color)
        }
    }
}
