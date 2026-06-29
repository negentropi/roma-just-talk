import SwiftUI
import VoiceInkCore

struct NoteRowView: View {
    let note: Transcription

    var body: some View {
        let presentation = VoiceInkNoteRowPresentation.make(
            status: note.transcriptionStatus,
            rawText: note.text,
            enhancedText: note.enhancedText,
            timestamp: note.timestamp,
            duration: note.duration
        )

        VStack(alignment: .leading, spacing: 8) {
            Text(presentation.displayText)
                .font(.body)
                .foregroundStyle(.primary)
                .lineSpacing(2)
                .lineLimit(3)
                .multilineTextAlignment(.leading)

            HStack(spacing: 8) {
                Text(presentation.timestampText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let durationText = presentation.durationText,
                   let metadataSeparatorText = presentation.metadataSeparatorText {
                    Text(metadataSeparatorText)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text(durationText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                if let statusPresentation = presentation.statusPresentation {
                    if statusPresentation.shouldShowInlineProgress {
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text(statusPresentation.badgeText)
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                    } else if statusPresentation.shouldShowInlineBadge {
                        Text(statusPresentation.badgeText)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(statusPresentation.tone.badgeColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(statusPresentation.tone.badgeBackgroundColor)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
