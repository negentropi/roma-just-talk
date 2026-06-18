import SwiftUI
import VoiceInkCore

/// A reusable grid component for selecting prompts with a plus button to add new ones
struct PromptSelectionGrid: View {
    @EnvironmentObject private var enhancementService: AIEnhancementService
    
    let prompts: [VoiceInkCustomPrompt]
    let selectedPromptId: UUID?
    let onPromptSelected: (VoiceInkCustomPrompt) -> Void
    let onEditPrompt: ((VoiceInkCustomPrompt) -> Void)?
    let onDeletePrompt: ((VoiceInkCustomPrompt) -> Void)?
    let onAddNewPrompt: (() -> Void)?
    
    init(
        prompts: [VoiceInkCustomPrompt],
        selectedPromptId: UUID?,
        onPromptSelected: @escaping (VoiceInkCustomPrompt) -> Void,
        onEditPrompt: ((VoiceInkCustomPrompt) -> Void)? = nil,
        onDeletePrompt: ((VoiceInkCustomPrompt) -> Void)? = nil,
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
                Text("No prompts available")
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
                        VoiceInkCustomPrompt.addNewButton {
                            onAddNewPrompt()
                        }
                        .help("Add new prompt")
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                
                // Helpful tip for users
                HStack {
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("Double-click to edit • Right-click for more options")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 8)
                .padding(.horizontal, 16)
            }
        }
    }
}
