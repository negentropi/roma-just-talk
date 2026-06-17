import Foundation
import VoiceInkCore

struct TranscriptionOutputFilter {
    static func filter(_ text: String) -> String {
        VoiceInkTranscriptionOutputFilter.filter(
            text,
            fillerWords: FillerWordManager.shared.isEnabled ? FillerWordManager.shared.fillerWords : []
        )
    }

    static func applyUserCleanupPreferences(_ text: String) -> String {
        let punctuationMode = PunctuationCleanupMode.current()
        let shouldLowercase = UserDefaults.standard.bool(forKey: VoiceInkUserDefaultsKey.lowercaseTranscription)

        return applyCleanupPreferences(text, punctuationMode: punctuationMode, shouldLowercase: shouldLowercase)
    }

    static func applyCleanupPreferences(_ text: String, punctuationMode: PunctuationCleanupMode, shouldLowercase: Bool) -> String {
        VoiceInkTranscriptionCleanupPreferences.apply(
            text,
            punctuationMode: punctuationMode,
            shouldLowercase: shouldLowercase
        )
    }
} 
