import Foundation
import LaunchAtLogin
import VoiceInkCore

enum AppDefaults {
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
            VoiceInkRollingBufferPreloadSettings.modeKey: VoiceInkRollingBufferPreloadSettings.defaultMode.rawValue,
            VoiceInkRollingBufferPreloadSettings.autoDisableCloudModelsKey: VoiceInkRollingBufferPreloadSettings.defaultAutoDisablesCloudModels,
            VoiceInkRollingBufferPreloadSettings.autoDisableLowBatteryLocalModelsKey: VoiceInkRollingBufferPreloadSettings.defaultAutoDisablesLowBatteryLocalModels,
            VoiceInkRollingBufferPreloadSettings.lowBatteryThresholdPercentKey: VoiceInkRollingBufferPreloadSettings.defaultLowBatteryThresholdPercent,
            VoiceInkRollingBufferPreloadSettings.bufferDurationSecondsKey: VoiceInkRollingBufferPreloadSettings.defaultBufferDurationSeconds,
            VoiceInkRollingBufferPreloadSettings.preRunFinalizationKey: VoiceInkRollingBufferPreloadSettings.defaultPreRunFinalization,
            VoiceInkRollingBufferVADSettings.modelKey: VoiceInkRollingBufferVADSettings.sileroModelName,
            VoiceInkRecorderStylePreference.userDefaultsKey: VoiceInkRecorderStylePreference.defaultRawValue,

            // UI & Behavior
            "DidApplyLaunchAtLoginDefault": false,
        ]

        platformDefaults.merge(VoiceInkMenuBarPreference.registeredDefaults) { _, sharedValue in sharedValue }
        platformDefaults.merge(VoiceInkAppendTrailingSpacePreference.registeredDefaults) { _, sharedValue in sharedValue }
        platformDefaults.merge(VoiceInkModelRuntimePreference.registeredDefaults) { _, sharedValue in sharedValue }
        platformDefaults.merge(VoiceInkRecorderPreviewPreference.registeredDefaults) { _, sharedValue in sharedValue }
        platformDefaults.merge(VoiceInkRecordingShortcutPreference.registeredDefaults) { _, sharedValue in sharedValue }
        platformDefaults.merge(VoiceInkRecordingFeedbackPreference.registeredDefaults) { _, sharedValue in sharedValue }
        platformDefaults.merge(VoiceInkAudioInputPreference.registeredDefaults) { _, sharedValue in sharedValue }
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
