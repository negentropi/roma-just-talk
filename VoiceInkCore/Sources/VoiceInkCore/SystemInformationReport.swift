import Foundation

public struct VoiceInkMacOSSystemInformationFacts: Equatable, Sendable {
    public let generated: String
    public let appVersion: String
    public let buildVersion: String
    public let licenseStatus: String
    public let operatingSystemVersion: String
    public let deviceModel: String
    public let cpu: String
    public let memory: String
    public let architecture: String
    public let audioInputMode: String
    public let currentAudioDevice: String
    public let availableAudioDevices: String
    public let primaryShortcut: String
    public let secondaryShortcut: String
    public let middleClickRecording: Bool
    public let middleClickActivationDelayMilliseconds: Int
    public let selectedModel: String
    public let selectedLanguage: String
    public let aiEnhancement: String
    public let aiProvider: String
    public let aiModel: String
    public let rollingBufferPreload: String
    public let hideDockIcon: Bool
    public let recorderStyle: String
    public let soundFeedback: Bool
    public let pauseMediaWhileRecording: Bool
    public let muteAudioWhileRecording: String
    public let audioResumptionDelaySeconds: Double
    public let restoreClipboardAfterPaste: Bool
    public let clipboardRestoreDelaySeconds: Double
    public let pasteMethod: String
    public let powerModeEnabled: Bool
    public let persistConfiguredPreferences: Bool
    public let autoDeleteTranscriptions: Bool
    public let transcriptionRetentionMinutes: Int
    public let autoDeleteAudioFiles: Bool
    public let audioRetentionPeriodDays: Int
    public let accessibilityPermission: String
    public let inputMonitoringPermission: String
    public let screenRecordingPermission: String
    public let microphonePermission: String

    public init(
        generated: String,
        appVersion: String,
        buildVersion: String,
        licenseStatus: String,
        operatingSystemVersion: String,
        deviceModel: String,
        cpu: String,
        memory: String,
        architecture: String,
        audioInputMode: String,
        currentAudioDevice: String,
        availableAudioDevices: String,
        primaryShortcut: String,
        secondaryShortcut: String,
        middleClickRecording: Bool,
        middleClickActivationDelayMilliseconds: Int,
        selectedModel: String,
        selectedLanguage: String,
        aiEnhancement: String,
        aiProvider: String,
        aiModel: String,
        rollingBufferPreload: String,
        hideDockIcon: Bool,
        recorderStyle: String,
        soundFeedback: Bool,
        pauseMediaWhileRecording: Bool,
        muteAudioWhileRecording: String,
        audioResumptionDelaySeconds: Double,
        restoreClipboardAfterPaste: Bool,
        clipboardRestoreDelaySeconds: Double,
        pasteMethod: String,
        powerModeEnabled: Bool,
        persistConfiguredPreferences: Bool,
        autoDeleteTranscriptions: Bool,
        transcriptionRetentionMinutes: Int,
        autoDeleteAudioFiles: Bool,
        audioRetentionPeriodDays: Int,
        accessibilityPermission: String,
        inputMonitoringPermission: String,
        screenRecordingPermission: String,
        microphonePermission: String
    ) {
        self.generated = generated
        self.appVersion = appVersion
        self.buildVersion = buildVersion
        self.licenseStatus = licenseStatus
        self.operatingSystemVersion = operatingSystemVersion
        self.deviceModel = deviceModel
        self.cpu = cpu
        self.memory = memory
        self.architecture = architecture
        self.audioInputMode = audioInputMode
        self.currentAudioDevice = currentAudioDevice
        self.availableAudioDevices = availableAudioDevices
        self.primaryShortcut = primaryShortcut
        self.secondaryShortcut = secondaryShortcut
        self.middleClickRecording = middleClickRecording
        self.middleClickActivationDelayMilliseconds = middleClickActivationDelayMilliseconds
        self.selectedModel = selectedModel
        self.selectedLanguage = selectedLanguage
        self.aiEnhancement = aiEnhancement
        self.aiProvider = aiProvider
        self.aiModel = aiModel
        self.rollingBufferPreload = rollingBufferPreload
        self.hideDockIcon = hideDockIcon
        self.recorderStyle = recorderStyle
        self.soundFeedback = soundFeedback
        self.pauseMediaWhileRecording = pauseMediaWhileRecording
        self.muteAudioWhileRecording = muteAudioWhileRecording
        self.audioResumptionDelaySeconds = audioResumptionDelaySeconds
        self.restoreClipboardAfterPaste = restoreClipboardAfterPaste
        self.clipboardRestoreDelaySeconds = clipboardRestoreDelaySeconds
        self.pasteMethod = pasteMethod
        self.powerModeEnabled = powerModeEnabled
        self.persistConfiguredPreferences = persistConfiguredPreferences
        self.autoDeleteTranscriptions = autoDeleteTranscriptions
        self.transcriptionRetentionMinutes = transcriptionRetentionMinutes
        self.autoDeleteAudioFiles = autoDeleteAudioFiles
        self.audioRetentionPeriodDays = audioRetentionPeriodDays
        self.accessibilityPermission = accessibilityPermission
        self.inputMonitoringPermission = inputMonitoringPermission
        self.screenRecordingPermission = screenRecordingPermission
        self.microphonePermission = microphonePermission
    }
}

public enum VoiceInkSystemInformationReport {
    public static func macOS(_ facts: VoiceInkMacOSSystemInformationFacts) -> String {
        """
        === VOICEINK SYSTEM INFORMATION ===
        Generated: \(facts.generated)

        APP INFORMATION:
        App Version: \(facts.appVersion)
        Build Version: \(facts.buildVersion)
        License Status: \(facts.licenseStatus)

        OPERATING SYSTEM:
        macOS Version: \(facts.operatingSystemVersion)

        HARDWARE INFORMATION:
        Device Model: \(facts.deviceModel)
        CPU: \(facts.cpu)
        Memory: \(facts.memory)
        Architecture: \(facts.architecture)

        AUDIO SETTINGS:
        Input Mode: \(facts.audioInputMode)
        Current Audio Device: \(facts.currentAudioDevice)
        Available Audio Devices: \(facts.availableAudioDevices)

        HOTKEY SETTINGS:
        Primary Shortcut: \(facts.primaryShortcut)
        Secondary Shortcut: \(facts.secondaryShortcut)
        Middle-Click Recording: \(facts.middleClickRecording)
        Middle-Click Activation Delay: \(facts.middleClickActivationDelayMilliseconds) ms

        TRANSCRIPTION SETTINGS:
        Selected Model: \(facts.selectedModel)
        Selected Language: \(facts.selectedLanguage)
        AI Enhancement: \(facts.aiEnhancement)
        AI Provider: \(facts.aiProvider)
        AI Model: \(facts.aiModel)

        ROLLING BUFFER PRELOAD:
        \(facts.rollingBufferPreload)

        UI SETTINGS:
        Hide Dock Icon: \(facts.hideDockIcon)
        Recorder Style: \(facts.recorderStyle)

        RECORDING FEEDBACK:
        Sound Feedback: \(facts.soundFeedback)
        Pause Media While Recording: \(facts.pauseMediaWhileRecording)
        Mute Audio While Recording: \(facts.muteAudioWhileRecording)
        Audio Resumption Delay: \(facts.audioResumptionDelaySeconds)s

        CLIPBOARD & PASTE SETTINGS:
        Restore Clipboard After Paste: \(facts.restoreClipboardAfterPaste)
        Clipboard Restore Delay: \(facts.clipboardRestoreDelaySeconds)s
        Paste Method: \(facts.pasteMethod)

        POWER MODE:
        Power Mode Enabled: \(facts.powerModeEnabled)
        Persist Configured Preferences: \(facts.persistConfiguredPreferences)

        DATA CLEANUP SETTINGS:
        Auto-Delete Transcriptions: \(facts.autoDeleteTranscriptions)
        Transcription Retention: \(facts.transcriptionRetentionMinutes) minutes
        Auto-Delete Audio Files: \(facts.autoDeleteAudioFiles)
        Audio Retention Period: \(facts.audioRetentionPeriodDays) days

        PERMISSIONS:
        Accessibility: \(facts.accessibilityPermission)
        Input Monitoring: \(facts.inputMonitoringPermission)
        Screen Recording: \(facts.screenRecordingPermission)
        Microphone: \(facts.microphonePermission)
        """
    }
}
