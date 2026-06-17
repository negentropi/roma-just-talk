import Foundation
import VoiceInkCore

struct TranscriptionOutputFilter {
    private static let lowercaseTranscriptionKey = "LowercaseTranscription"

    static func filter(_ text: String) -> String {
        VoiceInkTranscriptionOutputFilter.filter(
            text,
            fillerWords: FillerWordManager.shared.isEnabled ? FillerWordManager.shared.fillerWords : []
        )
    }

    static func applyUserCleanupPreferences(_ text: String) -> String {
        let punctuationMode = PunctuationCleanupMode.current()
        let shouldLowercase = UserDefaults.standard.bool(forKey: lowercaseTranscriptionKey)

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
