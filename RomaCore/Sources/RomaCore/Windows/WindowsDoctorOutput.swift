import Foundation

public enum WindowsDoctorOutput {
    public static var runtimeDefaultProofLines: [String] {
        [
            "default_record_seconds=\(RomaWindowsAgentConfiguration.defaultRecordSeconds)",
            "default_hold_timeout_seconds=\(RomaWindowsAgentConfiguration.defaultHoldTimeoutSeconds)",
            "default_hold_timeout_milliseconds=\(RomaWindowsAgentConfiguration.defaultHoldTimeoutMilliseconds)",
            "default_clipboard_restore_delay_seconds=\(WindowsClipboardRestoreConfiguration.defaultRestoreDelaySeconds)",
            "maximum_clipboard_restore_delay_seconds=\(WindowsClipboardRestoreConfiguration.maximumRestoreDelaySeconds)"
        ]
    }

    public static var holdTimeoutProofLines: [String] {
        [
            "default_timeout_seconds=\(RomaWindowsAgentConfiguration.defaultHoldTimeoutSeconds)",
            "default_timeout_milliseconds=\(RomaWindowsAgentConfiguration.defaultHoldTimeoutMilliseconds)"
        ]
    }

    public static var clipboardRestoreProofLines: [String] {
        [
            "default_clipboard_restore_delay_seconds=\(WindowsClipboardRestoreConfiguration.defaultRestoreDelaySeconds)",
            "maximum_clipboard_restore_delay_seconds=\(WindowsClipboardRestoreConfiguration.maximumRestoreDelaySeconds)"
        ]
    }
}
