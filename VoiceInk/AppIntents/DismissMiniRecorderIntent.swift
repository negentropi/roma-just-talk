import AppIntents
import Foundation
import VoiceInkCore

struct DismissMiniRecorderIntent: AppIntent {
    private static let presentation = VoiceInkMiniRecorderAppIntentPresentation.dismiss

    static var title: LocalizedStringResource = "Dismiss VoiceInk Recorder"
    static var description = IntentDescription("Dismiss the VoiceInk mini recorder and cancel any active recording.")
    
    static var openAppWhenRun: Bool = false
    
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        NotificationCenter.default.post(name: .dismissMiniRecorder, object: nil)
        
        let dialog = IntentDialog(stringLiteral: Self.presentation.successDialog)
        return .result(dialog: dialog)
    }
}
