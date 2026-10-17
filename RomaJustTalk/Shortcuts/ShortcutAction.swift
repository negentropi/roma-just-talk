import Foundation
import RomaCore

typealias ShortcutAction = RomaShortcutActionIdentifier

extension RomaShortcutActionIdentifier {
    var userDefaultsKey: String {
        shortcutStorageKey
    }

    var isStored: Bool {
        isStoredShortcut
    }

    var displayName: String {
        RomaShortcutActionPresentation.displayName(
            for: self,
            powerModeName: powerModeConfigurationName
        )
    }

    static let globalUtilityActions: [RomaShortcutActionIdentifier] = [
        .pasteLastTranscription,
        .pasteLastEnhancement,
        .retryLastTranscription,
        .openHistoryWindow,
        .quickAddToDictionary
    ]

    static let miniRecorderStoredActions: [RomaShortcutActionIdentifier] = [
        .cancelRecorder,
        .toggleEnhancement
    ]

    private var powerModeConfigurationName: String? {
        guard case .powerMode(let id) = self else {
            return nil
        }

        return PowerModeManager.shared.configurations.powerModeConfiguration(with: id)?.name
    }
}
