import Foundation
import AppKit
import AVFoundation
import RomaCore

class SystemInfoService {
    static let shared = SystemInfoService()

    private init() {}

    func getSystemInfoString() -> String {
        RomaSystemInformationReport.macOS(makeMacOSSystemInformationFacts())
    }

    func copySystemInfoToClipboard() {
        let info = getSystemInfoString()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(info, forType: .string)
    }

    private func getAppVersion() -> String {
        RomaSystemInformationReport.knownText(
            Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        )
    }

    private func getBuildVersion() -> String {
        RomaSystemInformationReport.knownText(
            Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        )
    }

    private func makeMacOSSystemInformationFacts() -> RomaMacOSSystemInformationFacts {
        let transcriptionCleanup = RomaTranscriptionAutoCleanupPreference.current()
        let audioCleanup = RomaAudioCleanupPreference.current()

        return RomaMacOSSystemInformationFacts(
            generated: RomaSystemInformationReport.generatedDateText(Date()),
            appVersion: getAppVersion(),
            buildVersion: getBuildVersion(),
            operatingSystemVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            deviceModel: getMacModel(),
            cpu: getCPUInfo(),
            memory: getMemoryInfo(),
            architecture: getArchitecture(),
            audioInputMode: getAudioInputMode(),
            currentAudioDevice: getCurrentAudioDevice(),
            availableAudioDevices: getAvailableAudioDevices(),
            primaryShortcut: getPrimaryShortcut(),
            secondaryShortcut: getSecondaryShortcut(),
            middleClickRecording: RomaRecordingShortcutPreference.isMiddleClickToggleEnabled(),
            middleClickActivationDelayMilliseconds: RomaRecordingShortcutPreference.middleClickActivationDelay(),
            selectedModel: getCurrentTranscriptionModel(),
            selectedLanguage: RomaTranscriptionLanguagePreference.selectedMacOSLanguage(),
            aiEnhancement: RomaAIEnhancementPreference.statusDiagnosticDescription(),
            aiProvider: RomaAIEnhancementProviderPreference.selectedProviderDiagnosticDescription(),
            aiModel: RomaAIEnhancementProviderPreference.selectedModelDiagnosticDescription(),
            hideDockIcon: !RomaMenuBarPreference.shouldShowDockIcon(),
            recorderStyle: RomaRecorderStylePreference.rawValue(),
            soundFeedback: RomaRecordingFeedbackPreference.isSoundFeedbackEnabled(),
            pauseMediaWhileRecording: RomaRecordingFeedbackPreference.isPauseMediaEnabled(),
            muteAudioWhileRecording: RomaRecordingFeedbackPreference.systemMuteMode().rawValue,
            audioResumptionDelaySeconds: RomaRecordingFeedbackPreference.audioResumptionDelay(),
            restoreClipboardAfterPaste: RomaPastePreference.shouldRestoreClipboardAfterPaste(),
            clipboardRestoreDelaySeconds: RomaPastePreference.clipboardRestoreDelay(),
            pasteMethod: RomaPasteMethod.current().displayName,
            powerModeEnabled: RomaPowerModePreference.isUIEnabled(),
            persistConfiguredPreferences: RomaPowerModePreference.shouldPersistConfiguredPreferences(),
            autoDeleteTranscriptions: transcriptionCleanup.isEnabled,
            transcriptionRetentionMinutes: transcriptionCleanup.retentionMinutes,
            autoDeleteAudioFiles: audioCleanup.isEnabled,
            audioRetentionPeriodDays: audioCleanup.retentionDays,
            accessibilityPermission: getAccessibilityStatus(),
            inputMonitoringPermission: getInputMonitoringStatus(),
            screenRecordingPermission: getScreenRecordingStatus(),
            microphonePermission: getMicrophoneStatus()
        )
    }

    private func getMacModel() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &machine, &size, nil, 0)
        return String(cString: machine)
    }

    private func getCPUInfo() -> String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0)
        return String(cString: buffer)
    }

    private func getMemoryInfo() -> String {
        let totalMemory = ProcessInfo.processInfo.physicalMemory
        return RomaPerformancePresentation.physicalMemoryText(byteCount: totalMemory)
    }

    private func getArchitecture() -> String {
        return RomaSystemArchitecture.macOSDisplayName
    }

    private func getAudioInputMode() -> String {
        AudioDeviceManager.shared.inputMode.rawValue
    }

    private func getCurrentAudioDevice() -> String {
        let audioManager = AudioDeviceManager.shared
        let deviceID = audioManager.getCurrentDevice()
        if deviceID != 0, let deviceName = audioManager.getDeviceName(deviceID: deviceID) {
            return RomaSystemInformationReport.knownText(deviceName)
        }
        return RomaSystemInformationReport.knownText(nil)
    }

    private func getAvailableAudioDevices() -> String {
        let devices = AudioDeviceManager.shared.availableDevices
        return RomaSystemInformationReport.availableAudioDevicesText(devices.map(\.name))
    }

    private func getPrimaryShortcut() -> String {
        shortcutDescription(for: .primaryRecording)
    }

    private func getSecondaryShortcut() -> String {
        shortcutDescription(for: .secondaryRecording)
    }

    private func shortcutDescription(for action: ShortcutAction) -> String {
        ShortcutStore.shortcut(for: action)?.displayString ?? ""
    }

    private func getCurrentTranscriptionModel() -> String {
        if let modelName = RomaCurrentTranscriptionModelPreference.modelName() {
            if let model = TranscriptionModelRegistry.models.first(where: { $0.name == modelName }) {
                return model.displayName
            }
            return modelName
        }
        return RomaModelManagementPresentation.noModelSelectedText
    }

    private func getAccessibilityStatus() -> String {
        RomaSystemInformationPermissionStatus.grantStatus(
            isGranted: AXIsProcessTrusted()
        ).displayText
    }

    private func getInputMonitoringStatus() -> String {
        RomaSystemInformationPermissionStatus.grantStatus(
            isGranted: ShortcutMonitor.preflightListenEventAccess()
        ).displayText
    }

    private func getScreenRecordingStatus() -> String {
        RomaSystemInformationPermissionStatus.grantStatus(
            isGranted: CGPreflightScreenCaptureAccess()
        ).displayText
    }

    private func getMicrophoneStatus() -> String {
        let status: RomaSystemInformationPermissionStatus
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            status = .granted
        case .denied:
            status = .denied
        case .restricted:
            status = .restricted
        case .notDetermined:
            status = .notDetermined
        @unknown default:
            status = .unknown
        }

        return status.displayText
    }

}
