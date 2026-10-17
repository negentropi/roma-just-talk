import Foundation
import LaunchAtLogin
import RomaCore

enum AppDefaults {
    static var registeredDefaults: [String: Any] {
        var defaults = RomaDefaultSettings.macOS.registeredUserDefaults(
            currentTranscriptionModel: RomaTranscriptionModelCatalog.defaultMacOSFluidAudioModelName
        )

        var platformDefaults: [String: Any] = [
            // Onboarding & General

            // Recording & Transcription
            RomaRecorderStylePreference.userDefaultsKey: RomaRecorderStylePreference.defaultRawValue,

            // UI & Behavior
        ]

        platformDefaults.merge(RomaMacOSLaunchAtLoginDefaultPolicy.registeredDefaults) { _, sharedValue in sharedValue }
        platformDefaults.merge(RomaMenuBarPreference.registeredDefaults) { _, sharedValue in sharedValue }
        platformDefaults.merge(RomaAppendTrailingSpacePreference.registeredDefaults) { _, sharedValue in sharedValue }
        platformDefaults.merge(RomaModelRuntimePreference.registeredDefaults) { _, sharedValue in sharedValue }
        platformDefaults.merge(RomaRecorderPreviewPreference.registeredDefaults) { _, sharedValue in sharedValue }
        platformDefaults.merge(RomaRecordingShortcutPreference.registeredDefaults) { _, sharedValue in sharedValue }
        platformDefaults.merge(RomaRecordingFeedbackPreference.registeredDefaults) { _, sharedValue in sharedValue }
        platformDefaults.merge(RomaCustomSoundPreference.registeredDefaults) { _, sharedValue in sharedValue }
        platformDefaults.merge(RomaAudioInputPreference.registeredDefaults) { _, sharedValue in sharedValue }
        platformDefaults.merge(RomaPastePreference.registeredDefaults) { _, sharedValue in sharedValue }
        platformDefaults.merge(RomaPowerModePreference.registeredDefaults) { _, sharedValue in sharedValue }
        defaults.merge(platformDefaults, uniquingKeysWith: { _, platformValue in platformValue })

        return defaults
    }

    static func registerDefaults() {
        let defaults = UserDefaults.standard
        let shouldEnableLaunchAtLoginByDefault = RomaMacOSLaunchAtLoginDefaultPolicy
            .shouldEnableByDefaultBeforeRegisteringDefaults(in: defaults)

        defaults.register(defaults: registeredDefaults)

        if shouldEnableLaunchAtLoginByDefault {
            LaunchAtLogin.isEnabled = true
            RomaMacOSLaunchAtLoginDefaultPolicy.markDefaultApplied(to: defaults)
        }

        RomaStartupPreferenceMigration.migrateLegacyPreferences(for: .macOS)
    }
}
