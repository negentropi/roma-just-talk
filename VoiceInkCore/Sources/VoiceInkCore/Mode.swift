import Foundation

public struct VoiceInkModeRuntimeConfiguration: Equatable, Sendable {
    public let transcriptionProvider: VoiceInkProviderKind
    public let transcriptionModel: String
    public let postProcessingProvider: VoiceInkProviderKind
    public let postProcessingModel: String
    public let prompt: String
    public let isPostProcessingEnabled: Bool

    public static var fallback: VoiceInkModeRuntimeConfiguration {
        Mode.defaultLocalWhisper().runtimeConfiguration
    }
}

public struct Mode: Identifiable, Codable {
    public let id: UUID
    public var name: String

    public var transcriptionProvider: VoiceInkProviderKind
    public var transcriptionModel: String

    public var isPostProcessingEnabled: Bool
    public var postProcessingProvider: VoiceInkProviderKind
    public var postProcessingModel: String
    public var promptTemplate: VoiceInkPostProcessingPromptTemplate

    public init(
        name: String,
        transcriptionProvider: VoiceInkProviderKind = .groq,
        transcriptionModel: String? = nil,
        isPostProcessingEnabled: Bool = false,
        postProcessingProvider: VoiceInkProviderKind = .groq,
        postProcessingModel: String? = nil,
        promptTemplate: VoiceInkPostProcessingPromptTemplate? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.transcriptionProvider = transcriptionProvider
        self.transcriptionModel = transcriptionModel
            ?? transcriptionProvider.defaultModel(for: .transcription)
            ?? VoiceInkTranscriptionModelCatalog.voiceInkTranscriptionModel
        self.isPostProcessingEnabled = isPostProcessingEnabled
        self.postProcessingProvider = postProcessingProvider
        self.postProcessingModel = postProcessingModel
            ?? postProcessingProvider.defaultModel(for: .postProcessing)
            ?? VoiceInkAIModelCatalog.defaultModel(for: .groq)
        self.promptTemplate = promptTemplate ?? VoiceInkPostProcessingPromptTemplate(type: .summary)
    }

    @available(*, deprecated, message: "Use promptTemplate instead")
    public var customPrompt: String {
        get {
            promptTemplate.type == .custom ? promptTemplate.customPrompt : ""
        }
        set {
            if !newValue.isEmpty {
                promptTemplate = VoiceInkPostProcessingPromptTemplate(type: .custom, customPrompt: newValue)
            }
        }
    }

    public var effectivePrompt: String {
        promptTemplate.effectivePrompt
    }

    public var effectiveTranscriptionModel: String {
        transcriptionProvider.fixedModel(for: .transcription) ?? transcriptionModel
    }

    public var effectivePostProcessingModel: String {
        postProcessingProvider.fixedModel(for: .postProcessing) ?? postProcessingModel
    }

    public var runtimeConfiguration: VoiceInkModeRuntimeConfiguration {
        VoiceInkModeRuntimeConfiguration(
            transcriptionProvider: transcriptionProvider,
            transcriptionModel: effectiveTranscriptionModel,
            postProcessingProvider: postProcessingProvider,
            postProcessingModel: effectivePostProcessingModel,
            prompt: effectivePrompt,
            isPostProcessingEnabled: isPostProcessingEnabled
        )
    }

    public static func defaultLocalWhisper(name: String = "Default") -> Mode {
        Mode(
            name: name,
            transcriptionProvider: .localWhisper,
            transcriptionModel: VoiceInkTranscriptionModelCatalog.localBaseModel,
            isPostProcessingEnabled: false,
            postProcessingProvider: .groq,
            postProcessingModel: VoiceInkProviderKind.groq.defaultModel(for: .postProcessing)
                ?? VoiceInkAIModelCatalog.defaultModel(for: .groq),
            promptTemplate: VoiceInkPostProcessingPromptTemplate(type: .summary)
        )
    }

    public static func isSaveableDraft(
        name: String,
        promptTemplateType: VoiceInkPostProcessingTemplateType,
        customPrompt: String
    ) -> Bool {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        if promptTemplateType == .custom {
            return !customPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        return true
    }
}

public extension Collection where Element == Mode {
    func activeMode(selectedModeId: UUID?) -> Mode? {
        if let selectedModeId,
           let selectedMode = first(where: { $0.id == selectedModeId }) {
            return selectedMode
        }

        return first
    }

    func runtimeConfiguration(selectedModeId: UUID?) -> VoiceInkModeRuntimeConfiguration {
        activeMode(selectedModeId: selectedModeId)?.runtimeConfiguration ?? .fallback
    }

    func repairedSelectedModeId(_ selectedModeId: UUID?) -> UUID? {
        guard let selectedModeId,
              contains(where: { $0.id == selectedModeId }) else {
            return first?.id
        }

        return selectedModeId
    }
}
