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
