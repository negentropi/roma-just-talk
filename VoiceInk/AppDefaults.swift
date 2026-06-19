import Foundation
import LaunchAtLogin
import VoiceInkCore

enum AppDefaults {
    enum Keys {
        static let showMenuBarIcon = "ShowMenuBarIcon"
    }

    static let showMenuBarIconDefault = false

    static var registeredDefaults: [String: Any] {
        var defaults = VoiceInkDefaultSettings.macOS.registeredUserDefaults(
            currentTranscriptionModel: "parakeet-tdt-0.6b-v2"
        )

        var platformDefaults: [String: Any] = [
            // Onboarding & General
            "enableAnnouncements": true,

            // Audio & Media
            CustomSoundManager.SoundType.start.builtInSoundKey: CustomSoundManager.SoundType.start.defaultBuiltInSound.rawValue,
            CustomSoundManager.SoundType.stop.builtInSoundKey: CustomSoundManager.SoundType.stop.defaultBuiltInSound.rawValue,

            // Recording & Transcription
            VoiceInkUserDefaultsKey.appendTrailingSpace: VoiceInkPreferenceDefault.appendTrailingSpace,
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

            // Shortcuts
            "isMiddleClickToggleEnabled": false,
            "middleClickActivationDelay": 200,
            SpecialShortcutSettings.pasteLastTranscriptOnEmptyTapKey: true,

            // Model
            "PrewarmModelOnWake": true,
        ]

        platformDefaults.merge(VoiceInkRecordingFeedbackPreference.registeredDefaults) { _, sharedValue in sharedValue }
        platformDefaults.merge(VoiceInkPastePreference.registeredDefaults) { _, sharedValue in sharedValue }
        platformDefaults.merge(VoiceInkPowerModePreference.registeredDefaults) { _, sharedValue in sharedValue }
        defaults.merge(platformDefaults, uniquingKeysWith: { _, platformValue in platformValue })

        return defaults
    }

    static func registerDefaults() {
        let defaults = UserDefaults.standard
        let shouldEnableLaunchAtLoginByDefault = !VoiceInkOnboardingPreference.hasStoredCompletionState(from: defaults)
            && defaults.object(forKey: "DidApplyLaunchAtLoginDefault") == nil

        defaults.register(defaults: registeredDefaults)

        if shouldEnableLaunchAtLoginByDefault {
            LaunchAtLogin.isEnabled = true
            defaults.set(true, forKey: "DidApplyLaunchAtLoginDefault")
        }

        PunctuationCleanupMode.migrateLegacyUserDefaultIfNeeded()
        VoiceInkPasteMethod.migrateLegacyUserDefaultIfNeeded()
    }
}
