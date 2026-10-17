import Foundation
import AppKit
import SelectedTextKit
import RomaCore

class SelectedTextService {
    static func fetchSelectedText() async -> String? {
        let strategies: [TextStrategy] = [.accessibility, .menuAction]
        do {
            let selectedText = try await SelectedTextManager.shared.getSelectedText(strategies: strategies)
            return selectedText
        } catch {
            print(RomaSelectedTextDiagnostics.fetchFailedMessage(errorDescription: String(describing: error)))
            return nil
        }
    }
}
