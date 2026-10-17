import SwiftUI
import RomaCore

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
                RomaTranscriptionMetadataPresentation.dateRow,
                value: RomaDatePresentation.abbreviatedTimestamp(transcription.timestamp)
            )

            metadataRow(
                RomaTranscriptionMetadataPresentation.durationRow,
                value: RomaDurationPresentation.compactElapsed(transcription.duration)
            )

            if let modelName = transcription.transcriptionModelName {
                metadataRow(
                    RomaTranscriptionMetadataPresentation.transcriptionModelRow,
                    value: modelName
                )

                if let duration = transcription.transcriptionDuration {
                    metadataRow(
                        RomaTranscriptionMetadataPresentation.transcriptionTimeRow,
                        value: RomaDurationPresentation.compactElapsed(duration)
                    )
                }
            }

            if let aiModel = transcription.aiEnhancementModelName {
                metadataRow(
                    RomaTranscriptionMetadataPresentation.enhancementModelRow,
                    value: aiModel
                )

                if let duration = transcription.enhancementDuration {
                    metadataRow(
                        RomaTranscriptionMetadataPresentation.enhancementTimeRow,
                        value: RomaDurationPresentation.compactElapsed(duration)
                    )
                }
            }

            if let promptName = transcription.promptName {
                metadataRow(
                    RomaTranscriptionMetadataPresentation.promptRow,
                    value: promptName
                )
            }

            let powerModeValue = RomaPowerModePresentation.displayName(
                name: transcription.powerModeName,
                emoji: transcription.powerModeEmoji
            )
            if !powerModeValue.isEmpty {
                metadataRow(
                    RomaTranscriptionMetadataPresentation.powerModeRow,
                    value: powerModeValue
                )
            }
        } header: {
            Text(RomaTranscriptionMetadataPresentation.detailsSectionTitle)
        }
    }

    // MARK: - AI Request Section

    @ViewBuilder
    private var aiRequestSection: some View {
        if RomaTranscriptionMetadataPresentation.shouldShowAIRequestSection(
            systemMessage: transcription.aiRequestSystemMessage,
            userMessage: transcription.aiRequestUserMessage
        ) {
            Section {
                if let systemMsg = transcription.aiRequestSystemMessage, !systemMsg.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(RomaTranscriptionMetadataPresentation.systemPromptLabel)
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
                        Text(RomaTranscriptionMetadataPresentation.userMessageLabel)
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
                    Text(RomaTranscriptionMetadataPresentation.aiRequestSectionTitle)
                    Spacer()
                    CopyIconButton(textToCopy: fullRequestText)
                }
            }
        }
    }

    // MARK: - Helpers

    private var fullRequestText: String {
        RomaTranscriptionMetadataPresentation.fullAIRequestText(
            systemMessage: transcription.aiRequestSystemMessage,
            userMessage: transcription.aiRequestUserMessage
        )
    }

    private func metadataRow(
        _ presentation: RomaTranscriptionMetadataRowPresentation,
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
