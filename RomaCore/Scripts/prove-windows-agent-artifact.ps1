param(
    [string]$PackageDir = "",
    [string]$InstallDir = "",
    [string]$ConfigPath = "",
    [string]$ProofReportPath = "",
    [string]$ProofSessionId = "",
    [string]$Endpoint = "",
    [string]$Model = "",
    [string]$ApiKeyEnv = "",
    [string]$ApiKeyName = "",
    [string]$SecretDir = "",
    [string]$WhisperCLI = "",
    [string]$WhisperModel = "",
    [string]$WhisperOutputDir = "",
    [string[]]$WhisperArgument = @(),
    [string]$Language = "",
    [string]$Prompt = "",
    [string[]]$WordReplacement = @("just talk=roma-just-talk"),
    [string]$ExpectedTranscriptText = "",
    [switch]$UseHoldHook,
    [switch]$UseToggle,
    [int]$HoldTimeoutSeconds = 15,
    [int]$RecordSeconds = 2,
    [switch]$PasteDictation,
    [switch]$RestoreClipboard,
    [switch]$NoRestoreClipboard,
    [double]$ClipboardRestoreDelaySeconds = 2,
    [switch]$UsePackagedWhisperMock,
    [switch]$RunDictation,
    [switch]$RunListenerProof,
    [switch]$CreateShortcut,
    [switch]$CreateStartupShortcut,
    [string]$ShortcutDir = "",
    [string]$StartupShortcutDir = "",
    [switch]$RunNotepadPasteProof,
    [string]$NotepadPasteProofPath = "",
    [string]$PasteProofText = "roma just talk proof",
    [switch]$DoctorOnly
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$proofCommonScript = Join-Path $PSScriptRoot "windows-proof-common.ps1"
if (!(Test-Path -LiteralPath $proofCommonScript)) {
    throw "Windows proof common helper was not found: $proofCommonScript"
}
. $proofCommonScript
Set-Alias -Name Invoke-Step -Value Invoke-RomaWindowsProofStep -Scope Local -Force
Set-Alias -Name Resolve-FullPath -Value Resolve-RomaWindowsFullPath -Scope Local -Force
Set-Alias -Name Require-File -Value Require-RomaWindowsFile -Scope Local -Force
Set-Alias -Name Assert-OutputContains -Value Assert-RomaWindowsOutputContains -Scope Local -Force
Set-Alias -Name Get-OutputValue -Value Get-RomaWindowsOutputValue -Scope Local -Force
Set-Alias -Name Get-OutputNumber -Value Get-RomaWindowsOutputNumber -Scope Local -Force
Set-Alias -Name Get-OutputLineNumber -Value Get-RomaWindowsOutputLineNumber -Scope Local -Force

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

function Invoke-ProofAgentDoctorCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$Command
    )

    Write-Host ""
    Write-Host "-- $Name --"
    $output = & $script:proofAgentPath $Command 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        Write-Host $output
        throw "RomaProofAgent $Command failed"
    }

    Write-Host $output
    return $output
}

function Invoke-PackagedListenerSmoke {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath
    )

    $output = & $agentPath listen `
        --config $ConfigPath `
        --max-sessions 0 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        Write-Host $output
        throw "RomaWindowsAgent listen smoke failed"
    }

    Write-Host $output
    Assert-RomaWindowsListenerSmokeOutput -Output $output
    return $output
}

function Invoke-InstalledListenerSmoke {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RunScriptPath,
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath
    )

    $output = & $RunScriptPath `
        -InstallDir $InstallDir `
        -ConfigPath $ConfigPath `
        -Listen `
        -MaxSessions 0 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        Write-Host $output
        throw "Installed launcher listen smoke failed"
    }

    Write-Host $output
    Assert-RomaWindowsListenerSmokeOutput -Output $output -RequireLauncherMode $true
    return $output
}

function Invoke-InstalledListenerRuntimeProof {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RunScriptPath,
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath
    )

    $logDir = Join-Path $InstallDir "smoke"
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    $logPath = Join-Path $logDir "windows-agent-listen.log"

    Write-RomaWindowsHoldDictationPrompt `
        -Name "installed_listener_runtime" `
        -ExpectedTranscriptText $ExpectedTranscriptText `
        -ListenerSessionCount 1

    $output = & $RunScriptPath `
        -InstallDir $InstallDir `
        -ConfigPath $ConfigPath `
        -Listen `
        -MaxSessions 1 2>&1 | Out-String
    Set-Content -LiteralPath $logPath -Encoding UTF8 -Value $output
    if ($LASTEXITCODE -ne 0) {
        Write-Host $output
        throw "Installed launcher listener runtime proof failed"
    }

    Write-Host $output
    Assert-RomaWindowsListenerRuntimeLogOutput -Output $output
    Write-Host "installed_listener_runtime_log=$logPath"
    Write-Host "installed_listener_runtime_ok=true"
    return $output
}

function Invoke-ConfigDoctor {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AgentPath,
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath
    )

    Require-File -Path $AgentPath
    Require-File -Path $ConfigPath
    $output = & $AgentPath config-doctor --config $ConfigPath 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        Write-Host $output
        throw "RomaWindowsAgent config-doctor failed"
    }

    Write-Host $output
    Assert-RomaWindowsConfigDoctorOutput -Output $output
    return $output
}

function Invoke-NotepadPasteProof {
    $proof = New-RomaWindowsNotepadPasteProof `
        -Requested $RunNotepadPasteProof.IsPresent `
        -Text $PasteProofText `
        -Path $NotepadPasteProofPath
    if (!$RunNotepadPasteProof) {
        return $proof
    }

    if ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
        throw "RunNotepadPasteProof requires Windows"
    }
    if ([string]::IsNullOrWhiteSpace($PasteProofText)) {
        throw "PasteProofText must not be empty"
    }

    $notepadParent = Split-Path -Parent $NotepadPasteProofPath
    if (![string]::IsNullOrWhiteSpace($notepadParent)) {
        New-Item -ItemType Directory -Force -Path $notepadParent | Out-Null
    }
    Set-Content -LiteralPath $NotepadPasteProofPath -Encoding UTF8 -NoNewline -Value ""

    $notepad = Start-Process `
        -FilePath "notepad.exe" `
        -ArgumentList @("`"$NotepadPasteProofPath`"") `
        -PassThru

    try {
        Wait-RomaWindowsProcessMainWindow -Process $notepad
        $proof["target_process_id"] = $notepad.Id
        $pasteOutput = & $script:proofAgentPath windows-paste-proof `
            --text $PasteProofText `
            --target-process-id $notepad.Id 2>&1 | Out-String
        $proof["output_present"] = ![string]::IsNullOrWhiteSpace($pasteOutput)
        Write-Host $pasteOutput
        if ($LASTEXITCODE -ne 0) {
            throw "RomaProofAgent windows-paste-proof failed for Notepad"
        }
        Assert-OutputContains -Output $pasteOutput -Expected "target_process_id=$($notepad.Id)"
        Assert-OutputContains -Output $pasteOutput -Expected "paste_sent=true"
        $proof["paste_sent"] = $true

        $shell = Set-RomaWindowsProcessForeground -Process $notepad
        $shell.SendKeys("^s")
        Start-Sleep -Milliseconds 750

        $savedText = Get-Content -LiteralPath $NotepadPasteProofPath -Raw
        $proof["text_found"] = $savedText.Contains($PasteProofText)
        if (!$proof["text_found"]) {
            throw "Notepad file did not contain pasted proof text: $NotepadPasteProofPath"
        }

        $proof["verified"] = $true
        $proof["file"] = Get-RomaWindowsFileProof -Path $NotepadPasteProofPath
        Write-Host "notepad_paste_file=$NotepadPasteProofPath"
        Write-Host "notepad_paste_verified=true"
        return $proof
    } finally {
        if ($null -ne $notepad) {
            $notepad.Refresh()
            if (!$notepad.HasExited) {
                $null = $notepad.CloseMainWindow()
                Start-Sleep -Milliseconds 500
                $notepad.Refresh()
            }
            if (!$notepad.HasExited) {
                Stop-Process -Id $notepad.Id -Force
            }
        }
    }
}

function Get-DictationRuntimeProof {
    return Get-RomaWindowsDictationRuntimeLogProof `
        -LogPath (Join-Path (Join-Path $InstallDir "smoke") "windows-agent-dictate.log") `
        -ExpectedText $ExpectedTranscriptText
}

function Get-ListenerRuntimeProof {
    return Get-RomaWindowsListenerRuntimeLogProof `
        -LogPath (Join-Path (Join-Path $InstallDir "smoke") "windows-agent-listen.log") `
        -ExpectedText $ExpectedTranscriptText
}

function Write-ProofReport {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Mode,
        [Parameter(Mandatory = $true)]
        [bool]$IsDoctorOnly
    )

    if ([string]::IsNullOrWhiteSpace($ProofReportPath)) {
        return
    }

    $reportParent = Split-Path -Parent $ProofReportPath
    if (![string]::IsNullOrWhiteSpace($reportParent)) {
        New-Item -ItemType Directory -Force -Path $reportParent | Out-Null
    }

    $shortcutPath = ""
    if (![string]::IsNullOrWhiteSpace($ShortcutDir)) {
        $shortcutPath = Join-Path $ShortcutDir "Roma Just Talk Agent.lnk"
    }
    $startupShortcutPath = ""
    if (![string]::IsNullOrWhiteSpace($StartupShortcutDir)) {
        $startupShortcutPath = Join-Path $StartupShortcutDir "Roma Just Talk Agent.lnk"
    } elseif ($CreateStartupShortcut) {
        $startup = [System.Environment]::GetFolderPath("Startup")
        if (![string]::IsNullOrWhiteSpace($startup)) {
            $startupShortcutPath = Join-Path $startup "Roma Just Talk Agent.lnk"
        }
    }
    $installedRunScriptPath = Join-Path $InstallDir "run-windows-agent.ps1"
    $fileProofs = Get-RomaWindowsAgentArtifactFileProofs `
        -AgentPath $agentPath `
        -ProofAgentPath $script:proofAgentPath `
        -WhisperCLIMockPath $script:packagedWhisperCLI `
        -InstallDir $InstallDir

    $report = [ordered]@{
        generated_at = (Get-Date).ToUniversalTime().ToString("o")
        proof_session_id = $ProofSessionId
        proof_mode = $Mode
        doctor_only = $IsDoctorOnly
        run_dictation = $RunDictation.IsPresent
        run_listener_proof = $RunListenerProof.IsPresent
        paste_dictation = $PasteDictation.IsPresent
        expected_transcript_text = $ExpectedTranscriptText
        create_shortcut = $CreateShortcut.IsPresent
        create_startup_shortcut = $CreateStartupShortcut.IsPresent
        restore_clipboard = $RestoreClipboard.IsPresent
        no_restore_clipboard = $NoRestoreClipboard.IsPresent
        os = Get-RomaWindowsOSReportProof
        package_dir = $PackageDir
        install_dir = $InstallDir
        config = (Get-RomaWindowsAgentConfigFileProof -ConfigPath $ConfigPath)
        doctor = [ordered]@{
            packaged_agent = (Get-RomaWindowsAgentDoctorOutputProof -Output $script:packagedAgentDoctorOutput)
            packaged_proof_agent = (Get-RomaWindowsProofAgentDoctorOutputProof -Output $script:packagedProofAgentDoctorOutput)
            packaged_native_doctors = (Get-RomaWindowsNativeDoctorOutputProofs -Outputs $script:packagedNativeDoctorOutputs)
            installed_launcher = (Get-RomaWindowsAgentDoctorOutputProof -Output $script:installedLauncherDoctorOutput)
        }
        packaged_listener = (Get-RomaWindowsListenerSmokeOutputProof -Output $script:packagedListenerOutput)
        installed_listener = (Get-RomaWindowsInstalledListenerSmokeOutputProof -Output $script:installedListenerOutput)
        config_doctor = (Get-RomaWindowsConfigDoctorOutputProof -Output $script:installedConfigDoctorOutput)
        files = $fileProofs
        manifest = $script:artifactManifest
        package_identity = (Get-RomaPackageIdentityProof -PackageDir $PackageDir)
        installed_script_parse = (Get-RomaWindowsScriptParseOutputProof -Output $script:installedScriptParseOutput)
    }
    if (![string]::IsNullOrWhiteSpace($shortcutPath)) {
        $report["shortcut"] = Get-RomaWindowsShortcutProof `
            -Path $shortcutPath `
            -RunScriptPath $installedRunScriptPath `
            -ConfigPath $ConfigPath `
            -WorkingDirectory $InstallDir
    }
    if (![string]::IsNullOrWhiteSpace($startupShortcutPath)) {
        $report["startup_shortcut"] = Get-RomaWindowsShortcutProof `
            -Path $startupShortcutPath `
            -RunScriptPath $installedRunScriptPath `
            -ConfigPath $ConfigPath `
            -WorkingDirectory $InstallDir
    }
    if ($RunDictation) {
        $report["dictation_runtime"] = Get-DictationRuntimeProof
    }
    if ($RunListenerProof) {
        $report["listener_runtime"] = Get-ListenerRuntimeProof
    }
    if ($RunNotepadPasteProof) {
        $report["notepad_paste"] = $script:notepadPasteProof
    }

    $report |
        ConvertTo-Json -Depth 8 |
        Set-Content -LiteralPath $ProofReportPath -Encoding UTF8
    Write-Host "proof_report=$ProofReportPath"
}

$hasExplicitClipboardRestoreDelay = $PSBoundParameters.ContainsKey("ClipboardRestoreDelaySeconds")

Assert-RomaWindowsAgentScriptCommonOptions `
    -UseHoldHook $UseHoldHook.IsPresent `
    -UseToggle $UseToggle.IsPresent `
    -PasteDictation $PasteDictation.IsPresent `
    -RestoreClipboard $RestoreClipboard.IsPresent `
    -NoRestoreClipboard $NoRestoreClipboard.IsPresent `
    -HasClipboardRestoreDelay $hasExplicitClipboardRestoreDelay `
    -ClipboardRestoreDelaySeconds $ClipboardRestoreDelaySeconds

if ([string]::IsNullOrWhiteSpace($PackageDir)) {
    $PackageDir = $PSScriptRoot
}
$PackageDir = Resolve-FullPath -Path $PackageDir

if ([string]::IsNullOrWhiteSpace($InstallDir)) {
    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        throw "LOCALAPPDATA is not set; pass -InstallDir explicitly"
    }
    $InstallDir = Join-Path $env:LOCALAPPDATA "roma-just-talk\agent"
}
$InstallDir = Resolve-FullPath -Path $InstallDir

if (![string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Resolve-FullPath -Path $ConfigPath
}
if (![string]::IsNullOrWhiteSpace($ProofReportPath)) {
    $ProofReportPath = Resolve-FullPath -Path $ProofReportPath
}
if ([string]::IsNullOrWhiteSpace($NotepadPasteProofPath)) {
    $NotepadPasteProofPath = Join-Path $InstallDir "smoke\notepad-paste-proof.txt"
}
$NotepadPasteProofPath = Resolve-FullPath -Path $NotepadPasteProofPath

$agentPath = Join-Path $PackageDir "RomaWindowsAgent.exe"
$script:proofAgentPath = Join-Path $PackageDir "RomaProofAgent.exe"
$smokeScript = Join-Path $PackageDir "smoke-windows-agent.ps1"
$installScript = Join-Path $PackageDir "install-windows-agent.ps1"
$runScript = Join-Path $PackageDir "run-windows-agent.ps1"
$proofScript = Join-Path $PackageDir "prove-windows-agent-artifact.ps1"
$laptopProofScript = Join-Path $PackageDir "run-windows-laptop-proof.ps1"
$parseScript = Join-Path $PackageDir "check-windows-scripts-parse.ps1"
$packagedProofCommonScript = Join-Path $PackageDir "windows-proof-common.ps1"
$checkReportScript = Join-Path $PackageDir "check-windows-proof-report.ps1"
$checkSetScript = Join-Path $PackageDir "check-windows-proof-set.ps1"
$manifestPath = Join-Path $PackageDir "manifest.txt"
$script:artifactManifest = @{}
$script:packagedWhisperCLI = ""
$script:packagedAgentDoctorOutput = ""
$script:packagedProofAgentDoctorOutput = ""
$script:packagedListenerOutput = ""
$script:installedListenerOutput = ""
$script:installedScriptParseOutput = ""
$script:installedConfigDoctorOutput = ""
$script:packagedNativeDoctorOutputs = New-RomaWindowsNativeDoctorOutputTable
$script:installedLauncherDoctorOutput = ""
$script:notepadPasteProof = New-RomaWindowsNotepadPasteProof `
    -Requested $RunNotepadPasteProof.IsPresent `
    -Text $PasteProofText `
    -Path $NotepadPasteProofPath

Invoke-Step "artifact files" {
    Require-File -Path $agentPath
    Require-File -Path $script:proofAgentPath
    Require-File -Path $smokeScript
    Require-File -Path $installScript
    Require-File -Path $runScript
    Require-File -Path $proofScript
    Require-File -Path $laptopProofScript
    Require-File -Path $parseScript
    Require-File -Path $packagedProofCommonScript
    Require-File -Path $checkReportScript
    Require-File -Path $checkSetScript
    Require-File -Path $manifestPath

    if ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT) {
        Require-File -Path (Join-Path $PackageDir "swiftCore.dll")
    }
}

Invoke-Step "artifact manifest" {
    $script:artifactManifest = Read-RomaWindowsManifest -Path $manifestPath
    foreach ($key in @(
        "agent",
        "output",
        "proof_agent",
        "whisper_cli_mock",
        "smoke_script",
        "run_script",
        "install_script",
        "proof_script",
        "laptop_proof_script",
        "parse_script",
        "check_report_script",
        "check_set_script",
        "install_proof_config",
        "install_proof_shortcut",
        "local_whisper_install_config",
        "local_whisper_shortcut",
        "proof_common_script",
        "manifest_script",
        "package_identity_script",
        "swift_runtime_dlls"
    )) {
        Require-RomaWindowsManifestKey -Manifest $script:artifactManifest -Key $key
    }
    $script:packagedWhisperCLI = Require-RomaWindowsManifestFile `
        -Manifest $script:artifactManifest `
        -Key "whisper_cli_mock" `
        -BaseDir $PackageDir
    Write-Host "manifest_whisper_cli_mock_path=$script:packagedWhisperCLI"
    $script:proofAgentPath = Require-RomaWindowsManifestFile `
        -Manifest $script:artifactManifest `
        -Key "proof_agent" `
        -BaseDir $PackageDir
    Write-Host "manifest_proof_agent_path=$script:proofAgentPath"
}

if ($UsePackagedWhisperMock) {
    if (![string]::IsNullOrWhiteSpace($WhisperCLI) -or
        ![string]::IsNullOrWhiteSpace($WhisperModel) -or
        ![string]::IsNullOrWhiteSpace($Endpoint) -or
        ![string]::IsNullOrWhiteSpace($Model)) {
        throw "UsePackagedWhisperMock cannot be combined with explicit WhisperCLI/WhisperModel or Endpoint/Model"
    }

    $WhisperCLI = $script:packagedWhisperCLI
    $WhisperModel = $agentPath
    Write-Host "packaged_whisper_cli=$WhisperCLI"
    Write-Host "packaged_whisper_model=$WhisperModel"
}

Invoke-Step "packaged agent doctor" {
    $script:packagedAgentDoctorOutput = & $agentPath doctor 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        Write-Host $script:packagedAgentDoctorOutput
        throw "RomaWindowsAgent doctor failed"
    }
    Write-Host $script:packagedAgentDoctorOutput
    Assert-RomaWindowsAgentDoctorOutput `
        -Output $script:packagedAgentDoctorOutput `
        -RequireRuntimeAvailable
}

Invoke-Step "packaged proof agent doctor" {
    $script:packagedProofAgentDoctorOutput = & $script:proofAgentPath doctor 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        Write-Host $script:packagedProofAgentDoctorOutput
        throw "RomaProofAgent doctor failed"
    }
    Write-Host $script:packagedProofAgentDoctorOutput
    Assert-RomaWindowsProofAgentDoctorOutput `
        -Output $script:packagedProofAgentDoctorOutput `
        -RequireNativeWindowsAdapters
}

Invoke-Step "packaged listener smoke" {
    $script:packagedListenerOutput = Invoke-PackagedListenerSmoke -ConfigPath (Join-Path $PackageDir "sample-windows-agent.json")
}

Invoke-Step "packaged native proof doctors" {
    $nativeDoctorSpecs = Get-RomaWindowsNativeDoctorSpecs
    foreach ($doctorName in $nativeDoctorSpecs.Keys) {
        $doctorSpec = $nativeDoctorSpecs[$doctorName]
        $script:packagedNativeDoctorOutputs[$doctorName] = Invoke-ProofAgentDoctorCommand `
            -Name ([string]$doctorSpec["label"]) `
            -Command ([string]$doctorSpec["command"])
        Assert-RomaWindowsNativeDoctorOutput `
            -Output ($script:packagedNativeDoctorOutputs[$doctorName]) `
            -Name $doctorName
    }
}

if ($DoctorOnly) {
    Write-ProofReport `
        -Mode (Get-RomaWindowsProofProfileExpectedModeByName -Name "doctor_only") `
        -IsDoctorOnly $true
    Write-Host ""
    Write-Host "artifact_doctor_only=true"
    exit 0
}

$hasEndpoint = ![string]::IsNullOrWhiteSpace($Endpoint)
$hasModel = ![string]::IsNullOrWhiteSpace($Model)
$hasWhisperCLI = ![string]::IsNullOrWhiteSpace($WhisperCLI)
$hasWhisperModel = ![string]::IsNullOrWhiteSpace($WhisperModel)
$usesCloud = $hasEndpoint -or $hasModel
$usesWhisper = $hasWhisperCLI -or $hasWhisperModel

if ($usesCloud -and $usesWhisper) {
    throw "Endpoint/Model and WhisperCLI/WhisperModel are mutually exclusive"
}

if ($usesCloud -and (!$hasEndpoint -or !$hasModel)) {
    throw "Endpoint and Model must be provided together"
}

if ($usesWhisper -and (!$hasWhisperCLI -or !$hasWhisperModel)) {
    throw "WhisperCLI and WhisperModel must be provided together"
}

if (!$usesCloud -and !$usesWhisper) {
    throw "Pass cloud Endpoint/Model/API key, local WhisperCLI/WhisperModel, or -UsePackagedWhisperMock"
}

if ($usesCloud -and
    [string]::IsNullOrWhiteSpace($ApiKeyEnv) -and
    [string]::IsNullOrWhiteSpace($ApiKeyName)) {
    throw "Cloud proof requires ApiKeyEnv or ApiKeyName"
}

$proofModeProfileName = if ($UsePackagedWhisperMock) {
    "packaged_whisper_mock_install"
} elseif ($usesWhisper -and $RunNotepadPasteProof) {
    "local_whisper_notepad_paste"
} elseif ($usesWhisper) {
    "local_whisper_dictation"
} else {
    "cloud_dictation"
}
$proofMode = Get-RomaWindowsProofProfileExpectedModeByName -Name $proofModeProfileName

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    if (($usesCloud -or $usesWhisper -or $RunDictation) -and
        ![string]::IsNullOrWhiteSpace($env:APPDATA)) {
        $ConfigPath = Join-Path $env:APPDATA "roma-just-talk\windows-agent.json"
    } else {
        $ConfigPath = Join-Path $InstallDir "smoke\windows-agent-smoke.json"
    }
    $ConfigPath = Resolve-FullPath -Path $ConfigPath
}

$installArgs = @(
    "-PackageDir", $PackageDir,
    "-InstallDir", $InstallDir
)
if (![string]::IsNullOrWhiteSpace($ConfigPath)) {
    $installArgs += @("-ConfigPath", $ConfigPath)
}
if ($usesWhisper) {
    $installArgs += @("-WhisperCLI", $WhisperCLI, "-WhisperModel", $WhisperModel)
    if (![string]::IsNullOrWhiteSpace($WhisperOutputDir)) {
        $installArgs += @("-WhisperOutputDir", $WhisperOutputDir)
    }
    $whisperArguments = @(
        $WhisperArgument |
            Where-Object { ![string]::IsNullOrWhiteSpace($_) }
    )
    if ($whisperArguments.Count -gt 0) {
        $installArgs += "-WhisperArgument"
        $installArgs += $whisperArguments
    }
} else {
    $installArgs += @("-Endpoint", $Endpoint, "-Model", $Model)
    if (![string]::IsNullOrWhiteSpace($ApiKeyEnv)) {
        $installArgs += @("-ApiKeyEnv", $ApiKeyEnv)
    }
    if (![string]::IsNullOrWhiteSpace($ApiKeyName)) {
        $installArgs += @("-ApiKeyName", $ApiKeyName)
    }
    if (![string]::IsNullOrWhiteSpace($SecretDir)) {
        $installArgs += @("-SecretDir", $SecretDir)
    }
}
$installArgs = Add-RomaWindowsAgentScriptCommonArgs `
    -ArgumentList $installArgs `
    -Language $Language `
    -Prompt $Prompt `
    -WordReplacement $WordReplacement `
    -UseHoldHook $UseHoldHook.IsPresent `
    -UseToggle $UseToggle.IsPresent `
    -HoldTimeoutSeconds $HoldTimeoutSeconds `
    -RecordSeconds $RecordSeconds `
    -PasteDictation $PasteDictation.IsPresent `
    -RestoreClipboard $RestoreClipboard.IsPresent `
    -NoRestoreClipboard $NoRestoreClipboard.IsPresent `
    -HasClipboardRestoreDelay $hasExplicitClipboardRestoreDelay `
    -ClipboardRestoreDelaySeconds $ClipboardRestoreDelaySeconds
if ($RunDictation) {
    $installArgs += "-RunDictation"
}
if ($CreateShortcut) {
    $installArgs += "-CreateShortcut"
    if (![string]::IsNullOrWhiteSpace($ShortcutDir)) {
        $installArgs += @("-ShortcutDir", $ShortcutDir)
    }
}
if ($CreateStartupShortcut) {
    $installArgs += "-CreateStartupShortcut"
    if (![string]::IsNullOrWhiteSpace($StartupShortcutDir)) {
        $installArgs += @("-StartupShortcutDir", $StartupShortcutDir)
    }
}

Invoke-Step "install packaged agent" {
    & $installScript @installArgs
}

Invoke-Step "installed script parse check" {
    $installedParseScript = Join-Path $InstallDir "check-windows-scripts-parse.ps1"
    Require-File -Path $installedParseScript
    $script:installedScriptParseOutput = & $installedParseScript -ScriptsDir $InstallDir 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        Write-Host $script:installedScriptParseOutput
        throw "Installed script parse check failed"
    }
    Write-Host $script:installedScriptParseOutput
    Assert-RomaWindowsScriptParseCount `
        -Output $script:installedScriptParseOutput `
        -ExpectedCount (Get-RomaWindowsInstalledProofSurfaceScriptCount) `
        -Name "installed"
}

Invoke-Step "installed launcher doctor" {
    $installedRun = Join-Path $InstallDir "run-windows-agent.ps1"
    Require-File -Path $installedRun
    $runArgs = @(
        "-InstallDir", $InstallDir,
        "-DoctorOnly"
    )
    if (![string]::IsNullOrWhiteSpace($ConfigPath)) {
        $runArgs += @("-ConfigPath", $ConfigPath)
    }
    $script:installedLauncherDoctorOutput = & $installedRun @runArgs 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        Write-Host $script:installedLauncherDoctorOutput
        throw "Installed launcher doctor failed"
    }
    Write-Host $script:installedLauncherDoctorOutput
}

Invoke-Step "installed config doctor" {
    $installedAgent = Join-Path $InstallDir "RomaWindowsAgent.exe"
    $script:installedConfigDoctorOutput = Invoke-ConfigDoctor `
        -AgentPath $installedAgent `
        -ConfigPath $ConfigPath
}

Invoke-Step "installed listener smoke" {
    $installedRun = Join-Path $InstallDir "run-windows-agent.ps1"
    Require-File -Path $installedRun
    $script:installedListenerOutput = Invoke-InstalledListenerSmoke `
        -RunScriptPath $installedRun `
        -ConfigPath $ConfigPath
}

if ($RunListenerProof) {
    Invoke-Step "installed listener runtime proof" {
        $installedRun = Join-Path $InstallDir "run-windows-agent.ps1"
        Require-File -Path $installedRun
        $null = Invoke-InstalledListenerRuntimeProof `
            -RunScriptPath $installedRun `
            -ConfigPath $ConfigPath
    }
}

if ($RunNotepadPasteProof) {
    Invoke-Step "notepad paste proof" {
        $script:notepadPasteProof = Invoke-NotepadPasteProof
    }
}

Write-ProofReport -Mode $proofMode -IsDoctorOnly $false

Write-Host ""
Write-Host "artifact_proof=ok"
Write-Host "package_dir=$PackageDir"
Write-Host "install_dir=$InstallDir"
if (![string]::IsNullOrWhiteSpace($ConfigPath)) {
    Write-Host "config=$ConfigPath"
}
