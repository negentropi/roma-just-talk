import SwiftUI
import VoiceInkCore

struct AddCustomModelCardView: View {
    private static let formPresentation = VoiceInkCustomCloudModelFormPresentation.macOS

    @ObservedObject var customModelManager: CustomCloudModelManager
    var onModelAdded: () -> Void
    var editingModel: CustomCloudModel? = nil
    private let presentation = Self.formPresentation
    
    @State private var isExpanded = false
    @State private var displayName = ""
    @State private var apiEndpoint = ""
    @State private var apiKey = ""
    @State private var modelName = ""
    @State private var isMultilingual = Self.formPresentation.defaultIsMultilingual
    
    @State private var validationErrors: [String] = []
    @State private var showingAlert = false
    @State private var isSaving = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Simple Add Model Button
            if !isExpanded {
                Button(action: {
                    withAnimation(.interpolatingSpring(stiffness: 170, damping: 20)) {
                        isExpanded = true
                        // Pre-fill values - either from editing model or defaults
                        if let editing = editingModel {
                            displayName = editing.displayName
                            apiEndpoint = editing.apiEndpoint
                            apiKey = editing.apiKey
                            modelName = editing.modelName
                            isMultilingual = editing.isMultilingualModel
                        } else {
                            // Pre-fill some default values when adding new
                            if apiEndpoint.isEmpty {
                                apiEndpoint = presentation.defaultAPIEndpoint
                            }
                            if modelName.isEmpty {
                                modelName = presentation.defaultModelName
                            }
                        }
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: presentation.addButtonSystemImageName)
                            .font(.system(size: 14, weight: .medium))
                        Text(presentation.buttonTitle(isEditing: editingModel != nil))
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.accentColor)
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
                .shadow(color: Color.accentColor.opacity(0.3), radius: 8, y: 4)
            }
            
            // Expandable Form Section
            if isExpanded {
                let formControlPresentation = VoiceInkCustomCloudModelPolicy.formControlPresentation(
                    for: currentDraft,
                    isSaving: isSaving
                )
                let submitButtonColor = formControlPresentation.usesEnabledSubmitStyle
                    ? Color(.controlAccentColor)
                    : Color.secondary
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    HStack {
                        Text(presentation.title(isEditing: editingModel != nil))
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        Button(action: {
                            withAnimation(.interpolatingSpring(stiffness: 170, damping: 20)) {
                                isExpanded = false
                                clearForm()
                            }
                        }) {
                            Image(systemName: presentation.closeSystemImageName)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    // Disclaimer
                    HStack(spacing: 8) {
                        Image(systemName: presentation.warningSystemImageName)
                            .foregroundColor(.orange)
                            .font(.caption)
                        Text(presentation.compatibilityWarningText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
                    
                    // Form fields
                    VStack(alignment: .leading, spacing: 16) {
                        FormField(
                            title: presentation.displayNameFieldTitle,
                            text: $displayName,
                            placeholder: presentation.displayNamePlaceholder
                        )
                        FormField(
                            title: presentation.apiEndpointFieldTitle,
                            text: $apiEndpoint,
                            placeholder: presentation.apiEndpointPlaceholder
                        )
                        FormField(
                            title: presentation.apiKeyFieldTitle,
                            text: $apiKey,
                            placeholder: presentation.apiKeyPlaceholder,
                            isSecure: true
                        )
                        FormField(
                            title: presentation.modelNameFieldTitle,
                            text: $modelName,
                            placeholder: presentation.modelNamePlaceholder
                        )
                        
                        Toggle(presentation.multilingualToggleTitle, isOn: $isMultilingual)
                    }
                    
                    // Action buttons
                    HStack(spacing: 12) {
                        Button(action: {
                            withAnimation(.interpolatingSpring(stiffness: 170, damping: 20)) {
                                isExpanded = false
                                clearForm()
                            }
                        }) {
                            Text(presentation.cancelButtonTitle)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: {
                            addModel()
                        }) {
                            HStack(spacing: 6) {
                                if formControlPresentation.isSubmitProgressVisible {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                        .frame(width: 14, height: 14)
                                } else {
                                    Image(systemName: presentation.submitButtonSystemImageName(isEditing: editingModel != nil))
                                        .font(.system(size: 14))
                                }
                                Text(presentation.submitButtonTitle(isEditing: editingModel != nil))
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(submitButtonColor)
                                    .shadow(color: submitButtonColor.opacity(0.2), radius: 2, x: 0, y: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(formControlPresentation.isSubmitButtonDisabled)
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.windowBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(.separatorColor), lineWidth: 1)
                        )
                )
            }
        }
        .alert(presentation.validationAlertTitle, isPresented: $showingAlert) {
            Button(presentation.validationAlertDismissButtonTitle) { }
        } message: {
            Text(presentation.validationAlertMessage(for: validationErrors))
        }
        .onChange(of: editingModel) { oldValue, newValue in
            if newValue != nil {
                withAnimation(.interpolatingSpring(stiffness: 170, damping: 20)) {
                    isExpanded = true
                    // Pre-fill values from editing model
                    if let editing = newValue {
                        displayName = editing.displayName
                        apiEndpoint = editing.apiEndpoint
                        apiKey = editing.apiKey
                        modelName = editing.modelName
                        isMultilingual = editing.isMultilingualModel
                    }
                }
            }
        }
    }
    
    private var currentDraft: VoiceInkCustomCloudModelDraft {
        VoiceInkCustomCloudModelPolicy.normalizedDraft(
            displayName: displayName,
            apiEndpoint: apiEndpoint,
            apiKey: apiKey,
            modelName: modelName
        )
    }
    
    private func clearForm() {
        displayName = ""
        apiEndpoint = ""
        apiKey = ""
        modelName = ""
        isMultilingual = presentation.defaultIsMultilingual
    }
    
    private func addModel() {
        let draft = currentDraft

        validationErrors = customModelManager.validateModel(
            draft,
            excludingId: editingModel?.id
        )
        
        if !validationErrors.isEmpty {
            showingAlert = true
            return
        }
        
        isSaving = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let editing = editingModel {
                let updatedModel = CustomCloudModel(
                    id: editing.id,
                    name: draft.name,
                    displayName: draft.displayName,
                    description: presentation.defaultModelDescription,
                    apiEndpoint: draft.apiEndpoint,
                    modelName: draft.modelName,
                    isMultilingual: isMultilingual
                )
                
                if APIKeyManager.shared.saveCustomModelAPIKey(draft.apiKey, forModelId: editing.id) {
                    customModelManager.updateCustomModel(updatedModel)
                } else {
                    validationErrors = [presentation.keychainSaveFailureMessage]
                    showingAlert = true
                    isSaving = false
                    return
                }
            } else {
                let customModel = CustomCloudModel(
                    name: draft.name,
                    displayName: draft.displayName,
                    description: presentation.defaultModelDescription,
                    apiEndpoint: draft.apiEndpoint,
                    modelName: draft.modelName,
                    isMultilingual: isMultilingual
                )
                
                if APIKeyManager.shared.saveCustomModelAPIKey(draft.apiKey, forModelId: customModel.id) {
                    customModelManager.addCustomModel(customModel)
                } else {
                    validationErrors = [presentation.keychainSaveFailureMessage]
                    showingAlert = true
                    isSaving = false
                    return
                }
            }

            onModelAdded()

            withAnimation(.interpolatingSpring(stiffness: 170, damping: 20)) {
                isExpanded = false
                clearForm()
                isSaving = false
            }
        }
    }
}

struct FormField: View {
    let title: String
    @Binding var text: String
    let placeholder: String
    var isSecure: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
            
            if isSecure {
                SecureField(placeholder, text: $text)
                    .textFieldStyle(.roundedBorder)
            } else {
                TextField(placeholder, text: $text)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }
}
