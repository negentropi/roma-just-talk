import Foundation

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
            ?? VoiceInkAIModelCatalog.firstAvailableModel(for: .groq)
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

    public static func defaultLocalWhisper(name: String = "Default") -> Mode {
        Mode(
            name: name,
            transcriptionProvider: .localWhisper,
            transcriptionModel: VoiceInkTranscriptionModelCatalog.localBaseModel,
            isPostProcessingEnabled: false,
            postProcessingProvider: .groq,
            postProcessingModel: VoiceInkAIModelCatalog.firstAvailableModel(for: .groq),
            promptTemplate: VoiceInkPostProcessingPromptTemplate(type: .summary)
        )
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
}
