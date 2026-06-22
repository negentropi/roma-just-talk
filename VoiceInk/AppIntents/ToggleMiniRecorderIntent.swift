import AppIntents
import Foundation
import VoiceInkCore

struct ToggleMiniRecorderIntent: AppIntent {
    private static let presentation = VoiceInkMiniRecorderAppIntentPresentation.toggle

    static var title = LocalizedStringResource(stringLiteral: presentation.title)
    static var description = IntentDescription(stringLiteral: presentation.description)
    
    static var openAppWhenRun: Bool = false
    
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        NotificationCenter.default.post(name: .toggleMiniRecorder, object: nil)
        
        let dialog = IntentDialog(stringLiteral: Self.presentation.successDialog)
        return .result(dialog: dialog)
    }
}
