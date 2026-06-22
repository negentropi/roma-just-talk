import Foundation
import VoiceInkCore

extension Notification.Name {
    static let AppSettingsDidChange = Notification.Name("appSettingsDidChange")
    static let languageDidChange = Notification.Name("languageDidChange")
    static let toggleMiniRecorder = VoiceInkMiniRecorderRequest.toggleNotificationName
    static let dismissMiniRecorder = VoiceInkMiniRecorderRequest.dismissNotificationName
    static let didChangeModel = Notification.Name("didChangeModel")
    static let aiProviderKeyChanged = Notification.Name("aiProviderKeyChanged")
    static let licenseStatusChanged = Notification.Name("licenseStatusChanged")
    static let openMainWindowRequested = Notification.Name("openMainWindowRequested")
    static let navigateToDestination = VoiceInkMacOSNavigationRequest.notificationName
    static let appPermissionsDidChange = Notification.Name("appPermissionsDidChange")
    static let promptSelectionChanged = Notification.Name("promptSelectionChanged")
    static let powerModeConfigurationApplied = Notification.Name("powerModeConfigurationApplied")
    static let powerModeConfigurationsDidChange = Notification.Name("PowerModeConfigurationsDidChange")
    static let powerModeShortcutAvailabilityDidChange = Notification.Name("powerModeShortcutAvailabilityDidChange")
    static let transcriptionCreated = Notification.Name("transcriptionCreated")
    static let transcriptionCompleted = Notification.Name("transcriptionCompleted")
    static let transcriptionDeleted = Notification.Name("transcriptionDeleted")
    static let rollingBufferPreloadPartialTranscript = Notification.Name("rollingBufferPreloadPartialTranscript")
    static let sessionMetricsDidChange = Notification.Name("sessionMetricsDidChange")
    static let enhancementToggleChanged = Notification.Name("enhancementToggleChanged")
    static let openFileForTranscription = VoiceInkMacOSFileTranscriptionRequest.notificationName
    static let audioDeviceSwitchRequired = VoiceInkMacOSAudioDeviceChangeRequest.switchRequiredNotificationName
    static let audioDeviceChanged = VoiceInkMacOSAudioDeviceChangeRequest.deviceChangedNotificationName
}
