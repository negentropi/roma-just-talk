import SwiftUI
import VoiceInkCore

struct TranscriptionDetailView: View {
    let transcription: Transcription
    var onInfoTap: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            ScrollView {
                VStack(spacing: 16) {
                    if transcription.dictationProfile != nil || transcription.processingFailureReason != nil {
                        VStack(alignment: .leading, spacing: 8) {
                            HistoryCapturedCleanupLabel(transcription: transcription)
                            HistoryProcessingWarning(transcription: transcription)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    ForEach(HistoryTextVariant.available(for: transcription)) { variant in
                        MessageBubble(
                            variant: variant,
                            text: variant.text(for: transcription)
                        )
                    }
                }
                .padding(16)
            }

            if let url = transcription.storedAudioAvailability().existingURL {
                VStack(spacing: 0) {
                    Divider()

                    AudioPlayerView(url: url, transcription: transcription, onInfoTap: onInfoTap)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
                        )
                        .padding(.horizontal, 12)
                        .padding(.top, 6)
                }
            }
        }
        .padding(.vertical, 12)
        .background(Color(NSColor.controlBackgroundColor))
    }
}

private struct MessageBubble: View {
    let variant: HistoryTextVariant
    let text: String

    private var isEnhanced: Bool { variant == .enhanced }

    var body: some View {
        HStack(alignment: .bottom) {
            if isEnhanced { Spacer(minLength: 60) }

            VStack(alignment: isEnhanced ? .leading : .trailing, spacing: 4) {
                Text(variant.title)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.7))
                    .padding(.horizontal, 12)
                    .help(variant.helpText)

                ScrollView {
                    Text(verbatim: text)
                        .font(.system(size: 14, weight: .regular))
                        .lineSpacing(2)
                        .textSelection(.enabled)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .accessibilityIdentifier(variant.textAccessibilityIdentifier)
                }
                .frame(maxHeight: 350)
                .background {
                    if isEnhanced {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.accentColor.opacity(0.2))
                    } else if variant == .recognized {
                        // Dashed edge marks the untouched recognizer output.
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(
                                Color.secondary.opacity(0.35),
                                style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                            )
                    } else {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(.thinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                            )
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    CopyIconButton(textToCopy: text)
                        .accessibilityIdentifier("history.copy.\(variant.rawValue)")
                        .padding(8)
                }
            }

            if !isEnhanced { Spacer(minLength: 60) }
        }
    }


}
