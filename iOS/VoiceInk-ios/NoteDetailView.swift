import SwiftUI
import SwiftData
import VoiceInkCore

struct NoteDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let note: Transcription
    
    @State private var isRetranscribing = false
    @StateObject private var settings = AppSettings.shared

    var body: some View {
        let presentation = VoiceInkNoteDetailPresentation.make(
            status: note.transcriptionStatus,
            rawText: note.text,
            enhancedText: note.enhancedText,
            transcriptionError: note.transcriptionError,
            isRetranscribing: isRetranscribing,
            audioAvailability: note.storedAudioAvailability(),
            duration: note.duration
        )

        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Main content with scroll
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Transcription status and retry button
                        if let statusPanel = presentation.statusPanel {
                            transcriptionStatusView(statusPanel)
                        }

                        // Transcript content
                        if let transcriptContent = presentation.transcriptContent {
                            transcriptContentView(transcriptContent)
                        }
                        
                        // Add bottom padding to account for audio player
                        if presentation.shouldShowAudioSection {
                            Color.clear
                                .frame(height: 100)
                        }
                    }
                    .padding()
                }
                .scrollIndicators(.hidden)

                // Bottom audio player (web-form style)
                if presentation.shouldShowAudioSection {
                    bottomAudioPlayer(audioAvailability: presentation.audioAvailability)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .padding(.horizontal)
                        .padding(.bottom, geometry.safeAreaInsets.bottom > 0 ? 0 : 16)
                }
            }
        }
        .navigationTitle(presentation.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemGroupedBackground))
    }
    
    private func transcriptContentView(_ content: VoiceInkTranscriptContentPresentation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(content.title)
                    .font(.headline)
                Spacer()
                Button(action: {
                    copyToClipboard(content.text)
                }) {
                    Image(systemName: content.copySystemImageName)
                        .font(.system(size: 16))
                        .foregroundStyle(.blue)
                }
            }
            
            Text(content.text)
                .font(.body)
                .textSelection(.enabled)
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    // Summary card removed per design feedback
    
    private func bottomAudioPlayer(audioAvailability: VoiceInkStoredAudioAvailability) -> some View {
        VStack(spacing: 0) {
            if let audioURL = audioAvailability.existingURL {
                AudioPlayerView(audioFilePath: audioURL.path, duration: note.duration, timestamp: note.timestamp)
            } else if let title = audioAvailability.unavailableTitle,
                      let detail = audioAvailability.unavailableDetail {
                audioUnavailableView(title: title, detail: detail)
            }
        }
    }

    private func audioUnavailableView(title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(.orange.opacity(0.2))
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: VoiceInkStoredAudioAvailability.unavailableSystemImageName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.orange)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
    
    @ViewBuilder
    private func transcriptionStatusView(_ statusPanel: VoiceInkNoteDetailStatusPanelPresentation) -> some View {
        let retryAction = statusPanel.retryControls.runtimeAction(retry: retranscribe)

        VStack(spacing: 12) {
            HStack {
                Image(systemName: statusPanel.statusPresentation.panelSystemImageName)
                    .foregroundStyle(statusPanel.statusPresentation.tone.statusColor)

                VStack(alignment: .leading, spacing: 6) {
                    Text(statusPanel.statusPresentation.title)
                        .font(.subheadline.weight(.medium))
                    if let error = statusPanel.errorDetail {
                        Text(error)
                            .font(.callout)
                            .textSelection(.enabled)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer()
            }

            // Mode selection for re-transcription
            if statusPanel.retryControls.shouldShowModeSelection {
                VoiceInkModeSelectionControlView(
                    modes: settings.modes,
                    selectedModeId: $settings.selectedModeId
                )
            }

            if statusPanel.retryControls.shouldShowProgress {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(statusPanel.retryControls.progressDisplayText ?? "")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else if let retryAction {
                Button(action: retryAction) {
                    Label(
                        statusPanel.retryButtonTitle,
                        systemImage: statusPanel.retryButtonSystemImageName
                    )
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .controlSize(.regular)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func retranscribe() {
        isRetranscribing = true
        
        Task {
            defer { isRetranscribing = false }
            
            _ = await settings.retranscribeStoredAudio(note)
            try? modelContext.save()
        }
    }
    
    private func copyToClipboard(_ text: String) {
        UIPasteboard.general.string = text
        
        // Optional: Add haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }
    

}
