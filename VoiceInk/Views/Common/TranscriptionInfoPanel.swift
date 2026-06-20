import SwiftUI
import VoiceInkCore

/// Reusable component that displays transcription Details and AI Request sections.
/// Used in both the inline history sliding panel and the separate history window's metadata view.
struct TranscriptionInfoPanel: View {
    let transcription: Transcription

    var body: some View {
        Form {
            detailsSection
            aiRequestSection
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Details Section

    private var detailsSection: some View {
        Section {
            metadataRow(
                VoiceInkTranscriptionMetadataPresentation.dateRow,
                value: VoiceInkDatePresentation.abbreviatedTimestamp(transcription.timestamp)
            )

            metadataRow(
                VoiceInkTranscriptionMetadataPresentation.durationRow,
                value: VoiceInkDurationPresentation.compactElapsed(transcription.duration)
            )

            if let modelName = transcription.transcriptionModelName {
                metadataRow(
                    VoiceInkTranscriptionMetadataPresentation.transcriptionModelRow,
                    value: modelName
                )

                if let duration = transcription.transcriptionDuration {
                    metadataRow(
                        VoiceInkTranscriptionMetadataPresentation.transcriptionTimeRow,
                        value: VoiceInkDurationPresentation.compactElapsed(duration)
                    )
                }
            }

            if let aiModel = transcription.aiEnhancementModelName {
                metadataRow(
                    VoiceInkTranscriptionMetadataPresentation.enhancementModelRow,
                    value: aiModel
                )

                if let duration = transcription.enhancementDuration {
                    metadataRow(
                        VoiceInkTranscriptionMetadataPresentation.enhancementTimeRow,
                        value: VoiceInkDurationPresentation.compactElapsed(duration)
                    )
                }
            }

            if let promptName = transcription.promptName {
                metadataRow(
                    VoiceInkTranscriptionMetadataPresentation.promptRow,
                    value: promptName
                )
            }

            let powerModeValue = VoiceInkPowerModePresentation.displayName(
                name: transcription.powerModeName,
                emoji: transcription.powerModeEmoji
            )
            if !powerModeValue.isEmpty {
                metadataRow(
                    VoiceInkTranscriptionMetadataPresentation.powerModeRow,
                    value: powerModeValue
                )
            }
        } header: {
            Text(VoiceInkTranscriptionMetadataPresentation.detailsSectionTitle)
        }
    }

    // MARK: - AI Request Section

    @ViewBuilder
    private var aiRequestSection: some View {
        if VoiceInkTranscriptionMetadataPresentation.shouldShowAIRequestSection(
            systemMessage: transcription.aiRequestSystemMessage,
            userMessage: transcription.aiRequestUserMessage
        ) {
            Section {
                if let systemMsg = transcription.aiRequestSystemMessage, !systemMsg.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(VoiceInkTranscriptionMetadataPresentation.systemPromptLabel)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                        Text(systemMsg)
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .lineSpacing(2)
                            .textSelection(.enabled)
                            .foregroundColor(.primary)
                    }
                }

                if let userMsg = transcription.aiRequestUserMessage, !userMsg.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(VoiceInkTranscriptionMetadataPresentation.userMessageLabel)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                        Text(userMsg)
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .lineSpacing(2)
                            .textSelection(.enabled)
                            .foregroundColor(.primary)
                    }
                }
            } header: {
                HStack {
                    Text(VoiceInkTranscriptionMetadataPresentation.aiRequestSectionTitle)
                    Spacer()
                    CopyIconButton(textToCopy: fullRequestText)
                }
            }
        }
    }

    // MARK: - Helpers

    private var fullRequestText: String {
        VoiceInkTranscriptionMetadataPresentation.fullAIRequestText(
            systemMessage: transcription.aiRequestSystemMessage,
            userMessage: transcription.aiRequestUserMessage
        )
    }

    private func metadataRow(
        _ presentation: VoiceInkTranscriptionMetadataRowPresentation,
        value: String
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: presentation.systemImageName)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 20, height: 20)

            Text(presentation.label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)

            Spacer(minLength: 0)

            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.primary)
                .lineLimit(1)
        }
    }
}
