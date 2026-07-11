import SwiftUI
import VoiceInkCore

struct IOSOllamaSettingsView: View {
    @ObservedObject var settings: AppSettings

    @State private var baseURL = VoiceInkDynamicAIProviderPreference.ollamaBaseURL()
    @State private var selectedModel = VoiceInkDynamicAIProviderPreference.ollamaRuntimeSelectedModel()
    @State private var availableModels = [String]()
    @State private var isRefreshing = false
    @State private var errorMessage: String?

    private let presentation = VoiceInkAIEnhancementProviderSettingsPresentation.iOS

    var body: some View {
        Form {
            Section(header: Text(presentation.sectionTitle)) {
                TextField(presentation.ollamaBaseURLFieldTitle, text: $baseURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)

                if availableModels.isEmpty {
                    TextField(presentation.modelPickerTitle, text: $selectedModel)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } else {
                    Picker(presentation.modelPickerTitle, selection: $selectedModel) {
                        ForEach(availableModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                }

                Button {
                    Task { await refreshModels() }
                } label: {
                    if isRefreshing {
                        ProgressView()
                    } else {
                        Text(presentation.refreshButtonTitle)
                    }
                }
                .disabled(isRefreshing || serverURL == nil)

                Button(presentation.ollamaSaveButtonTitle, action: save)
                    .disabled(!canSave)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Ollama")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refreshModels() }
    }

    private var serverURL: URL? {
        URL(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var canSave: Bool {
        serverURL != nil && VoiceInkProviderCredential.nonBlank(selectedModel) != nil
    }

    private func save() {
        settings.updateOllamaConfiguration(baseURL: baseURL, model: selectedModel)
    }

    private func refreshModels() async {
        guard let serverURL else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let models = try await VoiceInkOpenAICompatibleClient().fetchModelIDs(
                baseURL: serverURL,
                apiKey: "local-ollama"
            )
            availableModels = models
            if !models.isEmpty, !models.contains(selectedModel) {
                selectedModel = models[0]
            }
            errorMessage = nil
        } catch {
            availableModels = []
            errorMessage = presentation.ollamaConnectionFailureMessage
        }
    }
}
