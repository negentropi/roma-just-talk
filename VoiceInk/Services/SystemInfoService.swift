import Foundation
import AppKit
import AVFoundation
import VoiceInkCore

class SystemInfoService {
    static let shared = SystemInfoService()

    private init() {}

    func getSystemInfoString() -> String {
        VoiceInkSystemInformationReport.macOS(makeMacOSSystemInformationFacts())
    }

    func copySystemInfoToClipboard() {
        let info = getSystemInfoString()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(info, forType: .string)
    }

    private func getAppVersion() -> String {
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    private func getBuildVersion() -> String {
        return Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }

    private func makeMacOSSystemInformationFacts() -> VoiceInkMacOSSystemInformationFacts {
        let transcriptionCleanup = VoiceInkTranscriptionAutoCleanupPreference.current()
        let audioCleanup = VoiceInkAudioCleanupPreference.current()

        return VoiceInkMacOSSystemInformationFacts(
            generated: VoiceInkSystemInformationReport.generatedDateText(Date()),
            appVersion: getAppVersion(),
            buildVersion: getBuildVersion(),
            licenseStatus: getLicenseStatus(),
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
            middleClickRecording: VoiceInkRecordingShortcutPreference.isMiddleClickToggleEnabled(),
            middleClickActivationDelayMilliseconds: VoiceInkRecordingShortcutPreference.middleClickActivationDelay(),
            selectedModel: getCurrentTranscriptionModel(),
            selectedLanguage: VoiceInkTranscriptionLanguagePreference.selectedMacOSLanguage(),
            aiEnhancement: VoiceInkAIEnhancementPreference.statusDiagnosticDescription(),
            aiProvider: VoiceInkAIEnhancementProviderPreference.selectedProviderDiagnosticDescription(),
            aiModel: VoiceInkAIEnhancementProviderPreference.selectedModelDiagnosticDescription(),
            rollingBufferPreload: getRollingBufferPreloadInfo(),
            hideDockIcon: VoiceInkMenuBarPreference.isMenuBarOnly(),
            recorderStyle: VoiceInkRecorderStylePreference.rawValue(),
            soundFeedback: VoiceInkRecordingFeedbackPreference.isSoundFeedbackEnabled(),
            pauseMediaWhileRecording: VoiceInkRecordingFeedbackPreference.isPauseMediaEnabled(),
            muteAudioWhileRecording: VoiceInkRecordingFeedbackPreference.systemMuteMode().rawValue,
            audioResumptionDelaySeconds: VoiceInkRecordingFeedbackPreference.audioResumptionDelay(),
            restoreClipboardAfterPaste: VoiceInkPastePreference.shouldRestoreClipboardAfterPaste(),
            clipboardRestoreDelaySeconds: VoiceInkPastePreference.clipboardRestoreDelay(),
            pasteMethod: VoiceInkPasteMethod.current().displayName,
            powerModeEnabled: VoiceInkPowerModePreference.isUIEnabled(),
            persistConfiguredPreferences: VoiceInkPowerModePreference.shouldPersistConfiguredPreferences(),
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
        return VoiceInkPerformancePresentation.physicalMemoryText(byteCount: totalMemory)
    }

    private func getArchitecture() -> String {
        return VoiceInkSystemArchitecture.macOSDisplayName
    }

    private func getAudioInputMode() -> String {
        AudioDeviceManager.shared.inputMode.rawValue
    }

    private func getCurrentAudioDevice() -> String {
        let audioManager = AudioDeviceManager.shared
        let deviceID = audioManager.getCurrentDevice()
        if deviceID != 0, let deviceName = audioManager.getDeviceName(deviceID: deviceID) {
            return deviceName
        }
        return "Unknown"
    }

    private func getAvailableAudioDevices() -> String {
        let devices = AudioDeviceManager.shared.availableDevices
        return VoiceInkSystemInformationReport.availableAudioDevicesText(devices.map(\.name))
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
        if let modelName = VoiceInkCurrentTranscriptionModelPreference.modelName() {
            if let model = TranscriptionModelRegistry.models.first(where: { $0.name == modelName }) {
                return model.displayName
            }
            return modelName
        }
        return VoiceInkModelManagementPresentation.noModelSelectedText
    }

    private func getRollingBufferPreloadInfo() -> String {
        let configuration = VoiceInkRollingBufferPreloadSettings.configuration()
        let powerState = IOKitRollingBufferPowerStateProvider().currentPowerState()
        let runtimeClaim = RollingBufferPreloadRuntimeDiagnostics.shared.currentQuickReleaseClaim()
        let currentModelName = VoiceInkCurrentTranscriptionModelPreference.modelName()
        let currentModelPreloadEnabled: Bool?
        if let currentModelName {
            currentModelPreloadEnabled = VoiceInkRollingBufferPreloadSettings.perModelPreloadEnabled(forModelName: currentModelName)
        } else {
            currentModelPreloadEnabled = nil
        }

        return VoiceInkRollingBufferPreloadDiagnostics.systemInformationText(
            configuration: configuration,
            selectedVADModelRawValue: VoiceInkRollingBufferVADSettings.selectedModel(),
            powerState: powerState,
            currentModelPreloadEnabled: currentModelPreloadEnabled,
            quickReleaseClaimExportSummary: runtimeClaim.exportSummary
        )
    }

    private func getAccessibilityStatus() -> String {
        VoiceInkSystemInformationPermissionStatus.grantStatus(
            isGranted: AXIsProcessTrusted()
        ).displayText
    }

    private func getInputMonitoringStatus() -> String {
        VoiceInkSystemInformationPermissionStatus.grantStatus(
            isGranted: ShortcutMonitor.preflightListenEventAccess()
        ).displayText
    }

    private func getScreenRecordingStatus() -> String {
        VoiceInkSystemInformationPermissionStatus.grantStatus(
            isGranted: CGPreflightScreenCaptureAccess()
        ).displayText
    }

    private func getMicrophoneStatus() -> String {
        let status: VoiceInkSystemInformationPermissionStatus
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

    private func getLicenseStatus() -> String {
        let licenseManager = LicenseManager.shared

        return VoiceInkSystemInformationLicenseStatus.status(
            hasUsableStoredLicense: VoiceInkLicensePreference.hasUsableStoredLicense(
                licenseKey: licenseManager.licenseKey,
                activationId: licenseManager.activationId
            )
        ).displayText
    }

}
