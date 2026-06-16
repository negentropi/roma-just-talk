import Foundation
import VoiceInkCore

/// Manages the creation and setup of default modes for first-time users
class DefaultModeManager {
    static let shared = DefaultModeManager()
    
    private init() {}
    
    /// Creates a default mode if no modes exist
    /// This ensures users can start recording immediately without setup
    @MainActor
    func ensureDefaultModeExists() {
        let settings = AppSettings.shared
        
        // Only create default mode if no modes exist
        guard settings.modes.isEmpty else { return }
        
        let defaultMode = Mode.defaultLocalWhisper()
        settings.modes.append(defaultMode)
        settings.selectedModeId = defaultMode.id
        
        print("✅ Created default mode: \(defaultMode.name)")
    }
    
    /// Call this when user first opens the app or clicks "start using"
    @MainActor
    func setupForFirstTimeUser() {
        ensureDefaultModeExists()
        
        // Additional first-time setup can go here if needed
        print("🎉 App ready for first-time user with default mode")
    }
}
