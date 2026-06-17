import Foundation
import VoiceInkCore

enum TranscriptionLanguageSupport {
    static func languages(for model: any TranscriptionModel) -> [String: String] {
        if model.provider == .assemblyAI {
            return VoiceInkTranscriptionLanguageSupport.assemblyAILanguages(
                usesRealtime: assemblyAIUsesRealtime(for: model)
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

enum LanguageDictionary {
    static let appleNative = VoiceInkLanguageCatalog.nativeApple
    static let all = VoiceInkLanguageCatalog.all

    static func forProvider(isMultilingual: Bool, provider: ModelProvider = .whisper) -> [String: String] {
        guard isMultilingual else {
            return VoiceInkLanguageCatalog.englishOnly
        }

        switch provider {
        case .whisper:
            return VoiceInkLanguageCatalog.whisperLanguages()
        case .nativeApple:
            return VoiceInkLanguageCatalog.nativeApple
        case .fluidAudio:
            return VoiceInkLanguageCatalog.fluidAudioLanguages()
        default:
            guard let coreProvider = provider.coreTranscriptionModelProvider else {
                return VoiceInkLanguageCatalog.all
            }
            return VoiceInkLanguageCatalog.languages(for: coreProvider)
        }
    }
}
