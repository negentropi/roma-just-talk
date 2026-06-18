import SwiftUI
import SwiftData
import VoiceInkCore

// Edit existing word replacement entry
struct EditReplacementSheet: View {
    let replacement: WordReplacement
    let modelContext: ModelContext

    @Environment(\.dismiss) private var dismiss

    @State private var originalWord: String
    @State private var replacementWord: String
    @State private var alertPresentation: VoiceInkDictionaryAlertPresentation?
    private let editPresentation = VoiceInkWordReplacementEditPresentation.macOS

    // MARK: – Initialiser
    init(replacement: WordReplacement, modelContext: ModelContext) {
        self.replacement = replacement
        self.modelContext = modelContext
        _originalWord = State(initialValue: replacement.originalText)
        _replacementWord = State(initialValue: replacement.replacementText)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .overlay(Divider().opacity(0.5), alignment: .bottom)
            formContent
        }
        .frame(width: 460, height: 560)
        .alert(item: $alertPresentation) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .cancel(Text(alert.primaryButtonTitle))
            )
        }
    }

    // MARK: – Subviews
    private var header: some View {
        HStack {
            Button(editPresentation.cancelButtonTitle, role: .cancel) { dismiss() }
                .buttonStyle(.borderless)
                .keyboardShortcut(.escape, modifiers: [])

            Spacer()

            Text(editPresentation.title)
                .font(.headline)

            Spacer()

            Button(editPresentation.saveButtonTitle) { saveChanges() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!canSave)
                .keyboardShortcut(.return, modifiers: [])
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(CardBackground(isSelected: false))
    }

    private var formContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                descriptionSection
                inputSection
            }
            .padding(.vertical)
        }
    }

    private var descriptionSection: some View {
        Text(editPresentation.descriptionText)
            .font(.subheadline)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.top, 8)
    }

    private var inputSection: some View {
        VStack(spacing: 16) {
            // Original Text Field
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(editPresentation.originalFieldTitle)
                        .font(.headline)
                    Text(editPresentation.requiredText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                TextField(editPresentation.originalPlaceholder, text: $originalWord)
                    .textFieldStyle(.roundedBorder)
                
            }
            .padding(.horizontal)

            // Replacement Text Field
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(editPresentation.replacementFieldTitle)
                        .font(.headline)
                    Text(editPresentation.requiredText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                TextEditor(text: $replacementWord)
                    .font(.body)
                    .frame(height: 100)
                    .padding(8)
                    .background(Color(.textBackgroundColor))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(.separatorColor), lineWidth: 1)
                    )
            }
            .padding(.horizontal)
        }
    }

    private var canSave: Bool {
        VoiceInkDictionaryPolicy.canSaveWordReplacementDraft(
            original: originalWord,
            replacement: replacementWord
        )
    }

    // MARK: – Actions
    private func saveChanges() {
        guard canSave else {
            return
        }

        if let error = DictionaryService.updateWordReplacement(
            replacement,
            original: originalWord,
            replacement: replacementWord,
            context: modelContext
        ) {
            alertPresentation = .wordReplacement(message: error)
            return
        }

        dismiss()
    }
}
