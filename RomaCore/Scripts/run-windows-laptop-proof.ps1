param(
    [string]$PackageDir = "",
    [string]$ProofDir = "",
    [string]$Endpoint = "",
    [string]$Model = "",
    [string]$ApiKeyEnv = "",
    [string]$ApiKeyName = "",
    [string]$SecretDir = "",
    [string]$PreflightReportPath = "",
    [string]$WhisperCLI = "",
    [string]$WhisperModel = "",
    [string]$WhisperOutputDir = "",
    [string[]]$WhisperArgument = @(),
    [string]$Language = "",
    [string]$Prompt = "",
    [string[]]$WordReplacement = @("just talk=roma-just-talk"),
    [string]$CloudExpectedTranscriptText = "cloud pre roll proof",
    [string]$LocalWhisperExpectedTranscriptText = "local whisper pre roll proof",
    [string]$StartupShortcutDir = "",
    [int]$HoldTimeoutSeconds = 15,
    [int]$RecordSeconds = 2,
    [double]$MicPreflightSeconds = 1,
    [switch]$PreflightOnly,
    [switch]$NativePreflightOnly,
    [switch]$RestoreClipboard,
    [switch]$NoRestoreClipboard,
    [double]$ClipboardRestoreDelaySeconds = 2
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$hasExplicitClipboardRestoreDelay = $PSBoundParameters.ContainsKey("ClipboardRestoreDelaySeconds")
$script:permissionPreflightOutput = ""
$script:hotkeyDeliveryPreflightOutput = ""
$script:microphonePreflightOutput = ""
$script:localWhisperPreflightOutput = ""

$proofCommonScript = Join-Path $PSScriptRoot "windows-proof-common.ps1"
if (!(Test-Path -LiteralPath $proofCommonScript)) {
    throw "Windows proof common helper was not found: $proofCommonScript"
}
. $proofCommonScript
Set-Alias -Name Invoke-Step -Value Invoke-RomaWindowsProofStep -Scope Local -Force
Set-Alias -Name Resolve-FullPath -Value Resolve-RomaWindowsFullPath -Scope Local -Force
Set-Alias -Name Require-File -Value Require-RomaWindowsFile -Scope Local -Force
Set-Alias -Name Assert-OutputContains -Value Assert-RomaWindowsOutputContains -Scope Local -Force

$packageIdentityScript = Join-Path $PSScriptRoot "windows-package-identity.ps1"
if (!(Test-Path -LiteralPath $packageIdentityScript)) {
    throw "Windows package identity helper was not found: $packageIdentityScript"
}
. $packageIdentityScript

$manifestScript = Join-Path $PSScriptRoot "windows-manifest.ps1"
if (!(Test-Path -LiteralPath $manifestScript)) {
    throw "Windows manifest helper was not found: $manifestScript"
}
. $manifestScript

function ConvertTo-PowerShellSingleQuotedString {
    param(
        [string]$Value = ""
    )

    return "'" + $Value.Replace("'", "''") + "'"
}

function Write-FullLaptopProofRecheckScript {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$PackageDir,
        [Parameter(Mandatory = $true)]
        [string]$LaptopPreflightReportPath,
        [Parameter(Mandatory = $true)]
        [string]$CloudDictationReportPath,
        [Parameter(Mandatory = $true)]
        [string]$LocalWhisperDictationReportPath,
        [Parameter(Mandatory = $true)]
        [string]$LocalWhisperNotepadPasteReportPath
    )

    $scriptLines = @(
        "param(",
        "    [string]`$PackageDir = $(ConvertTo-PowerShellSingleQuotedString -Value $PackageDir)",
        ")",
        "",
        '$ErrorActionPreference = "Stop"',
        "Set-StrictMode -Version Latest",
        "",
        '$manifestScript = Join-Path $PackageDir "windows-manifest.ps1"',
        'if (!(Test-Path -LiteralPath $manifestScript)) {',
        '    throw "Windows manifest helper was not found: $manifestScript"',
        '}',
        ". `$manifestScript",
        '$manifestPath = Join-Path $PackageDir "manifest.txt"',
        '$manifest = Read-RomaWindowsManifest -Path $manifestPath',
        '$proofCommonScript = Require-RomaWindowsManifestFile -Manifest $manifest -Key "proof_common_script" -BaseDir $PackageDir',
        ". `$proofCommonScript",
        '$checkSetScript = Require-RomaWindowsManifestFile -Manifest $manifest -Key "check_set_script" -BaseDir $PackageDir',
        "",
        "`$laptopPreflightReportPath = $(ConvertTo-PowerShellSingleQuotedString -Value $LaptopPreflightReportPath)",
        "`$cloudDictationReportPath = $(ConvertTo-PowerShellSingleQuotedString -Value $CloudDictationReportPath)",
        "`$localWhisperDictationReportPath = $(ConvertTo-PowerShellSingleQuotedString -Value $LocalWhisperDictationReportPath)",
        "`$localWhisperNotepadPasteReportPath = $(ConvertTo-PowerShellSingleQuotedString -Value $LocalWhisperNotepadPasteReportPath)",
        "",
        "`$proofSetOutput = & `$checkSetScript ``",
        "    -LaptopPreflightReportPath `$laptopPreflightReportPath ``",
        "    -CloudDictationReportPath `$cloudDictationReportPath ``",
        "    -LocalWhisperDictationReportPath `$localWhisperDictationReportPath ``",
        "    -LocalWhisperNotepadPasteReportPath `$localWhisperNotepadPasteReportPath ``",
        "    -RequireLaptopPreflight ``",
        "    -RequireFullLaptopProof 2>&1 | Out-String",
        "Write-Host `$proofSetOutput",
        "Assert-RomaWindowsFullLaptopProofSetOutput -Output `$proofSetOutput",
        'Write-Host "windows_laptop_recheck_ok=true"'
    )

    $scriptLines | Set-Content -LiteralPath $Path -Encoding UTF8
    Write-Host "windows_laptop_recheck_script=$Path"
}

function Write-NotepadPastePrompt {
    Write-Host ""
    Write-Host "ACTION_REQUIRED=local_whisper_notepad_paste"
    Write-Host "notepad=will_open_and_verify_file"
    Write-Host "manual_focus_required=false"
}

function Write-HotkeyDeliveryPreflightPrompt {
    Write-Host ""
    Write-Host "ACTION_REQUIRED=hotkey_delivery_preflight"
    Write-Host "hold_hotkey=Ctrl+Shift+R"
    Write-Host "press_and_release_hotkey=true"
    Write-Host "hold_timeout_seconds=$HoldTimeoutSeconds"
}

function Invoke-PermissionPreflight {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProofAgentPath
    )

    $output = & $ProofAgentPath windows-permission-doctor 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        Write-Host $output
        throw "RomaProofAgent windows-permission-doctor failed during laptop permission preflight"
    }

    Write-Host $output
    Assert-RomaWindowsMinimumPermissionOutput -Output $output
    Write-Host "permission_surface_preflight_ok=true"
    return $output
}

function Invoke-HotkeyDeliveryPreflight {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProofAgentPath,
        [Parameter(Mandatory = $true)]
        [int]$TimeoutSeconds
    )

    $output = & $ProofAgentPath windows-keyboard-hook-proof `
        --timeout "$TimeoutSeconds" 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        Write-Host $output
        throw "RomaProofAgent windows-keyboard-hook-proof failed during laptop hotkey preflight"
    }

    Write-Host $output
    Assert-OutputContains -Output $output -Expected "waiting_for_hold=Ctrl+Shift+R"
    Assert-OutputContains -Output $output -Expected "key_down=true"
    Assert-OutputContains -Output $output -Expected "key_up=true"
    Write-Host "hotkey_delivery_preflight_ok=true"
    return $output
}

function Invoke-MicrophonePreflight {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProofAgentPath,
        [Parameter(Mandatory = $true)]
        [string]$OutputPath,
        [Parameter(Mandatory = $true)]
        [double]$Seconds
    )

    $output = & $ProofAgentPath miniaudio-record-proof `
        --out $OutputPath `
        --seconds "$Seconds" 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        Write-Host $output
        throw "RomaProofAgent miniaudio-record-proof failed during laptop microphone preflight"
    }

    Write-Host $output
    Assert-OutputContains -Output $output -Expected "sample_rate=16000"
    Assert-OutputContains -Output $output -Expected "channels=1"
    $durationSeconds = Get-RomaWindowsOutputNumber -Output $output -Name "duration_seconds"
    if (($null -eq $durationSeconds) -or ($durationSeconds -le 0)) {
        throw "Laptop microphone preflight did not report positive duration_seconds"
    }
    $includedPreRollSeconds = Get-RomaWindowsOutputNumber -Output $output -Name "included_pre_roll_seconds"
    if (($null -eq $includedPreRollSeconds) -or ($includedPreRollSeconds -le 0)) {
        throw "Laptop microphone preflight did not report positive included_pre_roll_seconds"
    }
    Assert-RomaWindowsFileWithMinimumBytes `
        -Path $OutputPath `
        -MinimumBytes 45 `
        -WriteProofFileMarkers
    Write-Host "microphone_preflight_duration_seconds=$durationSeconds"
    Write-Host "microphone_preflight_included_pre_roll_seconds=$includedPreRollSeconds"
    Write-Host "microphone_preflight_wav=$OutputPath"
    Write-Host "microphone_preflight_ok=true"
    return $output
}

function Invoke-LocalWhisperPreflight {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProofAgentPath,
        [Parameter(Mandatory = $true)]
        [string]$WhisperCLIPath,
        [Parameter(Mandatory = $true)]
        [string]$WhisperModelPath,
        [string]$OutputDir = "",
        [string[]]$ExtraArguments = @()
    )

    $doctorArgs = @(
        "whisper-cli-doctor",
        "--whisper-cli", $WhisperCLIPath,
        "--whisper-model", $WhisperModelPath
    )
    if (![string]::IsNullOrWhiteSpace($OutputDir)) {
        $doctorArgs += @("--output-dir", $OutputDir)
    }
    foreach ($argument in $ExtraArguments) {
        if (![string]::IsNullOrWhiteSpace($argument)) {
            $doctorArgs += @("--whisper-arg", $argument)
        }
    }

    $output = & $ProofAgentPath @doctorArgs 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        Write-Host $output
        throw "RomaProofAgent whisper-cli-doctor failed during laptop preflight"
    }

    Write-Host $output
    Assert-OutputContains -Output $output -Expected "transcription_client=whisper.cpp-cli"
    Assert-OutputContains -Output $output -Expected "network_required=false"
    Assert-OutputContains -Output $output -Expected "executable="
    Assert-OutputContains -Output $output -Expected "model_file="
    Write-Host "local_whisper_preflight_cli=$WhisperCLIPath"
    Write-Host "local_whisper_preflight_model=$WhisperModelPath"
    Write-Host "local_whisper_preflight_ok=true"
    return $output
}

function Write-PreflightReport {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$ProofSessionId,
        [Parameter(Mandatory = $true)]
        [string]$ProofAgentPath,
        [Parameter(Mandatory = $true)]
        [string]$MicPreflightPath,
        [string]$WhisperCLIPath = "",
        [string]$WhisperModelPath = ""
    )

    $reportParent = Split-Path -Parent $Path
    if (![string]::IsNullOrWhiteSpace($reportParent)) {
        New-Item -ItemType Directory -Force -Path $reportParent | Out-Null
    }
    $hasLocalWhisperPreflight = ![string]::IsNullOrWhiteSpace($WhisperCLIPath) -and
        ![string]::IsNullOrWhiteSpace($WhisperModelPath)

    $report = New-RomaWindowsLaptopPreflightReport `
        -ProofSessionId $ProofSessionId `
        -PackageDir $PackageDir `
        -ProofDir $ProofDir `
        -Manifest $script:artifactManifest `
        -PackageIdentity (Get-RomaPackageIdentityProof -PackageDir $PackageDir) `
        -PreflightOutputs (New-RomaWindowsLaptopPreflightOutputProofs `
            -PermissionSurfaceOutput $script:permissionPreflightOutput `
            -HotkeyDeliveryOutput $script:hotkeyDeliveryPreflightOutput `
            -MicrophoneOutput $script:microphonePreflightOutput `
            -LocalWhisperOutput $script:localWhisperPreflightOutput) `
        -FileProofs ([ordered]@{
            proof_agent = Get-RomaWindowsFileProof -Path $ProofAgentPath
            mic_preflight_wav = Get-RomaWindowsFileProof -Path $MicPreflightPath
            whisper_cli = Get-RomaWindowsOptionalFileProof -Path $WhisperCLIPath
            whisper_model = Get-RomaWindowsOptionalFileProof -Path $WhisperModelPath
        }) `
        -IncludeLocalWhisper $hasLocalWhisperPreflight

    $report |
        ConvertTo-Json -Depth 8 |
        Set-Content -LiteralPath $Path -Encoding UTF8
    Write-Host "windows_laptop_preflight_report=$Path"
}

function Add-ShortcutProofArgs {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$ArgumentList,
        [Parameter(Mandatory = $true)]
        [string]$ShortcutDir,
        [string]$StartupDir = ""
    )

    $ArgumentList += @(
        "-CreateShortcut",
        "-ShortcutDir", $ShortcutDir,
        "-CreateStartupShortcut"
    )
    if (![string]::IsNullOrWhiteSpace($StartupDir)) {
        $ArgumentList += @("-StartupShortcutDir", $StartupDir)
    }

    return $ArgumentList
}

Assert-RomaWindowsAgentScriptCommonOptions `
    -PasteDictation $true `
    -RestoreClipboard $RestoreClipboard.IsPresent `
    -NoRestoreClipboard $NoRestoreClipboard.IsPresent `
    -HasClipboardRestoreDelay $hasExplicitClipboardRestoreDelay `
    -ClipboardRestoreDelaySeconds $ClipboardRestoreDelaySeconds

if ($MicPreflightSeconds -le 0) {
    throw "MicPreflightSeconds must be positive"
}

if ($NativePreflightOnly -and !$PreflightOnly) {
    throw "NativePreflightOnly can only be used with PreflightOnly"
}

if ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
    throw "Windows laptop proof must run on Windows"
}

if ([string]::IsNullOrWhiteSpace($PackageDir)) {
    $PackageDir = $PSScriptRoot
}
$PackageDir = Resolve-FullPath -Path $PackageDir

if ([string]::IsNullOrWhiteSpace($ProofDir)) {
    $ProofDir = Join-Path ([System.IO.Path]::GetTempPath()) "roma-windows-laptop-proof"
}
$ProofDir = Resolve-FullPath -Path $ProofDir
New-Item -ItemType Directory -Force -Path $ProofDir | Out-Null
if (![string]::IsNullOrWhiteSpace($StartupShortcutDir)) {
    $StartupShortcutDir = Resolve-FullPath -Path $StartupShortcutDir
}
if ([string]::IsNullOrWhiteSpace($PreflightReportPath)) {
    $PreflightReportPath = Join-Path $ProofDir "preflight-proof.json"
}
$PreflightReportPath = Resolve-FullPath -Path $PreflightReportPath

if (!$PreflightOnly) {
    if ([string]::IsNullOrWhiteSpace($Endpoint) -or
        [string]::IsNullOrWhiteSpace($Model)) {
        throw "Endpoint and Model are required for the cloud dictation proof"
    }

    if ([string]::IsNullOrWhiteSpace($ApiKeyEnv) -and
        [string]::IsNullOrWhiteSpace($ApiKeyName)) {
        throw "Cloud proof requires ApiKeyEnv or ApiKeyName"
    }
}

if (!$NativePreflightOnly -and (
    [string]::IsNullOrWhiteSpace($WhisperCLI) -or
    [string]::IsNullOrWhiteSpace($WhisperModel))) {
    throw "WhisperCLI and WhisperModel are required for local whisper laptop proof"
}
if (!$NativePreflightOnly) {
    $WhisperCLI = Resolve-FullPath -Path $WhisperCLI
    $WhisperModel = Resolve-FullPath -Path $WhisperModel
    Require-File -Path $WhisperCLI
    Require-File -Path $WhisperModel
}
$whisperArguments = @(
    $WhisperArgument |
        Where-Object { ![string]::IsNullOrWhiteSpace($_) }
)

$manifestPath = Join-Path $PackageDir "manifest.txt"
Require-File -Path $manifestPath
$script:artifactManifest = Read-RomaWindowsManifest -Path $manifestPath
$proofScript = Require-RomaWindowsManifestFile `
    -Manifest $script:artifactManifest `
    -Key "proof_script" `
    -BaseDir $PackageDir
$checkSetScript = Require-RomaWindowsManifestFile `
    -Manifest $script:artifactManifest `
    -Key "check_set_script" `
    -BaseDir $PackageDir
$proofAgent = Require-RomaWindowsManifestFile `
    -Manifest $script:artifactManifest `
    -Key "proof_agent" `
    -BaseDir $PackageDir
$packagedProofCommonScript = Require-RomaWindowsManifestFile `
    -Manifest $script:artifactManifest `
    -Key "proof_common_script" `
    -BaseDir $PackageDir

$proofSessionId = [guid]::NewGuid().ToString("D")

$cloudReport = Join-Path $ProofDir "cloud-dictation-proof.json"
$localWhisperDictationReport = Join-Path $ProofDir "local-whisper-dictation-proof.json"
$localWhisperNotepadReport = Join-Path $ProofDir "local-whisper-notepad-paste-proof.json"
$recheckScriptPath = Join-Path $ProofDir "recheck-full-laptop-proof.ps1"
$micPreflightPath = Join-Path $ProofDir "mic-preflight.wav"

$cloudInstallDir = Join-Path $ProofDir "cloud-install"
$cloudConfigPath = Join-Path $cloudInstallDir "windows-agent.json"
$localInstallDir = Join-Path $ProofDir "local-whisper-install"
$localConfigPath = Join-Path $localInstallDir "windows-agent.json"
$notepadInstallDir = Join-Path $ProofDir "local-whisper-notepad-install"
$notepadConfigPath = Join-Path $notepadInstallDir "windows-agent.json"
$startupShortcutBaseDir = $StartupShortcutDir
if ([string]::IsNullOrWhiteSpace($startupShortcutBaseDir)) {
    $startupShortcutBaseDir = Join-Path $ProofDir "startup-shortcuts"
}
$cloudStartupShortcutDir = Join-Path $startupShortcutBaseDir "cloud"
$localStartupShortcutDir = Join-Path $startupShortcutBaseDir "local-whisper"

Invoke-Step "permission surface preflight" {
    $script:permissionPreflightOutput = Invoke-PermissionPreflight -ProofAgentPath $proofAgent
}

Invoke-Step "hotkey delivery preflight" {
    Write-HotkeyDeliveryPreflightPrompt
    $script:hotkeyDeliveryPreflightOutput = Invoke-HotkeyDeliveryPreflight `
        -ProofAgentPath $proofAgent `
        -TimeoutSeconds $HoldTimeoutSeconds
}

Invoke-Step "microphone preflight" {
    $script:microphonePreflightOutput = Invoke-MicrophonePreflight `
        -ProofAgentPath $proofAgent `
        -OutputPath $micPreflightPath `
        -Seconds $MicPreflightSeconds
}

if ($NativePreflightOnly) {
    Write-Host ""
    Write-Host "== local whisper CLI preflight skipped =="
    Write-Host "native_preflight_only=true"
} else {
    Invoke-Step "local whisper CLI preflight" {
        $preflightOutputDir = ""
        if (![string]::IsNullOrWhiteSpace($WhisperOutputDir)) {
            $preflightOutputDir = Resolve-FullPath -Path $WhisperOutputDir
        }
        $script:localWhisperPreflightOutput = Invoke-LocalWhisperPreflight `
            -ProofAgentPath $proofAgent `
            -WhisperCLIPath $WhisperCLI `
            -WhisperModelPath $WhisperModel `
            -OutputDir $preflightOutputDir `
            -ExtraArguments $whisperArguments
    }
}

Write-PreflightReport `
    -Path $PreflightReportPath `
    -ProofSessionId $proofSessionId `
    -ProofAgentPath $proofAgent `
    -MicPreflightPath $micPreflightPath `
    -WhisperCLIPath $WhisperCLI `
    -WhisperModelPath $WhisperModel

if ($PreflightOnly) {
    & $checkSetScript `
        -LaptopPreflightReportPath $PreflightReportPath `
        -RequireLaptopPreflight
    Write-Host ""
    Write-Host "windows_laptop_proof_dir=$ProofDir"
    Write-Host "windows_laptop_proof_session_id=$proofSessionId"
    Write-Host "windows_laptop_permission_preflight=true"
    Write-Host "windows_laptop_hotkey_delivery_preflight=true"
    Write-Host "windows_laptop_mic_preflight=$micPreflightPath"
    Write-Host "windows_laptop_local_whisper_preflight=$(!$NativePreflightOnly)"
    Write-Host "windows_laptop_preflight_only=true"
    Write-Host "windows_laptop_preflight_ok=true"
    exit 0
}

$cloudArgs = @(
    "-PackageDir", $PackageDir,
    "-InstallDir", $cloudInstallDir,
    "-ConfigPath", $cloudConfigPath,
    "-ProofReportPath", $cloudReport,
    "-ProofSessionId", $proofSessionId,
    "-Endpoint", $Endpoint,
    "-Model", $Model
)
if (![string]::IsNullOrWhiteSpace($ApiKeyEnv)) {
    $cloudArgs += @("-ApiKeyEnv", $ApiKeyEnv)
}
if (![string]::IsNullOrWhiteSpace($ApiKeyName)) {
    $cloudArgs += @("-ApiKeyName", $ApiKeyName)
}
if (![string]::IsNullOrWhiteSpace($SecretDir)) {
    $cloudArgs += @("-SecretDir", (Resolve-FullPath -Path $SecretDir))
}
if (![string]::IsNullOrWhiteSpace($CloudExpectedTranscriptText)) {
    $cloudArgs += @("-ExpectedTranscriptText", $CloudExpectedTranscriptText)
}
$cloudArgs = Add-RomaWindowsAgentScriptCommonArgs `
    -ArgumentList $cloudArgs `
    -Language $Language `
    -Prompt $Prompt `
    -WordReplacement $WordReplacement `
    -UseHoldHook $true `
    -HoldTimeoutSeconds $HoldTimeoutSeconds `
    -RecordSeconds $RecordSeconds `
    -RestoreClipboard $RestoreClipboard.IsPresent `
    -NoRestoreClipboard $NoRestoreClipboard.IsPresent `
    -HasClipboardRestoreDelay $hasExplicitClipboardRestoreDelay `
    -ClipboardRestoreDelaySeconds $ClipboardRestoreDelaySeconds
$cloudArgs += @("-RunDictation", "-PasteDictation")
$cloudArgs = Add-ShortcutProofArgs `
    -ArgumentList $cloudArgs `
    -ShortcutDir (Join-Path $ProofDir "cloud-shortcuts") `
    -StartupDir $cloudStartupShortcutDir

$localArgs = @(
    "-PackageDir", $PackageDir,
    "-InstallDir", $localInstallDir,
    "-ConfigPath", $localConfigPath,
    "-ProofReportPath", $localWhisperDictationReport,
    "-ProofSessionId", $proofSessionId,
    "-WhisperCLI", $WhisperCLI,
    "-WhisperModel", $WhisperModel
)
if (![string]::IsNullOrWhiteSpace($WhisperOutputDir)) {
    $localArgs += @("-WhisperOutputDir", (Resolve-FullPath -Path $WhisperOutputDir))
}
if ($whisperArguments.Count -gt 0) {
    $localArgs += "-WhisperArgument"
    $localArgs += $whisperArguments
}
if (![string]::IsNullOrWhiteSpace($LocalWhisperExpectedTranscriptText)) {
    $localArgs += @("-ExpectedTranscriptText", $LocalWhisperExpectedTranscriptText)
}
$localArgs = Add-RomaWindowsAgentScriptCommonArgs `
    -ArgumentList $localArgs `
    -Language $Language `
    -Prompt $Prompt `
    -WordReplacement $WordReplacement `
    -UseHoldHook $true `
    -HoldTimeoutSeconds $HoldTimeoutSeconds `
    -RecordSeconds $RecordSeconds `
    -RestoreClipboard $RestoreClipboard.IsPresent `
    -NoRestoreClipboard $NoRestoreClipboard.IsPresent `
    -HasClipboardRestoreDelay $hasExplicitClipboardRestoreDelay `
    -ClipboardRestoreDelaySeconds $ClipboardRestoreDelaySeconds
$localArgs += @("-RunDictation", "-PasteDictation")
$localArgs += "-RunListenerProof"
$localArgs = Add-ShortcutProofArgs `
    -ArgumentList $localArgs `
    -ShortcutDir (Join-Path $ProofDir "local-whisper-shortcuts") `
    -StartupDir $localStartupShortcutDir

$notepadArgs = @(
    "-PackageDir", $PackageDir,
    "-InstallDir", $notepadInstallDir,
    "-ConfigPath", $notepadConfigPath,
    "-ProofReportPath", $localWhisperNotepadReport,
    "-ProofSessionId", $proofSessionId,
    "-WhisperCLI", $WhisperCLI,
    "-WhisperModel", $WhisperModel,
    "-RunNotepadPasteProof"
)
if (![string]::IsNullOrWhiteSpace($WhisperOutputDir)) {
    $notepadArgs += @("-WhisperOutputDir", (Resolve-FullPath -Path $WhisperOutputDir))
}
if ($whisperArguments.Count -gt 0) {
    $notepadArgs += "-WhisperArgument"
    $notepadArgs += $whisperArguments
}
$notepadArgs = Add-RomaWindowsAgentScriptCommonArgs `
    -ArgumentList $notepadArgs `
    -Language $Language `
    -Prompt $Prompt `
    -WordReplacement $WordReplacement `
    -UseHoldHook $true `
    -HoldTimeoutSeconds $HoldTimeoutSeconds `
    -RecordSeconds $RecordSeconds `
    -RestoreClipboard $RestoreClipboard.IsPresent `
    -NoRestoreClipboard $NoRestoreClipboard.IsPresent `
    -HasClipboardRestoreDelay $hasExplicitClipboardRestoreDelay `
    -ClipboardRestoreDelaySeconds $ClipboardRestoreDelaySeconds

Invoke-Step "cloud dictation laptop proof" {
    Write-RomaWindowsHoldDictationPrompt `
        -Name "cloud_dictation" `
        -ExpectedTranscriptText $CloudExpectedTranscriptText `
        -HoldTimeoutSeconds $HoldTimeoutSeconds
    & $proofScript @cloudArgs
}

Invoke-Step "local whisper dictation laptop proof" {
    Write-RomaWindowsHoldDictationPrompt `
        -Name "local_whisper_dictation" `
        -ExpectedTranscriptText $LocalWhisperExpectedTranscriptText `
        -HoldTimeoutSeconds $HoldTimeoutSeconds
    & $proofScript @localArgs
}

Invoke-Step "local whisper Notepad paste proof" {
    Write-NotepadPastePrompt
    & $proofScript @notepadArgs
}

Invoke-Step "full laptop proof set check" {
    & $checkSetScript `
        -LaptopPreflightReportPath $PreflightReportPath `
        -CloudDictationReportPath $cloudReport `
        -LocalWhisperDictationReportPath $localWhisperDictationReport `
        -LocalWhisperNotepadPasteReportPath $localWhisperNotepadReport `
        -RequireLaptopPreflight `
        -RequireFullLaptopProof
}

Invoke-Step "write full laptop proof recheck" {
    Write-FullLaptopProofRecheckScript `
        -Path $recheckScriptPath `
        -PackageDir $PackageDir `
        -LaptopPreflightReportPath $PreflightReportPath `
        -CloudDictationReportPath $cloudReport `
        -LocalWhisperDictationReportPath $localWhisperDictationReport `
        -LocalWhisperNotepadPasteReportPath $localWhisperNotepadReport
}

Write-Host ""
Write-Host "windows_laptop_proof_dir=$ProofDir"
Write-Host "windows_laptop_proof_session_id=$proofSessionId"
Write-Host "windows_laptop_startup_shortcut_base_dir=$startupShortcutBaseDir"
Write-Host "windows_laptop_permission_preflight=true"
Write-Host "windows_laptop_hotkey_delivery_preflight=true"
Write-Host "windows_laptop_mic_preflight=$micPreflightPath"
Write-Host "windows_laptop_preflight_report=$PreflightReportPath"
Write-Host "windows_laptop_cloud_report=$cloudReport"
Write-Host "windows_laptop_local_whisper_report=$localWhisperDictationReport"
Write-Host "windows_laptop_notepad_report=$localWhisperNotepadReport"
Write-Host "windows_laptop_recheck_script=$recheckScriptPath"
Write-Host "windows_laptop_proof_ok=true"
