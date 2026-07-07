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
    @Binding private var removeFillerWords: Bool
    @State private var fillerWords = VoiceInkFillerWordPreference.words()
    @State private var draftState = VoiceInkFillerWordDraftState()
    @State private var alertPresentation: VoiceInkDictionaryAlertPresentation?
    private let cleanupPresentation = VoiceInkTranscriptionCleanupPresentation.macOS

    init(removeFillerWords: Binding<Bool>) {
        self._removeFillerWords = removeFillerWords
    }

    var body: some View {
        let editorPresentation = VoiceInkFillerWords.editorPresentation(
            isEnabled: removeFillerWords,
            words: fillerWords
        )

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

            if editorPresentation.shouldShowEditor {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        TextField(cleanupPresentation.addFillerWordPlaceholder, text: $draftState.draft)
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
                        .disabled(!draftState.canSubmit)
                    }
                    .padding(.vertical, 4)

                    if editorPresentation.shouldShowWordList {
                        FlowLayout(spacing: 6) {
                            ForEach(fillerWords, id: \.self) { word in
                                FillerWordChip(word: word) {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        removeWord(word)
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
        draftState
            .submitting(existingWords: fillerWords)
            .applyRuntimeState(
                applyPlan: applySubmissionPlan,
                setDraftState: { draftState = $0 },
                setAlertPresentation: { alertPresentation = $0 }
            )
    }

    private func applySubmissionPlan(_ plan: VoiceInkFillerWordSubmissionPlan) {
        plan.applyRuntimeState(currentWords: fillerWords, setWords: setFillerWords)
    }

    private func removeWord(_ word: String) {
        setFillerWords(VoiceInkFillerWords.removing(word, from: fillerWords))
    }

    private func setFillerWords(_ words: [String]) {
        fillerWords = words
        VoiceInkFillerWordPreference.saveWords(words)
    }
}
