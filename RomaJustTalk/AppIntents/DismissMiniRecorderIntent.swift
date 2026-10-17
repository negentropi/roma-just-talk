import AppIntents
import Foundation
import RomaCore

struct DismissMiniRecorderIntent: AppIntent {
    static var title: LocalizedStringResource = "Dismiss Roma Just Talk Recorder"
    static var description = IntentDescription("Dismiss the Roma Just Talk mini recorder and cancel any active recording.")
    
    static var openAppWhenRun: Bool = false
    
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        NotificationCenter.default.post(name: .dismissMiniRecorder, object: nil)
        
        let dialog = IntentDialog(
            stringLiteral: RomaMiniRecorderAppIntentPresentation.dismissSuccessDialog
        )
        return .result(dialog: dialog)
    }
}
