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
        let cleanupConfiguration = VoiceInkTranscriptionCleanupConfiguration.current()
        return applyCleanupPreferences(
            text,
            punctuationMode: cleanupConfiguration.punctuationMode,
            shouldLowercase: cleanupConfiguration.shouldLowercase
        )
    }

    static func applyCleanupPreferences(_ text: String, punctuationMode: PunctuationCleanupMode, shouldLowercase: Bool) -> String {
        VoiceInkTranscriptionCleanupPreferences.apply(
            text,
            punctuationMode: punctuationMode,
            shouldLowercase: shouldLowercase
        )
    }
} 
