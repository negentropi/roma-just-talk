import Foundation
@testable import VoiceInkCore

final class SystemInformationReportTests: XCTestCase {
    func testMacOSSystemInformationReportPreservesSectionOrderAndLabels() {
        let report = VoiceInkSystemInformationReport.macOS(Self.sampleFacts)

        XCTAssertEqual(
            report,
            """
            === VOICEINK SYSTEM INFORMATION ===
            Generated: June 24, 2026 at 3:42:11 PM

            APP INFORMATION:
            App Version: 1.2.3
            Build Version: 456
            License Status: Licensed (Pro)

            OPERATING SYSTEM:
            macOS Version: Version 26.0

            HARDWARE INFORMATION:
            Device Model: Mac16,1
            CPU: Apple M4 Pro
            Memory: 48 GB
            Architecture: arm64

            AUDIO SETTINGS:
            Input Mode: automatic
            Current Audio Device: Studio Display Microphone
            Available Audio Devices: Built-in Microphone, Studio Display Microphone

            HOTKEY SETTINGS:
            Primary Shortcut: Control Space
            Secondary Shortcut: Option Space
            Middle-Click Recording: true
            Middle-Click Activation Delay: 300 ms

            TRANSCRIPTION SETTINGS:
            Selected Model: Parakeet V3
            Selected Language: en
            AI Enhancement: Enabled
            AI Provider: OpenAI
            AI Model: gpt-5-mini

            ROLLING BUFFER PRELOAD:
            Mode: Smart
            Pre-run Finalization: true
            Buffer Duration: 8.0s
            Last Quick Release Claim: none

            UI SETTINGS:
            Hide Dock Icon: false
            Recorder Style: notch

            RECORDING FEEDBACK:
            Sound Feedback: true
            Pause Media While Recording: false
            Mute Audio While Recording: smart
            Audio Resumption Delay: 1.25s

            CLIPBOARD & PASTE SETTINGS:
            Restore Clipboard After Paste: true
            Clipboard Restore Delay: 0.5s
            Paste Method: Standard

            POWER MODE:
            Power Mode Enabled: true
            Persist Configured Preferences: false

            DATA CLEANUP SETTINGS:
            Auto-Delete Transcriptions: false
            Transcription Retention: 60 minutes
            Auto-Delete Audio Files: true
            Audio Retention Period: 7 days

            PERMISSIONS:
            Accessibility: Granted
            Input Monitoring: Not Granted
            Screen Recording: Granted
            Microphone: Denied
            """
        )
    }

    func testMacOSSystemInformationReportKeepsRollingBufferBlockVerbatim() {
        let facts = VoiceInkMacOSSystemInformationFacts(
            generated: "now",
            appVersion: "app",
            buildVersion: "build",
            licenseStatus: "license",
            operatingSystemVersion: "os",
            deviceModel: "model",
            cpu: "cpu",
            memory: "memory",
            architecture: "arch",
            audioInputMode: "mode",
            currentAudioDevice: "current",
            availableAudioDevices: "available",
            primaryShortcut: "",
            secondaryShortcut: "",
            middleClickRecording: false,
            middleClickActivationDelayMilliseconds: 0,
            selectedModel: "selected",
            selectedLanguage: "auto",
            aiEnhancement: "disabled",
            aiProvider: "none",
            aiModel: "none",
            rollingBufferPreload: "line one\nline two",
            hideDockIcon: true,
            recorderStyle: "mini",
            soundFeedback: false,
            pauseMediaWhileRecording: true,
            muteAudioWhileRecording: "off",
            audioResumptionDelaySeconds: 0,
            restoreClipboardAfterPaste: false,
            clipboardRestoreDelaySeconds: 0,
            pasteMethod: "Direct",
            powerModeEnabled: false,
            persistConfiguredPreferences: true,
            autoDeleteTranscriptions: true,
            transcriptionRetentionMinutes: 10,
            autoDeleteAudioFiles: false,
            audioRetentionPeriodDays: 1,
            accessibilityPermission: "Unknown",
            inputMonitoringPermission: "Unknown",
            screenRecordingPermission: "Unknown",
            microphonePermission: "Unknown"
        )

        XCTAssertTrue(VoiceInkSystemInformationReport.macOS(facts).contains("ROLLING BUFFER PRELOAD:\nline one\nline two\n\nUI SETTINGS:"))
    }

    func testAvailableAudioDevicesTextPreservesMacOSDiagnosticsListPolicy() {
        XCTAssertEqual(
            VoiceInkSystemInformationReport.availableAudioDevicesText([
                "Built-in Microphone",
                "Studio Display Microphone"
            ]),
            "Built-in Microphone, Studio Display Microphone"
        )
        XCTAssertEqual(
            VoiceInkSystemInformationReport.availableAudioDevicesText([]),
            "None detected"
        )
    }

    func testGeneratedDateTextPreservesMacOSFormattingStyle() {
        let generatedAt = Date(timeIntervalSince1970: 1_782_315_731)

        XCTAssertEqual(
            VoiceInkSystemInformationReport.generatedDateText(generatedAt),
            generatedAt.formatted(date: .long, time: .standard)
        )
    }

    func testSystemInformationCopyPresentationPreservesDashboardButtonPolicy() {
        XCTAssertEqual(
            VoiceInkSystemInformationCopyPresentation.button(isCopied: false),
            VoiceInkSystemInformationCopyButtonPresentation(
                systemImageName: "doc.on.doc",
                title: "Copy System Info"
            )
        )
        XCTAssertEqual(
            VoiceInkSystemInformationCopyPresentation.button(isCopied: true),
            VoiceInkSystemInformationCopyButtonPresentation(
                systemImageName: "checkmark",
                title: "Copied!"
            )
        )
        XCTAssertEqual(VoiceInkSystemInformationCopyPresentation.copiedResetDelay, 1.5)
    }

    private static var sampleFacts: VoiceInkMacOSSystemInformationFacts {
        VoiceInkMacOSSystemInformationFacts(
            generated: "June 24, 2026 at 3:42:11 PM",
            appVersion: "1.2.3",
            buildVersion: "456",
            licenseStatus: "Licensed (Pro)",
            operatingSystemVersion: "Version 26.0",
            deviceModel: "Mac16,1",
            cpu: "Apple M4 Pro",
            memory: "48 GB",
            architecture: "arm64",
            audioInputMode: "automatic",
            currentAudioDevice: "Studio Display Microphone",
            availableAudioDevices: "Built-in Microphone, Studio Display Microphone",
            primaryShortcut: "Control Space",
            secondaryShortcut: "Option Space",
            middleClickRecording: true,
            middleClickActivationDelayMilliseconds: 300,
            selectedModel: "Parakeet V3",
            selectedLanguage: "en",
            aiEnhancement: "Enabled",
            aiProvider: "OpenAI",
            aiModel: "gpt-5-mini",
            rollingBufferPreload: """
            Mode: Smart
            Pre-run Finalization: true
            Buffer Duration: 8.0s
            Last Quick Release Claim: none
            """,
            hideDockIcon: false,
            recorderStyle: "notch",
            soundFeedback: true,
            pauseMediaWhileRecording: false,
            muteAudioWhileRecording: "smart",
            audioResumptionDelaySeconds: 1.25,
            restoreClipboardAfterPaste: true,
            clipboardRestoreDelaySeconds: 0.5,
            pasteMethod: "Standard",
            powerModeEnabled: true,
            persistConfiguredPreferences: false,
            autoDeleteTranscriptions: false,
            transcriptionRetentionMinutes: 60,
            autoDeleteAudioFiles: true,
            audioRetentionPeriodDays: 7,
            accessibilityPermission: "Granted",
            inputMonitoringPermission: "Not Granted",
            screenRecordingPermission: "Granted",
            microphonePermission: "Denied"
        )
    }
}
