import SwiftUI
import RomaCore

private enum IOSPromptEditorTarget: Identifiable {
    case add
    case edit(RomaCustomPrompt)

    var id: String {
        switch self {
        case .add:
            return "add"
        case .edit(let prompt):
            return prompt.id.uuidString
        }
    }

    var context: RomaCustomPromptEditorContext {
        switch self {
        case .add:
            return .add
        case .edit(let prompt):
            return .edit(prompt: prompt)
        }
    }
}

struct IOSPromptLibraryView: View {
    @ObservedObject var settings: AppSettings
    @State private var editorTarget: IOSPromptEditorTarget?
    @State private var deletionTarget: RomaCustomPrompt?

    var body: some View {
        List {
            ForEach(settings.customPrompts) { prompt in
                Button {
                    editorTarget = .edit(prompt)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: prompt.icon)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(prompt.title)
                                .foregroundStyle(.primary)
                            if let description = prompt.description, !description.isEmpty {
                                Text(description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let summary = RomaCustomPromptPresentation.triggerSummary(
                                for: prompt.triggerWords
                            ) {
                                Label(summary.text, systemImage: summary.iconSystemName)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
                .swipeActions {
                    if !prompt.isPredefined {
                        Button(role: .destructive) {
                            deletionTarget = prompt
                        } label: {
                            Label(
                                RomaCustomPromptPresentation.deleteActionTitle,
                                systemImage: RomaCustomPromptPresentation.deleteActionSystemImageName
                            )
                        }
                    }
                }
            }
            .onMove(perform: settings.movePrompts)
        }
        .navigationTitle("Prompt Library")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                EditButton()
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editorTarget = .add
                } label: {
                    Image(systemName: RomaCustomPromptPresentation.addPromptSystemImageName)
                }
                .accessibilityLabel(RomaCustomPromptPresentation.addPromptHelpText)
            }
        }
        .sheet(item: $editorTarget) { target in
            NavigationStack {
                IOSPromptEditorView(context: target.context) { plan in
                    plan.applyRuntimeState(
                        addPrompt: settings.addPrompt,
                        updatePrompt: settings.updatePrompt
                    )
                }
            }
        }
        .confirmationDialog(
            RomaCustomPromptPresentation.deletePromptConfirmationTitle,
            isPresented: Binding(
                get: { deletionTarget != nil },
                set: { if !$0 { deletionTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(RomaCustomPromptPresentation.deleteActionTitle, role: .destructive) {
                if let deletionTarget {
                    settings.removePrompt(deletionTarget)
                }
                deletionTarget = nil
            }
            Button(RomaCustomPromptPresentation.cancelActionTitle, role: .cancel) {
                deletionTarget = nil
            }
        } message: {
            if let deletionTarget {
                Text(RomaCustomPromptPresentation.deletePromptConfirmationMessage(
                    promptTitle: deletionTarget.title
                ))
            }
        }
    }
}

private struct IOSPromptEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let context: RomaCustomPromptEditorContext
    let onSave: (RomaCustomPromptEditorSavePlan) -> Void
    @State private var draft: RomaCustomPromptDraft
    @State private var triggerWordDraft = RomaPromptTriggerDraftState()

    init(
        context: RomaCustomPromptEditorContext,
        onSave: @escaping (RomaCustomPromptEditorSavePlan) -> Void
    ) {
        self.context = context
        self.onSave = onSave
        _draft = State(initialValue: context.initialDraft)
    }

    var body: some View {
        Form {
            if context.shouldShowPredefinedPromptForm {
                Section {
                    Text(RomaCustomPromptPresentation.predefinedPromptRestrictionText)
                        .foregroundStyle(.secondary)
                }
            } else {
                if context.shouldShowTemplateSection {
                    Section(RomaCustomPromptPresentation.startWithTemplateTitle) {
                        Menu("Choose Template") {
                            ForEach(RomaPromptTemplates.macTemplates) { template in
                                Button(template.title) {
                                    draft = draft.applyingTemplate(template)
                                }
                            }
                        }
                    }
                }

                Section(RomaCustomPromptPresentation.detailsSectionTitle) {
                    TextField(RomaCustomPromptPresentation.promptNamePlaceholder, text: $draft.title)
                    TextField(RomaCustomPromptPresentation.descriptionPlaceholder, text: $draft.description)
                    Picker("Icon", selection: $draft.icon) {
                        ForEach(RomaCustomPromptPresentation.iconSystemNames, id: \.self) { icon in
                            Label(icon, systemImage: icon).tag(icon)
                        }
                    }
                }

                Section(RomaCustomPromptPresentation.instructionsSectionTitle) {
                    TextEditor(text: $draft.promptText)
                        .frame(minHeight: 160)
                    Toggle(
                        RomaCustomPromptPresentation.useSystemTemplateTitle,
                        isOn: $draft.useSystemInstructions
                    )
                    Text(RomaCustomPromptPresentation.useSystemTemplateHelpText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section(RomaCustomPromptPresentation.triggerWordsSectionTitle) {
                HStack {
                    TextField(
                        RomaCustomPromptPresentation.triggerWordPlaceholder,
                        text: $triggerWordDraft.draft
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit(addTriggerWord)

                    Button(action: addTriggerWord) {
                        Image(systemName: RomaCustomPromptPresentation.addTriggerWordSystemImageName)
                    }
                    .disabled(!triggerWordDraft.canSubmit)
                }

                if draft.triggerWords.isEmpty {
                    Text(RomaCustomPromptPresentation.noTriggerWordsText)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(draft.triggerWords, id: \.self) { word in
                        HStack {
                            Text(word)
                            Spacer()
                            Button(role: .destructive) {
                                draft.triggerWords = RomaPromptTriggerPolicy.removingTriggerWord(
                                    word,
                                    from: draft.triggerWords
                                )
                            } label: {
                                Image(systemName: RomaCustomPromptPresentation.removeTriggerWordSystemImageName)
                            }
                        }
                    }
                }

                Text(RomaCustomPromptPresentation.triggerWordsHelpText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(context.editorTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(RomaCustomPromptPresentation.cancelActionTitle) {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(RomaCustomPromptPresentation.saveChangesButtonTitle) {
                    onSave(context.savePlan(for: draft))
                    dismiss()
                }
                .disabled(context.isSaveButtonDisabled(for: draft))
            }
        }
    }

    private func addTriggerWord() {
        triggerWordDraft
            .submitting(existingWords: draft.triggerWords)
            .applyRuntimeState(
                setTriggerWords: { draft.triggerWords = $0 },
                setDraftState: { triggerWordDraft = $0 }
            )
    }
}
