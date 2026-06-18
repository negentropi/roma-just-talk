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
                    bottomAudioPlayer
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
                    Image(systemName: "doc.on.doc")
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
    
    private var shouldShowAudioSection: Bool {
        audioAvailability.shouldShowAudioSection(duration: note.duration)
    }

    private var audioAvailability: VoiceInkStoredAudioAvailability {
        note.storedAudioAvailability()
    }

    private var statusPresentation: VoiceInkTranscriptStatusPresentation? {
        VoiceInkTranscriptPresentation.statusPresentation(for: note.transcriptionStatus)
    }

    // Summary card removed per design feedback
    
    private var bottomAudioPlayer: some View {
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
                    Image(systemName: "exclamationmark")
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
        if let statusPresentation {
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: statusPresentation.panelSystemImageName)
                        .foregroundStyle(statusPresentation.tone.statusColor)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(statusPresentation.title)
                            .font(.subheadline.weight(.medium))
                        if let error = note.transcriptionError, !error.isEmpty {
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
                if !isRetranscribing {
                    VoiceInkModeSelectionControlView(
                        modes: settings.modes,
                        selectedModeId: $settings.selectedModeId
                    )
                }

                if isRetranscribing {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text(VoiceInkTranscriptPresentation.retranscribingDisplayText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button {
                        retranscribe()
                    } label: {
                        Label(VoiceInkTranscriptPresentation.retryTranscriptionButtonTitle, systemImage: "arrow.clockwise")
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

private extension VoiceInkTranscriptStatusPresentation.Tone {
    var statusColor: Color {
        switch self {
        case .processing:
            return .orange
        case .failure:
            return .red
        }
    }
}
