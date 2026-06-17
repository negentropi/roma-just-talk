import Foundation
import VoiceInkCore


@MainActor
class WhisperPrompt: ObservableObject {
    @Published var transcriptionPrompt: String = VoiceInkTranscriptionPromptPreference.storedPrompt() ?? ""

    // Store user-customized prompts
    private var customPrompts: [String: String] = [:]

    init() {
        loadCustomPrompts()
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
    
    private func loadCustomPrompts() {
        customPrompts = VoiceInkLocalWhisperPromptCatalog.storedCustomPrompts()
    }
    
    private func saveCustomPrompts() {
        VoiceInkLocalWhisperPromptCatalog.saveCustomPrompts(customPrompts)
        UserDefaults.standard.synchronize() // Force immediate synchronization
    }
    
    func updateTranscriptionPrompt() {
        // Get the currently selected language from UserDefaults
        let selectedLanguage = VoiceInkTranscriptionLanguagePreference.selectedLanguage(fallback: "en")
        
        // Get the prompt for the selected language (custom if available, otherwise default)
        let basePrompt = getLanguagePrompt(for: selectedLanguage)
        let prompt = basePrompt.isEmpty ? "" : basePrompt
        
        transcriptionPrompt = prompt
        VoiceInkTranscriptionPromptPreference.savePrompt(prompt)
        UserDefaults.standard.synchronize() // Force immediate synchronization
        
    }
    
    func getLanguagePrompt(for language: String) -> String {
        VoiceInkLocalWhisperPromptCatalog.prompt(for: language, customPrompts: customPrompts)
    }
    
    func setCustomPrompt(_ prompt: String, for language: String) {
        customPrompts[language] = prompt
        saveCustomPrompts()
        updateTranscriptionPrompt()
        
        // Force update the UI
        objectWillChange.send()
    }
}
