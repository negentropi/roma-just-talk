import Foundation
import VoiceInkCore

extension Notification.Name {
    static let AppSettingsDidChange = VoiceInkMacOSAppEventRequest.appSettingsDidChangeNotificationName
    static let languageDidChange = VoiceInkMacOSAppEventRequest.languageDidChangeNotificationName
    static let toggleMiniRecorder = VoiceInkMiniRecorderRequest.toggleNotificationName
    static let dismissMiniRecorder = VoiceInkMiniRecorderRequest.dismissNotificationName
    static let didChangeModel = VoiceInkMacOSAppEventRequest.didChangeModelNotificationName
    static let aiProviderKeyChanged = VoiceInkAIEnhancementProviderKeyChangeRequest.notificationName
    static let licenseStatusChanged = VoiceInkLicenseStatusChangeRequest.notificationName
    static let openMainWindowRequested = VoiceInkMacOSAppEventRequest.openMainWindowRequestedNotificationName
    static let navigateToDestination = VoiceInkMacOSNavigationRequest.notificationName
    static let appPermissionsDidChange = VoiceInkMacOSAppEventRequest.appPermissionsDidChangeNotificationName
    static let promptSelectionChanged = VoiceInkMacOSAppEventRequest.promptSelectionChangedNotificationName
    static let powerModeConfigurationApplied = VoiceInkMacOSAppEventRequest.powerModeConfigurationAppliedNotificationName
    static let powerModeConfigurationsDidChange = VoiceInkMacOSAppEventRequest.powerModeConfigurationsDidChangeNotificationName
    static let powerModeShortcutAvailabilityDidChange = VoiceInkMacOSAppEventRequest.powerModeShortcutAvailabilityDidChangeNotificationName
    static let transcriptionCreated = VoiceInkMacOSAppEventRequest.transcriptionCreatedNotificationName
    static let transcriptionCompleted = VoiceInkMacOSAppEventRequest.transcriptionCompletedNotificationName
    static let transcriptionDeleted = VoiceInkMacOSAppEventRequest.transcriptionDeletedNotificationName
    static let sessionMetricsDidChange = VoiceInkMacOSAppEventRequest.sessionMetricsDidChangeNotificationName
    static let enhancementToggleChanged = VoiceInkMacOSAppEventRequest.enhancementToggleChangedNotificationName
    static let openFileForTranscription = VoiceInkMacOSFileTranscriptionRequest.notificationName
    static let audioDeviceSwitchRequired = VoiceInkMacOSAudioDeviceChangeRequest.switchRequiredNotificationName
    static let audioDeviceChanged = VoiceInkMacOSAudioDeviceChangeRequest.deviceChangedNotificationName
}
