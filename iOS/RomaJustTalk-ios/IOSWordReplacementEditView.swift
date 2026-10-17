import SwiftUI
import RomaCore

struct IOSWordReplacementEditSelection: Identifiable {
    let id = UUID()
    let rule: RomaWordReplacementRule
}

struct IOSWordReplacementEditView: View {
    let selection: IOSWordReplacementEditSelection
    let snapshot: RomaDictionarySettingsSnapshot
    let setRules: ([RomaWordReplacementRule]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var editState: RomaWordReplacementEditState
    @State private var alertPresentation: RomaDictionaryAlertPresentation?

    private let presentation = RomaWordReplacementEditPresentation.iOS

    init(
        selection: IOSWordReplacementEditSelection,
        snapshot: RomaDictionarySettingsSnapshot,
        setRules: @escaping ([RomaWordReplacementRule]) -> Void
    ) {
        self.selection = selection
        self.snapshot = snapshot
        self.setRules = setRules
        _editState = State(initialValue: RomaWordReplacementEditState(
            original: selection.rule.originalText,
            replacement: selection.rule.replacementText
        ))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(presentation.originalPlaceholder, text: $editState.original)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    requiredHeader(presentation.originalFieldTitle)
                }

                Section {
                    TextField(
                        presentation.replacementFieldTitle,
                        text: $editState.replacement,
                        axis: .vertical
                    )
                    .lineLimit(3...6)
                } header: {
                    requiredHeader(presentation.replacementFieldTitle)
                } footer: {
                    Text(presentation.descriptionText)
                }
            }
            .navigationTitle(presentation.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(presentation.cancelButtonTitle, role: .cancel) { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(presentation.saveButtonTitle, action: save)
                        .disabled(!editState.canSave)
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
    }

    private func requiredHeader(_ title: String) -> some View {
        HStack(spacing: 4) {
            Text(title)
            Text(presentation.requiredText)
                .foregroundStyle(.secondary)
        }
    }

    private func save() {
        let submission = snapshot.wordReplacementEditSubmission(
            editState,
            replacing: selection.rule
        )
        if let alert = submission.alertPresentation {
            alertPresentation = alert
            return
        }

        snapshot.applyWordReplacementEditSubmission(
            submission,
            replacing: selection.rule,
            setRules: setRules
        )
        if submission.shouldComplete {
            dismiss()
        }
    }
}
