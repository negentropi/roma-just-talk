import SwiftUI
import VoiceInkCore

struct ModeConfigurationView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var settings: AppSettings
    
    @State private var mode: Mode
    @State private var isEditing: Bool
    
    let onSave: (Mode) -> Void
    
    init(mode: Mode? = nil, settings: AppSettings, onSave: @escaping (Mode) -> Void) {
        self.settings = settings
        self.onSave = onSave
        self.isEditing = mode != nil
        let initialMode = mode ?? Mode(name: "")
        self._mode = State(initialValue: initialMode)
    }
    
    /// Available transcription providers (those with valid API keys or downloaded local models)
    private var availableTranscriptionProviders: [VoiceInkProviderKind] {
        settings.availableProviders(for: .transcription)
    }
    
    /// Available post-processing providers (those with valid API keys)
    private var availablePostProcessingProviders: [VoiceInkProviderKind] {
        settings.availableProviders(for: .postProcessing)
    }

    private var canSave: Bool {
        mode.isSaveableDraft(
            availableTranscriptionProviders: availableTranscriptionProviders,
            availablePostProcessingProviders: availablePostProcessingProviders
        )
    }
    
    var body: some View {
        Form {
            Section(header: Text("Mode Details")) {
                TextField("Mode Name", text: $mode.name)
                    .textInputAutocapitalization(.words)
            }
            
            Section(header: Text("Transcription")) {
                Picker("Provider", selection: $mode.transcriptionProvider) {
                    ForEach(availableTranscriptionProviders) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }

                ProviderModelSelectionView(
                    provider: mode.transcriptionProvider,
                    use: .transcription,
                    selectedModel: $mode.transcriptionModel
                )
            }
            
            Section(header: Text("Post-processing"), 
                   footer: mode.isPostProcessingEnabled ? Text("Configure how the raw transcription should be processed and refined.") : nil) {
                Toggle("Enable Post-processing", isOn: $mode.isPostProcessingEnabled)
                
                if mode.isPostProcessingEnabled {
                    Picker("Provider", selection: $mode.postProcessingProvider) {
                        ForEach(availablePostProcessingProviders) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }

                    ProviderModelSelectionView(
                        provider: mode.postProcessingProvider,
                        use: .postProcessing,
                        selectedModel: $mode.postProcessingModel
                    )
                    
                    // Prompt Template Selection
                    Picker("Prompt Template", selection: $mode.promptTemplate.type) {
                        ForEach(VoiceInkPostProcessingTemplateType.allCases, id: \.self) { templateType in
                            Text(templateType.displayName).tag(templateType)
                        }
                    }
                    
                    // Show custom prompt field only when Custom is selected
                    if mode.promptTemplate.type == .custom {
                        TextField("Custom Prompt", text: $mode.promptTemplate.customPrompt, axis: .vertical)
                            .lineLimit(4, reservesSpace: true)
                    }
                }
            }
        }
        .navigationTitle(isEditing ? "Edit Mode" : "New Mode")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    onSave(mode)
                    dismiss()
                }
                .disabled(!canSave)
            }
        }
        .onAppear(perform: repairUnavailableProviderSelections)
        .onChange(of: availableTranscriptionProviders) { _, _ in
            repairUnavailableProviderSelections()
        }
        .onChange(of: availablePostProcessingProviders) { _, _ in
            repairUnavailableProviderSelections()
        }
        .onChange(of: mode.isPostProcessingEnabled) { _, _ in
            repairUnavailableProviderSelections()
        }
        .onChange(of: mode.transcriptionProvider) { _, _ in
            mode.selectTranscriptionProvider(mode.transcriptionProvider)
        }
        .onChange(of: mode.postProcessingProvider) { _, _ in
            mode.selectPostProcessingProvider(mode.postProcessingProvider)
        }
    }

    private func repairUnavailableProviderSelections() {
        mode.repairProviderSelection(
            availableTranscriptionProviders: availableTranscriptionProviders,
            availablePostProcessingProviders: availablePostProcessingProviders
        )
    }
}

private struct ProviderModelSelectionView: View {
    let provider: VoiceInkProviderKind
    let use: VoiceInkProviderModelUse
    @Binding var selectedModel: String

    var body: some View {
        switch provider.modelSelectionPresentation(for: use) {
        case .fixedModel(let model):
            HStack {
                Text("Model")
                Spacer()
                Text(model)
                    .foregroundColor(.secondary)
            }
        case .selectableModels(let models):
            Picker("Model", selection: $selectedModel) {
                ForEach(models, id: \.self) { model in
                    Text(model).tag(model)
                }
            }
        }
    }
}

#Preview {
    ModeConfigurationView(settings: AppSettings.shared) { _ in }
}
