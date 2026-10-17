import AppIntents
import Foundation
import RomaCore

struct ToggleMiniRecorderIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Roma Just Talk Recorder"
    static var description = IntentDescription("Start or stop the Roma Just Talk mini recorder for voice transcription.")
    
    static var openAppWhenRun: Bool = false
    
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        NotificationCenter.default.post(name: .toggleMiniRecorder, object: nil)
        
        let dialog = IntentDialog(
            stringLiteral: RomaMiniRecorderAppIntentPresentation.toggleSuccessDialog
        )
        return .result(dialog: dialog)
    }
}
