import SwiftUI
import VoiceInkCore

struct ModeConfigurationView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var settings: AppSettings
    
    @State private var mode: Mode
    @State private var isEditing: Bool
    @State private var selectedTemplateType: VoiceInkPostProcessingTemplateType
    @State private var customPromptText: String
    
    let onSave: (Mode) -> Void
    
    init(mode: Mode? = nil, settings: AppSettings, onSave: @escaping (Mode) -> Void) {
        self.settings = settings
        self.onSave = onSave
        self.isEditing = mode != nil
        let initialMode = mode ?? Mode(name: "")
        self._mode = State(initialValue: initialMode)
        self._selectedTemplateType = State(initialValue: initialMode.promptTemplate.type)
        self._customPromptText = State(initialValue: initialMode.promptTemplate.customPrompt)
    }
    
    /// Available transcription providers (those with valid API keys or downloaded local models)
    private var availableTranscriptionProviders: [VoiceInkProviderKind] {
        VoiceInkProviderKind.availableProviders(for: .transcription) { provider in
            settings.isKeyVerified(for: provider)
        }
    }
    
    /// Available post-processing providers (those with valid API keys)
    private var availablePostProcessingProviders: [VoiceInkProviderKind] {
        VoiceInkProviderKind.availableProviders(for: .postProcessing) { provider in
            settings.isKeyVerified(for: provider)
        }
    }

    private var canSave: Bool {
        mode.isSaveableDraft(
            promptTemplateType: selectedTemplateType,
            customPrompt: customPromptText,
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
                
                if let fixedModel = mode.transcriptionProvider.fixedModel(for: .transcription) {
                    HStack {
                        Text("Model")
                        Spacer()
                        Text(fixedModel)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Picker("Model", selection: $mode.transcriptionModel) {
                        ForEach(mode.transcriptionProvider.models(for: .transcription), id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                }
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
                    
                    if let fixedModel = mode.postProcessingProvider.fixedModel(for: .postProcessing) {
                        HStack {
                            Text("Model")
                            Spacer()
                            Text(fixedModel)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Picker("Model", selection: $mode.postProcessingModel) {
                            ForEach(mode.postProcessingProvider.models(for: .postProcessing), id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                    }
                    
                    // Prompt Template Selection
                    Picker("Prompt Template", selection: $selectedTemplateType) {
                        ForEach(VoiceInkPostProcessingTemplateType.allCases, id: \.self) { templateType in
                            Text(templateType.displayName).tag(templateType)
                        }
                    }
                    
                    // Show custom prompt field only when Custom is selected
                    if selectedTemplateType == .custom {
                        TextField("Custom Prompt", text: $customPromptText, axis: .vertical)
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
                    // Update the mode's prompt template before saving
                    mode.promptTemplate = VoiceInkPostProcessingPromptTemplate(type: selectedTemplateType, customPrompt: customPromptText)
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

#Preview {
    ModeConfigurationView(settings: AppSettings.shared) { _ in }
}
