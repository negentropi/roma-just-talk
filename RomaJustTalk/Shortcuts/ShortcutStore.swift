import Foundation
import RomaCore

enum ShortcutStore {
    static let shortcutDidChange = RomaRecordingShortcutPreference.shortcutDidChangeNotificationName

    static func rawShortcut(for action: ShortcutAction) -> Shortcut? {
        RomaShortcutStoragePreference.shortcutData(for: action.userDefaultsKey)
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
            RomaShortcutStoragePreference.saveShortcutData(data, for: action.userDefaultsKey)
            ShortcutMigration.removeLegacyCustomRecordingShortcut(for: action)
            ShortcutMigration.removeLegacyKeyboardShortcut(for: action)
        } else {
            RomaShortcutStoragePreference.markShortcutCleared(for: action.userDefaultsKey)
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

        RomaShortcutStoragePreference.removeShortcutStorage(for: action.userDefaultsKey)
        ShortcutMigration.removeLegacyCustomRecordingShortcut(for: action)
        ShortcutMigration.removeLegacyKeyboardShortcut(for: action)
        NotificationCenter.default.post(
            name: shortcutDidChange,
            object: action
        )
    }

    static func storedState(for action: ShortcutAction) -> RomaShortcutStorageState {
        RomaShortcutStoragePreference.storedState(for: action.userDefaultsKey)
    }

    static func restoreStoredState(_ state: RomaShortcutStorageState, for action: ShortcutAction) {
        guard action.isStored else {
            return
        }

        RomaShortcutStoragePreference.restoreStoredState(state, for: action.userDefaultsKey)
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
        RomaShortcutStoragePreference.isShortcutCleared(for: action.userDefaultsKey)
    }
}
