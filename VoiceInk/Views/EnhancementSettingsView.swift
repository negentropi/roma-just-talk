import SwiftUI
import UniformTypeIdentifiers
import VoiceInkCore

struct EnhancementSettingsView: View {
    @EnvironmentObject private var enhancementService: AIEnhancementService
    private let presentation = VoiceInkEnhancementSettingsPresentation.macOS
    /// The one owner of which sheet is up. Each case carries what its content needs, so the
    /// sheet renders from the presented item rather than from separate flags.
    @State private var activeSheet: ActiveSheet?

    private let sheetWidth: CGFloat = 400

    private enum ActiveSheet: Identifiable {
        case settings
        case addPrompt
        case editPrompt(VoiceInkCustomPrompt)

        var id: String {
            switch self {
            case .settings: "settings"
            case .addPrompt: "prompt.add"
            case .editPrompt(let prompt): "prompt.edit.\(prompt.id.uuidString)"
            }
        }
    }

    private var isShowingSettings: Bool {
        activeSheet?.id == ActiveSheet.settings.id
    }

    private func closeSheet() {
        activeSheet = nil
    }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $enhancementService.isEnhancementEnabled) {
                    HStack(spacing: 4) {
                        Text(presentation.enableEnhancementTitle)
                        InfoTip(
                            presentation.enableEnhancementHelp,
                            learnMoreURL: presentation.enableEnhancementLearnMoreURLString
                        )
                    }
                }
                .toggleStyle(.switch)
            } header: {
                HStack {
                    Text(presentation.generalSectionTitle)
                    Spacer()
                    Button {
                        activeSheet = .settings
                    } label: {
                        Image(systemName: presentation.settingsButtonSystemImageName)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(isShowingSettings ? .accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help(presentation.settingsButtonHelp)
                    .accessibilityLabel(presentation.settingsButtonHelp)
                    .accessibilityIdentifier("enhancement.settings.open")
                }
            }

            APIKeyManagementView()

            WritingActionsSettingsSection()

            Section {
                ReorderablePromptGrid(
                    selectedPromptId: enhancementService.selectedPromptId,
                    onPromptSelected: { prompt in
                        enhancementService.setActivePrompt(prompt)
                    },
                    onEditPrompt: { prompt in
                        activeSheet = .editPrompt(prompt)
                    },
                    onDeletePrompt: { prompt in
                        enhancementService.deletePrompt(prompt)
                    }
                )
                .padding(.vertical, 8)
            } header: {
                HStack {
                    Text(presentation.promptsSectionTitle)
                    Spacer()
                    Button {
                        activeSheet = .addPrompt
                    } label: {
                        Image(systemName: VoiceInkCustomPromptPresentation.addPromptSystemImageName)
                            .font(.system(size: 18))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(VoiceInkCustomPromptPresentation.addPromptHelpText)
                    .accessibilityLabel(VoiceInkCustomPromptPresentation.addPromptHelpText)
                    .accessibilityIdentifier("enhancement.prompts.add")
                }
            }
            .opacity(enhancementService.isEnhancementEnabled ? 1.0 : 0.8)
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color(NSColor.controlBackgroundColor))
        .settingsSheet(item: $activeSheet, width: sheetWidth) { sheet in
            switch sheet {
            case .settings:
                EnhancementSettingsPanel(onDismiss: closeSheet)
            case .addPrompt:
                PromptEditorView(mode: .add, onDismiss: closeSheet)
            case .editPrompt(let prompt):
                PromptEditorView(mode: .edit(prompt), onDismiss: closeSheet)
            }
        }
        .frame(minWidth: 500, minHeight: 400)
    }
}

// MARK: - Reorderable Grid
private struct ReorderablePromptGrid: View {
    @EnvironmentObject private var enhancementService: AIEnhancementService

    let selectedPromptId: UUID?
    let onPromptSelected: (VoiceInkCustomPrompt) -> Void
    let onEditPrompt: ((VoiceInkCustomPrompt) -> Void)?
    let onDeletePrompt: ((VoiceInkCustomPrompt) -> Void)?

    @State private var draggingItem: VoiceInkCustomPrompt?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if enhancementService.customPrompts.isEmpty {
                Text(VoiceInkCustomPromptPresentation.promptGridEmptyText)
                    .foregroundColor(.secondary)
                    .font(.caption)
            } else {
                let columns = [
                    GridItem(.adaptive(minimum: 80, maximum: 100), spacing: 36)
                ]

                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(enhancementService.customPrompts) { prompt in
                        prompt.promptIcon(
                            isSelected: selectedPromptId == prompt.id,
                            onTap: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    onPromptSelected(prompt)
                                }
                            },
                            onEdit: onEditPrompt,
                            onDelete: onDeletePrompt
                        )
                        .opacity(draggingItem?.id == prompt.id ? 0.3 : 1.0)
                        .scaleEffect(draggingItem?.id == prompt.id ? 1.05 : 1.0)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(
                                    draggingItem != nil && draggingItem?.id != prompt.id
                                    ? Color.accentColor.opacity(0.25)
                                    : Color.clear,
                                    lineWidth: 1
                                )
                        )
                        .animation(.easeInOut(duration: 0.15), value: draggingItem?.id == prompt.id)
                        .onDrag {
                            draggingItem = prompt
                            return NSItemProvider(object: prompt.id.uuidString as NSString)
                        }
                        .onDrop(
                            of: [UTType.text],
                            delegate: PromptDropDelegate(
                                item: prompt,
                                prompts: $enhancementService.customPrompts,
                                draggingItem: $draggingItem
                            )
                        )
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)

                HStack {
                    Image(systemName: VoiceInkCustomPromptPresentation.promptGridInfoSystemImageName)
                    .font(.caption)
                    .foregroundColor(.secondary)

                    Text(VoiceInkCustomPromptPresentation.promptGridHelpText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                .padding(.top, 8)
                .padding(.horizontal, 16)
            }
        }
    }
}

// MARK: - Drop Delegate
private struct PromptDropDelegate: DropDelegate {
    let item: VoiceInkCustomPrompt
    @Binding var prompts: [VoiceInkCustomPrompt]
    @Binding var draggingItem: VoiceInkCustomPrompt?

    func dropEntered(info: DropInfo) {
        guard let draggingItem = draggingItem, draggingItem != item else { return }
        guard let fromIndex = prompts.firstIndex(of: draggingItem),
              let toIndex = prompts.firstIndex(of: item) else { return }

        if prompts[toIndex].id != draggingItem.id {
            withAnimation(.easeInOut(duration: 0.12)) {
                let from = fromIndex
                let to = toIndex
                prompts.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
            }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingItem = nil
        return true
    }
}
