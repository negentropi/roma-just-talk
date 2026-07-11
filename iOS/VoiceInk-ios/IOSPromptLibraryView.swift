import SwiftUI
import VoiceInkCore

private enum IOSPromptEditorTarget: Identifiable {
    case add
    case edit(VoiceInkCustomPrompt)

    var id: String {
        switch self {
        case .add:
            return "add"
        case .edit(let prompt):
            return prompt.id.uuidString
        }
    }

    var context: VoiceInkCustomPromptEditorContext {
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
    @State private var deletionTarget: VoiceInkCustomPrompt?

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
                            if let summary = VoiceInkCustomPromptPresentation.triggerSummary(
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
                                VoiceInkCustomPromptPresentation.deleteActionTitle,
                                systemImage: VoiceInkCustomPromptPresentation.deleteActionSystemImageName
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
                    Image(systemName: VoiceInkCustomPromptPresentation.addPromptSystemImageName)
                }
                .accessibilityLabel(VoiceInkCustomPromptPresentation.addPromptHelpText)
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
            VoiceInkCustomPromptPresentation.deletePromptConfirmationTitle,
            isPresented: Binding(
                get: { deletionTarget != nil },
                set: { if !$0 { deletionTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(VoiceInkCustomPromptPresentation.deleteActionTitle, role: .destructive) {
                if let deletionTarget {
                    settings.removePrompt(deletionTarget)
                }
                deletionTarget = nil
            }
            Button(VoiceInkCustomPromptPresentation.cancelActionTitle, role: .cancel) {
                deletionTarget = nil
            }
        } message: {
            if let deletionTarget {
                Text(VoiceInkCustomPromptPresentation.deletePromptConfirmationMessage(
                    promptTitle: deletionTarget.title
                ))
            }
        }
    }
}

private struct IOSPromptEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let context: VoiceInkCustomPromptEditorContext
    let onSave: (VoiceInkCustomPromptEditorSavePlan) -> Void
    @State private var draft: VoiceInkCustomPromptDraft
    @State private var triggerWordDraft = VoiceInkPromptTriggerDraftState()

    init(
        context: VoiceInkCustomPromptEditorContext,
        onSave: @escaping (VoiceInkCustomPromptEditorSavePlan) -> Void
    ) {
        self.context = context
        self.onSave = onSave
        _draft = State(initialValue: context.initialDraft)
    }

    var body: some View {
        Form {
            if context.shouldShowPredefinedPromptForm {
                Section {
                    Text(VoiceInkCustomPromptPresentation.predefinedPromptRestrictionText)
                        .foregroundStyle(.secondary)
                }
            } else {
                if context.shouldShowTemplateSection {
                    Section(VoiceInkCustomPromptPresentation.startWithTemplateTitle) {
                        Menu("Choose Template") {
                            ForEach(VoiceInkPromptTemplates.macTemplates) { template in
                                Button(template.title) {
                                    draft = draft.applyingTemplate(template)
                                }
                            }
                        }
                    }
                }

                Section(VoiceInkCustomPromptPresentation.detailsSectionTitle) {
                    TextField(VoiceInkCustomPromptPresentation.promptNamePlaceholder, text: $draft.title)
                    TextField(VoiceInkCustomPromptPresentation.descriptionPlaceholder, text: $draft.description)
                    Picker("Icon", selection: $draft.icon) {
                        ForEach(VoiceInkCustomPromptPresentation.iconSystemNames, id: \.self) { icon in
                            Label(icon, systemImage: icon).tag(icon)
                        }
                    }
                }

                Section(VoiceInkCustomPromptPresentation.instructionsSectionTitle) {
                    TextEditor(text: $draft.promptText)
                        .frame(minHeight: 160)
                    Toggle(
                        VoiceInkCustomPromptPresentation.useSystemTemplateTitle,
                        isOn: $draft.useSystemInstructions
                    )
                    Text(VoiceInkCustomPromptPresentation.useSystemTemplateHelpText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section(VoiceInkCustomPromptPresentation.triggerWordsSectionTitle) {
                HStack {
                    TextField(
                        VoiceInkCustomPromptPresentation.triggerWordPlaceholder,
                        text: $triggerWordDraft.draft
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit(addTriggerWord)

                    Button(action: addTriggerWord) {
                        Image(systemName: VoiceInkCustomPromptPresentation.addTriggerWordSystemImageName)
                    }
                    .disabled(!triggerWordDraft.canSubmit)
                }

                if draft.triggerWords.isEmpty {
                    Text(VoiceInkCustomPromptPresentation.noTriggerWordsText)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(draft.triggerWords, id: \.self) { word in
                        HStack {
                            Text(word)
                            Spacer()
                            Button(role: .destructive) {
                                draft.triggerWords = VoiceInkPromptTriggerPolicy.removingTriggerWord(
                                    word,
                                    from: draft.triggerWords
                                )
                            } label: {
                                Image(systemName: VoiceInkCustomPromptPresentation.removeTriggerWordSystemImageName)
                            }
                        }
                    }
                }

                Text(VoiceInkCustomPromptPresentation.triggerWordsHelpText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(context.editorTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(VoiceInkCustomPromptPresentation.cancelActionTitle) {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(VoiceInkCustomPromptPresentation.saveChangesButtonTitle) {
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
