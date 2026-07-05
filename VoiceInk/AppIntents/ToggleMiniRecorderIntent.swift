import AppIntents
import Foundation
import VoiceInkCore

struct ToggleMiniRecorderIntent: AppIntent {
    private static let presentation = VoiceInkMiniRecorderAppIntentPresentation.toggle

    static var title: LocalizedStringResource = "Toggle VoiceInk Recorder"
    static var description = IntentDescription("Start or stop the VoiceInk mini recorder for voice transcription.")
    
    static var openAppWhenRun: Bool = false
    
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        NotificationCenter.default.post(name: .toggleMiniRecorder, object: nil)
        
        let dialog = IntentDialog(stringLiteral: Self.presentation.successDialog)
        return .result(dialog: dialog)
    }
}
