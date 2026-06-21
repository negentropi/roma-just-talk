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
    
    private var providerAvailability: VoiceInkModeFormProviderAvailability {
        settings.modeFormProviderAvailability
    }
    
    var body: some View {
        let formPresentation = mode.formPresentation(isEditing: isEditing)

        Form {
            Section(header: Text(formPresentation.modeDetailsSectionTitle)) {
                TextField(formPresentation.modeNamePlaceholder, text: $mode.name)
                    .textInputAutocapitalization(.words)
            }
            
            Section(header: Text(formPresentation.transcriptionSectionTitle)) {
                Picker(formPresentation.providerPickerTitle, selection: $mode.transcriptionProvider) {
                    ForEach(providerAvailability.transcriptionProviders) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }

                ProviderModelSelectionView(
                    provider: mode.transcriptionProvider,
                    use: .transcription,
                    selectedModel: $mode.transcriptionModel,
                    presentation: formPresentation
                )
            }
            
            Section(
                header: Text(formPresentation.postProcessingSectionTitle),
                footer: formPresentation.postProcessingFooterText.map { Text($0) }
            ) {
                Toggle(formPresentation.enablePostProcessingTitle, isOn: $mode.isPostProcessingEnabled)
                
                if mode.isPostProcessingEnabled {
                    Picker(formPresentation.providerPickerTitle, selection: $mode.postProcessingProvider) {
                        ForEach(providerAvailability.postProcessingProviders) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }

                    ProviderModelSelectionView(
                        provider: mode.postProcessingProvider,
                        use: .postProcessing,
                        selectedModel: $mode.postProcessingModel,
                        presentation: formPresentation
                    )
                    
                    // Prompt Template Selection
                    Picker(formPresentation.promptTemplatePickerTitle, selection: $mode.promptTemplate.type) {
                        ForEach(VoiceInkPostProcessingTemplateType.allCases, id: \.self) { templateType in
                            Text(templateType.displayName).tag(templateType)
                        }
                    }
                    
                    // Show custom prompt field only when Custom is selected
                    if mode.promptTemplate.type == .custom {
                        TextField(
                            formPresentation.customPromptPlaceholder,
                            text: $mode.promptTemplate.customPrompt,
                            axis: .vertical
                        )
                            .lineLimit(4, reservesSpace: true)
                    }
                }
            }
        }
        .navigationTitle(formPresentation.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(formPresentation.saveButtonTitle) {
                    onSave(mode)
                    dismiss()
                }
                .disabled(!providerAvailability.canSave(mode))
            }
        }
        .onAppear(perform: repairUnavailableProviderSelections)
        .onChange(of: providerAvailability) { _, _ in
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
        mode = providerAvailability.repairedMode(mode)
    }
}

private struct ProviderModelSelectionView: View {
    let provider: VoiceInkProviderKind
    let use: VoiceInkProviderModelUse
    @Binding var selectedModel: String
    let presentation: VoiceInkModeFormPresentation

    var body: some View {
        switch provider.modelSelectionPresentation(for: use) {
        case .fixedModel(let model):
            HStack {
                Text(presentation.modelFieldTitle)
                Spacer()
                Text(model)
                    .foregroundColor(.secondary)
            }
        case .selectableModels(let models):
            Picker(presentation.modelFieldTitle, selection: $selectedModel) {
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
