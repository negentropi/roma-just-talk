import SwiftUI
import VoiceInkCore

struct PromptEditorView: View {
    enum Mode {
        case add
        case edit(VoiceInkCustomPrompt)
        
        static func == (lhs: Mode, rhs: Mode) -> Bool {
            switch (lhs, rhs) {
            case (.add, .add):
                return true
            case let (.edit(prompt1), .edit(prompt2)):
                return prompt1.id == prompt2.id
            default:
                return false
            }
        }
    }
    
    let mode: Mode
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var enhancementService: AIEnhancementService
    var onDismiss: (() -> Void)?
    @State private var draft: VoiceInkCustomPromptDraft
    @State private var showingIconPicker = false
    
    private var isEditingPredefinedPrompt: Bool {
        if case .edit(let prompt) = mode {
            return prompt.isPredefined
        }
        return false
    }

    init(mode: Mode, onDismiss: (() -> Void)? = nil) {
        self.mode = mode
        self.onDismiss = onDismiss
        switch mode {
        case .add:
            _draft = State(initialValue: .newPrompt)
        case .edit(let prompt):
            _draft = State(initialValue: VoiceInkCustomPromptDraft(prompt: prompt))
        }
    }
    
    private func dismissPanel() {
        if let onDismiss = onDismiss {
            onDismiss()
        } else {
            dismiss()
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Text(
                    VoiceInkCustomPromptPresentation.editorTitle(
                        isEditingPredefinedPrompt: isEditingPredefinedPrompt,
                        isAddingPrompt: mode == .add
                    )
                )
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Spacer()

                Button(action: dismissPanel) {
                    Image(systemName: VoiceInkCustomPromptPresentation.closeSystemImageName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(6)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help(VoiceInkCustomPromptPresentation.closeHelpText)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(NSColor.windowBackgroundColor))
            .overlay(
                Divider().opacity(0.5), alignment: .bottom
            )

            // Content
            if isEditingPredefinedPrompt {
                predefinedPromptForm
            } else {
                customPromptForm
            }

            // Footer
            VStack(spacing: 0) {
                HStack {
                    Button(VoiceInkCustomPromptPresentation.cancelActionTitle) { dismissPanel() }
                        .keyboardShortcut(.escape, modifiers: [])
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)

                    Spacer()

                    Button {
                        save()
                        dismissPanel()
                    } label: {
                        Text(VoiceInkCustomPromptPresentation.saveChangesButtonTitle)
                            .frame(minWidth: 100)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isEditingPredefinedPrompt ? false : !draft.isSaveable)
                    .keyboardShortcut(.return, modifiers: .command)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(Color(NSColor.windowBackgroundColor))
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Predefined Prompt Form

    private var predefinedPromptForm: some View {
        Form {
            Section {
                Text(VoiceInkCustomPromptPresentation.predefinedPromptRestrictionText)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } header: {
                Text(VoiceInkCustomPromptPresentation.editingHeaderTitle(for: draft.title))
            }

            Section {
                TriggerWordsEditor(triggerWords: $draft.triggerWords)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Custom Prompt Form

    private var customPromptForm: some View {
        Form {
            Section {
                HStack(alignment: .center, spacing: 14) {
                    Button(action: { showingIconPicker = true }) {
                        Image(systemName: draft.icon)
                            .font(.system(size: 22))
                            .foregroundColor(.primary)
                            .frame(width: 44, height: 44)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showingIconPicker, arrowEdge: .bottom) {
                        IconPickerPopover(selectedIcon: $draft.icon, isPresented: $showingIconPicker)
                    }

                    TextField(VoiceInkCustomPromptPresentation.promptNamePlaceholder, text: $draft.title)
                        .textFieldStyle(.roundedBorder)
                }

                TextField(VoiceInkCustomPromptPresentation.descriptionPlaceholder, text: $draft.description)
                    .textFieldStyle(.roundedBorder)
            } header: {
                Text(VoiceInkCustomPromptPresentation.detailsSectionTitle)
            }

            Section {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $draft.promptText)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 160)
                        .scrollContentBackground(.hidden)

                    if draft.promptText.isEmpty {
                        Text(VoiceInkCustomPromptPresentation.promptInstructionsPlaceholder)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }

                Toggle(isOn: $draft.useSystemInstructions) {
                    HStack(spacing: 4) {
                        Text(VoiceInkCustomPromptPresentation.useSystemTemplateTitle)
                        InfoTip(VoiceInkCustomPromptPresentation.useSystemTemplateHelpText)
                    }
                }
                .toggleStyle(.switch)
            } header: {
                Text(VoiceInkCustomPromptPresentation.instructionsSectionTitle)
            }

            Section {
                TriggerWordsEditor(triggerWords: $draft.triggerWords)
            } header: {
                HStack(spacing: 4) {
                    Text(VoiceInkCustomPromptPresentation.triggerWordsSectionTitle)
                    InfoTip(VoiceInkCustomPromptPresentation.triggerWordsHelpText)
                }
            }

            if case .add = mode {
                Section {
                    Menu {
                        ForEach(VoiceInkPromptTemplates.macTemplates, id: \.title) { template in
                            Button {
                                draft = draft.applyingTemplate(template)
                            } label: {
                                Label(template.title, systemImage: template.icon)
                            }
                        }
                    } label: {
                        Label(
                            VoiceInkCustomPromptPresentation.startWithTemplateTitle,
                            systemImage: VoiceInkCustomPromptPresentation.startWithTemplateIconSystemName
                        )
                    }
                    .menuStyle(.borderlessButton)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private func save() {
        switch mode {
        case .add:
            enhancementService.addPrompt(draft.customPrompt)
        case .edit(let prompt):
            enhancementService.updatePrompt(
                draft.applying(to: prompt)
            )
        }
    }
}

// MARK: - Trigger Words Editor
struct TriggerWordsEditor: View {
    @Binding var triggerWords: [String]
    @State private var triggerWordDraftState = VoiceInkPromptTriggerDraftState()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField(VoiceInkCustomPromptPresentation.triggerWordPlaceholder, text: $triggerWordDraftState.draft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addTriggerWord() }

                Button(action: { addTriggerWord() }) {
                    Image(systemName: VoiceInkCustomPromptPresentation.addTriggerWordSystemImageName)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.accentColor)
                        .font(.system(size: 18))
                }
                .buttonStyle(.plain)
                .disabled(!triggerWordDraftState.canSubmit)
            }

            if !triggerWords.isEmpty {
                TagLayout(alignment: .leading, spacing: 6) {
                    ForEach(triggerWords, id: \.self) { word in
                        TriggerWordItemView(word: word) {
                            triggerWords = VoiceInkPromptTriggerPolicy.removingTriggerWord(word, from: triggerWords)
                        }
                    }
                }
            } else {
                Text(VoiceInkCustomPromptPresentation.noTriggerWordsText)
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.7))
                    .italic()
            }
        }
    }
    
    private func addTriggerWord() {
        triggerWordDraftState
            .submitting(existingWords: triggerWords)
            .applyRuntimeState(
                setTriggerWords: { triggerWords = $0 },
                setDraftState: { triggerWordDraftState = $0 }
            )
    }
}

// MARK: - Trigger Word Item
struct TriggerWordItemView: View {
    let word: String
    let onDelete: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 4) {
                Text(word)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 120, alignment: .leading)
                    .foregroundColor(.primary)

            Button(action: onDelete) {
                Image(systemName: VoiceInkCustomPromptPresentation.removeTriggerWordSystemImageName)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.leading, 2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Tag Layout
struct TagLayout: Layout {
    var alignment: Alignment = .leading
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var height: CGFloat = 0
        var currentRowWidth: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            
            if currentRowWidth + size.width > maxWidth {
                // New row
                height += size.height + spacing
                currentRowWidth = size.width + spacing
            } else {
                // Same row
                currentRowWidth += size.width + spacing
            }
            
            if height == 0 {
                height = size.height
            }
        }
        
        return CGSize(width: maxWidth, height: height)
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        let maxHeight = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            
            if x + size.width > bounds.maxX {
                x = bounds.minX
                y += maxHeight + spacing
            }
            
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
        }
    }
}

// MARK: - Icon Picker
struct IconPickerPopover: View {
    @Binding var selectedIcon: String
    @Binding var isPresented: Bool
    
    var body: some View {
        let columns = [
            GridItem(.adaptive(minimum: 45, maximum: 52), spacing: 14)
        ]
        
        ScrollView {
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(VoiceInkCustomPromptPresentation.iconSystemNames, id: \.self) { icon in
                    Button(action: {
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                            selectedIcon = icon
                            isPresented = false
                        }
                    }) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(selectedIcon == icon ? Color(NSColor.windowBackgroundColor) : Color(NSColor.controlBackgroundColor))
                                .frame(width: 52, height: 52)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(selectedIcon == icon ? Color(NSColor.separatorColor) : Color.secondary.opacity(0.2), lineWidth: selectedIcon == icon ? 2 : 1)
                                )
                            
                            Image(systemName: icon)
                                .font(.system(size: 24, weight: .medium))
                                .foregroundColor(.primary)
                        }
                        .scaleEffect(selectedIcon == icon ? 1.1 : 1.0)
                        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: selectedIcon == icon)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
        }
        .frame(width: 400, height: 400)
    }
}
