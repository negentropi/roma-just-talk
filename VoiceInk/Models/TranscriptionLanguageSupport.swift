import Foundation
import VoiceInkCore

enum TranscriptionLanguageSupport {
    static func languages(for model: any TranscriptionModel) -> [String: String] {
        if model.provider == .assemblyAI {
            return VoiceInkTranscriptionLanguageSupport.languages(
                for: .provider(.assemblyAI),
                assemblyAIUsesRealtime: assemblyAIUsesRealtime(for: model)
            )
        }

        return model.supportedLanguages
    }

    static func validLanguageOrFallback(_ language: String?, for model: any TranscriptionModel) -> String {
        VoiceInkTranscriptionLanguageSupport.validLanguageOrFallback(
            language,
            languages: languages(for: model),
            prefersNativeAppleEnglish: model.provider == .nativeApple
        )
    }

    private static func assemblyAIUsesRealtime(for model: any TranscriptionModel) -> Bool {
        guard model.provider == .assemblyAI, model.supportsStreaming else {
            return false
        }

        if let cloudProvider = CloudProviderRegistry.provider(for: model.provider), cloudProvider.isStreamingOnly {
            return true
        }

        return UserDefaults.standard.object(forKey: "streaming-enabled-\(model.name)") as? Bool ?? true
    }
}

extension ModelProvider {
    func supportedLanguages(isMultilingual: Bool) -> [String: String] {
        VoiceInkTranscriptionLanguageSupport.languages(
            for: transcriptionLanguageSource,
            isMultilingual: isMultilingual
        )
    }

    private var transcriptionLanguageSource: VoiceInkTranscriptionLanguageSource {
        switch self {
        case .whisper:
            return .whisper
        case .nativeApple:
            return .nativeApple
        case .fluidAudio:
            return .fluidAudio
        default:
            guard let coreProvider = coreTranscriptionModelProvider else {
                return .all
            }
            return .provider(coreProvider)
        }
    }
}
