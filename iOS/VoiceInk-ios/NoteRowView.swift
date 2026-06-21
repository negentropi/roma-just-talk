import SwiftUI
import VoiceInkCore

struct NoteRowView: View {
    let note: Transcription

    var body: some View {
        let statusPresentation = VoiceInkTranscriptPresentation.statusPresentation(for: note.transcriptionStatus)

        VStack(alignment: .leading, spacing: 8) {
            Text(VoiceInkTranscriptPresentation.displayText(
                status: note.transcriptionStatus,
                rawText: note.text,
                enhancedText: note.enhancedText
            ))
                .font(.body)
                .foregroundStyle(.primary)
                .lineSpacing(2)
                .lineLimit(3)
                .multilineTextAlignment(.leading)

            HStack(spacing: 8) {
                Text(VoiceInkDatePresentation.relativeTimestamp(note.timestamp))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if VoiceInkDurationPresentation.shouldShowPositiveDuration(note.duration) {
                    Text(VoiceInkDurationPresentation.metadataSeparatorText)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text(VoiceInkDurationPresentation.minutesSeconds(
                        note.duration,
                        padMinutesToTwoDigits: true
                    ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                if let statusPresentation {
                    switch statusPresentation.inlineAccessory {
                    case .progress:
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text(statusPresentation.badgeText)
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                    case .badge:
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
