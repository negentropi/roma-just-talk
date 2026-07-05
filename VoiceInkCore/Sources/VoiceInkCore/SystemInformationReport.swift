import Foundation
import OSLog

public struct VoiceInkDiagnosticLogSessionRange: Equatable, Sendable {
    public let label: String
    public let start: Date
    public let end: Date?

    public init(label: String, start: Date, end: Date?) {
        self.label = label
        self.start = start
        self.end = end
    }
}

public enum VoiceInkDiagnosticsSettingsPresentation {
    public static let rollingBufferLastClaimLabel = "Rolling Buffer Last Claim"
    public static let showInFinderButtonTitle = "Show in Finder"
    public static let exportButtonTitle = "Export"
    public static let exportLogsLabel = "Export Logs"
    public static let exportFailedAlertTitle = "Export Failed"
    public static let alertDismissButtonTitle = "OK"
    public static let exportedLogSuccessSystemImageName = "checkmark.circle.fill"
}

public enum VoiceInkDiagnosticLogExportPolicy {
    public static let sessionStartDatesKey = "logExporter.sessionStartDates.v1"
    public static let maxSessionStartDatesToKeep = 3
    public static let timestampDateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    public static let fileNameDateFormat = "yyyy-MM-dd_HH-mm-ss"
    public static let fileNamePrefix = "VoiceInk_Logs_"
    public static let fileNameExtension = "log"
    public static let headerTitle = "=== VoiceInk Diagnostic Logs ==="
    public static let headerDivider = "================================"
    public static let noLogsFoundMessage = "No logs found for this session."
    public static let exporterErrorDomain = "LogExporter"
    public static let downloadsDirectoryUnavailableErrorCode = 1
    public static let downloadsDirectoryUnavailableDescription = "Downloads directory unavailable"

    public static func storedSessionStartDates(from defaults: UserDefaults = .standard) -> [Date] {
        guard let data = defaults.data(forKey: sessionStartDatesKey),
              let dates = try? JSONDecoder().decode([Date].self, from: data) else {
            return []
        }

        return dates
    }

    public static func saveSessionStartDates(
        _ dates: [Date],
        to defaults: UserDefaults = .standard
    ) {
        guard let data = try? JSONEncoder().encode(dates) else {
            return
        }

        defaults.set(data, forKey: sessionStartDatesKey)
    }

    public static func sessionStartDates(
        starting currentDate: Date,
        storedDates: [Date]
    ) -> [Date] {
        Array(([currentDate] + storedDates).prefix(maxSessionStartDatesToKeep))
    }

    public static func sessionRanges(
        from sessionStartDates: [Date]
    ) -> [VoiceInkDiagnosticLogSessionRange] {
        let totalSessions = sessionStartDates.count
        return sessionStartDates.enumerated().map { index, start in
            let end: Date? = (index == 0) ? nil : sessionStartDates[index - 1]
            let sessionNumber = totalSessions - index
            return VoiceInkDiagnosticLogSessionRange(
                label: sessionLabel(
                    index: index,
                    totalSessions: totalSessions,
                    sessionNumber: sessionNumber
                ),
                start: start,
                end: end
            )
        }
    }

    public static func headerLines(
        exportDate: Date,
        subsystem: String,
        sessionCount: Int,
        systemInfo: String
    ) -> [String] {
        [
            headerTitle,
            "Export Date: \(formattedTimestamp(exportDate))",
            "Subsystem: \(subsystem)",
            "Total Sessions: \(sessionCount)",
            headerDivider,
            "",
            systemInfo,
            ""
        ]
    }

    public static func sessionHeaderLines(label: String) -> [String] {
        [
            "--- \(label) ---",
            ""
        ]
    }

    public static func logEntryLine(
        date: Date,
        level: String,
        category: String,
        message: String
    ) -> String {
        "[\(formattedTimestamp(date))] [\(level)] [\(category)] \(message)"
    }

    public static func exportContent(from lines: [String]) -> String {
        lines.joined(separator: "\n")
    }

    public static func logLevelLabel(for level: OSLogEntryLog.Level) -> String {
        switch level {
        case .undefined:
            return "UNDEFINED"
        case .debug:
            return "DEBUG"
        case .info:
            return "INFO"
        case .notice:
            return "NOTICE"
        case .error:
            return "ERROR"
        case .fault:
            return "FAULT"
        @unknown default:
            return "UNKNOWN"
        }
    }

    public static func fileName(for date: Date) -> String {
        "\(fileNamePrefix)\(formattedDate(date, format: fileNameDateFormat)).\(fileNameExtension)"
    }

    public static func downloadsDirectoryUnavailableError() -> NSError {
        NSError(
            domain: exporterErrorDomain,
            code: downloadsDirectoryUnavailableErrorCode,
            userInfo: [NSLocalizedDescriptionKey: downloadsDirectoryUnavailableDescription]
        )
    }

    public static func formattedTimestamp(_ date: Date) -> String {
        formattedDate(date, format: timestampDateFormat)
    }

    private static func sessionLabel(
        index: Int,
        totalSessions: Int,
        sessionNumber: Int
    ) -> String {
        if totalSessions == 1 {
            return "Session 1 (Current)"
        } else if index == 0 {
            return "Session \(sessionNumber) (Current)"
        } else if index == totalSessions - 1 {
            return "Session 1 (Oldest)"
        } else {
            return "Session \(sessionNumber)"
        }
    }

    private static func formattedDate(_ date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}

public enum VoiceInkSystemArchitecture {
    public static var isIntelMac: Bool {
        #if os(macOS) && arch(x86_64)
        return true
        #else
        return false
        #endif
    }

    public static var macOSDisplayName: String {
        #if arch(arm64)
        return "Apple Silicon (ARM64)"
        #elseif arch(x86_64)
        return "Intel (x86_64)"
        #else
        return "Unknown"
        #endif
    }
}

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
    public static let noAudioDevicesDetectedText = "None detected"
    public static let unknownValueText = "Unknown"

    public static func generatedDateText(_ date: Date) -> String {
        date.formatted(date: .long, time: .standard)
    }

    public static func knownText(_ text: String?) -> String {
        text ?? unknownValueText
    }

    public static func availableAudioDevicesText(_ deviceNames: [String]) -> String {
        guard !deviceNames.isEmpty else {
            return noAudioDevicesDetectedText
        }
        return deviceNames.joined(separator: ", ")
    }

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

public enum VoiceInkSystemInformationPermissionStatus: Equatable, Sendable {
    case granted
    case notGranted
    case denied
    case restricted
    case notDetermined
    case unknown

    public var displayText: String {
        switch self {
        case .granted:
            return "Granted"
        case .notGranted:
            return "Not Granted"
        case .denied:
            return "Denied"
        case .restricted:
            return "Restricted"
        case .notDetermined:
            return "Not Determined"
        case .unknown:
            return "Unknown"
        }
    }

    public static func grantStatus(isGranted: Bool) -> Self {
        isGranted ? .granted : .notGranted
    }
}

public enum VoiceInkSystemInformationLicenseStatus: Equatable, Sendable {
    case licensedPro
    case notLicensed

    public var displayText: String {
        switch self {
        case .licensedPro:
            return "Licensed (Pro)"
        case .notLicensed:
            return "Not Licensed"
        }
    }

    public static func status(hasUsableStoredLicense: Bool) -> Self {
        hasUsableStoredLicense ? .licensedPro : .notLicensed
    }
}

public struct VoiceInkSystemInformationCopyButtonPresentation: Equatable, Sendable {
    public let systemImageName: String
    public let title: String

    public init(systemImageName: String, title: String) {
        self.systemImageName = systemImageName
        self.title = title
    }
}

public enum VoiceInkSystemInformationCopyPresentation {
    public static let idleSystemImageName = "doc.on.doc"
    public static let copiedSystemImageName = "checkmark"
    public static let idleTitle = "Copy System Info"
    public static let copiedTitle = "Copied!"
    public static let copiedResetDelay: TimeInterval = 1.5

    public static func button(isCopied: Bool) -> VoiceInkSystemInformationCopyButtonPresentation {
        VoiceInkSystemInformationCopyButtonPresentation(
            systemImageName: isCopied ? copiedSystemImageName : idleSystemImageName,
            title: isCopied ? copiedTitle : idleTitle
        )
    }
}
