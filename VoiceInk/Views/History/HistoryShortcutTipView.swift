import SwiftUI
import VoiceInkCore

struct HistoryShortcutTipView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: VoiceInkHistoryPresentation.macOSShortcutTip.systemImageName)
                    .font(.system(size: 20))
                    .foregroundColor(.accentColor)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(VoiceInkHistoryPresentation.macOSShortcutTip.title)
                        .font(.headline)
                    Text(VoiceInkHistoryPresentation.macOSShortcutTip.subtitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            Divider()
                .padding(.vertical, 4)

            HStack(spacing: 12) {
                Text(VoiceInkHistoryPresentation.macOSShortcutTip.shortcutLabel)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)

                ShortcutRecorder(action: .openHistoryWindow)
                    .controlSize(.small)

                Spacer()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(NSColor.separatorColor).opacity(0.3), lineWidth: 1)
        )
    }
}
