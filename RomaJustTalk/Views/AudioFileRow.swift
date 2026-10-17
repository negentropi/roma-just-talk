import SwiftUI
import RomaCore

struct AudioFileRow: View {
    @ObservedObject var item: AudioFileQueueItem
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    let onRemove: () -> Void
    let onRetry: () -> Void

    @State private var selectedTab: RomaTranscriptTextVariant = .original

    private var displayText: String {
        selectedTab.displayText(
            rawText: item.transcription?.text ?? "",
            enhancedText: item.transcription?.enhancedText
        )
    }

    /// Text for copy/save — matches visible content regardless of expansion state.
    private var actionText: String {
        RomaTranscriptPresentation.transcriptActionText(
            selectedVariant: selectedTab,
            isExpanded: isExpanded,
            rawText: item.transcription?.text ?? "",
            enhancedText: item.transcription?.enhancedText
        )
    }

    var body: some View {
        switch item.status {
        case .pending:
            pendingRow
        case .processing(let phase):
            processingRow(phase: phase)
        case .completed:
            completedRows
        case .failed(let message):
            failedRow(message: message)
        }
    }

    // MARK: - Pending

    private var pendingRow: some View {
        HStack {
            Image(systemName: RomaAudioFileQueuePresentation.pendingStatusSystemImageName)
                .foregroundColor(.secondary)

            Text(item.filename)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Text(RomaAudioFileQueuePresentation.pendingStatusText)
                .font(.caption)
                .foregroundColor(.secondary)

            Button {
                onRemove()
            } label: {
                Image(systemName: RomaAudioFileQueuePresentation.removeButtonSystemImageName)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Processing

    private func processingRow(phase: RomaAudioFileQueueProcessingPhase) -> some View {
        HStack {
            ProgressView()
                .scaleEffect(0.5)
                .frame(width: 16, height: 16)

            Text(item.filename)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Text(phase.displayText)
                .font(.caption)
                .foregroundColor(.accentColor)
        }
    }

    // MARK: - Completed

    @ViewBuilder
    private var completedRows: some View {
        HStack {
            Image(systemName: RomaAudioFileQueuePresentation.completedStatusSystemImageName)
                .foregroundColor(.green)

            Text(item.filename)
                .foregroundColor(.primary)
                .lineLimit(1)
                .truncationMode(.middle)

            if !isExpanded, let transcription = item.transcription {
                Text(
                    RomaTranscriptPresentation.preferredText(
                        rawText: transcription.text,
                        enhancedText: transcription.enhancedText
                    ) ?? transcription.text
                )
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if let transcription = item.transcription {
                HStack(spacing: 2) {
                    CopyIconButton(textToCopy: actionText)
                    SaveIconButton(textToSave: actionText)
                }

                if RomaDurationPresentation.shouldShowPositiveDuration(transcription.duration) {
                    Text(RomaDurationPresentation.minutesSeconds(transcription.duration))
                        .font(.caption.weight(.medium))
                        .foregroundColor(.secondary)
                }
            }

            Image(systemName: RomaAudioFileQueuePresentation.expandSystemImageName)
                .font(.caption2.weight(.semibold))
                .foregroundColor(.secondary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .animation(.easeInOut(duration: 0.2), value: isExpanded)
        }
        .contentShape(Rectangle())
        .onTapGesture { onToggleExpand() }

        if isExpanded, let transcription = item.transcription {
            if RomaTranscriptTextVariant.shouldShowTabs(enhancedText: transcription.enhancedText) {
                HStack(spacing: 4) {
                    tabButton(tab: .original)
                    tabButton(tab: .enhanced)
                    Spacer()
                }
            }

            ScrollView {
                Text(displayText)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 350)

            HStack(spacing: 12) {
                if let model = transcription.transcriptionModelName {
                    Label(model, systemImage: RomaAudioFileQueuePresentation.transcriptionModelSystemImageName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if let prompt = transcription.promptName {
                    Label(prompt, systemImage: RomaAudioFileQueuePresentation.promptSystemImageName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
        }
    }

    private func tabButton(tab: RomaTranscriptTextVariant) -> some View {
        Button {
            selectedTab = tab
        } label: {
            Text(tab.title)
                .font(.subheadline.weight(selectedTab == tab ? .semibold : .regular))
                .foregroundColor(selectedTab == tab ? .accentColor : .secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(selectedTab == tab ? Color.accentColor.opacity(0.12) : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Failed

    private func failedRow(message: String) -> some View {
        HStack {
            Image(systemName: RomaAudioFileQueuePresentation.failedStatusSystemImageName)
                .foregroundColor(.red)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.filename)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(message)
                    .font(.caption)
                    .foregroundColor(.red.opacity(0.8))
                    .lineLimit(2)
            }

            Spacer()

            Button {
                onRetry()
            } label: {
                Image(systemName: RomaAudioFileQueuePresentation.retryButtonSystemImageName)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

}
