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
        let audioAvailability = note.storedAudioAvailability()
        let shouldShowAudioSection = audioAvailability.shouldShowAudioSection(duration: note.duration)

        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Main content with scroll
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Transcription status and retry button
                        if VoiceInkTranscriptPresentation.shouldShowStatusPanel(for: note.transcriptionStatus) {
                            transcriptionStatusView
                        }

                        // Transcript content
                        if VoiceInkTranscriptPresentation.shouldShowCompletedContent(for: note.transcriptionStatus) {
                            transcriptContentView
                        }
                        
                        // Add bottom padding to account for audio player
                        if shouldShowAudioSection {
                            Color.clear
                                .frame(height: 100)
                        }
                    }
                    .padding()
                }
                .scrollIndicators(.hidden)

                // Bottom audio player (web-form style)
                if shouldShowAudioSection {
                    bottomAudioPlayer(audioAvailability: audioAvailability)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .padding(.horizontal)
                        .padding(.bottom, geometry.safeAreaInsets.bottom > 0 ? 0 : 16)
                }
            }
        }
        .navigationTitle(VoiceInkTranscriptPresentation.noteDetailNavigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemGroupedBackground))
    }
    
    private var transcriptContentView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(VoiceInkTranscriptPresentation.transcriptTitle)
                    .font(.headline)
                Spacer()
                Button(action: {
                    copyToClipboard(VoiceInkTranscriptPresentation.preferredTextOrEmptyContent(
                        rawText: note.text,
                        enhancedText: note.enhancedText
                    ))
                }) {
                    Image(systemName: VoiceInkTranscriptPresentation.copyTranscriptSystemImageName)
                        .font(.system(size: 16))
                        .foregroundStyle(.blue)
                }
            }
            
            Text(VoiceInkTranscriptPresentation.preferredTextOrEmptyContent(
                rawText: note.text,
                enhancedText: note.enhancedText
            ))
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
    private var transcriptionStatusView: some View {
        let statusPresentation = VoiceInkTranscriptPresentation.statusPresentation(for: note.transcriptionStatus)
        let retryControls = VoiceInkTranscriptPresentation.retryControls(
            for: note.transcriptionStatus,
            isRetranscribing: isRetranscribing
        )
        let retryAction = retryControls.action.runtimeAction(retry: retranscribe)

        if let statusPresentation {
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: statusPresentation.panelSystemImageName)
                        .foregroundStyle(statusPresentation.tone.statusColor)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(statusPresentation.title)
                            .font(.subheadline.weight(.medium))
                        if let error = VoiceInkTranscriptPresentation.statusErrorDetail(note.transcriptionError) {
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
                if retryControls.shouldShowModeSelection {
                    VoiceInkModeSelectionControlView(
                        modes: settings.modes,
                        selectedModeId: $settings.selectedModeId
                    )
                }

                switch retryControls.action {
                case .hidden:
                    EmptyView()
                case .showProgress:
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text(retryControls.progressText ?? VoiceInkTranscriptPresentation.retranscribingDisplayText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                case .showRetryButton:
                    if let retryAction {
                        Button(action: retryAction) {
                            Label(
                                VoiceInkTranscriptPresentation.retryTranscriptionButtonTitle,
                                systemImage: VoiceInkTranscriptPresentation.retryTranscriptionSystemImageName
                            )
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                        .controlSize(.regular)
                    }
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private func retranscribe() {
        isRetranscribing = true
        
        Task {
            defer { isRetranscribing = false }
            
            do {
                _ = try await TranscriptionRetryService.shared.retranscribe(note: note)
            } catch {
                // Failure state is already applied by the retry adapter.
            }
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
