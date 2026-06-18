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
        model.provider == .assemblyAI &&
            VoiceInkTranscriptionStreamingPreference.shouldUseStreaming(for: model.streamingPreferenceSnapshot)
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
