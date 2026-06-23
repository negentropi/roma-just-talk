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
            generated: Date().formatted(date: .long, time: .standard),
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
        return SystemArchitecture.current
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
        if devices.isEmpty {
            return "None detected"
        }
        return devices.map { $0.name }.joined(separator: ", ")
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
        let powerDescription: String
        if powerState.isOnBattery {
            powerDescription = "Battery (\(powerState.batteryLevelPercent.map { "\($0)" } ?? "unknown")%)"
        } else {
            powerDescription = "External Power"
        }

        let currentModelName = VoiceInkCurrentTranscriptionModelPreference.modelName()
        let currentModelPreloadEnabled: String
        if let currentModelName {
            let enabled = VoiceInkRollingBufferPreloadSettings.perModelPreloadEnabled(forModelName: currentModelName)
            currentModelPreloadEnabled = "\(enabled)"
        } else {
            currentModelPreloadEnabled = VoiceInkModelManagementPresentation.noModelSelectedText
        }

        return """
        Mode: \(configuration.mode.displayName)
        Pre-run Finalization: \(configuration.preRunFinalization)
        Buffer Duration: \(configuration.bufferDurationSeconds)s
        Rolling VAD Model: \(VoiceInkRollingBufferVADSettings.selectedModel())
        Auto Disable Cloud Models: \(configuration.autoDisablesCloudModels)
        Auto Disable Local Models on Low Battery: \(configuration.autoDisablesLowBatteryLocalModels)
        Low Battery Threshold: \(configuration.lowBatteryThresholdPercent)%
        Current Power State: \(powerDescription)
        Current Model Buffer Preload: \(currentModelPreloadEnabled)
        Last Quick Release Claim: \(runtimeClaim.exportSummary)
        """
    }

    private func getAccessibilityStatus() -> String {
        return AXIsProcessTrusted() ? "Granted" : "Not Granted"
    }

    private func getInputMonitoringStatus() -> String {
        return ShortcutMonitor.preflightListenEventAccess() ? "Granted" : "Not Granted"
    }

    private func getScreenRecordingStatus() -> String {
        return CGPreflightScreenCaptureAccess() ? "Granted" : "Not Granted"
    }

    private func getMicrophoneStatus() -> String {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return "Granted"
        case .denied:
            return "Denied"
        case .restricted:
            return "Restricted"
        case .notDetermined:
            return "Not Determined"
        @unknown default:
            return "Unknown"
        }
    }

    private func getLicenseStatus() -> String {
        let licenseManager = LicenseManager.shared

        // Check for existing license key and activation
        if VoiceInkLicensePreference.hasUsableStoredLicense(
            licenseKey: licenseManager.licenseKey,
            activationId: licenseManager.activationId
        ) {
            return "Licensed (Pro)"
        }

        return "Not Licensed"
    }

}
