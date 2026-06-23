import Foundation
import VoiceInkCore

enum ShortcutAction: Hashable {
    case primaryRecording
    case secondaryRecording
    case pasteLastTranscription
    case pasteLastEnhancement
    case retryLastTranscription
    case cancelRecorder
    case openHistoryWindow
    case quickAddToDictionary
    case toggleEnhancement
    case powerMode(UUID)
    case miniRecorderEscape
    case miniRecorderPrompt(Int)
    case miniRecorderPowerMode(Int)

    var userDefaultsKey: String {
        coreIdentifier.shortcutStorageKey
    }

    var isStored: Bool {
        coreIdentifier.isStoredShortcut
    }

    var storageName: String {
        coreIdentifier.storageName
    }

    var coreIdentifier: VoiceInkShortcutActionIdentifier {
        switch self {
        case .primaryRecording:
            return .primaryRecording
        case .secondaryRecording:
            return .secondaryRecording
        case .pasteLastTranscription:
            return .pasteLastTranscription
        case .pasteLastEnhancement:
            return .pasteLastEnhancement
        case .retryLastTranscription:
            return .retryLastTranscription
        case .cancelRecorder:
            return .cancelRecorder
        case .openHistoryWindow:
            return .openHistoryWindow
        case .quickAddToDictionary:
            return .quickAddToDictionary
        case .toggleEnhancement:
            return .toggleEnhancement
        case .powerMode(let id):
            return .powerMode(id)
        case .miniRecorderEscape:
            return .miniRecorderEscape
        case .miniRecorderPrompt(let index):
            return .miniRecorderPrompt(index)
        case .miniRecorderPowerMode(let index):
            return .miniRecorderPowerMode(index)
        }
    }

    init(coreIdentifier: VoiceInkShortcutActionIdentifier) {
        switch coreIdentifier {
        case .primaryRecording:
            self = .primaryRecording
        case .secondaryRecording:
            self = .secondaryRecording
        case .pasteLastTranscription:
            self = .pasteLastTranscription
        case .pasteLastEnhancement:
            self = .pasteLastEnhancement
        case .retryLastTranscription:
            self = .retryLastTranscription
        case .cancelRecorder:
            self = .cancelRecorder
        case .openHistoryWindow:
            self = .openHistoryWindow
        case .quickAddToDictionary:
            self = .quickAddToDictionary
        case .toggleEnhancement:
            self = .toggleEnhancement
        case .powerMode(let id):
            self = .powerMode(id)
        case .miniRecorderEscape:
            self = .miniRecorderEscape
        case .miniRecorderPrompt(let index):
            self = .miniRecorderPrompt(index)
        case .miniRecorderPowerMode(let index):
            self = .miniRecorderPowerMode(index)
        }
    }

    var displayName: String {
        switch self {
        case .primaryRecording:
            return "Primary Shortcut"
        case .secondaryRecording:
            return "Secondary Shortcut"
        case .pasteLastTranscription:
            return "Paste Last Transcription"
        case .pasteLastEnhancement:
            return "Paste Last Enhanced Transcription"
        case .retryLastTranscription:
            return "Retry Last Transcription"
        case .cancelRecorder:
            return "Cancel Recording"
        case .openHistoryWindow:
            return VoiceInkHistoryPresentation.macOSShortcutTip.shortcutLabel
        case .quickAddToDictionary:
            return "Quick Add to Dictionary"
        case .toggleEnhancement:
            return "Toggle Enhancement"
        case .powerMode(let id):
            if let config = PowerModeManager.shared.configurations.powerModeConfiguration(with: id) {
                return "\(config.name) Power Mode"
            }

            return "Power Mode"
        case .miniRecorderEscape:
            return "Mini Recorder Cancel"
        case .miniRecorderPrompt(let index):
            return "Select Prompt \(Self.displayNumber(forMiniRecorderIndex: index))"
        case .miniRecorderPowerMode(let index):
            return "Select Power Mode \(Self.displayNumber(forMiniRecorderIndex: index))"
        }
    }

    static let globalUtilityActions: [Self] = [
        .pasteLastTranscription,
        .pasteLastEnhancement,
        .retryLastTranscription,
        .openHistoryWindow,
        .quickAddToDictionary
    ]

    static let miniRecorderStoredActions: [Self] = [
        .cancelRecorder,
        .toggleEnhancement
    ]

    static let legacyKeyboardShortcutActions = VoiceInkShortcutActionIdentifier.legacyKeyboardShortcutActions.map(Self.init(coreIdentifier:))

    private static func displayNumber(forMiniRecorderIndex index: Int) -> String {
        index == 9 ? "10" : "\(index + 1)"
    }
}
