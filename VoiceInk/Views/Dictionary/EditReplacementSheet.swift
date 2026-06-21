import SwiftUI
import SwiftData
import VoiceInkCore

// Edit existing word replacement entry
struct EditReplacementSheet: View {
    let replacement: WordReplacement
    let modelContext: ModelContext

    @Environment(\.dismiss) private var dismiss

    @State private var editState: VoiceInkWordReplacementEditState
    @State private var alertPresentation: VoiceInkDictionaryAlertPresentation?
    private let editPresentation = VoiceInkWordReplacementEditPresentation.macOS

    // MARK: – Initialiser
    init(replacement: WordReplacement, modelContext: ModelContext) {
        self.replacement = replacement
        self.modelContext = modelContext
        _editState = State(initialValue: VoiceInkWordReplacementEditState(
            original: replacement.originalText,
            replacement: replacement.replacementText
        ))
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
                TextField(editPresentation.originalPlaceholder, text: $editState.original)
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
                TextEditor(text: $editState.replacement)
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
        editState.canSave
    }

    // MARK: – Actions
    private func saveChanges() {
        guard canSave else {
            return
        }

        let submission = DictionaryService.updateWordReplacement(
            replacement,
            editState: editState,
            context: modelContext
        )
        if let alert = submission.alertPresentation {
            alertPresentation = alert
            return
        }

        if submission.shouldComplete {
            dismiss()
        }
    }
}
