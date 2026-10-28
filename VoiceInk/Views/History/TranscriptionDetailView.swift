import SwiftUI
import SwiftData
import VoiceInkCore

struct TranscriptionDetailView: View {
    let transcription: Transcription
    var onInfoTap: (() -> Void)?

    @Environment(\.modelContext) private var modelContext
    @State private var correctionTarget: SaveCorrectionTarget?
    @State private var correctionErrors: [HistoryTextVariant: String] = [:]

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
                        let text = variant.text(for: transcription)
                        // Keyed here, not inside the bubble: its `text` input can compare canonically
                        // equal, so an NFC/NFD-only change could skip the bubble's body entirely.
                        MessageBubble(
                            variant: variant,
                            text: text,
                            correctionError: correctionErrors[variant],
                            onSaveCorrection: { displayedText in
                                beginCorrection(variant: variant, displayedText: displayedText)
                            }
                        )
                        .id(HistoryRenderedTextIdentity(variant: variant, text: text))
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
        .settingsSheet(item: $correctionTarget, width: SaveCorrectionSheet.width) { target in
            SaveCorrectionSheet(target: target)
        }
    }

    /// Receives exactly the text the bubble rendered; never re-reads the record at click time.
    /// The service rejects it if the stored variant no longer matches those code units.
    private func beginCorrection(variant: HistoryTextVariant, displayedText: String) {
        do {
            correctionTarget = try SaveCorrectionTarget.capture(
                transcriptionID: transcription.id,
                variant: variant,
                displayedText: displayedText,
                using: modelContext
            )
            correctionErrors[variant] = nil
        } catch {
            correctionErrors[variant] = error.localizedDescription
        }
    }
}

private struct MessageBubble: View {
    let variant: HistoryTextVariant
    let text: String
    let correctionError: String?
    /// Called with the exact text value this bubble rendered.
    let onSaveCorrection: (_ displayedText: String) -> Void

    private var isEnhanced: Bool { variant == .enhanced }

    var body: some View {
        // One value per body evaluation: rendered, copied and captured for Save Correction alike.
        let shownText = text
        HStack(alignment: .bottom) {
            if isEnhanced { Spacer(minLength: 60) }

            VStack(alignment: isEnhanced ? .leading : .trailing, spacing: 4) {
                HStack(spacing: 8) {
                    Text(variant.title)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.7))
                        .help(variant.helpText)
                    SaveCorrectionButton(variant: variant) { onSaveCorrection(shownText) }
                }
                .padding(.horizontal, 12)

                ScrollView {
                    Text(verbatim: shownText)
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
                    CopyIconButton(textToCopy: shownText)
                        .accessibilityIdentifier("history.copy.\(variant.rawValue)")
                        .padding(8)
                }

                if let correctionError {
                    SaveCorrectionCaptureError(variant: variant, message: correctionError)
                        .padding(.horizontal, 12)
                }
            }

            if !isEnhanced { Spacer(minLength: 60) }
        }
    }


}
