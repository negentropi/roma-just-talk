import SwiftUI
import VoiceInkCore

struct NoteRowView: View {
    let note: Transcription

    var body: some View {
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

                if note.duration > 0 {
                    Text("•")
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

                if note.transcriptionStatus == .pending {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text(VoiceInkTranscriptPresentation.statusBadgeText(for: note.transcriptionStatus) ?? "")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                } else if note.transcriptionStatus == .failed {
                    Text(VoiceInkTranscriptPresentation.statusBadgeText(for: note.transcriptionStatus) ?? "")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
