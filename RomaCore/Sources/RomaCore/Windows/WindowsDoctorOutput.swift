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

    public static var proofAgentSourceProofLines: [String] {
        [
            "windows_register_hotkey_adapter_source=true",
            "windows_low_level_keyboard_hook_source=true",
            "windows_paste_adapter_source=true",
            "windows_permission_surface_source=true",
            "windows_dpapi_secret_store_source=true",
            "miniaudio_capture_adapter_source=true",
            "openai_compatible_transcription_source=true",
            "whisper_cli_transcription_source=true",
            "roma_transcription_client_source=true",
            "transcription_output_filter_source=true",
            "word_replacement_processor_source=true",
            "windows_dictation_runtime_source=true",
            "windows_dictation_runtime_uses_pipeline_source=true",
            "windows_listener_output_isolation_source=true",
            "windows_listener_pre_roll_runtime_source=true",
            "windows_hold_hook_single_window_source=true",
            "windows_dictation_proof_source=true",
            "windows_proof_args_shared_source=true"
        ]
    }
}
