import Foundation
import VoiceInkCore

struct Mode: Identifiable, Codable {
    let id: UUID
    var name: String
    
    // Transcription settings
    var transcriptionProvider: VoiceInkProviderKind
    var transcriptionModel: String
    
    // Post-processing settings
    var isPostProcessingEnabled: Bool
    var postProcessingProvider: VoiceInkProviderKind
    var postProcessingModel: String
    var promptTemplate: VoiceInkPostProcessingPromptTemplate
    
    init(name: String, 
         transcriptionProvider: VoiceInkProviderKind = .groq,
         transcriptionModel: String? = nil,
         isPostProcessingEnabled: Bool = false,
         postProcessingProvider: VoiceInkProviderKind = .groq,
         postProcessingModel: String? = nil,
         promptTemplate: VoiceInkPostProcessingPromptTemplate? = nil) {
        self.id = UUID()
        self.name = name
        self.transcriptionProvider = transcriptionProvider
        self.transcriptionModel = transcriptionModel
            ?? transcriptionProvider.fixedModel(for: .transcription)
            ?? transcriptionProvider.models(for: .transcription).first
            ?? VoiceInkTranscriptionModelCatalog.voiceInkTranscriptionModel
        self.isPostProcessingEnabled = isPostProcessingEnabled
        self.postProcessingProvider = postProcessingProvider
        self.postProcessingModel = postProcessingModel
            ?? postProcessingProvider.fixedModel(for: .postProcessing)
            ?? postProcessingProvider.models(for: .postProcessing).first
            ?? VoiceInkAIModelCatalog.firstAvailableModel(for: .groq)
        self.promptTemplate = promptTemplate ?? VoiceInkPostProcessingPromptTemplate(type: .summary)
    }
    
    /// Legacy support for custom prompts - creates a custom template
    @available(*, deprecated, message: "Use promptTemplate instead")
    var customPrompt: String {
        get {
            return promptTemplate.type == .custom ? promptTemplate.customPrompt : ""
        }
        set {
            if !newValue.isEmpty {
                promptTemplate = VoiceInkPostProcessingPromptTemplate(type: .custom, customPrompt: newValue)
            }
        }
    }
    
    /// Returns the effective prompt to use for post-processing
    var effectivePrompt: String {
        return promptTemplate.effectivePrompt
    }
}
