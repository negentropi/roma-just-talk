import Foundation
import VoiceInkCore


@MainActor
class WhisperPrompt: ObservableObject {
    @Published var transcriptionPrompt: String = UserDefaults.standard.string(forKey: VoiceInkUserDefaultsKey.transcriptionPrompt) ?? ""

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
        if let savedPrompts = UserDefaults.standard.dictionary(forKey: VoiceInkLocalWhisperPromptCatalog.customLanguagePromptsKey) as? [String: String] {
            customPrompts = savedPrompts
        }
    }
    
    private func saveCustomPrompts() {
        UserDefaults.standard.set(customPrompts, forKey: VoiceInkLocalWhisperPromptCatalog.customLanguagePromptsKey)
        UserDefaults.standard.synchronize() // Force immediate synchronization
    }
    
    func updateTranscriptionPrompt() {
        // Get the currently selected language from UserDefaults
        let selectedLanguage = VoiceInkTranscriptionLanguagePreference.selectedLanguage(fallback: "en")
        
        // Get the prompt for the selected language (custom if available, otherwise default)
        let basePrompt = getLanguagePrompt(for: selectedLanguage)
        let prompt = basePrompt.isEmpty ? "" : basePrompt
        
        transcriptionPrompt = prompt
        UserDefaults.standard.set(prompt, forKey: VoiceInkUserDefaultsKey.transcriptionPrompt)
        UserDefaults.standard.synchronize() // Force immediate synchronization
        
        // Notify that the prompt has changed
        NotificationCenter.default.post(name: .promptDidChange, object: nil)
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
