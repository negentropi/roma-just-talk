import Foundation
import RomaCore

extension Notification.Name {
    static let AppSettingsDidChange = RomaMacOSAppEventRequest.appSettingsDidChangeNotificationName
    static let languageDidChange = RomaMacOSAppEventRequest.languageDidChangeNotificationName
    static let toggleMiniRecorder = RomaMiniRecorderRequest.toggleNotificationName
    static let dismissMiniRecorder = RomaMiniRecorderRequest.dismissNotificationName
    static let didChangeModel = RomaMacOSAppEventRequest.didChangeModelNotificationName
    static let aiProviderKeyChanged = RomaAIEnhancementProviderKeyChangeRequest.notificationName
    static let openMainWindowRequested = RomaMacOSAppEventRequest.openMainWindowRequestedNotificationName
    static let navigateToDestination = RomaMacOSNavigationRequest.notificationName
    static let appPermissionsDidChange = RomaMacOSAppEventRequest.appPermissionsDidChangeNotificationName
    static let promptSelectionChanged = RomaMacOSAppEventRequest.promptSelectionChangedNotificationName
    static let powerModeConfigurationApplied = RomaMacOSAppEventRequest.powerModeConfigurationAppliedNotificationName
    static let powerModeConfigurationsDidChange = RomaMacOSAppEventRequest.powerModeConfigurationsDidChangeNotificationName
    static let powerModeShortcutAvailabilityDidChange = RomaMacOSAppEventRequest.powerModeShortcutAvailabilityDidChangeNotificationName
    static let transcriptionCreated = RomaMacOSAppEventRequest.transcriptionCreatedNotificationName
    static let transcriptionCompleted = RomaMacOSAppEventRequest.transcriptionCompletedNotificationName
    static let transcriptionDeleted = RomaMacOSAppEventRequest.transcriptionDeletedNotificationName
    static let sessionMetricsDidChange = RomaMacOSAppEventRequest.sessionMetricsDidChangeNotificationName
    static let enhancementToggleChanged = RomaMacOSAppEventRequest.enhancementToggleChangedNotificationName
    static let openFileForTranscription = RomaMacOSFileTranscriptionRequest.notificationName
    static let audioDeviceSwitchRequired = RomaMacOSAudioDeviceChangeRequest.switchRequiredNotificationName
    static let audioDeviceChanged = RomaMacOSAudioDeviceChangeRequest.deviceChangedNotificationName
}
