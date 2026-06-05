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
    $InstallDir = Get-RomaWindowsDefaultInstallDir
}
$InstallDir = Resolve-FullPath -Path $InstallDir

if ([string]::IsNullOrWhiteSpace($AgentPath)) {
    $AgentPath = Join-RomaWindowsInstalledAgentPath -InstallDir $InstallDir
}
$AgentPath = Resolve-FullPath -Path $AgentPath
Require-File -Path $AgentPath

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $userConfigPath = Get-RomaWindowsUserAgentConfigPath
    if (![string]::IsNullOrWhiteSpace($userConfigPath)) {
        $ConfigPath = $userConfigPath
    } else {
        $ConfigPath = Join-RomaWindowsInstalledAgentConfigPath -InstallDir $InstallDir
    }
}
$ConfigPath = Resolve-FullPath -Path $ConfigPath

$SecretDir = Resolve-RomaWindowsAgentSecretDir `
    -SecretDir $SecretDir `
    -DefaultSecretDir (Join-RomaWindowsInstalledSecretDirPath -InstallDir $InstallDir) `
    -ApiKeyName $ApiKeyName

Write-Host "agent_exe=$AgentPath"
Write-Host "config=$ConfigPath"

$doctorOutput = & $AgentPath doctor 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) {
    Write-Host $doctorOutput
    throw "RomaWindowsAgent doctor failed"
}
Write-Host $doctorOutput
Assert-RomaWindowsAgentDoctorOutput -Output $doctorOutput -RequireRuntimeAvailable
if ($DoctorOnly) {
    exit 0
}

$configMode = Get-RomaWindowsAgentTranscriptionConfigMode `
    -Endpoint $Endpoint `
    -Model $Model `
    -WhisperCLI $WhisperCLI `
    -WhisperModel $WhisperModel `
    -RequireCloudApiKey $true `
    -ApiKeyEnv $ApiKeyEnv `
    -ApiKeyName $ApiKeyName `
    -CloudApiKeyMessage "Pass ApiKeyEnv or ApiKeyName when writing cloud config"
$usesCloud = [bool]$configMode["uses_cloud"]
$usesWhisper = [bool]$configMode["uses_whisper"]
$hasConfigInput = [bool]$configMode["has_config_input"]
$hasConfig = Test-Path -LiteralPath $ConfigPath

if ($hasConfigInput) {
    $configArgs = @(
        "write-config",
        "--config", $ConfigPath
    )

    if ($usesCloud -and
        ![string]::IsNullOrWhiteSpace($ApiKeyName) -and
        ![string]::IsNullOrWhiteSpace($ApiKeyEnv) -and
        ![string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($ApiKeyEnv))) {
        $saveKeyArgs = New-RomaWindowsAgentSaveKeyArgs `
            -ApiKeyName $ApiKeyName `
            -ApiKeyEnv $ApiKeyEnv `
            -SecretDir $SecretDir
        $saveKeyOutput = & $AgentPath @saveKeyArgs 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) {
            Write-Host $saveKeyOutput
            throw "RomaWindowsAgent save-key-from-env failed"
        }
        Write-Host $saveKeyOutput
    }

    $configArgs = Add-RomaWindowsAgentConfigurationArgs `
        -Arguments $configArgs `
        -UseWhisperCLI $usesWhisper `
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
Assert-RomaWindowsConfigDoctorOutput -Output $configDoctorOutput

$agentMode = if ($Listen) { "listen" } else { "dictate" }
$agentArgs = @(
    $agentMode,
    "--config", $ConfigPath
)
if ($Listen -and $PSBoundParameters.ContainsKey("MaxSessions")) {
    $agentArgs += @("--max-sessions", "$MaxSessions")
}

$operatorPromptName = if ($Listen) { "installed_agent_listener" } else { "installed_agent_dictation" }
$usesHoldHook = !(Test-RomaWindowsContainsText -Text $configDoctorOutput -Needle "recording_mode=toggle")
$promptsPaste = Test-RomaWindowsContainsText -Text $configDoctorOutput -Needle "paste=true"
$listenerSessionCount = if ($Listen -and $PSBoundParameters.ContainsKey("MaxSessions")) { $MaxSessions } else { -1 }
Write-RomaWindowsDictationOperatorPrompt `
    -Name $operatorPromptName `
    -UseHoldHook $usesHoldHook `
    -HoldTimeoutSeconds $HoldTimeoutSeconds `
    -ListenerSessionCount $listenerSessionCount `
    -PasteDictation $promptsPaste
Write-Host "mode=RomaWindowsAgent $agentMode"
& $AgentPath @agentArgs
if ($LASTEXITCODE -ne 0) {
    throw "RomaWindowsAgent $agentMode failed"
}
