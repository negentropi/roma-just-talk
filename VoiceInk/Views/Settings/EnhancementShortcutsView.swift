import SwiftUI
import VoiceInkCore

struct EnhancementShortcutsView: View {
    private let presentation = VoiceInkEnhancementSettingsPresentation.macOS

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                HStack(spacing: 4) {
                    Text(presentation.toggleEnhancementShortcutTitle)
                        .font(.system(size: 13))

                    InfoTip(
                        presentation.toggleEnhancementShortcutHelp,
                        learnMoreURL: presentation.shortcutLearnMoreURLString
                    )
                }

                Spacer()

                ShortcutRecorder(action: .toggleEnhancement)
                    .controlSize(.small)
            }

            HStack(alignment: .center, spacing: 12) {
                HStack(spacing: 4) {
                    Text(presentation.switchPromptShortcutTitle)
                        .font(.system(size: 13))

                    InfoTip(
                        presentation.switchPromptShortcutHelp,
                        learnMoreURL: presentation.shortcutLearnMoreURLString
                    )
                }

                Spacer()

                HStack(spacing: 4) {
                    ForEach(presentation.switchPromptKeyChipTitles, id: \.self) { title in
                        KeyChip(label: title)
                    }
                }
            }
        }
        .background(Color.clear)
    }
}

// MARK: - Supporting Views
private struct KeyChip: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundColor(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(
                        Color(NSColor.separatorColor).opacity(0.5),
                        lineWidth: 0.5
                    )
            )
    }
}
