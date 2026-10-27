import SwiftUI
import VoiceInkCore

/// Text variants a History record can show.
/// `recognized` exists only on records that captured recognizer output, and is offered only
/// when it differs from `text` by exact UTF-8 code units (no normalization or trimming).
enum HistoryTextVariant: String, CaseIterable, Identifiable {
    case recognized
    case original
    case enhanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recognized: return "Recognized"
        case .original: return VoiceInkTranscriptTextVariant.original.title
        case .enhanced: return VoiceInkTranscriptTextVariant.enhanced.title
        }
    }

    var helpText: String {
        switch self {
        case .recognized: return "Exactly what speech recognition returned, before any cleanup."
        case .original: return "The transcription before AI enhancement."
        case .enhanced: return "The result returned by AI."
        }
    }

    var accessibilityIdentifier: String { "history.variant.\(rawValue)" }
    var textAccessibilityIdentifier: String { "history.text.\(rawValue)" }

    static func available(for transcription: Transcription) -> [Self] {
        var variants: [Self] = []
        if let recognition = transcription.recognitionText,
           !recognition.utf8.elementsEqual(transcription.text.utf8) {
            variants.append(.recognized)
        }
        variants.append(.original)
        if VoiceInkTranscriptTextVariant.shouldShowTabs(enhancedText: transcription.enhancedText) {
            variants.append(.enhanced)
        }
        return variants
    }

    func text(for transcription: Transcription) -> String {
        switch self {
        case .recognized:
            return transcription.recognitionText ?? ""
        case .original:
            return VoiceInkTranscriptTextVariant.original.displayText(
                rawText: transcription.text,
                enhancedText: transcription.enhancedText
            )
        case .enhanced:
            return VoiceInkTranscriptTextVariant.enhanced.displayText(
                rawText: transcription.text,
                enhancedText: transcription.enhancedText
            )
        }
    }
}

/// Inline notice for a record whose Light/Clarity processing failed.
/// It never stands in for the enhanced result and never claims editor delivery.
struct HistoryProcessingWarning: View {
    let transcription: Transcription

    private var title: String {
        guard let profile = transcription.dictationProfile else { return "Cleanup didn’t finish" }
        return "\(profile.historyTitle) cleanup didn’t finish"
    }

    private var message: String {
        if let recognition = transcription.recognitionText,
           recognition.utf8.elementsEqual(transcription.text.utf8) {
            return "The recognized text was kept unchanged as Original. Nothing was removed."
        }
        return "The transcription was kept without this cleanup step. Nothing was removed."
    }

    var body: some View {
        if let reason = transcription.processingFailureReason {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    if !reason.isEmpty {
                        Text(verbatim: reason)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .accessibilityIdentifier("history.processingWarning.reason")
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.yellow.opacity(0.12))
            )
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Warning: \(title)")
            .accessibilityIdentifier("history.processingWarning")
        }
    }
}

/// Compact list-row marker pointing at the full warning in the expanded/detail view.
struct HistoryProcessingWarningBadge: View {
    let transcription: Transcription

    var body: some View {
        if transcription.processingFailureReason != nil {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundStyle(.yellow)
                .help("Cleanup didn’t finish. The transcription was kept.")
                .accessibilityLabel("Cleanup didn’t finish")
                .accessibilityIdentifier("history.row.processingWarning")
        }
    }
}

/// Dictation Cleanup captured when the operation started. Hidden for older records and
/// for values this version does not recognize; nothing is defaulted to Custom or Natural.
struct HistoryCapturedCleanupLabel: View {
    let transcription: Transcription

    private var value: String? {
        guard let profile = transcription.dictationProfile else { return nil }
        if profile == .clarity, let style = transcription.clarityStyle {
            return "\(profile.historyTitle) · \(style.historyTitle)"
        }
        return profile.historyTitle
    }

    var body: some View {
        if let value {
            Label {
                Text("Cleanup: \(value)")
            } icon: {
                Image(systemName: "wand.and.sparkles")
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
            .help("Dictation Cleanup in effect when this transcription started.")
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("history.capturedCleanup")
        }
    }
}

private extension VoiceInkDictationProfile {
    var historyTitle: String {
        switch self {
        case .custom: return "Custom"
        case .none: return "None"
        case .light: return "Light"
        case .clarity: return "Clarity"
        }
    }
}

private extension VoiceInkClarityStyle {
    var historyTitle: String {
        switch self {
        case .natural: return "Natural"
        case .casual: return "Casual"
        case .formal: return "Formal"
        }
    }
}
