import SwiftUI
import RomaCore

/// A reusable grid component for selecting prompts with a plus button to add new ones
struct PromptSelectionGrid: View {
    @EnvironmentObject private var enhancementService: AIEnhancementService
    
    let prompts: [RomaCustomPrompt]
    let selectedPromptId: UUID?
    let onPromptSelected: (RomaCustomPrompt) -> Void
    let onEditPrompt: ((RomaCustomPrompt) -> Void)?
    let onDeletePrompt: ((RomaCustomPrompt) -> Void)?
    let onAddNewPrompt: (() -> Void)?
    
    init(
        prompts: [RomaCustomPrompt],
        selectedPromptId: UUID?,
        onPromptSelected: @escaping (RomaCustomPrompt) -> Void,
        onEditPrompt: ((RomaCustomPrompt) -> Void)? = nil,
        onDeletePrompt: ((RomaCustomPrompt) -> Void)? = nil,
        onAddNewPrompt: (() -> Void)? = nil
    ) {
        self.prompts = prompts
        self.selectedPromptId = selectedPromptId
        self.onPromptSelected = onPromptSelected
        self.onEditPrompt = onEditPrompt
        self.onDeletePrompt = onDeletePrompt
        self.onAddNewPrompt = onAddNewPrompt
    }
    

    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if prompts.isEmpty {
                Text(RomaCustomPromptPresentation.promptGridEmptyText)
                    .foregroundColor(.secondary)
                    .font(.caption)
            } else {
                let columns = [
                    GridItem(.adaptive(minimum: 80, maximum: 100), spacing: 36)
                ]
                
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(prompts) { prompt in
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
                    }
                    
                    if let onAddNewPrompt = onAddNewPrompt {
                        RomaCustomPrompt.addNewButton {
                            onAddNewPrompt()
                        }
                        .help(RomaCustomPromptPresentation.addPromptHelpText)
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                
                // Helpful tip for users
                HStack {
                    Image(systemName: RomaCustomPromptPresentation.promptGridInfoSystemImageName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(RomaCustomPromptPresentation.promptGridHelpText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 8)
                .padding(.horizontal, 16)
            }
        }
    }
}
