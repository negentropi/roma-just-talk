import Foundation
import VoiceInkCore


@MainActor
class WhisperPrompt: ObservableObject {
    @Published var transcriptionPrompt: String = VoiceInkTranscriptionPromptPreference.storedPrompt() ?? ""

    init() {
        updateTranscriptionPrompt()
        
        // Setup notification observer
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLanguageChange),
            name: .languageDidChange,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func handleLanguageChange() {
        updateTranscriptionPrompt()
    }
    
    func updateTranscriptionPrompt() {
        transcriptionPrompt = VoiceInkTranscriptionPromptPreference.saveLocalWhisperPromptForSelectedLanguage()
        UserDefaults.standard.synchronize() // Force immediate synchronization
    }
    
    func getLanguagePrompt(for language: String) -> String {
        VoiceInkLocalWhisperPromptCatalog.prompt(
            for: language,
            customPrompts: VoiceInkLocalWhisperPromptCatalog.storedCustomPrompts()
        )
    }
    
    func setCustomPrompt(_ prompt: String, for language: String) {
        VoiceInkLocalWhisperPromptCatalog.saveCustomPrompt(prompt, for: language)
        UserDefaults.standard.synchronize() // Force immediate synchronization
        updateTranscriptionPrompt()
        
        // Force update the UI
        objectWillChange.send()
    }
}
