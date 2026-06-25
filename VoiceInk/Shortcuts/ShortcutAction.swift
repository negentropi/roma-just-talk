import Foundation
import VoiceInkCore

typealias ShortcutAction = VoiceInkShortcutActionIdentifier

extension VoiceInkShortcutActionIdentifier {
    var userDefaultsKey: String {
        shortcutStorageKey
    }

    var isStored: Bool {
        isStoredShortcut
    }

    var displayName: String {
        VoiceInkShortcutActionPresentation.displayName(
            for: self,
            powerModeName: powerModeConfigurationName
        )
    }

    static let globalUtilityActions: [VoiceInkShortcutActionIdentifier] = [
        .pasteLastTranscription,
        .pasteLastEnhancement,
        .retryLastTranscription,
        .openHistoryWindow,
        .quickAddToDictionary
    ]

    static let miniRecorderStoredActions: [VoiceInkShortcutActionIdentifier] = [
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
