param(
    [Parameter(Mandatory = $true)]
    [string]$ProofReportPath,
    [string]$ExpectedMode = "",
    [string]$RequireProofProfile = "",
    [switch]$RequireWindowsPlatform,
    [switch]$RequireInstall,
    [switch]$RequireShortcut,
    [switch]$RequireStartupShortcut,
    [switch]$RequirePermissionSurface,
    [switch]$RequireProofAgentSurface,
    [switch]$RequireNativeDoctorSurface,
    [switch]$RequirePackagedListener,
    [switch]$RequireInstalledListener,
    [switch]$RequireConfigDoctor,
    [switch]$RequirePackagedMock,
    [switch]$RequireHoldHook,
    [switch]$RequireCloudConfig,
    [switch]$RequireRealCloudBackend,
    [switch]$RequireWhisperConfig,
    [switch]$RequireRealWhisperBackend,
    [switch]$RequireDictation,
    [switch]$RequireListenerRuntime,
    [switch]$RequireExpectedTranscriptText,
    [switch]$RequirePaste,
    [switch]$RequireNotepadPaste
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$proofCommonScript = Join-Path $PSScriptRoot "windows-proof-common.ps1"
if (!(Test-Path -LiteralPath $proofCommonScript)) {
    throw "Windows proof common helper was not found: $proofCommonScript"
}
. $proofCommonScript

Set-Alias -Name Require-Property -Value Require-RomaWindowsProofReportProperty -Scope Local -Force
Set-Alias -Name Assert-Boolean -Value Assert-RomaWindowsProofReportBoolean -Scope Local -Force
Set-Alias -Name Assert-NonEmptyString -Value Assert-RomaWindowsProofReportNonEmptyString -Scope Local -Force
Set-Alias -Name Get-NonEmptyStringProperty -Value Get-RomaWindowsProofReportNonEmptyString -Scope Local -Force
Set-Alias -Name Assert-StringEquals -Value Assert-RomaWindowsProofReportStringEquals -Scope Local -Force
Set-Alias -Name Assert-NumberGreaterThan -Value Assert-RomaWindowsProofReportNumberGreaterThan -Scope Local -Force
Set-Alias -Name Assert-NumberEquals -Value Assert-RomaWindowsProofReportNumberEquals -Scope Local -Force
Set-Alias -Name Assert-FileProof -Value Assert-RomaWindowsProofReportFile -Scope Local -Force
Set-Alias -Name Assert-FileHashEquals -Value Assert-RomaWindowsProofReportFileHashEquals -Scope Local -Force
Set-Alias -Name Assert-ShortcutProof -Value Assert-RomaWindowsProofReportShortcut -Scope Local -Force
Set-Alias -Name Assert-DictationRuntimeProof -Value Assert-RomaWindowsProofReportDictationRuntime -Scope Local -Force
Set-Alias -Name Assert-ListenerRuntimeProof -Value Assert-RomaWindowsProofReportListenerRuntime -Scope Local -Force
Set-Alias -Name Assert-PasteIntentProof -Value Assert-RomaWindowsProofReportPasteIntent -Scope Local -Force
Set-Alias -Name Assert-HoldHookRuntimeProof -Value Assert-RomaWindowsProofReportHoldHookRuntime -Scope Local -Force

function Assert-PackageIdentityProof {
    param(
        [Parameter(Mandatory = $true)]
        [object]$PackageIdentity
    )

    $fingerprint = Get-RomaWindowsPackageIdentityFingerprint `
        -PackageIdentity $PackageIdentity `
        -Context "package_identity" `
        -RequireEntryCount
    Write-Host "proof_value=package_identity.algorithm value=sha256"
    Write-Host "proof_number=package_identity.entry_count value=$([int64](Require-Property -Object $PackageIdentity -Name "entry_count")) minimum=0"

    return $fingerprint
}

function Assert-RealCloudBackendProof {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Config
    )

    $endpoint = [string](Require-Property -Object $Config -Name "endpoint")
    $model = [string](Require-Property -Object $Config -Name "model")
    try {
        $uri = [System.Uri]::new($endpoint)
    } catch {
        throw "Cloud endpoint is not a valid URI: $endpoint"
    }
    if (!$uri.IsAbsoluteUri -or [string]::IsNullOrWhiteSpace($uri.Host)) {
        throw "Cloud endpoint must be an absolute URI with a host: $endpoint"
    }
    if ($uri.Scheme -ne "https") {
        throw "Cloud laptop proof must use an https endpoint: $endpoint"
    }
    $endpointPath = $uri.AbsolutePath.ToLowerInvariant().TrimEnd("/")
    if (!$endpointPath.EndsWith("/audio/transcriptions")) {
        throw "Cloud laptop proof must use an audio transcription endpoint: $endpoint"
    }

    $endpointHost = $uri.Host.ToLowerInvariant()
    if ($endpointHost -eq "localhost" -or
        $endpointHost.EndsWith(".localhost") -or
        $endpointHost.EndsWith(".local") -or
        $endpointHost.EndsWith(".test") -or
        $endpointHost.EndsWith(".invalid") -or
        $endpointHost -eq "example.com" -or
        $endpointHost.EndsWith(".example.com") -or
        $endpointHost -eq "::1" -or
        $endpointHost -eq "0.0.0.0" -or
        $endpointHost.StartsWith("127.")) {
        throw "Cloud laptop proof cannot use a loopback/mock endpoint: $endpoint"
    }
    $endpointAddress = $null
    if ([System.Net.IPAddress]::TryParse($endpointHost, [ref]$endpointAddress)) {
        if ([System.Net.IPAddress]::IsLoopback($endpointAddress)) {
            throw "Cloud laptop proof cannot use a loopback/mock endpoint: $endpoint"
        }
        $addressBytes = $endpointAddress.GetAddressBytes()
        if ($endpointAddress.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork) {
            $isPrivateOrReserved = $addressBytes[0] -eq 10 -or
                $addressBytes[0] -eq 0 -or
                $addressBytes[0] -eq 127 -or
                ($addressBytes[0] -eq 172 -and $addressBytes[1] -ge 16 -and $addressBytes[1] -le 31) -or
                ($addressBytes[0] -eq 192 -and $addressBytes[1] -eq 168) -or
                ($addressBytes[0] -eq 169 -and $addressBytes[1] -eq 254) -or
                ($addressBytes[0] -eq 100 -and $addressBytes[1] -ge 64 -and $addressBytes[1] -le 127) -or
                ($addressBytes[0] -eq 192 -and $addressBytes[1] -eq 0 -and $addressBytes[2] -eq 0) -or
                ($addressBytes[0] -eq 192 -and $addressBytes[1] -eq 0 -and $addressBytes[2] -eq 2) -or
                ($addressBytes[0] -eq 198 -and ($addressBytes[1] -eq 18 -or $addressBytes[1] -eq 19)) -or
                ($addressBytes[0] -eq 198 -and $addressBytes[1] -eq 51 -and $addressBytes[2] -eq 100) -or
                ($addressBytes[0] -eq 203 -and $addressBytes[1] -eq 0 -and $addressBytes[2] -eq 113) -or
                ($addressBytes[0] -ge 224)
            if ($isPrivateOrReserved) {
                throw "Cloud laptop proof cannot use a private or reserved endpoint: $endpoint"
            }
        } elseif ($endpointAddress.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetworkV6) {
            $isUnspecified = ($addressBytes | Where-Object { $_ -ne 0 }).Count -eq 0
            $isPrivateOrReserved = $isUnspecified -or
                (($addressBytes[0] -band 0xfe) -eq 0xfc) -or
                ($addressBytes[0] -eq 0xfe -and (($addressBytes[1] -band 0xc0) -eq 0x80)) -or
                ($addressBytes[0] -eq 0xff) -or
                ($addressBytes[0] -eq 0x20 -and $addressBytes[1] -eq 0x01 -and $addressBytes[2] -eq 0x0d -and $addressBytes[3] -eq 0xb8)
            if ($isPrivateOrReserved) {
                throw "Cloud laptop proof cannot use a private or reserved endpoint: $endpoint"
            }
        }
    }
    if ($model -match "(?i)(^|[-_.])mock($|[-_.])") {
        throw "Cloud laptop proof cannot use a mock model name: $model"
    }

    Write-Host "proof_real_cloud_backend host=$endpointHost model=$model"
}

function Assert-ManifestSourceProof {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Manifest
    )

    $source = Get-RomaWindowsManifestSourceProvenance `
        -Manifest $Manifest `
        -Context "manifest"
    Assert-NonEmptyString -Object $Manifest -Name "source_branch"

    Write-Host "proof_source_commit=$($source['Commit'])"
    Write-Host "proof_source_dirty=$($source['Dirty'])"
}

function Assert-HoldTimeoutDefaultProof {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Proof
    )

    Assert-Boolean -Object $Proof -Name "default_hold_timeout_seconds" -Expected $true
    Assert-Boolean -Object $Proof -Name "default_hold_timeout_milliseconds" -Expected $true
}

function Assert-ClipboardRestoreDefaultProof {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Proof
    )

    Assert-Boolean -Object $Proof -Name "default_clipboard_restore_delay_seconds" -Expected $true
    Assert-Boolean -Object $Proof -Name "maximum_clipboard_restore_delay_seconds" -Expected $true
}

function Assert-RuntimeDefaultProof {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Proof
    )

    Assert-Boolean -Object $Proof -Name "default_record_seconds" -Expected $true
    Assert-HoldTimeoutDefaultProof -Proof $Proof
    Assert-ClipboardRestoreDefaultProof -Proof $Proof
}

function Assert-DoctorOutputProof {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Proof,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    Assert-Boolean -Object $Proof -Name "output_present" -Expected $true
    Assert-Boolean -Object $Proof -Name "runtime_available" -Expected $true
    Assert-Boolean -Object $Proof -Name "dictation_runtime" -Expected $true
    Assert-Boolean -Object $Proof -Name "recorder_miniaudio" -Expected $true
    Assert-Boolean -Object $Proof -Name "paste_win32_clipboard_sendinput" -Expected $true
    Assert-Boolean -Object $Proof -Name "secret_store_dpapi" -Expected $true
    Assert-Boolean -Object $Proof -Name "os_permission_grants_microphone" -Expected $true
    Assert-Boolean -Object $Proof -Name "microphone_settings_uri" -Expected $true
    Assert-Boolean -Object $Proof -Name "desktop_app_microphone_access_required" -Expected $true
    Assert-Boolean -Object $Proof -Name "native_capabilities_register_hotkey" -Expected $true
    Assert-RuntimeDefaultProof -Proof $Proof
    Assert-Boolean -Object $Proof -Name "no_accessibility_permission_prompt" -Expected $true
    Assert-Boolean -Object $Proof -Name "no_automation_permission_prompt" -Expected $true
    Assert-Boolean -Object $Proof -Name "no_admin_required" -Expected $true
    Assert-Boolean -Object $Proof -Name "startup_launcher_run_script" -Expected $true
    Assert-Boolean -Object $Proof -Name "startup_launch_mode_listen" -Expected $true
    Assert-Boolean -Object $Proof -Name "no_startup_permission_prompt" -Expected $true
    Assert-Boolean -Object $Proof -Name "no_screen_capture_required" -Expected $true
    Assert-Boolean -Object $Proof -Name "no_screen_recording_permission_prompt" -Expected $true
    Write-Host "proof_doctor=$Name"
}

function Assert-ProofAgentDoctorOutputProof {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Proof,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    Assert-Boolean -Object $Proof -Name "output_present" -Expected $true
    Assert-Boolean -Object $Proof -Name "swift_core" -Expected $true
    Assert-Boolean -Object $Proof -Name "native_windows_adapters" -Expected $true
    Assert-Boolean -Object $Proof -Name "pre_roll_config" -Expected $true
    Assert-RuntimeDefaultProof -Proof $Proof
    Assert-Boolean -Object $Proof -Name "windows_paste_adapter_source" -Expected $true
    Assert-Boolean -Object $Proof -Name "windows_permission_surface_source" -Expected $true
    Assert-Boolean -Object $Proof -Name "windows_dictation_runtime_source" -Expected $true
    Assert-Boolean -Object $Proof -Name "windows_dictation_runtime_uses_pipeline_source" -Expected $true
    Assert-Boolean -Object $Proof -Name "windows_listener_output_isolation_source" -Expected $true
    Assert-Boolean -Object $Proof -Name "windows_listener_pre_roll_runtime_source" -Expected $true
    Assert-Boolean -Object $Proof -Name "windows_hold_hook_single_window_source" -Expected $true
    Assert-Boolean -Object $Proof -Name "windows_dictation_proof_source" -Expected $true
    Assert-Boolean -Object $Proof -Name "miniaudio_capture_adapter_source" -Expected $true
    Assert-Boolean -Object $Proof -Name "openai_compatible_transcription_source" -Expected $true
    Assert-Boolean -Object $Proof -Name "whisper_cli_transcription_source" -Expected $true
    Assert-Boolean -Object $Proof -Name "roma_transcription_client_source" -Expected $true
    Assert-Boolean -Object $Proof -Name "transcription_output_filter_source" -Expected $true
    Assert-Boolean -Object $Proof -Name "word_replacement_processor_source" -Expected $true
    Assert-Boolean -Object $Proof -Name "windows_proof_args_shared_source" -Expected $true
    Write-Host "proof_agent_doctor=$Name"
}

function Assert-NativeDoctorOutputProof {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Proof,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    Assert-Boolean -Object $Proof -Name "output_present" -Expected $true
    Assert-Boolean -Object $Proof -Name "platform_windows" -Expected $true
    Assert-NonEmptyString -Object $Proof -Name "expected_marker"
    $actualMarker = [string](Require-Property -Object $Proof -Name "expected_marker")
    $expectedMarker = Get-RomaWindowsNativeDoctorExpectedMarker -Name $Name
    if ($actualMarker -ne $expectedMarker) {
        throw "$Name expected_marker mismatch: actual=$actualMarker expected=$expectedMarker"
    }
    Assert-Boolean -Object $Proof -Name "expected_marker_present" -Expected $true
    if ($Name -eq "keyboard_hook") {
        Assert-HoldTimeoutDefaultProof -Proof $Proof
    }
    if ($Name -eq "register_hotkey_available") {
        Assert-Boolean -Object $Proof -Name "register_hotkey_available" -Expected $true
    }
    if ($Name -eq "paste") {
        Assert-ClipboardRestoreDefaultProof -Proof $Proof
    }
    Write-Host "proof_native_doctor=$Name"
}

function Assert-PackagedListenerProof {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Proof
    )

    Assert-Boolean -Object $Proof -Name "output_present" -Expected $true
    Assert-Boolean -Object $Proof -Name "mode_listen" -Expected $true
    Assert-Boolean -Object $Proof -Name "shared_pre_roll_runtime" -Expected $true
    Assert-Boolean -Object $Proof -Name "zero_session" -Expected $true
    Assert-Boolean -Object $Proof -Name "completed_zero_sessions" -Expected $true
    Write-Host "proof_packaged_listener=listen_zero_session"
}

function Assert-ConfigDoctorProof {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Proof,
        [Parameter(Mandatory = $true)]
        [string]$ExpectedConfigPath
    )

    Assert-Boolean -Object $Proof -Name "output_present" -Expected $true
    Assert-Boolean -Object $Proof -Name "config_path_present" -Expected $true
    Assert-StringEquals `
        -Actual ([string](Require-Property -Object $Proof -Name "config_path")) `
        -Expected $ExpectedConfigPath `
        -Name "config_doctor.config_path"
    Assert-Boolean -Object $Proof -Name "config_valid" -Expected $true
    Assert-Boolean -Object $Proof -Name "transcription_client_present" -Expected $true
    Write-Host "proof_config_doctor=config_valid"
}

function Assert-InstalledListenerProof {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Proof,
        [Parameter(Mandatory = $true)]
        [string]$ExpectedConfigPath,
        [Parameter(Mandatory = $true)]
        [string]$ExpectedAgentPath
    )

    Assert-Boolean -Object $Proof -Name "output_present" -Expected $true
    Assert-Boolean -Object $Proof -Name "mode_listen" -Expected $true
    Assert-Boolean -Object $Proof -Name "shared_pre_roll_runtime" -Expected $true
    Assert-Boolean -Object $Proof -Name "zero_session" -Expected $true
    Assert-Boolean -Object $Proof -Name "completed_zero_sessions" -Expected $true
    Assert-Boolean -Object $Proof -Name "config_path_present" -Expected $true
    Assert-StringEquals `
        -Actual ([string](Require-Property -Object $Proof -Name "config_path")) `
        -Expected $ExpectedConfigPath `
        -Name "installed_listener.config_path"
    Assert-Boolean -Object $Proof -Name "agent_path_present" -Expected $true
    Assert-StringEquals `
        -Actual ([string](Require-Property -Object $Proof -Name "agent_path")) `
        -Expected $ExpectedAgentPath `
        -Name "installed_listener.agent_path"
    Write-Host "proof_installed_listener=listen_zero_session"
}

function Assert-LaptopPreflightReport {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Report
    )

    Assert-StringEquals `
        -Actual ([string](Require-Property -Object $Report -Name "proof_mode")) `
        -Expected (Get-RomaWindowsProofProfileExpectedModeByName -Name "laptop_preflight") `
        -Name "proof_mode"
    Assert-Boolean -Object $Report -Name "preflight_only" -Expected $true
    $proofSessionId = Assert-RomaWindowsProofSessionId `
        -Value ([string](Require-Property -Object $Report -Name "proof_session_id")) `
        -Name "proof_session_id" `
        -WriteProofValue
    $generatedAt = ConvertTo-RomaWindowsProofTimestamp `
        -Value ([string](Require-Property -Object $Report -Name "generated_at")) `
        -Name "generated_at" `
        -WriteProofValue
    $packageDir = Get-NonEmptyStringProperty -Object $Report -Name "package_dir"
    $proofDir = Get-NonEmptyStringProperty -Object $Report -Name "proof_dir"

    $packageIdentity = Require-Property -Object $Report -Name "package_identity"
    $packageFingerprint = Assert-PackageIdentityProof -PackageIdentity $packageIdentity

    $manifest = Require-Property -Object $Report -Name "manifest"
    Assert-ManifestSourceProof -Manifest $manifest
    $sourceRepository = [string](Require-Property -Object $manifest -Name "source_repository")
    $sourceBranch = [string](Require-Property -Object $manifest -Name "source_branch")
    $sourceCommit = [string](Require-Property -Object $manifest -Name "source_commit")
    $sourceDirty = [string](Require-Property -Object $manifest -Name "source_dirty")
    if ($sourceDirty -ne "false") {
        throw "Laptop preflight proof requires a clean packaged source checkout, got source_dirty=$sourceDirty"
    }

    $os = Require-Property -Object $Report -Name "os"
    $platform = [string](Require-Property -Object $os -Name "platform")
    if ($platform -ne "Win32NT") {
        throw "Laptop preflight proof must run on Windows, got platform $platform"
    }
    Write-Host "proof_windows_platform=$platform"
    $machine = Get-NonEmptyStringProperty -Object $os -Name "machine"
    $userName = Get-NonEmptyStringProperty -Object $os -Name "user_name"
    $userSid = Get-NonEmptyStringProperty -Object $os -Name "user_sid"

    $preflights = Require-Property -Object $Report -Name "preflights"
    Assert-Boolean -Object $preflights -Name "permission_surface" -Expected $true
    Assert-Boolean -Object $preflights -Name "hotkey_delivery" -Expected $true
    Assert-Boolean -Object $preflights -Name "microphone" -Expected $true
    $hasLocalWhisperPreflight = [bool](Require-Property -Object $preflights -Name "local_whisper")

    $preflightOutputs = Require-Property -Object $Report -Name "preflight_outputs"
    $permissionOutput = Require-Property -Object $preflightOutputs -Name "permission_surface"
    Assert-Boolean -Object $permissionOutput -Name "output_present" -Expected $true
    Assert-Boolean -Object $permissionOutput -Name "os_permission_grants_microphone" -Expected $true
    Assert-Boolean -Object $permissionOutput -Name "microphone_settings_uri" -Expected $true
    Assert-Boolean -Object $permissionOutput -Name "desktop_app_microphone_access_required" -Expected $true
    Assert-Boolean -Object $permissionOutput -Name "native_capabilities_register_hotkey" -Expected $true
    Assert-Boolean -Object $permissionOutput -Name "no_accessibility_permission_prompt" -Expected $true
    Assert-Boolean -Object $permissionOutput -Name "no_automation_permission_prompt" -Expected $true
    Assert-Boolean -Object $permissionOutput -Name "no_admin_required" -Expected $true
    Assert-Boolean -Object $permissionOutput -Name "startup_launcher_run_script" -Expected $true
    Assert-Boolean -Object $permissionOutput -Name "startup_launch_mode_listen" -Expected $true
    Assert-Boolean -Object $permissionOutput -Name "no_startup_permission_prompt" -Expected $true
    Assert-Boolean -Object $permissionOutput -Name "no_screen_capture_required" -Expected $true
    Assert-Boolean -Object $permissionOutput -Name "no_screen_recording_permission_prompt" -Expected $true

    $hotkeyOutput = Require-Property -Object $preflightOutputs -Name "hotkey_delivery"
    Assert-Boolean -Object $hotkeyOutput -Name "output_present" -Expected $true
    Assert-Boolean -Object $hotkeyOutput -Name "waiting_for_hold" -Expected $true
    Assert-Boolean -Object $hotkeyOutput -Name "key_down" -Expected $true
    Assert-Boolean -Object $hotkeyOutput -Name "key_up" -Expected $true
    Assert-Boolean -Object $hotkeyOutput -Name "observed_events_present" -Expected $true

    $microphoneOutput = Require-Property -Object $preflightOutputs -Name "microphone"
    Assert-Boolean -Object $microphoneOutput -Name "output_present" -Expected $true
    Assert-Boolean -Object $microphoneOutput -Name "wrote_present" -Expected $true
    Assert-Boolean -Object $microphoneOutput -Name "reported_duration" -Expected $true
    Assert-Boolean -Object $microphoneOutput -Name "reported_positive_duration" -Expected $true
    Assert-NumberGreaterThan -Object $microphoneOutput -Name "duration_seconds" -Minimum 0
    Assert-Boolean -Object $microphoneOutput -Name "reported_pre_roll" -Expected $true
    Assert-Boolean -Object $microphoneOutput -Name "reported_positive_pre_roll" -Expected $true
    Assert-NumberGreaterThan -Object $microphoneOutput -Name "included_pre_roll_seconds" -Minimum 0
    Assert-Boolean -Object $microphoneOutput -Name "sample_rate_16000" -Expected $true
    Assert-Boolean -Object $microphoneOutput -Name "channels_mono" -Expected $true

    $localWhisperOutput = Require-Property -Object $preflightOutputs -Name "local_whisper"
    if ($hasLocalWhisperPreflight) {
        Assert-Boolean -Object $localWhisperOutput -Name "output_present" -Expected $true
        Assert-Boolean -Object $localWhisperOutput -Name "transcription_client_whisper" -Expected $true
        Assert-Boolean -Object $localWhisperOutput -Name "network_required_false" -Expected $true
        Assert-Boolean -Object $localWhisperOutput -Name "executable_present" -Expected $true
        Assert-Boolean -Object $localWhisperOutput -Name "model_file_present" -Expected $true
    } else {
        Assert-Boolean -Object $localWhisperOutput -Name "output_present" -Expected $false
    }

    $files = Require-Property -Object $Report -Name "files"
    Assert-FileProof -Proof (Require-Property -Object $files -Name "proof_agent") -Name "laptop_preflight.proof_agent"
    Assert-FileProof -Proof (Require-Property -Object $files -Name "mic_preflight_wav") -Name "laptop_preflight.mic_preflight_wav" -MinimumBytes 45
    if ($hasLocalWhisperPreflight) {
        Assert-FileProof -Proof (Require-Property -Object $files -Name "whisper_cli") -Name "laptop_preflight.whisper_cli"
        Assert-FileProof -Proof (Require-Property -Object $files -Name "whisper_model") -Name "laptop_preflight.whisper_model"
    }

    Write-Host "proof_set_laptop_preflight_session_id=$proofSessionId"
    Write-Host "proof_set_laptop_preflight_generated_at=$($generatedAt.ToString("o"))"
    Write-Host "proof_set_laptop_preflight_machine=$machine"
    Write-Host "proof_set_laptop_preflight_user=$userName"
    Write-Host "proof_set_laptop_preflight_user_sid=$userSid"
    Write-Host "proof_set_laptop_preflight_package_dir=$packageDir"
    Write-Host "proof_set_laptop_preflight_package_fingerprint=$packageFingerprint"
    Write-Host "proof_set_laptop_preflight_source_repository=$sourceRepository"
    Write-Host "proof_set_laptop_preflight_source_branch=$sourceBranch"
    Write-Host "proof_set_laptop_preflight_source_commit=$sourceCommit"
    Write-Host "proof_set_laptop_preflight_source_dirty=$sourceDirty"
    Write-Host "proof_set_laptop_preflight_proof_dir=$proofDir"
    Write-Host "proof_set_laptop_preflight_permission_surface=true"
    Write-Host "proof_set_laptop_preflight_local_whisper=$hasLocalWhisperPreflight"
}

function Set-ExpectedModeFromProfile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Mode,
        [Parameter(Mandatory = $true)]
        [string]$Profile
    )

    if (![string]::IsNullOrWhiteSpace($script:ExpectedMode) -and $script:ExpectedMode -ne $Mode) {
        throw "Proof profile $Profile expects mode $Mode, got ExpectedMode $script:ExpectedMode"
    }

    $script:ExpectedMode = $Mode
}

function Write-ProofProfileRequirements {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Profile
    )

    foreach ($requirement in (Get-RomaWindowsProofProfileRequirements -Profile $Profile)) {
        Write-Host "proof_requirement=$requirement status=pass"
    }
    Write-Host "proof_profile_ok=$Profile"
}

function Enable-ProofProfileAssertion {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    switch ($Name) {
        "windows_platform" { $script:RequireWindowsPlatform = $true }
        "install" { $script:RequireInstall = $true }
        "shortcut" { $script:RequireShortcut = $true }
        "startup_shortcut" { $script:RequireStartupShortcut = $true }
        "permission_surface" { $script:RequirePermissionSurface = $true }
        "proof_agent_surface" { $script:RequireProofAgentSurface = $true }
        "native_doctor_surface" { $script:RequireNativeDoctorSurface = $true }
        "packaged_listener" { $script:RequirePackagedListener = $true }
        "installed_listener" { $script:RequireInstalledListener = $true }
        "config_doctor" { $script:RequireConfigDoctor = $true }
        "hold_hook" { $script:RequireHoldHook = $true }
        "cloud_config" { $script:RequireCloudConfig = $true }
        "real_cloud_backend" { $script:RequireRealCloudBackend = $true }
        "dictation" { $script:RequireDictation = $true }
        "expected_transcript_text" { $script:RequireExpectedTranscriptText = $true }
        "paste" { $script:RequirePaste = $true }
        "whisper_config" { $script:RequireWhisperConfig = $true }
        "real_whisper_backend" { $script:RequireRealWhisperBackend = $true }
        "listener_runtime" { $script:RequireListenerRuntime = $true }
        "notepad_paste" { $script:RequireNotepadPaste = $true }
        "packaged_mock" { $script:RequirePackagedMock = $true }
        default { throw "Unknown Windows proof profile assertion: $Name" }
    }
}

function Enable-ProofProfileAssertions {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Profile
    )

    foreach ($assertion in (Get-RomaWindowsProofProfileAssertions -Profile $Profile)) {
        Enable-ProofProfileAssertion -Name $assertion
    }
}

$ProofReportPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ProofReportPath)
if (!(Test-Path -LiteralPath $ProofReportPath)) {
    throw "Proof report was not found: $ProofReportPath"
}

$report = Get-Content -LiteralPath $ProofReportPath -Raw | ConvertFrom-Json
$dictationRuntime = $null

if (![string]::IsNullOrWhiteSpace($RequireProofProfile)) {
    Set-ExpectedModeFromProfile `
        -Mode (Get-RomaWindowsProofProfileExpectedMode -Profile $RequireProofProfile) `
        -Profile $RequireProofProfile
    Enable-ProofProfileAssertions -Profile $RequireProofProfile
}

if (![string]::IsNullOrWhiteSpace($RequireProofProfile)) {
    Write-Host "proof_profile=$RequireProofProfile"
}

if ($RequireProofProfile -eq "laptop-preflight") {
    Assert-LaptopPreflightReport -Report $report
    Write-ProofProfileRequirements -Profile $RequireProofProfile
    Write-Host "proof_report_ok=$ProofReportPath"
    return
}

Assert-NonEmptyString -Object $report -Name "generated_at"
Assert-NonEmptyString -Object $report -Name "proof_mode"
Assert-NonEmptyString -Object $report -Name "package_dir"
Assert-NonEmptyString -Object $report -Name "install_dir"
$packageIdentity = Require-Property -Object $report -Name "package_identity"
Assert-StringEquals `
    -Actual ([string](Require-Property -Object $packageIdentity -Name "algorithm")) `
    -Expected "sha256" `
    -Name "package_identity.algorithm"
Assert-NonEmptyString -Object $packageIdentity -Name "fingerprint"
Assert-NumberGreaterThan -Object $packageIdentity -Name "entry_count" -Minimum 0
$manifest = Require-Property -Object $report -Name "manifest"
Assert-ManifestSourceProof -Manifest $manifest

if ($RequireWindowsPlatform) {
    $os = Require-Property -Object $report -Name "os"
    $platform = [string](Require-Property -Object $os -Name "platform")
    if ($platform -ne "Win32NT") {
        throw "Expected os.platform to be Win32NT, got $platform"
    }

    Write-Host "proof_windows_platform=$platform"
    Assert-NonEmptyString -Object $os -Name "user_name"
    Assert-NonEmptyString -Object $os -Name "user_sid"
    $userName = [string](Require-Property -Object $os -Name "user_name")
    Write-Host "proof_windows_user=$userName"
}

if (![string]::IsNullOrWhiteSpace($ExpectedMode)) {
    $actualMode = [string](Require-Property -Object $report -Name "proof_mode")
    if ($actualMode -ne $ExpectedMode) {
        throw "Expected proof_mode to be $ExpectedMode, got $actualMode"
    }

    Write-Host "proof_mode=$actualMode"
}

$files = Require-Property -Object $report -Name "files"
Assert-FileProof -Proof (Require-Property -Object $files -Name "packaged_agent") -Name "packaged_agent"
Assert-FileProof -Proof (Require-Property -Object $files -Name "packaged_proof_agent") -Name "packaged_proof_agent"

if ($RequirePackagedMock) {
    Assert-FileProof -Proof (Require-Property -Object $files -Name "packaged_whisper_cli_mock") -Name "packaged_whisper_cli_mock"
}

if ($RequireInstall) {
    $installedAgent = Require-Property -Object $files -Name "installed_agent"
    $installedProofAgent = Require-Property -Object $files -Name "installed_proof_agent"
    Assert-FileProof -Proof $installedAgent -Name "installed_agent"
    Assert-FileProof -Proof $installedProofAgent -Name "installed_proof_agent"
    Assert-FileHashEquals `
        -ActualProof $installedAgent `
        -ExpectedProof (Require-Property -Object $files -Name "packaged_agent") `
        -Name "installed_agent_matches_package"
    Assert-FileHashEquals `
        -ActualProof $installedProofAgent `
        -ExpectedProof (Require-Property -Object $files -Name "packaged_proof_agent") `
        -Name "installed_proof_agent_matches_package"
    $packageIdentityFiles = Require-Property -Object $packageIdentity -Name "files"
    foreach ($proofSurfaceFile in Get-RomaWindowsInstalledProofSurfaceFileMap) {
        $reportProperty = [string]$proofSurfaceFile.ReportProperty
        $packageFile = [string]$proofSurfaceFile.PackageFile
        $installedFile = Require-Property -Object $files -Name $reportProperty
        Assert-FileProof -Proof $installedFile -Name $reportProperty
        Assert-FileHashEquals `
            -ActualProof $installedFile `
            -ExpectedProof (Require-Property -Object $packageIdentityFiles -Name $packageFile) `
            -Name "$($reportProperty)_matches_package"
    }

    $config = Require-Property -Object $report -Name "config"
    Assert-FileProof -Proof $config -Name "config"
    $installedScriptParse = Require-Property -Object $report -Name "installed_script_parse"
    Assert-Boolean -Object $installedScriptParse -Name "output_present" -Expected $true
    Assert-Boolean -Object $installedScriptParse -Name "ok" -Expected $true
    Assert-Boolean -Object $installedScriptParse -Name "count_present" -Expected $true
    Assert-NumberEquals `
        -Object $installedScriptParse `
        -Name "count" `
        -Expected (Get-RomaWindowsInstalledProofSurfaceScriptCount)
}

if ($RequireShortcut) {
    Assert-ShortcutProof -Proof (Require-Property -Object $report -Name "shortcut") -Name "shortcut"
}

if ($RequireStartupShortcut) {
    Assert-ShortcutProof -Proof (Require-Property -Object $report -Name "startup_shortcut") -Name "startup_shortcut"
}

if ($RequirePermissionSurface) {
    $doctor = Require-Property -Object $report -Name "doctor"
    $packagedDoctor = Require-Property -Object $doctor -Name "packaged_agent"
    Assert-DoctorOutputProof -Proof $packagedDoctor -Name "packaged_agent"
    if ($RequireInstall) {
        $installedDoctor = Require-Property -Object $doctor -Name "installed_launcher"
        Assert-DoctorOutputProof -Proof $installedDoctor -Name "installed_launcher"
    }
}

if ($RequireProofAgentSurface) {
    $doctor = Require-Property -Object $report -Name "doctor"
    $packagedProofAgent = Require-Property -Object $doctor -Name "packaged_proof_agent"
    Assert-ProofAgentDoctorOutputProof -Proof $packagedProofAgent -Name "packaged_proof_agent"
}

if ($RequireNativeDoctorSurface) {
    $doctor = Require-Property -Object $report -Name "doctor"
    $nativeDoctors = Require-Property -Object $doctor -Name "packaged_native_doctors"
    $nativeDoctorSpecs = Get-RomaWindowsNativeDoctorSpecs
    foreach ($name in $nativeDoctorSpecs.Keys) {
        Assert-NativeDoctorOutputProof `
            -Proof (Require-Property -Object $nativeDoctors -Name $name) `
            -Name $name
    }
}

if ($RequirePackagedListener) {
    Assert-PackagedListenerProof -Proof (Require-Property -Object $report -Name "packaged_listener")
}

if ($RequireInstalledListener) {
    $config = Require-Property -Object $report -Name "config"
    $installedAgent = Require-Property -Object $files -Name "installed_agent"
    Assert-InstalledListenerProof `
        -Proof (Require-Property -Object $report -Name "installed_listener") `
        -ExpectedConfigPath ([string](Require-Property -Object $config -Name "path")) `
        -ExpectedAgentPath ([string](Require-Property -Object $installedAgent -Name "path"))
}

if ($RequireConfigDoctor) {
    $config = Require-Property -Object $report -Name "config"
    $configDoctor = Require-Property -Object $report -Name "config_doctor"
    Assert-ConfigDoctorProof `
        -Proof $configDoctor `
        -ExpectedConfigPath ([string](Require-Property -Object $config -Name "path"))
    if ($RequireCloudConfig) {
        Assert-Boolean -Object $configDoctor -Name "uses_cloud" -Expected $true
        Assert-Boolean -Object $configDoctor -Name "api_key_resolved" -Expected $true
    }
    if ($RequireWhisperConfig) {
        Assert-Boolean -Object $configDoctor -Name "uses_whisper_cli" -Expected $true
        Assert-Boolean -Object $configDoctor -Name "whisper_cli_exists" -Expected $true
        Assert-Boolean -Object $configDoctor -Name "whisper_model_exists" -Expected $true
    }
}

if ($RequireHoldHook) {
    $config = Require-Property -Object $report -Name "config"
    Assert-Boolean -Object $config -Name "uses_hold_hook" -Expected $true
}

if ($RequireCloudConfig) {
    $config = Require-Property -Object $report -Name "config"
    Assert-Boolean -Object $config -Name "uses_whisper_cli" -Expected $false
    Assert-NonEmptyString -Object $config -Name "endpoint"
    Assert-NonEmptyString -Object $config -Name "model"
}

if ($RequireRealCloudBackend) {
    $config = Require-Property -Object $report -Name "config"
    Assert-RealCloudBackendProof -Config $config
}

if ($RequireWhisperConfig) {
    $config = Require-Property -Object $report -Name "config"
    Assert-Boolean -Object $config -Name "uses_whisper_cli" -Expected $true
    Assert-NonEmptyString -Object $config -Name "whisper_cli_path"
    Assert-NonEmptyString -Object $config -Name "whisper_model_path"
    Assert-FileProof -Proof (Require-Property -Object $config -Name "whisper_cli_file") -Name "whisper_cli"
    Assert-FileProof -Proof (Require-Property -Object $config -Name "whisper_model_file") -Name "whisper_model"
}

if ($RequireRealWhisperBackend) {
    $config = Require-Property -Object $report -Name "config"
    Assert-RomaWindowsRealWhisperBackendProof -Config $config -Files $files
}

if ($RequireDictation) {
    Assert-Boolean -Object $report -Name "run_dictation" -Expected $true
    $config = Require-Property -Object $report -Name "config"
    $outputFile = Require-Property -Object $config -Name "output_file"
    Assert-FileProof -Proof $outputFile -Name "dictation_output" -MinimumBytes 45
    $dictationRuntime = Assert-DictationRuntimeProof `
        -Report $report `
        -RequireExpectedTranscriptText:$RequireExpectedTranscriptText.IsPresent
    Assert-StringEquals `
        -Actual ([string](Require-Property -Object $dictationRuntime -Name "wrote_path")) `
        -Expected ([string](Require-Property -Object $outputFile -Name "path")) `
        -Name "dictation_runtime_wrote_path"
    if ($RequireHoldHook) {
        Assert-HoldHookRuntimeProof -Runtime $dictationRuntime
    }
}

if ($RequireListenerRuntime) {
    Assert-Boolean -Object $report -Name "run_listener_proof" -Expected $true
    $listenerRuntime = Assert-ListenerRuntimeProof `
        -Report $report `
        -RequireExpectedTranscriptText:$RequireExpectedTranscriptText.IsPresent
    if ($RequireHoldHook) {
        Assert-HoldHookRuntimeProof -Runtime $listenerRuntime
    }
    if ($RequirePaste) {
        Assert-Boolean -Object $listenerRuntime -Name "reported_paste_sent" -Expected $true
    }
}

if ($RequirePaste) {
    Assert-Boolean -Object $report -Name "paste_dictation" -Expected $true
    $config = Require-Property -Object $report -Name "config"
    Assert-Boolean -Object $config -Name "should_paste" -Expected $true
    Assert-PasteIntentProof -Report $report -Config $config
    if ($null -eq $dictationRuntime) {
        $dictationRuntime = Assert-DictationRuntimeProof `
            -Report $report `
            -RequireExpectedTranscriptText:$RequireExpectedTranscriptText.IsPresent
    }
    if ($RequireHoldHook) {
        Assert-HoldHookRuntimeProof -Runtime $dictationRuntime
    }
    Assert-Boolean -Object $dictationRuntime -Name "reported_paste_sent" -Expected $true
}

if ($RequireNotepadPaste) {
    $notepadPaste = Require-Property -Object $report -Name "notepad_paste"
    Assert-Boolean -Object $notepadPaste -Name "requested" -Expected $true
    Assert-Boolean -Object $notepadPaste -Name "output_present" -Expected $true
    Assert-Boolean -Object $notepadPaste -Name "paste_sent" -Expected $true
    Assert-Boolean -Object $notepadPaste -Name "text_found" -Expected $true
    Assert-Boolean -Object $notepadPaste -Name "verified" -Expected $true
    Assert-FileProof -Proof (Require-Property -Object $notepadPaste -Name "file") -Name "notepad_paste_file"
}

if (![string]::IsNullOrWhiteSpace($RequireProofProfile)) {
    Write-ProofProfileRequirements -Profile $RequireProofProfile
}

Write-Host "proof_report_ok=$ProofReportPath"
