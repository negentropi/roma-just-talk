import SwiftUI
import VoiceInkCore

struct NoteRowView: View {
    let note: Transcription

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(transcriptText)
                .font(.body)
                .foregroundStyle(.primary)
                .lineSpacing(2)
                .lineLimit(3)
                .multilineTextAlignment(.leading)

            HStack(spacing: 8) {
                Text(relativeTimestamp)
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
                        Text(statusBadgeText)
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                } else if note.transcriptionStatus == .failed {
                    Text(statusBadgeText)
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
    

    
    private var transcriptText: String {
        VoiceInkTranscriptPresentation.displayText(
            status: note.transcriptionStatus,
            rawText: note.text,
            enhancedText: note.enhancedText,
            pendingText: "New transcription",
            failedText: "Transcription failed - tap to retry",
            canceledText: "Transcription canceled",
            emptyCompletedText: "No audible content detected."
        )
    }

    private var statusBadgeText: String {
        VoiceInkTranscriptPresentation.statusBadgeText(for: note.transcriptionStatus) ?? ""
    }

    private var relativeTimestamp: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: note.timestamp, relativeTo: Date())
    }

}
