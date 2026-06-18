import Foundation
import LaunchAtLogin
import VoiceInkCore

enum AppDefaults {
    enum Keys {
        static let showMenuBarIcon = "ShowMenuBarIcon"
    }

    static let showMenuBarIconDefault = false

    static var registeredDefaults: [String: Any] {
        var defaults = VoiceInkDefaultSettings(
            selectedTranscriptionLanguage: "en"
        ).registeredUserDefaults(
            currentTranscriptionModel: "parakeet-tdt-0.6b-v2"
        )

        defaults.merge([
            // Onboarding & General
            "enableAnnouncements": true,

            // Clipboard
            "restoreClipboardAfterPaste": true,
            "clipboardRestoreDelay": 2.0,
            "useAppleScriptPaste": false,

            // Audio & Media
            "systemMuteMode": SystemMuteMode.automatic.rawValue,
            "isSystemMuteEnabled": true,
            "audioResumptionDelay": 0.0,
            "isPauseMediaEnabled": false,
            "isSoundFeedbackEnabled": false,
            CustomSoundManager.SoundType.start.builtInSoundKey: CustomSoundManager.SoundType.start.defaultBuiltInSound.rawValue,
            CustomSoundManager.SoundType.stop.builtInSoundKey: CustomSoundManager.SoundType.stop.defaultBuiltInSound.rawValue,

            // Recording & Transcription
            "AppendTrailingSpace": true,
            "showLiveTextPreview": false,
            VoiceInkRollingBufferPreloadSettings.modeKey: VoiceInkRollingBufferPreloadSettings.defaultMode.rawValue,
            VoiceInkRollingBufferPreloadSettings.autoDisableCloudModelsKey: VoiceInkRollingBufferPreloadSettings.defaultAutoDisablesCloudModels,
            VoiceInkRollingBufferPreloadSettings.autoDisableLowBatteryLocalModelsKey: VoiceInkRollingBufferPreloadSettings.defaultAutoDisablesLowBatteryLocalModels,
            VoiceInkRollingBufferPreloadSettings.lowBatteryThresholdPercentKey: VoiceInkRollingBufferPreloadSettings.defaultLowBatteryThresholdPercent,
            VoiceInkRollingBufferPreloadSettings.bufferDurationSecondsKey: VoiceInkRollingBufferPreloadSettings.defaultBufferDurationSeconds,
            VoiceInkRollingBufferPreloadSettings.preRunFinalizationKey: VoiceInkRollingBufferPreloadSettings.defaultPreRunFinalization,
            RollingBufferVADSettings.modelKey: RollingBufferVADSettings.sileroModelName,
            "RecorderType": "none",

            // UI & Behavior
            "IsMenuBarOnly": true,
            Keys.showMenuBarIcon: showMenuBarIconDefault,
            "DidApplyLaunchAtLoginDefault": false,
            "powerModePersistConfig": false,

            // Shortcuts
            "isMiddleClickToggleEnabled": false,
            "middleClickActivationDelay": 200,
            SpecialShortcutSettings.pasteLastTranscriptOnEmptyTapKey: true,

            // Model
            "PrewarmModelOnWake": true,
        ], uniquingKeysWith: { _, platformValue in platformValue })

        return defaults
    }

    static func registerDefaults() {
        let defaults = UserDefaults.standard
        let shouldEnableLaunchAtLoginByDefault = defaults.object(forKey: VoiceInkUserDefaultsKey.hasCompletedOnboarding) == nil
            && defaults.object(forKey: "DidApplyLaunchAtLoginDefault") == nil

        defaults.register(defaults: registeredDefaults)

        if shouldEnableLaunchAtLoginByDefault {
            LaunchAtLogin.isEnabled = true
            defaults.set(true, forKey: "DidApplyLaunchAtLoginDefault")
        }

        PunctuationCleanupMode.migrateLegacyUserDefaultIfNeeded()
        PasteMethod.migrateLegacyUserDefaultIfNeeded()
    }
}
