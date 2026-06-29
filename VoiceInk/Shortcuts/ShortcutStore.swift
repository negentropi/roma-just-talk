import Foundation
import VoiceInkCore

enum ShortcutStore {
    static let shortcutDidChange = VoiceInkRecordingShortcutPreference.shortcutDidChangeNotificationName

    static func rawShortcut(for action: ShortcutAction) -> Shortcut? {
        VoiceInkShortcutStoragePreference.shortcutData(for: action.userDefaultsKey)
            .flatMap { try? JSONDecoder().decode(Shortcut.self, from: $0) }
    }

    static func shortcut(for action: ShortcutAction) -> Shortcut? {
        guard action.isStored else {
            return nil
        }

        guard !isShortcutCleared(for: action) else {
            return nil
        }

        return rawShortcut(for: action)
    }

    static func setShortcut(_ shortcut: Shortcut?, for action: ShortcutAction) {
        guard action.isStored else {
            return
        }

        if let shortcut, ShortcutValidator.validationError(for: shortcut, action: action) != nil {
            return
        }

        if let shortcut,
           let data = try? JSONEncoder().encode(shortcut) {
            VoiceInkShortcutStoragePreference.saveShortcutData(data, for: action.userDefaultsKey)
            ShortcutMigration.removeLegacyCustomRecordingShortcut(for: action)
            ShortcutMigration.removeLegacyKeyboardShortcut(for: action)
        } else {
            VoiceInkShortcutStoragePreference.markShortcutCleared(for: action.userDefaultsKey)
            ShortcutMigration.removeLegacyCustomRecordingShortcut(for: action)
            ShortcutMigration.removeLegacyKeyboardShortcut(for: action)
        }

        NotificationCenter.default.post(
            name: shortcutDidChange,
            object: action
        )
    }

    static func removeShortcutStorage(for action: ShortcutAction) {
        guard action.isStored else {
            return
        }

        VoiceInkShortcutStoragePreference.removeShortcutStorage(for: action.userDefaultsKey)
        ShortcutMigration.removeLegacyCustomRecordingShortcut(for: action)
        ShortcutMigration.removeLegacyKeyboardShortcut(for: action)
        NotificationCenter.default.post(
            name: shortcutDidChange,
            object: action
        )
    }

    static func storedState(for action: ShortcutAction) -> VoiceInkShortcutStorageState {
        VoiceInkShortcutStoragePreference.storedState(for: action.userDefaultsKey)
    }

    static func restoreStoredState(_ state: VoiceInkShortcutStorageState, for action: ShortcutAction) {
        guard action.isStored else {
            return
        }

        VoiceInkShortcutStoragePreference.restoreStoredState(state, for: action.userDefaultsKey)
        NotificationCenter.default.post(
            name: shortcutDidChange,
            object: action
        )
    }

    static func shortcuts(for actions: [ShortcutAction]) -> [ShortcutAction: Shortcut] {
        actions.reduce(into: [:]) { result, action in
            if let shortcut = shortcut(for: action) {
                result[action] = shortcut
            }
        }
    }

    static func isShortcutCleared(for action: ShortcutAction) -> Bool {
        VoiceInkShortcutStoragePreference.isShortcutCleared(for: action.userDefaultsKey)
    }
}
