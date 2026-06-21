import SwiftUI
import SwiftData
import VoiceInkCore

struct VocabularyView: View {
    @Query private var vocabularyWords: [VocabularyWord]
    @Environment(\.modelContext) private var modelContext
    @State private var vocabularyDraftState = VoiceInkVocabularyDraftState()
    @State private var alertPresentation: VoiceInkDictionaryAlertPresentation?
    @State private var sortMode: VoiceInkVocabularySortMode = .defaultMode
    private let dictionaryPresentation = VoiceInkDictionarySettingsPresentation.macOS
    private let listPresentation = VoiceInkVocabularyListPresentation.macOS

    init() {
        _sortMode = State(initialValue: VoiceInkDictionaryListSortPreference.vocabularySortMode())
    }

    private func toggleSort() {
        sortMode = sortMode.toggled()
        VoiceInkDictionaryListSortPreference.saveVocabularySortMode(sortMode)
    }

    var body: some View {
        let sortedItems = VoiceInkDictionaryListSortPolicy.sortedVocabulary(vocabularyWords, mode: sortMode) { $0.word }
        let shouldShowAddButton = vocabularyDraftState.canSubmit

        VStack(alignment: .leading, spacing: 20) {
            if let helpText = dictionaryPresentation.vocabularyHelpText {
                GroupBox {
                    Label {
                        Text(helpText)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.blue)
                    }
                }
            }

            HStack(spacing: 8) {
                TextField(dictionaryPresentation.vocabularyPlaceholder, text: $vocabularyDraftState.draft)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
                    .onSubmit { addWords() }

                if shouldShowAddButton {
                    Button(action: addWords) {
                        Image(systemName: "plus.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.blue)
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .buttonStyle(.borderless)
                    .disabled(!shouldShowAddButton)
                    .help(dictionaryPresentation.addVocabularyButtonHelp ?? "")
                }
            }
            .animation(.easeInOut(duration: 0.2), value: shouldShowAddButton)

            if !vocabularyWords.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Button(action: toggleSort) {
                        HStack(spacing: 4) {
                            Text(listPresentation.wordsTitle(count: vocabularyWords.count))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)

                            Image(systemName: sortMode.indicatorSystemImageName)
                                .font(.caption)
                                .foregroundColor(.accentColor)
                        }
                    }
                    .buttonStyle(.plain)
                    .help(listPresentation.sortHelpText)

                    ScrollView {
                        FlowLayout(spacing: 8) {
                            ForEach(sortedItems) { item in
                                VocabularyWordView(
                                    item: item,
                                    removeButtonHelp: listPresentation.removeButtonHelp
                                ) {
                                    removeWord(item)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(maxHeight: 200)
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .alert(item: $alertPresentation) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .cancel(Text(alert.primaryButtonTitle))
            )
        }
    }
    
    private func addWords() {
        let submission = vocabularyDraftState.submitting(
            existingWords: vocabularyWords.map(\.word)
        )
        let appliedSubmission = DictionaryService.applyVocabularySubmission(
            submission,
            context: modelContext
        )
        vocabularyDraftState = appliedSubmission.draftStateAfterSubmit
        alertPresentation = appliedSubmission.alertPresentation
    }

    private func removeWord(_ word: VocabularyWord) {
        modelContext.delete(word)

        do {
            try modelContext.save()
        } catch {
            // Rollback the delete to restore UI consistency
            modelContext.rollback()
            alertPresentation = .vocabulary(
                message: VoiceInkDictionaryAlertPresentation.failedToRemoveVocabularyWord(
                    localizedDescription: error.localizedDescription
                )
            )
        }
    }
}

struct VocabularyWordView: View {
    let item: VocabularyWord
    let removeButtonHelp: String
    let onDelete: () -> Void
    @State private var isDeleteHovered = false

    var body: some View {
        HStack(spacing: 6) {
            Text(item.word)
                .font(.system(size: 13))
                .lineLimit(1)
                .foregroundColor(.primary)

            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isDeleteHovered ? .red : .secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.borderless)
            .help(removeButtonHelp)
            .onHover { hover in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isDeleteHovered = hover
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(.windowBackgroundColor).opacity(0.4))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.05), radius: 2, y: 1)
    }
} 
