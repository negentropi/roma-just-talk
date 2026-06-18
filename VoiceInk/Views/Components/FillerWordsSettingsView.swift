import SwiftUI
import VoiceInkCore

struct FillerWordChip: View {
    let word: String
    let onDelete: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 4) {
            Text(word)
                .font(.system(size: 12))
                .foregroundColor(.primary)

            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isHovered ? .red : .secondary)
                    .font(.system(size: 10))
            }
            .buttonStyle(.borderless)
            .onHover { hover in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isHovered = hover
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(.windowBackgroundColor).opacity(0.4))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
}

struct FillerWordsSettingsView: View {
    @AppStorage(VoiceInkUserDefaultsKey.removeFillerWords)
    private var removeFillerWords = VoiceInkPreferenceDefault.removeFillerWords
    @StateObject private var fillerWordManager = FillerWordManager.shared
    @State private var newWord = ""
    @State private var alertPresentation: VoiceInkDictionaryAlertPresentation?
    private let cleanupPresentation = VoiceInkTranscriptionCleanupPresentation.macOS

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(cleanupPresentation.removeFillerWordsToggleTitle)
                if let helpText = cleanupPresentation.removeFillerWordsHelpText {
                    InfoTip(helpText)
                }
                Spacer()
                Toggle("", isOn: $removeFillerWords)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            if removeFillerWords {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        TextField(cleanupPresentation.addFillerWordPlaceholder, text: $newWord)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel(cleanupPresentation.addFillerWordPlaceholder)
                            .onSubmit { addWord() }

                        Button(action: addWord) {
                            Image(systemName: "plus.circle.fill")
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.blue)
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(cleanupPresentation.addFillerWordPlaceholder)
                        .disabled(!canAddWord)
                    }
                    .padding(.vertical, 4)

                    if !fillerWordManager.fillerWords.isEmpty {
                        FlowLayout(spacing: 6) {
                            ForEach(fillerWordManager.fillerWords, id: \.self) { word in
                                FillerWordChip(word: word) {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        fillerWordManager.removeWord(word)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .alert(item: $alertPresentation) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .cancel(Text(alert.primaryButtonTitle))
            )
        }
    }

    private func addWord() {
        guard canAddWord else { return }

        if let errorMessage = fillerWordManager.addWord(newWord) {
            alertPresentation = .duplicateFillerWord(message: errorMessage)
            return
        }

        newWord = ""
    }

    private var canAddWord: Bool {
        VoiceInkFillerWords.hasDraft(newWord)
    }
}
