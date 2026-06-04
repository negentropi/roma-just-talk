$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Invoke-RomaWindowsProofStep {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [scriptblock]$Command
    )

    Write-Host ""
    Write-Host "== $Name =="
    & $Command
}

function Resolve-RomaWindowsFullPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
}

function Require-RomaWindowsFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (!(Test-Path -LiteralPath $Path)) {
        throw "Required file was not found: $Path"
    }
}

function Get-RomaWindowsCurrentUserSid {
    if ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
        return ""
    }

    try {
        $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        if ($null -ne $identity -and $null -ne $identity.User) {
            return [string]$identity.User.Value
        }
    } catch {
        return ""
    }

    return ""
}

function Require-RomaWindowsCurrentUserSid {
    $userSid = Get-RomaWindowsCurrentUserSid
    if ([string]::IsNullOrWhiteSpace($userSid)) {
        throw "Current Windows user SID was not available"
    }

    return $userSid
}

function Get-RomaWindowsProofSurfaceFiles {
    return @(
        "smoke-windows-agent.ps1",
        "run-windows-agent.ps1",
        "install-windows-agent.ps1",
        "prove-windows-agent-artifact.ps1",
        "run-windows-laptop-proof.ps1",
        "WINDOWS-LAPTOP-PROOF.txt",
        "check-windows-scripts-parse.ps1",
        "check-windows-proof-report.ps1",
        "check-windows-proof-set.ps1",
        "windows-proof-common.ps1",
        "windows-manifest.ps1",
        "windows-package-identity.ps1"
    )
}

function Get-RomaWindowsProofSurfaceScriptCount {
    return @(
        Get-RomaWindowsProofSurfaceFiles |
            Where-Object { [string]$_ -like "*.ps1" }
    ).Count
}

function Get-RomaWindowsInstalledProofSurfaceFileMap {
    return @(
        @{ ReportProperty = "installed_smoke_script"; PackageFile = "smoke-windows-agent.ps1" },
        @{ ReportProperty = "installed_run_script"; PackageFile = "run-windows-agent.ps1" },
        @{ ReportProperty = "installed_install_script"; PackageFile = "install-windows-agent.ps1" },
        @{ ReportProperty = "installed_proof_script"; PackageFile = "prove-windows-agent-artifact.ps1" },
        @{ ReportProperty = "installed_laptop_proof_script"; PackageFile = "run-windows-laptop-proof.ps1" },
        @{ ReportProperty = "installed_laptop_proof_guide"; PackageFile = "WINDOWS-LAPTOP-PROOF.txt" },
        @{ ReportProperty = "installed_parse_script"; PackageFile = "check-windows-scripts-parse.ps1" },
        @{ ReportProperty = "installed_proof_common_script"; PackageFile = "windows-proof-common.ps1" },
        @{ ReportProperty = "installed_manifest_script"; PackageFile = "windows-manifest.ps1" },
        @{ ReportProperty = "installed_package_identity_script"; PackageFile = "windows-package-identity.ps1" },
        @{ ReportProperty = "installed_check_report_script"; PackageFile = "check-windows-proof-report.ps1" },
        @{ ReportProperty = "installed_check_set_script"; PackageFile = "check-windows-proof-set.ps1" }
    )
}

function Get-RomaWindowsInstalledProofSurfaceScriptCount {
    return @(
        Get-RomaWindowsInstalledProofSurfaceFileMap |
            Where-Object { [string]$_.PackageFile -like "*.ps1" }
    ).Count
}

function Assert-RomaWindowsOutputContains {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Output,
        [Parameter(Mandatory = $true)]
        [string]$Expected
    )

    if (!$Output.Contains($Expected)) {
        throw "Expected command output to contain '$Expected'"
    }

    Write-Host "asserted_output=$Expected"
}

function Get-RomaWindowsScriptParseCount {
    param(
        [string]$Output = ""
    )

    $match = [regex]::Match($Output, "(?m)^windows_scripts_parse_count=(\d+)\s*$")
    if (!$match.Success) {
        return $null
    }

    return [int]::Parse(
        $match.Groups[1].Value,
        [System.Globalization.CultureInfo]::InvariantCulture
    )
}

function Assert-RomaWindowsScriptParseCount {
    param(
        [string]$Output = "",
        [Parameter(Mandatory = $true)]
        [int]$ExpectedCount,
        [string]$Name = "scripts"
    )

    Assert-RomaWindowsOutputContains -Output $Output -Expected "windows_scripts_parse_ok=true"
    $actualCount = Get-RomaWindowsScriptParseCount -Output $Output
    if ($null -eq $actualCount) {
        throw "Windows script parse count was not found for $Name"
    }
    if ($actualCount -ne $ExpectedCount) {
        throw "Expected $Name script parse count to be $ExpectedCount, got $actualCount"
    }

    Write-Host "asserted_script_parse_count=$Name count=$actualCount expected=$ExpectedCount"
}

function Get-RomaWindowsRuntimeDefaultOutputMarkers {
    return [ordered]@{
        default_record_seconds = "default_record_seconds=2.0"
        default_hold_timeout_seconds = "default_hold_timeout_seconds=15.0"
        default_hold_timeout_milliseconds = "default_hold_timeout_milliseconds=15000"
        default_clipboard_restore_delay_seconds = "default_clipboard_restore_delay_seconds=2.0"
        maximum_clipboard_restore_delay_seconds = "maximum_clipboard_restore_delay_seconds=4294967.295"
    }
}

function Get-RomaWindowsHoldTimeoutDefaultOutputMarkers {
    return [ordered]@{
        default_hold_timeout_seconds = "default_timeout_seconds=15.0"
        default_hold_timeout_milliseconds = "default_timeout_milliseconds=15000"
    }
}

function Get-RomaWindowsClipboardRestoreDefaultOutputMarkers {
    return [ordered]@{
        default_clipboard_restore_delay_seconds = "default_clipboard_restore_delay_seconds=2.0"
        maximum_clipboard_restore_delay_seconds = "maximum_clipboard_restore_delay_seconds=4294967.295"
    }
}

function Get-RomaWindowsMinimumPermissionOutputMarkers {
    return [ordered]@{
        os_permission_grants_microphone = "os_permission_grants=microphone"
        native_capabilities_register_hotkey = "native_capabilities=RegisterHotKey"
        microphone_settings_uri = "microphone_settings_uri=ms-settings:privacy-microphone"
        desktop_app_microphone_access_required = "desktop_app_microphone_access_required=true"
        no_accessibility_permission_prompt = "accessibility_permission_prompt=false"
        no_automation_permission_prompt = "automation_permission_prompt=false"
        no_admin_required = "admin_required=false"
        startup_launcher_run_script = "startup_launcher=run-windows-agent.ps1"
        startup_launch_mode_listen = "startup_launch_mode=listen"
        no_startup_permission_prompt = "startup_permission_prompt=false"
        no_screen_capture_required = "screen_capture_required=false"
        no_screen_recording_permission_prompt = "screen_recording_permission_prompt=false"
    }
}

function Get-RomaWindowsProofAgentSourceOutputMarkers {
    return [ordered]@{
        windows_register_hotkey_adapter_source = "windows_register_hotkey_adapter_source=true"
        windows_low_level_keyboard_hook_source = "windows_low_level_keyboard_hook_source=true"
        windows_paste_adapter_source = "windows_paste_adapter_source=true"
        windows_permission_surface_source = "windows_permission_surface_source=true"
        windows_dpapi_secret_store_source = "windows_dpapi_secret_store_source=true"
        miniaudio_capture_adapter_source = "miniaudio_capture_adapter_source=true"
        openai_compatible_transcription_source = "openai_compatible_transcription_source=true"
        whisper_cli_transcription_source = "whisper_cli_transcription_source=true"
        roma_transcription_client_source = "roma_transcription_client_source=true"
        transcription_output_filter_source = "transcription_output_filter_source=true"
        word_replacement_processor_source = "word_replacement_processor_source=true"
        windows_dictation_runtime_source = "windows_dictation_runtime_source=true"
        windows_dictation_runtime_uses_pipeline_source = "windows_dictation_runtime_uses_pipeline_source=true"
        windows_listener_output_isolation_source = "windows_listener_output_isolation_source=true"
        windows_listener_pre_roll_runtime_source = "windows_listener_pre_roll_runtime_source=true"
        windows_hold_hook_single_window_source = "windows_hold_hook_single_window_source=true"
        windows_dictation_proof_source = "windows_dictation_proof_source=true"
        windows_proof_args_shared_source = "windows_proof_args_shared_source=true"
    }
}

function Get-RomaWindowsNativeDoctorSpecs {
    return [ordered]@{
        register_hotkey = [ordered]@{
            label = "register hotkey"
            command = "windows-hotkey-doctor"
            expected_marker = "windows_hotkey_runtime=true"
        }
        register_hotkey_available = [ordered]@{
            label = "register hotkey availability"
            command = "windows-hotkey-availability-proof"
            expected_marker = "hotkey_registration_available=true"
        }
        keyboard_hook = [ordered]@{
            label = "keyboard hook"
            command = "windows-keyboard-hook-doctor"
            expected_marker = "runtime=true"
        }
        paste = [ordered]@{
            label = "paste"
            command = "windows-paste-doctor"
            expected_marker = "windows_paste_runtime=true"
        }
        dpapi_secret = [ordered]@{
            label = "dpapi secret"
            command = "windows-secret-doctor"
            expected_marker = "dpapi_runtime=true"
        }
        miniaudio_capture = [ordered]@{
            label = "miniaudio capture"
            command = "miniaudio-capture-doctor"
            expected_marker = "native_capture_adapter=true"
        }
    }
}

function Get-RomaWindowsNativeDoctorSpec {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $specs = Get-RomaWindowsNativeDoctorSpecs
    if (!$specs.Contains($Name)) {
        throw "Unknown Windows native doctor proof name: $Name"
    }
    return $specs[$Name]
}

function Get-RomaWindowsNativeDoctorExpectedMarkers {
    $markers = [ordered]@{}
    $specs = Get-RomaWindowsNativeDoctorSpecs
    foreach ($name in $specs.Keys) {
        $markers[$name] = [string]$specs[$name]["expected_marker"]
    }
    return $markers
}

function Get-RomaWindowsNativeDoctorExpectedMarker {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $spec = Get-RomaWindowsNativeDoctorSpec -Name $Name
    return [string]$spec["expected_marker"]
}

function New-RomaWindowsNativeDoctorOutputTable {
    $outputs = [ordered]@{}
    $specs = Get-RomaWindowsNativeDoctorSpecs
    foreach ($name in $specs.Keys) {
        $outputs[$name] = ""
    }
    return $outputs
}

function Get-RomaWindowsLaptopPreflightGuideMarkers {
    return [ordered]@{
        laptop_preflight_proof_set = "proof_set_ok=laptop-preflight"
        laptop_preflight_ok = "windows_laptop_preflight_ok=true"
        laptop_preflight_report = "windows_laptop_preflight_report=C:\tmp\roma-windows-laptop-proof\preflight-proof.json"
        package_fingerprint = "proof_set_laptop_preflight_package_fingerprint="
        source_dirty = "proof_set_laptop_preflight_source_dirty=false"
        permission_surface = "proof_set_laptop_preflight_permission_surface=true"
        local_whisper_disabled = "proof_set_laptop_preflight_local_whisper=False"
        microphone_duration = "microphone_preflight_duration_seconds="
        microphone_pre_roll = "microphone_preflight_included_pre_roll_seconds="
        positive_pre_roll = "proof_bool=reported_positive_pre_roll value=True"
        included_pre_roll_seconds = "proof_number=included_pre_roll_seconds value="
        laptop_preflight_profile = "proof_profile_ok=laptop-preflight"
    }
}

function Get-RomaWindowsLaptopPreflightLocalWhisperGuideMarkers {
    return [ordered]@{
        local_whisper_enabled = "proof_set_laptop_preflight_local_whisper=True"
    }
}

function Get-RomaWindowsFullLaptopProofSetOutputMarkers {
    return [ordered]@{
        laptop_preflight_profile = "proof_profile_ok=laptop-preflight"
        cloud_dictation_profile = "proof_profile_ok=cloud-dictation"
        local_whisper_dictation_profile = "proof_profile_ok=local-whisper-dictation"
        local_whisper_notepad_paste_profile = "proof_profile_ok=local-whisper-notepad-paste"
        full_laptop_proof_set = "proof_set_ok=full-laptop"
    }
}

function Get-RomaWindowsFullLaptopProofGuideMarkers {
    $markers = [ordered]@{
        laptop_preflight_matches_full = "proof_set_laptop_preflight_matches_full=true"
        generated_at_window_minutes = "proof_set_generated_at_window_minutes="
    }

    $proofSetMarkers = Get-RomaWindowsFullLaptopProofSetOutputMarkers
    foreach ($key in $proofSetMarkers.Keys) {
        $markers[$key] = $proofSetMarkers[$key]
    }

    $markers["listener_runtime"] = "proof_listener_runtime=installed_listener"
    $markers["listen_completed_sessions"] = "listen_completed_sessions=1"
    $markers["source_dirty"] = "proof_set_source_dirty=false"
    $markers["recheck_script"] = "windows_laptop_recheck_script=C:\tmp\roma-windows-laptop-proof\recheck-full-laptop-proof.ps1"
    $markers["proof_ok"] = "windows_laptop_proof_ok=true"
    return $markers
}

function Assert-RomaWindowsOutputMarkers {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Output,
        [Parameter(Mandatory = $true)]
        [object]$Markers
    )

    foreach ($key in $Markers.Keys) {
        Assert-RomaWindowsOutputContains -Output $Output -Expected $Markers[$key]
    }
}

function Assert-RomaWindowsProofAgentSourceOutput {
    param(
        [string]$Output = ""
    )

    Assert-RomaWindowsOutputMarkers `
        -Output $Output `
        -Markers (Get-RomaWindowsProofAgentSourceOutputMarkers)
}

function Assert-RomaWindowsNativeDoctorOutput {
    param(
        [string]$Output = "",
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    Assert-RomaWindowsOutputContains `
        -Output $Output `
        -Expected (Get-RomaWindowsNativeDoctorExpectedMarker -Name $Name)

    if ($Name -eq "keyboard_hook") {
        Assert-RomaWindowsHoldTimeoutDefaultOutput -Output $Output
    }
    if ($Name -eq "paste") {
        Assert-RomaWindowsClipboardRestoreDefaultOutput -Output $Output
    }
}

function Get-RomaWindowsLaptopPreflightCommonOutputMarkers {
    param(
        [bool]$ExpectLocalWhisper = $true
    )

    return [ordered]@{
        permission_surface = "proof_set_laptop_preflight_permission_surface=true"
        local_whisper = "proof_set_laptop_preflight_local_whisper=$($ExpectLocalWhisper.ToString())"
        source_dirty = "proof_set_laptop_preflight_source_dirty=false"
    }
}

function Assert-RomaWindowsLaptopPreflightProfileOutput {
    param(
        [string]$Output = "",
        [bool]$ExpectLocalWhisper = $true
    )

    $markers = [ordered]@{
        profile = "proof_profile_ok=laptop-preflight"
        report_ok = "proof_report_ok="
    }

    $commonMarkers = Get-RomaWindowsLaptopPreflightCommonOutputMarkers -ExpectLocalWhisper $ExpectLocalWhisper
    foreach ($key in $commonMarkers.Keys) {
        $markers[$key] = $commonMarkers[$key]
    }

    Assert-RomaWindowsOutputMarkers -Output $Output -Markers $markers
}

function Assert-RomaWindowsLaptopPreflightSetOutput {
    param(
        [string]$Output = "",
        [bool]$ExpectLocalWhisper = $true
    )

    $markers = Get-RomaWindowsLaptopPreflightCommonOutputMarkers -ExpectLocalWhisper $ExpectLocalWhisper
    $markers["profile"] = "proof_profile_ok=laptop-preflight"
    $markers["proof_set"] = "proof_set_ok=laptop-preflight"

    Assert-RomaWindowsOutputMarkers -Output $Output -Markers $markers
}

function Assert-RomaWindowsFullLaptopProofSetOutput {
    param(
        [string]$Output = ""
    )

    Assert-RomaWindowsOutputMarkers `
        -Output $Output `
        -Markers (Get-RomaWindowsFullLaptopProofSetOutputMarkers)
}

function Get-RomaWindowsOutputMarkerProof {
    param(
        [string]$Output = "",
        [Parameter(Mandatory = $true)]
        [object]$Markers
    )

    $proof = [ordered]@{}
    foreach ($key in $Markers.Keys) {
        $proof[$key] = $Output.Contains($Markers[$key])
    }
    return $proof
}

function Get-RomaWindowsProofAgentSourceOutputProof {
    param(
        [string]$Output = ""
    )

    return Get-RomaWindowsOutputMarkerProof `
        -Output $Output `
        -Markers (Get-RomaWindowsProofAgentSourceOutputMarkers)
}

function Get-RomaWindowsNativeDoctorOutputProof {
    param(
        [string]$Output = "",
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $expectedMarker = Get-RomaWindowsNativeDoctorExpectedMarker -Name $Name
    $proof = [ordered]@{
        output_present = ![string]::IsNullOrWhiteSpace($Output)
        platform_windows = $Output.Contains("platform=windows")
        expected_marker = $expectedMarker
        expected_marker_present = $Output.Contains($expectedMarker)
        register_hotkey_available = $Output.Contains((Get-RomaWindowsNativeDoctorExpectedMarker -Name "register_hotkey_available"))
    }
    Add-RomaWindowsProofFields -Proof $proof -Fields (Get-RomaWindowsHoldTimeoutDefaultOutputProof -Output $Output) | Out-Null
    Add-RomaWindowsProofFields -Proof $proof -Fields (Get-RomaWindowsClipboardRestoreDefaultOutputProof -Output $Output) | Out-Null
    return $proof
}

function Get-RomaWindowsNativeDoctorOutputProofs {
    param(
        [object]$Outputs
    )

    $proofs = [ordered]@{}
    $specs = Get-RomaWindowsNativeDoctorSpecs
    foreach ($name in $specs.Keys) {
        $output = ""
        if ($null -ne $Outputs -and $Outputs.Contains($name)) {
            $output = $Outputs[$name]
        }
        $proofs[$name] = Get-RomaWindowsNativeDoctorOutputProof -Output $output -Name $name
    }
    return $proofs
}

function Get-RomaWindowsOutputValue {
    param(
        [Alias("Content")]
        [Parameter(Mandatory = $true)]
        [string]$Output,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $escapedName = [regex]::Escape($Name)
    $match = [regex]::Match($Output, "(?m)^$escapedName=(.+?)\s*$")
    if (!$match.Success) {
        return ""
    }

    return $match.Groups[1].Value
}

function Get-RomaWindowsOutputNumber {
    param(
        [Alias("Content")]
        [Parameter(Mandatory = $true)]
        [string]$Output,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $escapedName = [regex]::Escape($Name)
    $match = [regex]::Match($Output, "(?m)^$escapedName=([+-]?\d+(?:\.\d+)?)\s*$")
    if (!$match.Success) {
        return $null
    }

    return [double]::Parse(
        $match.Groups[1].Value,
        [System.Globalization.CultureInfo]::InvariantCulture
    )
}

function Get-RomaWindowsOutputLineNumber {
    param(
        [Alias("Content")]
        [Parameter(Mandatory = $true)]
        [string]$Output,
        [Parameter(Mandatory = $true)]
        [string]$Needle
    )

    $lines = $Output -split "\r?\n"
    for ($index = 0; $index -lt $lines.Count; $index += 1) {
        if ($lines[$index].Contains($Needle)) {
            return $index + 1
        }
    }

    return 0
}

function Add-RomaWindowsProofFields {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Proof,
        [Parameter(Mandatory = $true)]
        [object]$Fields
    )

    foreach ($key in $Fields.Keys) {
        $Proof[$key] = $Fields[$key]
    }
    return $Proof
}

function Assert-RomaWindowsRuntimeDefaultOutput {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Output
    )

    Assert-RomaWindowsOutputMarkers -Output $Output -Markers (Get-RomaWindowsRuntimeDefaultOutputMarkers)
}

function Assert-RomaWindowsHoldTimeoutDefaultOutput {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Output
    )

    Assert-RomaWindowsOutputMarkers -Output $Output -Markers (Get-RomaWindowsHoldTimeoutDefaultOutputMarkers)
}

function Assert-RomaWindowsClipboardRestoreDefaultOutput {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Output
    )

    Assert-RomaWindowsOutputMarkers -Output $Output -Markers (Get-RomaWindowsClipboardRestoreDefaultOutputMarkers)
}

function Assert-RomaWindowsMinimumPermissionOutput {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Output
    )

    Assert-RomaWindowsOutputMarkers -Output $Output -Markers (Get-RomaWindowsMinimumPermissionOutputMarkers)
}

function Assert-RomaWindowsAgentScriptCommonOptions {
    param(
        [bool]$UseHoldHook = $false,
        [bool]$UseToggle = $false,
        [bool]$PasteDictation = $false,
        [bool]$NoPaste = $false,
        [bool]$RestoreClipboard = $false,
        [bool]$NoRestoreClipboard = $false,
        [bool]$HasClipboardRestoreDelay = $false,
        [double]$ClipboardRestoreDelaySeconds = 2
    )

    if ($UseHoldHook -and $UseToggle) {
        throw "UseHoldHook and UseToggle are mutually exclusive"
    }

    if ($PasteDictation -and $NoPaste) {
        throw "PasteDictation and NoPaste are mutually exclusive"
    }

    if ($RestoreClipboard -and $NoRestoreClipboard) {
        throw "RestoreClipboard and NoRestoreClipboard are mutually exclusive"
    }

    if ($NoRestoreClipboard -and $HasClipboardRestoreDelay) {
        throw "NoRestoreClipboard and ClipboardRestoreDelaySeconds are mutually exclusive"
    }

    if ($ClipboardRestoreDelaySeconds -lt 0) {
        throw "ClipboardRestoreDelaySeconds must be non-negative"
    }
}

function Get-RomaWindowsRuntimeDefaultOutputProof {
    param(
        [string]$Output = ""
    )

    return Get-RomaWindowsOutputMarkerProof -Output $Output -Markers (Get-RomaWindowsRuntimeDefaultOutputMarkers)
}

function Get-RomaWindowsHoldTimeoutDefaultOutputProof {
    param(
        [string]$Output = ""
    )

    return Get-RomaWindowsOutputMarkerProof -Output $Output -Markers (Get-RomaWindowsHoldTimeoutDefaultOutputMarkers)
}

function Get-RomaWindowsClipboardRestoreDefaultOutputProof {
    param(
        [string]$Output = ""
    )

    return Get-RomaWindowsOutputMarkerProof -Output $Output -Markers (Get-RomaWindowsClipboardRestoreDefaultOutputMarkers)
}

function Get-RomaWindowsMinimumPermissionOutputProof {
    param(
        [string]$Output = ""
    )

    return Get-RomaWindowsOutputMarkerProof -Output $Output -Markers (Get-RomaWindowsMinimumPermissionOutputMarkers)
}

function Add-RomaWindowsAgentConfigurationArgs {
    param(
        [string[]]$Arguments = @(),
        [bool]$UseWhisperCLI = $false,
        [string]$WhisperCLI = "",
        [string]$WhisperModel = "",
        [string]$WhisperOutputDir = "",
        [string[]]$WhisperArgument = @(),
        [string]$Endpoint = "",
        [string]$Model = "",
        [bool]$UseHoldHook = $true,
        [double]$HoldTimeoutSeconds = 15,
        [double]$RecordSeconds = 2,
        [string]$ApiKeyName = "",
        [string]$ApiKeyEnv = "",
        [string]$SecretDir = "",
        [string]$Language = "",
        [string]$Prompt = "",
        [string[]]$WordReplacement = @(),
        [bool]$PasteDictation = $false,
        [bool]$NoPaste = $false,
        [bool]$RestoreClipboard = $false,
        [bool]$NoRestoreClipboard = $false,
        [bool]$HasClipboardRestoreDelay = $false,
        [double]$ClipboardRestoreDelaySeconds = 2
    )

    $configArgs = @($Arguments)
    if ($UseWhisperCLI) {
        $configArgs += @("--whisper-cli", $WhisperCLI, "--whisper-model", $WhisperModel)
        if (![string]::IsNullOrWhiteSpace($WhisperOutputDir)) {
            $configArgs += @("--whisper-output-dir", $WhisperOutputDir)
        }
        foreach ($argument in $WhisperArgument) {
            if (![string]::IsNullOrWhiteSpace($argument)) {
                $configArgs += @("--whisper-arg", $argument)
            }
        }
    } else {
        $configArgs += @("--endpoint", $Endpoint, "--model", $Model)
        if (![string]::IsNullOrWhiteSpace($ApiKeyName)) {
            $configArgs += @("--api-key-name", $ApiKeyName, "--secret-dir", $SecretDir)
        } elseif (![string]::IsNullOrWhiteSpace($ApiKeyEnv)) {
            $configArgs += @("--api-key-env", $ApiKeyEnv)
        }
    }

    if ($UseHoldHook) {
        $configArgs += @("--hold-hook", "--timeout", "$HoldTimeoutSeconds")
    } else {
        $configArgs += @("--toggle", "--seconds", "$RecordSeconds")
    }
    if (![string]::IsNullOrWhiteSpace($Language)) {
        $configArgs += @("--language", $Language)
    }
    if (![string]::IsNullOrWhiteSpace($Prompt)) {
        $configArgs += @("--prompt", $Prompt)
    }
    foreach ($replacement in $WordReplacement) {
        if (![string]::IsNullOrWhiteSpace($replacement)) {
            $configArgs += @("--replace", $replacement)
        }
    }
    if ($PasteDictation) {
        $configArgs += "--paste"
    }
    if ($NoPaste) {
        $configArgs += "--no-paste"
    }
    if ($RestoreClipboard) {
        $configArgs += "--restore-clipboard"
    }
    if ($NoRestoreClipboard) {
        $configArgs += "--no-restore-clipboard"
    }
    if ($HasClipboardRestoreDelay) {
        $configArgs += @("--clipboard-restore-delay", "$ClipboardRestoreDelaySeconds")
    }

    return $configArgs
}

function Add-RomaWindowsAgentScriptCommonArgs {
    param(
        [object[]]$ArgumentList = @(),
        [string]$Language = "",
        [string]$Prompt = "",
        [string[]]$WordReplacement = @(),
        [bool]$UseHoldHook = $false,
        [bool]$UseToggle = $false,
        [double]$HoldTimeoutSeconds = 15,
        [double]$RecordSeconds = 2,
        [bool]$PasteDictation = $false,
        [bool]$RestoreClipboard = $false,
        [bool]$NoRestoreClipboard = $false,
        [bool]$HasClipboardRestoreDelay = $false,
        [double]$ClipboardRestoreDelaySeconds = 2
    )

    $scriptArgs = @($ArgumentList)
    if (![string]::IsNullOrWhiteSpace($Language)) {
        $scriptArgs += @("-Language", $Language)
    }
    if (![string]::IsNullOrWhiteSpace($Prompt)) {
        $scriptArgs += @("-Prompt", $Prompt)
    }

    $replacementValues = @(
        $WordReplacement |
            Where-Object { ![string]::IsNullOrWhiteSpace($_) }
    )
    if ($replacementValues.Count -gt 0) {
        $scriptArgs += "-WordReplacement"
        $scriptArgs += $replacementValues
    }

    if ($UseHoldHook) {
        $scriptArgs += "-UseHoldHook"
    }
    if ($UseToggle) {
        $scriptArgs += "-UseToggle"
    }
    $scriptArgs += @("-HoldTimeoutSeconds", "$HoldTimeoutSeconds")
    $scriptArgs += @("-RecordSeconds", "$RecordSeconds")
    if ($PasteDictation) {
        $scriptArgs += "-PasteDictation"
    }
    if ($RestoreClipboard) {
        $scriptArgs += "-RestoreClipboard"
    }
    if ($NoRestoreClipboard) {
        $scriptArgs += "-NoRestoreClipboard"
    }
    if ($HasClipboardRestoreDelay) {
        $scriptArgs += @("-ClipboardRestoreDelaySeconds", "$ClipboardRestoreDelaySeconds")
    }

    return $scriptArgs
}

function Get-RomaWindowsFileProof {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $exists = Test-Path -LiteralPath $Path
    $bytes = 0
    if ($exists) {
        $bytes = (Get-Item -LiteralPath $Path).Length
    }

    return [ordered]@{
        path = $Path
        exists = $exists
        bytes = $bytes
    }
}

function Get-RomaWindowsEmptyFileProof {
    return [ordered]@{
        path = ""
        exists = $false
        bytes = 0
    }
}

function Get-RomaWindowsOptionalFileProof {
    param(
        [string]$Path = ""
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return Get-RomaWindowsEmptyFileProof
    }

    return Get-RomaWindowsFileProof -Path $Path
}

function Require-RomaWindowsFileProof {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    Require-RomaWindowsFile -Path $Path
    return Get-RomaWindowsFileProof -Path $Path
}

function Get-RomaWindowsFileHashProof {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $proof = Get-RomaWindowsFileProof -Path $Path
    $proof["sha256"] = ""
    if ($proof["exists"]) {
        $proof["sha256"] = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    }

    return $proof
}

function Get-RomaWindowsInstalledProofSurfaceFileProofs {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallDir
    )

    $proofs = [ordered]@{}
    foreach ($proofSurfaceFile in Get-RomaWindowsInstalledProofSurfaceFileMap) {
        $reportProperty = [string]$proofSurfaceFile.ReportProperty
        $packageFile = [string]$proofSurfaceFile.PackageFile
        $proofs[$reportProperty] = Get-RomaWindowsFileHashProof -Path (Join-Path $InstallDir $packageFile)
    }

    return $proofs
}
