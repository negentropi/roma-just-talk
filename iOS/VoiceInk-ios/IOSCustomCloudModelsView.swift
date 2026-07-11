import SwiftUI
import VoiceInkCore

private enum IOSCustomCloudModelSheetTarget: Identifiable {
    case add(UUID)
    case edit(VoiceInkCustomCloudModelStoredRecord)

    var id: UUID {
        switch self {
        case .add(let id):
            return id
        case .edit(let model):
            return model.id
        }
    }

    var model: VoiceInkCustomCloudModelStoredRecord? {
        guard case .edit(let model) = self else { return nil }
        return model
    }
}

struct IOSCustomCloudModelsView: View {
    @StateObject private var manager = IOSCustomCloudModelManager.shared
    @State private var sheetTarget: IOSCustomCloudModelSheetTarget?
    @State private var errorMessage: String?

    var body: some View {
        List {
            if manager.models.isEmpty {
                ContentUnavailableView(
                    "No Custom Models",
                    systemImage: "server.rack",
                    description: Text("Add an OpenAI-compatible transcription endpoint.")
                )
            } else {
                ForEach(manager.models, id: \.id) { model in
                    Button {
                        sheetTarget = .edit(model)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.displayName)
                                .foregroundStyle(.primary)
                            Text(model.modelName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(model.apiEndpoint)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .onDelete(perform: deleteModels)
            }
        }
        .navigationTitle("Custom Cloud Models")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    sheetTarget = .add(UUID())
                } label: {
                    Label("Add Model", systemImage: "plus")
                }
            }
        }
        .sheet(item: $sheetTarget) { target in
            NavigationStack {
                IOSCustomCloudModelEditorView(target: target, manager: manager)
            }
        }
        .alert("Custom Model Error", isPresented: errorAlertBinding) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func deleteModels(at offsets: IndexSet) {
        let ids = offsets.map { manager.models[$0].id }
        do {
            for id in ids {
                try manager.remove(id: id)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

@MainActor
private struct IOSCustomCloudModelEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var manager: IOSCustomCloudModelManager

    private let target: IOSCustomCloudModelSheetTarget
    private let presentation = VoiceInkCustomCloudModelFormPresentation.macOS

    @State private var displayName: String
    @State private var apiEndpoint: String
    @State private var apiKey: String
    @State private var modelName: String
    @State private var isMultilingual: Bool
    @State private var errorMessage: String?

    init(target: IOSCustomCloudModelSheetTarget, manager: IOSCustomCloudModelManager) {
        self.target = target
        self.manager = manager
        let model = target.model
        _displayName = State(initialValue: model?.displayName ?? "")
        _apiEndpoint = State(
            initialValue: model?.apiEndpoint
                ?? VoiceInkCustomCloudModelFormPresentation.macOS.defaultAPIEndpoint
        )
        _apiKey = State(initialValue: model.flatMap { manager.apiKey(for: $0.id) } ?? "")
        _modelName = State(
            initialValue: model?.modelName
                ?? VoiceInkCustomCloudModelFormPresentation.macOS.defaultModelName
        )
        _isMultilingual = State(
            initialValue: model?.isMultilingualModel
                ?? VoiceInkCustomCloudModelFormPresentation.macOS.defaultIsMultilingual
        )
    }

    var body: some View {
        let controls = VoiceInkCustomCloudModelPolicy.formControlPresentation(
            for: draft,
            isSaving: false
        )

        Form {
            Section {
                TextField(presentation.displayNameFieldTitle, text: $displayName)
                TextField(presentation.apiEndpointFieldTitle, text: $apiEndpoint)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                SecureField(presentation.apiKeyFieldTitle, text: $apiKey)
                    .textInputAutocapitalization(.never)
                TextField(presentation.modelNameFieldTitle, text: $modelName)
                    .textInputAutocapitalization(.never)
                Toggle(presentation.multilingualToggleTitle, isOn: $isMultilingual)
            } footer: {
                Text(presentation.compatibilityWarningText)
            }
        }
        .navigationTitle(presentation.title(isEditing: target.model != nil))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(presentation.cancelButtonTitle) { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(presentation.submitButtonTitle(isEditing: target.model != nil)) {
                    save()
                }
                .disabled(controls.isSubmitButtonDisabled)
            }
        }
        .alert(presentation.validationAlertTitle, isPresented: errorAlertBinding) {
            Button(presentation.validationAlertDismissButtonTitle, role: .cancel) { }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    private var draft: VoiceInkCustomCloudModelDraft {
        VoiceInkCustomCloudModelPolicy.normalizedDraft(
            displayName: displayName,
            apiEndpoint: apiEndpoint,
            apiKey: apiKey,
            modelName: modelName
        )
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func save() {
        do {
            try manager.save(
                draft: draft,
                isMultilingual: isMultilingual,
                editingID: target.model?.id
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
