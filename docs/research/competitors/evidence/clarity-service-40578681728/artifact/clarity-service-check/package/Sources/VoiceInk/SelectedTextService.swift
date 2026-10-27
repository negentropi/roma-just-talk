import Foundation
import AppKit
import SelectedTextKit
import VoiceInkCore

class SelectedTextService {
    static func fetchSelectedText() async -> String? {
        let strategies: [TextStrategy] = [.accessibility, .menuAction]
        do {
            let selectedText = try await SelectedTextManager.shared.getSelectedText(strategies: strategies)
            return selectedText
        } catch {
            print(VoiceInkSelectedTextDiagnostics.fetchFailedMessage(errorDescription: String(describing: error)))
            return nil
        }
    }
}
