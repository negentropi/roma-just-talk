import Foundation
import VoiceInkCore

/// The action and destination belong to one recording, even if preferences or
/// focus change while speech recognition is running.
@MainActor
final class WritingActionSession {
    let kind: VoiceInkWritingActionKind
    let targetLanguage: String
    let target: WritingTarget
    let provider: WritingActionProviderSnapshot

    init(kind: VoiceInkWritingActionKind, provider: WritingActionProviderSnapshot) throws {
        self.kind = kind
        self.provider = provider
        let preferences = VoiceInkWritingActionPreferences.load()
        targetLanguage = preferences.selectedTargetLanguage
        if kind == .translate,
           VoiceInkWritingActionPreferences.targetLanguageName(for: targetLanguage) == nil {
            throw VoiceInkWritingActionError.missingTranslationTarget
        }
        target = try WritingTarget.capture(requiresSelection: kind.requiresSelection)
        if kind.requiresSelection,
           target.selectedText.count > VoiceInkWritingActionRequest.maximumSelectionCharacters {
            throw VoiceInkWritingActionError.selectionTooLong
        }
    }

    func request(transcript: String) throws -> VoiceInkWritingActionRequest {
        try VoiceInkWritingActionRequest(
            kind: kind,
            transcript: transcript,
            selectedText: kind.requiresSelection ? target.selectedText : "",
            targetLanguage: targetLanguage
        )
    }
}
