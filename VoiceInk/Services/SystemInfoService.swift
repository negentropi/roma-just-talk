import Foundation
import AppKit
import AVFoundation
import VoiceInkCore

class SystemInfoService {
    static let shared = SystemInfoService()

    private init() {}

    func getSystemInfoString() -> String {
        let transcriptionCleanup = VoiceInkTranscriptionAutoCleanupPreference.current()
        let audioCleanup = VoiceInkAudioCleanupPreference.current()
        let info = """
        === VOICEINK SYSTEM INFORMATION ===
        Generated: \(Date().formatted(date: .long, time: .standard))

        APP INFORMATION:
        App Version: \(getAppVersion())
        Build Version: \(getBuildVersion())
        License Status: \(getLicenseStatus())

        OPERATING SYSTEM:
        macOS Version: \(ProcessInfo.processInfo.operatingSystemVersionString)

        HARDWARE INFORMATION:
        Device Model: \(getMacModel())
        CPU: \(getCPUInfo())
        Memory: \(getMemoryInfo())
        Architecture: \(getArchitecture())

        AUDIO SETTINGS:
        Input Mode: \(getAudioInputMode())
        Current Audio Device: \(getCurrentAudioDevice())
        Available Audio Devices: \(getAvailableAudioDevices())

        HOTKEY SETTINGS:
        Primary Shortcut: \(getPrimaryShortcut())
        Secondary Shortcut: \(getSecondaryShortcut())
        Middle-Click Recording: \(VoiceInkRecordingShortcutPreference.isMiddleClickToggleEnabled())
        Middle-Click Activation Delay: \(VoiceInkRecordingShortcutPreference.middleClickActivationDelay()) ms

        TRANSCRIPTION SETTINGS:
        Selected Model: \(getCurrentTranscriptionModel())
        Selected Language: \(getCurrentLanguage())
        AI Enhancement: \(VoiceInkAIEnhancementPreference.statusDiagnosticDescription())
        AI Provider: \(VoiceInkAIEnhancementProviderPreference.selectedProviderDiagnosticDescription())
        AI Model: \(VoiceInkAIEnhancementProviderPreference.selectedModelDiagnosticDescription())

        ROLLING BUFFER PRELOAD:
        \(getRollingBufferPreloadInfo())

        UI SETTINGS:
        Hide Dock Icon: \(UserDefaults.standard.bool(forKey: "IsMenuBarOnly"))
        Recorder Style: \(VoiceInkRecorderStylePreference.rawValue())

        RECORDING FEEDBACK:
        Sound Feedback: \(VoiceInkRecordingFeedbackPreference.isSoundFeedbackEnabled())
        Pause Media While Recording: \(VoiceInkRecordingFeedbackPreference.isPauseMediaEnabled())
        Mute Audio While Recording: \(VoiceInkRecordingFeedbackPreference.systemMuteMode().rawValue)
        Audio Resumption Delay: \(VoiceInkRecordingFeedbackPreference.audioResumptionDelay())s

        CLIPBOARD & PASTE SETTINGS:
        Restore Clipboard After Paste: \(VoiceInkPastePreference.shouldRestoreClipboardAfterPaste())
        Clipboard Restore Delay: \(VoiceInkPastePreference.clipboardRestoreDelay())s
        Paste Method: \(VoiceInkPasteMethod.current().displayName)

        POWER MODE:
        Power Mode Enabled: \(VoiceInkPowerModePreference.isUIEnabled())
        Persist Configured Preferences: \(VoiceInkPowerModePreference.shouldPersistConfiguredPreferences())

        DATA CLEANUP SETTINGS:
        Auto-Delete Transcriptions: \(transcriptionCleanup.isEnabled)
        Transcription Retention: \(transcriptionCleanup.retentionMinutes) minutes
        Auto-Delete Audio Files: \(audioCleanup.isEnabled)
        Audio Retention Period: \(audioCleanup.retentionDays) days

        PERMISSIONS:
        Accessibility: \(getAccessibilityStatus())
        Input Monitoring: \(getInputMonitoringStatus())
        Screen Recording: \(getScreenRecordingStatus())
        Microphone: \(getMicrophoneStatus())
        """

        return info
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
        return ByteCountFormatter.string(fromByteCount: Int64(totalMemory), countStyle: .memory)
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
        if licenseManager.licenseKey != nil {
            if licenseManager.activationId != nil || !UserDefaults.standard.bool(forKey: "VoiceInkLicenseRequiresActivation") {
                return "Licensed (Pro)"
            }
        }

        return "Not Licensed"
    }

    private func getCurrentLanguage() -> String {
        return VoiceInkTranscriptionLanguagePreference.selectedMacOSLanguage()
    }

}
