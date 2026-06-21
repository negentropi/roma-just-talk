import AppKit
import Carbon.HIToolbox
import Foundation
import VoiceInkCore

struct LegacyKeyboardShortcut: Codable {
    let carbonKeyCode: Int
    let carbonModifiers: Int
}

struct ShortcutBackup: Codable {
    let shortcut: Shortcut

    init(_ shortcut: Shortcut) {
        self.shortcut = shortcut
    }

    init(from decoder: Decoder) throws {
        if let shortcut = try? Shortcut(from: decoder) {
            self.shortcut = shortcut
            return
        }

        let legacyShortcut = try LegacyKeyboardShortcut(from: decoder)
        self.shortcut = Shortcut.fromLegacyShortcut(legacyShortcut)
    }

    func encode(to encoder: Encoder) throws {
        try shortcut.encode(to: encoder)
    }
}

enum ShortcutMigration {
    static func migrateLegacyShortcutsIfNeeded() {
        migrateLegacyCustomRecordingShortcutsIfNeeded()
        migrateLegacyKeyboardShortcutsIfNeeded()
    }

    static func migrateLegacyKeyboardShortcutsIfNeeded() {
        guard !VoiceInkRecordingShortcutPreference.isLegacyKeyboardShortcutsMigrationComplete() else {
            return
        }

        for action in ShortcutAction.legacyKeyboardShortcutActions {
            migrateLegacyKeyboardShortcut(for: action)
        }

        for config in PowerModeManager.shared.configurations {
            migrateLegacyKeyboardShortcut(for: .powerMode(config.id))
        }

        VoiceInkRecordingShortcutPreference.markLegacyKeyboardShortcutsMigrationComplete()
    }

    static func migrateShortcutSelection(
        action: ShortcutAction,
        allowsNone: Bool
    ) -> RecordingShortcutManager.ShortcutSelection {
        let plan = VoiceInkRecordingShortcutPreference.shortcutSelectionMigrationPlan(
            for: action.coreIdentifier,
            allowsNone: allowsNone
        )

        if let preset = plan.presetToStore,
           let shortcut = legacyPresetShortcut(for: preset) {
            ShortcutStore.setShortcut(shortcut, for: action)
        }

        if let defaultPreset = plan.defaultPresetToStore,
           ShortcutStore.shortcut(for: action) == nil,
           let shortcut = legacyPresetShortcut(for: defaultPreset) {
            ShortcutStore.setShortcut(shortcut, for: action)
        }

        VoiceInkRecordingShortcutPreference.applyShortcutSelectionMigrationPlan(plan)
        return plan.selection
    }

    static func migrateShortcutMode(
        for action: ShortcutAction
    ) -> RecordingShortcutManager.Mode {
        VoiceInkRecordingShortcutPreference.migrateShortcutMode(for: action.coreIdentifier)
    }

    static func removeLegacyCustomRecordingShortcut(for action: ShortcutAction) {
        VoiceInkRecordingShortcutPreference.removeLegacyCustomRecordingShortcut(for: action.coreIdentifier)
    }

    static func removeLegacyKeyboardShortcut(for action: ShortcutAction) {
        VoiceInkRecordingShortcutPreference.removeLegacyKeyboardShortcut(for: action.coreIdentifier)
    }

    static func migrateLegacyKeyboardShortcut(for action: ShortcutAction) {
        defer {
            removeLegacyKeyboardShortcut(for: action)
        }

        guard
            ShortcutStore.rawShortcut(for: action) == nil,
            !ShortcutStore.isShortcutCleared(for: action),
            let shortcut = legacyKeyboardShortcut(for: action)
        else {
            return
        }

        ShortcutStore.setShortcut(shortcut, for: action)
    }

    private static func migrateLegacyCustomRecordingShortcutsIfNeeded() {
        guard !VoiceInkRecordingShortcutPreference.isLegacyCustomRecordingShortcutsMigrationComplete() else {
            return
        }

        for identifier in VoiceInkShortcutActionIdentifier.legacyCustomRecordingShortcutActions {
            let action = ShortcutAction(coreIdentifier: identifier)
            migrateLegacyCustomRecordingShortcut(for: action)
        }

        VoiceInkRecordingShortcutPreference.markLegacyCustomRecordingShortcutsMigrationComplete()
    }

    private static func migrateLegacyCustomRecordingShortcut(for action: ShortcutAction) {
        defer {
            removeLegacyCustomRecordingShortcut(for: action)
        }

        guard
            ShortcutStore.rawShortcut(for: action) == nil,
            !ShortcutStore.isShortcutCleared(for: action),
            let data = UserDefaults.standard.data(forKey: action.coreIdentifier.legacyCustomRecordingShortcutKey),
            let shortcut = try? JSONDecoder().decode(Shortcut.self, from: data)
        else {
            return
        }

        ShortcutStore.setShortcut(shortcut, for: action)
    }

    private static func legacyPresetShortcut(for preset: VoiceInkLegacyRecordingShortcutPreset) -> Shortcut? {
        switch preset {
        case .rightOption:
            return .modifierOnly(keyCode: UInt16(kVK_RightOption), modifierFlags: [.option])
        case .leftOption:
            return .modifierOnly(keyCode: UInt16(kVK_Option), modifierFlags: [.option])
        case .leftControl:
            return .modifierOnly(keyCode: UInt16(kVK_Control), modifierFlags: [.control])
        case .rightControl:
            return .modifierOnly(keyCode: UInt16(kVK_RightControl), modifierFlags: [.control])
        case .fn:
            return .modifierOnly(keyCode: UInt16(kVK_Function), modifierFlags: [.function])
        case .rightCommand:
            return .modifierOnly(keyCode: UInt16(kVK_RightCommand), modifierFlags: [.command])
        case .rightShift:
            return .modifierOnly(keyCode: UInt16(kVK_RightShift), modifierFlags: [.shift])
        case .leftShift:
            return .modifierOnly(keyCode: UInt16(kVK_Shift), modifierFlags: [.shift])
        }
    }

    private static func legacyKeyboardShortcut(for action: ShortcutAction) -> Shortcut? {
        guard
            let storageKey = action.coreIdentifier.legacyKeyboardShortcutStorageKey,
            let data = UserDefaults.standard.string(forKey: storageKey)?.data(using: .utf8),
            let legacyShortcut = try? JSONDecoder().decode(LegacyKeyboardShortcut.self, from: data)
        else {
            return nil
        }

        return Shortcut.fromLegacyShortcut(legacyShortcut)
    }
}
