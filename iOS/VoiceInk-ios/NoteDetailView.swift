import SwiftUI
import SwiftData
import VoiceInkCore

struct NoteDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let note: Transcription
    
    @StateObject private var settings = AppSettings.shared
    @StateObject private var transcriptionTasks = IOSTranscriptionTaskCoordinator.shared
    @State private var selectedReprocessingPromptId: UUID?
    @State private var isReEnhancing = false
    @State private var reEnhancementTask: Task<Void, Never>?
    @State private var actionBanner: VoiceInkAudioPlaybackActionBannerPresentation?

    var body: some View {
        let isTranscriptionActive = transcriptionTasks.isActive(noteID: note.id)
        let presentation = VoiceInkNoteDetailPresentation.make(
            status: note.transcriptionStatus,
            rawText: note.text,
            enhancedText: note.enhancedText,
            transcriptionError: note.transcriptionError,
            isRetranscribing: isTranscriptionActive,
            canCancel: isTranscriptionActive,
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

                        if note.transcriptionStatus == .completed && !isTranscriptionActive {
                            historyReprocessingView(audioAvailability: presentation.audioAvailability)
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
        .onAppear {
            transcriptionTasks.recoverInterruptedTranscriptions(
                [note],
                persist: { try? modelContext.save() }
            )
        }
        .onDisappear {
            reEnhancementTask?.cancel()
        }
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
                    Spacer()
                    if statusPanel.retryControls.shouldShowCancelButton {
                        Button(role: .destructive) {
                            transcriptionTasks.cancel(noteID: note.id)
                        } label: {
                            Label(
                                VoiceInkTranscriptPresentation.cancelTranscriptionButtonTitle,
                                systemImage: VoiceInkTranscriptPresentation.cancelTranscriptionSystemImageName
                            )
                        }
                        .buttonStyle(.bordered)
                    }
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

    private func historyReprocessingView(
        audioAvailability: VoiceInkStoredAudioAvailability
    ) -> some View {
        let runSettings = settings.historyReprocessingRunSettings(
            promptOverrideId: selectedReprocessingPromptId
        )
        let reEnhancementControl = VoiceInkAudioPlaybackReEnhancementControlPresentation(
            isOperationInProgress: isReEnhancing,
            isEnhancementEnabled: runSettings.configuration.isPostProcessingEnabled,
            isEnhancementConfigured: VoiceInkProviderCredential.nonBlank(
                settings.apiKey(for: runSettings.configuration.postProcessingProvider)
            ) != nil
        )

        return VStack(alignment: .leading, spacing: 12) {
            Text(VoiceInkAudioPlaybackPresentation.historyReprocessingTitle)
                .font(.headline)

            VoiceInkModeSelectionControlView(
                modes: settings.modes,
                selectedModeId: $settings.selectedModeId
            )

            if runSettings.configuration.isPostProcessingEnabled {
                Picker(
                    VoiceInkAudioPlaybackPresentation.selectEnhancementPromptHelpText,
                    selection: $selectedReprocessingPromptId
                ) {
                    Text(VoiceInkAudioPlaybackPresentation.modePromptTitle).tag(nil as UUID?)
                    ForEach(settings.customPrompts) { prompt in
                        Text(prompt.title).tag(prompt.id as UUID?)
                    }
                }
            }

            HStack(spacing: 12) {
                Button {
                    retranscribeCompletedRecord(runSettings: runSettings)
                } label: {
                    Label(
                        VoiceInkAudioPlaybackPresentation.retranscribeButtonTitle,
                        systemImage: "arrow.clockwise"
                    )
                }
                .disabled(audioAvailability.existingURL == nil || isReEnhancing)

                Button {
                    reEnhance(runSettings: runSettings)
                } label: {
                    if isReEnhancing {
                        ProgressView()
                    } else {
                        Label(
                            VoiceInkAudioPlaybackPresentation.reEnhanceButtonTitle,
                            systemImage: "wand.and.stars"
                        )
                    }
                }
                .disabled(reEnhancementControl.isActionDisabled)
            }
            .buttonStyle(.bordered)

            if isReEnhancing {
                Button(role: .destructive) {
                    reEnhancementTask?.cancel()
                } label: {
                    Label(
                        VoiceInkTranscriptPresentation.cancelTranscriptionButtonTitle,
                        systemImage: VoiceInkTranscriptPresentation.cancelTranscriptionSystemImageName
                    )
                }
                .buttonStyle(.bordered)
            } else if let actionBanner {
                Label(
                    actionBanner.message,
                    systemImage: actionBanner.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                )
                .font(.callout)
                .foregroundStyle(actionBanner.isError ? Color.red : Color.green)
            } else if let unavailable = reEnhancementControl.unavailableBannerPresentation {
                Text(unavailable.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func retranscribe() {
        transcriptionTasks.start(
            note: note,
            persist: { try? modelContext.save() }
        )
    }

    private func retranscribeCompletedRecord(
        runSettings: VoiceInkTranscriptionRunSettings
    ) {
        let originalError = note.transcriptionError
        actionBanner = nil
        transcriptionTasks.start(
            note: note,
            persist: { try? modelContext.save() },
            operation: { note in
                await settings.retranscribeStoredAudio(note, runSettings: runSettings)
            },
            completion: { outcome in
                switch outcome {
                case .succeeded:
                    actionBanner = .retranscriptionSuccess
                case .failed(let reason):
                    note.transcriptionStatus = .completed
                    note.transcriptionError = originalError
                    try? modelContext.save()
                    actionBanner = .retranscriptionFailure(errorDescription: reason)
                case .canceled:
                    note.transcriptionStatus = .completed
                    note.transcriptionError = originalError
                    try? modelContext.save()
                }
            }
        )
    }

    private func reEnhance(runSettings: VoiceInkTranscriptionRunSettings) {
        actionBanner = nil
        isReEnhancing = true
        reEnhancementTask = Task {
            let outcome = await settings.reEnhanceStoredTranscription(
                note,
                runSettings: runSettings
            )

            switch outcome {
            case .succeeded:
                try? modelContext.save()
                actionBanner = .reEnhancementSuccess
            case .failed(let reason):
                actionBanner = .reEnhancementFailure(errorDescription: reason)
            case .canceled:
                break
            }
            isReEnhancing = false
            reEnhancementTask = nil
        }
    }
    
    private func copyToClipboard(_ text: String) {
        UIPasteboard.general.string = text
        
        // Optional: Add haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }
    

}
