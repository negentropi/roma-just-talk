import SwiftUI
import VoiceInkCore

struct ModeConfigurationView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var settings: AppSettings
    
    @State private var draftState: VoiceInkModeFormDraftState
    private let isEditing: Bool
    
    let onSave: (Mode) -> Void
    
    init(mode: Mode? = nil, settings: AppSettings, onSave: @escaping (Mode) -> Void) {
        self.settings = settings
        self.onSave = onSave
        self.isEditing = mode != nil
        self._draftState = State(initialValue: VoiceInkModeFormDraftState(
            existingMode: mode,
            providerAvailability: settings.providerAccess.modeFormProviderAvailability
        ))
    }
    
    var body: some View {
        let formPresentation = draftState.mode.formPresentation(isEditing: isEditing)
        let providerAvailability = settings.providerAccess.modeFormProviderAvailability
        let formStatePresentation = providerAvailability.formStatePresentation(for: draftState.mode)

        Form {
            Section(header: Text(formPresentation.modeDetailsSectionTitle)) {
                TextField(formPresentation.modeNamePlaceholder, text: $draftState.mode.name)
                    .textInputAutocapitalization(.words)
            }
            
            Section(header: Text(formPresentation.transcriptionSectionTitle)) {
                Picker(
                    formPresentation.providerPickerTitle,
                    selection: Binding(
                        get: { draftState.mode.transcriptionProvider },
                        set: { draftState.selectTranscriptionProvider($0) }
                    )
                ) {
                    ForEach(providerAvailability.transcriptionProviders) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }

                ProviderModelSelectionView(
                    provider: draftState.mode.transcriptionProvider,
                    use: .transcription,
                    selectedModel: $draftState.mode.transcriptionModel,
                    presentation: formPresentation
                )
            }
            
            Section(
                header: Text(formPresentation.postProcessingSectionTitle),
                footer: formPresentation.postProcessingFooterText.map { Text($0) }
            ) {
                Toggle(
                    formPresentation.enablePostProcessingTitle,
                    isOn: Binding(
                        get: { draftState.mode.isPostProcessingEnabled },
                        set: { isEnabled in
                            draftState.setPostProcessingEnabled(
                                isEnabled,
                                providerAvailability: providerAvailability
                            )
                        }
                    )
                )
                
                if formStatePresentation.shouldShowPostProcessingControls {
                    Picker(
                        formPresentation.providerPickerTitle,
                        selection: Binding(
                            get: { draftState.mode.postProcessingProvider },
                            set: { draftState.selectPostProcessingProvider($0) }
                        )
                    ) {
                        ForEach(providerAvailability.postProcessingProviders) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }

                    ProviderModelSelectionView(
                        provider: draftState.mode.postProcessingProvider,
                        use: .postProcessing,
                        selectedModel: $draftState.mode.postProcessingModel,
                        presentation: formPresentation
                    )
                    
                    // Prompt Template Selection
                    Picker(formPresentation.promptTemplatePickerTitle, selection: $draftState.mode.promptTemplate.type) {
                        ForEach(VoiceInkPostProcessingTemplateType.allCases, id: \.self) { templateType in
                            Text(templateType.displayName).tag(templateType)
                        }
                    }
                    
                    if formStatePresentation.shouldShowCustomPromptField {
                        TextField(
                            formPresentation.customPromptPlaceholder,
                            text: $draftState.mode.promptTemplate.customPrompt,
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
                    onSave(draftState.mode)
                    dismiss()
                }
                .disabled(formStatePresentation.isSaveButtonDisabled)
            }
        }
        .onAppear {
            draftState.repairProviderAvailability(providerAvailability)
        }
        .onChange(of: providerAvailability) { _, availability in
            draftState.repairProviderAvailability(availability)
        }
    }
}

private struct ProviderModelSelectionView: View {
    let provider: VoiceInkProviderKind
    let use: VoiceInkProviderModelUse
    @Binding var selectedModel: String
    let presentation: VoiceInkModeFormPresentation

    var body: some View {
        let modelSelection = provider.modelSelectionPresentation(for: use)

        if let model = modelSelection.fixedModelName {
            HStack {
                Text(presentation.modelFieldTitle)
                Spacer()
                Text(model)
                    .foregroundColor(.secondary)
            }
        } else {
            Picker(presentation.modelFieldTitle, selection: $selectedModel) {
                ForEach(modelSelection.selectableModels, id: \.self) { model in
                    Text(model).tag(model)
                }
            }
        }
    }
}

#Preview {
    ModeConfigurationView(settings: AppSettings.shared) { _ in }
}
