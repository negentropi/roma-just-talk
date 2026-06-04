param(
    [string]$InstallDir = "",
    [string]$AgentPath = "",
    [string]$ConfigPath = "",
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
    [string[]]$WordReplacement = @(),
    [switch]$UseHoldHook,
    [switch]$UseToggle,
    [int]$HoldTimeoutSeconds = 15,
    [int]$RecordSeconds = 2,
    [switch]$PasteDictation,
    [switch]$NoPaste,
    [switch]$RestoreClipboard,
    [switch]$NoRestoreClipboard,
    [double]$ClipboardRestoreDelaySeconds = 2,
    [switch]$Listen,
    [int]$MaxSessions = -1,
    [switch]$DoctorOnly
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$hasExplicitClipboardRestoreDelay = $PSBoundParameters.ContainsKey("ClipboardRestoreDelaySeconds")

$proofCommonScript = Join-Path $PSScriptRoot "windows-proof-common.ps1"
if (!(Test-Path -LiteralPath $proofCommonScript)) {
    throw "Windows proof common helper was not found: $proofCommonScript"
}
. $proofCommonScript
Set-Alias -Name Resolve-FullPath -Value Resolve-RomaWindowsFullPath -Scope Local -Force
Set-Alias -Name Require-File -Value Require-RomaWindowsFile -Scope Local -Force
Set-Alias -Name Assert-OutputContains -Value Assert-RomaWindowsOutputContains -Scope Local -Force

Assert-RomaWindowsAgentScriptCommonOptions `
    -UseHoldHook $UseHoldHook.IsPresent `
    -UseToggle $UseToggle.IsPresent `
    -PasteDictation $PasteDictation.IsPresent `
    -NoPaste $NoPaste.IsPresent `
    -RestoreClipboard $RestoreClipboard.IsPresent `
    -NoRestoreClipboard $NoRestoreClipboard.IsPresent `
    -HasClipboardRestoreDelay $hasExplicitClipboardRestoreDelay `
    -ClipboardRestoreDelaySeconds $ClipboardRestoreDelaySeconds

if ($PSBoundParameters.ContainsKey("MaxSessions") -and $MaxSessions -lt 0) {
    throw "MaxSessions must be non-negative"
}

if ([string]::IsNullOrWhiteSpace($InstallDir)) {
    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        throw "LOCALAPPDATA is not set; pass -InstallDir explicitly"
    }
    $InstallDir = Join-Path $env:LOCALAPPDATA "roma-just-talk\agent"
}
$InstallDir = Resolve-FullPath -Path $InstallDir

if ([string]::IsNullOrWhiteSpace($AgentPath)) {
    $AgentPath = Join-Path $InstallDir "RomaWindowsAgent.exe"
}
$AgentPath = Resolve-FullPath -Path $AgentPath
Require-File -Path $AgentPath

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    if (![string]::IsNullOrWhiteSpace($env:APPDATA)) {
        $ConfigPath = Join-Path $env:APPDATA "roma-just-talk\windows-agent.json"
    } else {
        $ConfigPath = Join-Path $InstallDir "windows-agent.json"
    }
}
$ConfigPath = Resolve-FullPath -Path $ConfigPath

if ([string]::IsNullOrWhiteSpace($SecretDir) -and
    ![string]::IsNullOrWhiteSpace($ApiKeyName)) {
    $SecretDir = Join-Path $InstallDir "secrets"
}
if (![string]::IsNullOrWhiteSpace($SecretDir)) {
    $SecretDir = Resolve-FullPath -Path $SecretDir
}

Write-Host "agent_exe=$AgentPath"
Write-Host "config=$ConfigPath"

$doctorOutput = & $AgentPath doctor 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) {
    Write-Host $doctorOutput
    throw "RomaWindowsAgent doctor failed"
}
Write-Host $doctorOutput
Assert-RomaWindowsRuntimeDefaultOutput -Output $doctorOutput
Assert-RomaWindowsMinimumPermissionOutput -Output $doctorOutput
Assert-OutputContains -Output $doctorOutput -Expected "paste=win32_clipboard_sendinput"
Assert-OutputContains -Output $doctorOutput -Expected "secret_store=dpapi"
if ($DoctorOnly) {
    exit 0
}

$hasEndpoint = ![string]::IsNullOrWhiteSpace($Endpoint)
$hasModel = ![string]::IsNullOrWhiteSpace($Model)
$hasWhisperCLI = ![string]::IsNullOrWhiteSpace($WhisperCLI)
$hasWhisperModel = ![string]::IsNullOrWhiteSpace($WhisperModel)
$hasConfig = Test-Path -LiteralPath $ConfigPath

if (($hasEndpoint -or $hasModel) -and ($hasWhisperCLI -or $hasWhisperModel)) {
    throw "Endpoint/Model and WhisperCLI/WhisperModel are mutually exclusive"
}

if ($hasEndpoint -or $hasModel -or $hasWhisperCLI -or $hasWhisperModel) {
    $configArgs = @(
        "write-config",
        "--config", $ConfigPath
    )

    if (!$hasEndpoint -or !$hasModel) {
        if (!$hasWhisperCLI -or !$hasWhisperModel) {
            throw "Pass Endpoint and Model together, or pass WhisperCLI and WhisperModel together"
        }
    }

    if ($hasEndpoint -and
        ![string]::IsNullOrWhiteSpace($ApiKeyName) -and
        ![string]::IsNullOrWhiteSpace($ApiKeyEnv) -and
        ![string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($ApiKeyEnv))) {
        $saveKeyArgs = @(
            "save-key-from-env",
            "--key", $ApiKeyName,
            "--value-env", $ApiKeyEnv,
            "--secret-dir", $SecretDir
        )
        $saveKeyOutput = & $AgentPath @saveKeyArgs 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) {
            Write-Host $saveKeyOutput
            throw "RomaWindowsAgent save-key-from-env failed"
        }
        Write-Host $saveKeyOutput
    }

    if ($hasEndpoint) {
        if ([string]::IsNullOrWhiteSpace($ApiKeyName) -and [string]::IsNullOrWhiteSpace($ApiKeyEnv)) {
            throw "Pass ApiKeyEnv or ApiKeyName when writing cloud config"
        }
    }
    $configArgs = Add-RomaWindowsAgentConfigurationArgs `
        -Arguments $configArgs `
        -UseWhisperCLI $hasWhisperCLI `
        -WhisperCLI $WhisperCLI `
        -WhisperModel $WhisperModel `
        -WhisperOutputDir $WhisperOutputDir `
        -WhisperArgument $WhisperArgument `
        -Endpoint $Endpoint `
        -Model $Model `
        -UseHoldHook ($UseHoldHook -or !$UseToggle) `
        -HoldTimeoutSeconds $HoldTimeoutSeconds `
        -RecordSeconds $RecordSeconds `
        -ApiKeyName $ApiKeyName `
        -ApiKeyEnv $ApiKeyEnv `
        -SecretDir $SecretDir `
        -Language $Language `
        -Prompt $Prompt `
        -WordReplacement $WordReplacement `
        -PasteDictation $PasteDictation.IsPresent `
        -NoPaste $NoPaste.IsPresent `
        -RestoreClipboard $RestoreClipboard.IsPresent `
        -NoRestoreClipboard $NoRestoreClipboard.IsPresent `
        -HasClipboardRestoreDelay $hasExplicitClipboardRestoreDelay `
        -ClipboardRestoreDelaySeconds $ClipboardRestoreDelaySeconds

    $configOutput = & $AgentPath @configArgs 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        Write-Host $configOutput
        throw "RomaWindowsAgent write-config failed"
    }
    Write-Host $configOutput
    $hasConfig = $true
}

if (!$hasConfig) {
    throw "Config was not found at $ConfigPath; rerun with cloud Endpoint/Model/API key or local WhisperCLI/WhisperModel"
}

$configDoctorOutput = & $AgentPath config-doctor --config $ConfigPath 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) {
    Write-Host $configDoctorOutput
    throw "RomaWindowsAgent config-doctor failed"
}
Write-Host $configDoctorOutput
Assert-OutputContains -Output $configDoctorOutput -Expected "config_valid=true"
Assert-OutputContains -Output $configDoctorOutput -Expected "transcription_client="

$agentMode = if ($Listen) { "listen" } else { "dictate" }
$agentArgs = @(
    $agentMode,
    "--config", $ConfigPath
)
if ($Listen -and $PSBoundParameters.ContainsKey("MaxSessions")) {
    $agentArgs += @("--max-sessions", "$MaxSessions")
}

Write-Host "waiting_for_hotkey=Ctrl+Shift+R"
Write-Host "mode=RomaWindowsAgent $agentMode"
& $AgentPath @agentArgs
if ($LASTEXITCODE -ne 0) {
    throw "RomaWindowsAgent $agentMode failed"
}
