param(
    [string]$PackageDir = "",
    [string]$AgentPath = "",
    [string]$OutputDir = "",
    [string]$ConfigPath = "",
    [string]$Endpoint = "http://127.0.0.1:1/v1/audio/transcriptions",
    [string]$Model = "mock-whisper",
    [string]$ApiKeyEnv = "PATH",
    [string]$ApiKeyName = "",
    [string]$SecretDir = "",
    [string]$WhisperCLI = "",
    [string]$WhisperModel = "",
    [string]$WhisperOutputDir = "",
    [string[]]$WhisperArgument = @(),
    [string]$Language = "",
    [string]$Prompt = "",
    [string[]]$WordReplacement = @("just talk=roma-just-talk"),
    [switch]$UseHoldHook,
    [switch]$UseToggle,
    [int]$HoldTimeoutSeconds = 15,
    [int]$RecordSeconds = 2,
    [switch]$PasteDictation,
    [switch]$RestoreClipboard,
    [switch]$NoRestoreClipboard,
    [double]$ClipboardRestoreDelaySeconds = 2,
    [switch]$RunDictation
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$hasExplicitClipboardRestoreDelay = $PSBoundParameters.ContainsKey("ClipboardRestoreDelaySeconds")

$proofCommonScript = Join-Path $PSScriptRoot "windows-proof-common.ps1"
if (!(Test-Path -LiteralPath $proofCommonScript)) {
    throw "Windows proof common helper was not found: $proofCommonScript"
}
. $proofCommonScript
Set-Alias -Name Invoke-Step -Value Invoke-RomaWindowsProofStep -Scope Local -Force
Set-Alias -Name Assert-OutputContains -Value Assert-RomaWindowsOutputContains -Scope Local -Force
Set-Alias -Name Resolve-FullPath -Value Resolve-RomaWindowsFullPath -Scope Local -Force

function Assert-JsonPropertyEquals {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Object,
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [object]$Expected
    )

    if (!($Object.PSObject.Properties.Name -contains $Name)) {
        throw "Expected JSON property '$Name' was not found"
    }

    $actual = $Object.$Name
    if ($actual -ne $Expected) {
        throw "Expected JSON property '$Name' to equal '$Expected', got '$actual'"
    }

    Write-Host "asserted_json=$Name"
}

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

if ([string]::IsNullOrWhiteSpace($AgentPath)) {
    $packageArtifactPaths = Get-RomaWindowsAgentArtifactPathSet -ArtifactDir $PackageDir
    $AgentPath = $packageArtifactPaths["agent"]
}
$AgentPath = Resolve-FullPath -Path $AgentPath

if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path (Split-Path -Parent $AgentPath) "smoke"
}
$OutputDir = Resolve-FullPath -Path $OutputDir
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path $OutputDir "windows-agent-smoke.json"
}
$ConfigPath = Resolve-FullPath -Path $ConfigPath

$SecretDir = Resolve-RomaWindowsAgentSecretDir `
    -SecretDir $SecretDir `
    -DefaultSecretDir (Join-Path $OutputDir "secrets") `
    -ApiKeyName $ApiKeyName

if (!(Test-Path -LiteralPath $AgentPath)) {
    throw "RomaWindowsAgent.exe was not found: $AgentPath"
}

$hasExplicitApiKeyEnv = $PSBoundParameters.ContainsKey("ApiKeyEnv")
$apiKeyEnvValue = if ([string]::IsNullOrWhiteSpace($ApiKeyEnv)) {
    ""
} else {
    [Environment]::GetEnvironmentVariable($ApiKeyEnv)
}
$hasWhisperCLI = ![string]::IsNullOrWhiteSpace($WhisperCLI)
$hasWhisperModel = ![string]::IsNullOrWhiteSpace($WhisperModel)
$usesWhisperCLI = $hasWhisperCLI -or $hasWhisperModel

if ($usesWhisperCLI -and (!$hasWhisperCLI -or !$hasWhisperModel)) {
    throw "WhisperCLI and WhisperModel must be provided together"
}

if ($RunDictation -and !$usesWhisperCLI -and
    [string]::IsNullOrWhiteSpace($ApiKeyName) -and
    (!$hasExplicitApiKeyEnv -or [string]::IsNullOrWhiteSpace($apiKeyEnvValue))) {
    throw "RunDictation requires -ApiKeyEnv with a set environment variable, or pass -ApiKeyName with a saved key"
}

$isWindowsHost = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
$shouldUseHoldHook = $UseHoldHook -or !$UseToggle
$dictationOutput = Join-Path $OutputDir "windows-agent-smoke.wav"
$dictationLog = Join-Path $OutputDir "windows-agent-dictate.log"

Invoke-Step "agent doctor" {
    $doctorOutput = & $AgentPath doctor 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        Write-Host $doctorOutput
        throw "RomaWindowsAgent doctor failed"
    }
    Write-Host $doctorOutput
    Assert-RomaWindowsAgentDoctorOutput -Output $doctorOutput -RequireRuntimeAvailable:$isWindowsHost
}

if (![string]::IsNullOrWhiteSpace($ApiKeyName) -and
    $hasExplicitApiKeyEnv -and
    ![string]::IsNullOrWhiteSpace($apiKeyEnvValue)) {
    Invoke-Step "agent save key" {
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
        Assert-OutputContains -Output $saveKeyOutput -Expected "stored=true"
        Assert-OutputContains -Output $saveKeyOutput -Expected "key=$ApiKeyName"
    }
} elseif ($RunDictation -and ![string]::IsNullOrWhiteSpace($ApiKeyName)) {
    Write-Host ""
    Write-Host "== agent save key skipped =="
    Write-Host "using existing stored key '$ApiKeyName' from $SecretDir"
}

Invoke-Step "agent config" {
    $configArgs = @(
        "write-config",
        "--config", $ConfigPath,
        "--out", $dictationOutput
    )
    $configArgs = Add-RomaWindowsAgentConfigurationArgs `
        -Arguments $configArgs `
        -UseWhisperCLI $usesWhisperCLI `
        -WhisperCLI $WhisperCLI `
        -WhisperModel $WhisperModel `
        -WhisperOutputDir $WhisperOutputDir `
        -WhisperArgument $WhisperArgument `
        -Endpoint $Endpoint `
        -Model $Model `
        -UseHoldHook $shouldUseHoldHook `
        -HoldTimeoutSeconds $HoldTimeoutSeconds `
        -RecordSeconds $RecordSeconds `
        -ApiKeyName $ApiKeyName `
        -ApiKeyEnv $ApiKeyEnv `
        -SecretDir $SecretDir `
        -Language $Language `
        -Prompt $Prompt `
        -WordReplacement $WordReplacement `
        -PasteDictation $PasteDictation.IsPresent `
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
    Assert-RomaWindowsAgentConfigWriteOutput `
        -Output $configOutput `
        -ConfigPath $ConfigPath `
        -RequireClipboardRestoreFields $true
    Assert-RomaWindowsFileWithMinimumBytes -Path $ConfigPath

    $configJson = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
    if ($usesWhisperCLI) {
        Assert-JsonPropertyEquals -Object $configJson -Name "whisperCLIPath" -Expected $WhisperCLI
        Assert-JsonPropertyEquals -Object $configJson -Name "whisperModelPath" -Expected $WhisperModel
    } else {
        Assert-JsonPropertyEquals -Object $configJson -Name "endpoint" -Expected $Endpoint
        Assert-JsonPropertyEquals -Object $configJson -Name "model" -Expected $Model
    }
    Assert-JsonPropertyEquals -Object $configJson -Name "outputPath" -Expected $dictationOutput
    Assert-JsonPropertyEquals -Object $configJson -Name "usesHoldHook" -Expected $shouldUseHoldHook
    if ($PasteDictation) {
        Assert-JsonPropertyEquals -Object $configJson -Name "shouldPaste" -Expected $true
    }
    if ($RestoreClipboard) {
        Assert-JsonPropertyEquals -Object $configJson -Name "restoreClipboardAfterPaste" -Expected $true
    }
    if ($NoRestoreClipboard) {
        Assert-JsonPropertyEquals -Object $configJson -Name "restoreClipboardAfterPaste" -Expected $false
    }
    if ($hasExplicitClipboardRestoreDelay) {
        Assert-JsonPropertyEquals `
            -Object $configJson `
            -Name "clipboardRestoreDelaySeconds" `
            -Expected $ClipboardRestoreDelaySeconds
    }
}

Invoke-Step "agent config doctor" {
    $configDoctorOutput = & $AgentPath config-doctor --config $ConfigPath 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        Write-Host $configDoctorOutput
        throw "RomaWindowsAgent config-doctor failed"
    }
    Write-Host $configDoctorOutput
    $requiresCloudConfigDoctor = !$usesWhisperCLI
    Assert-RomaWindowsConfigDoctorOutput `
        -Output $configDoctorOutput `
        -RequireWhisperCLI $usesWhisperCLI `
        -RequireCloud $requiresCloudConfigDoctor
}

if ($RunDictation) {
    Invoke-Step "agent dictate" {
        Write-RomaWindowsDictationOperatorPrompt `
            -Name "installed_agent_dictation" `
            -UseHoldHook $shouldUseHoldHook `
            -HoldTimeoutSeconds $HoldTimeoutSeconds `
            -PasteDictation $PasteDictation.IsPresent

        $dictateOutput = & $AgentPath dictate --config $ConfigPath 2>&1 | Out-String
        Write-Host $dictateOutput
        Set-Content -LiteralPath $dictationLog -Value $dictateOutput -Encoding UTF8
        if ($LASTEXITCODE -ne 0) {
            throw "RomaWindowsAgent dictate failed"
        }
        Assert-RomaWindowsFileWithMinimumBytes -Path $dictationOutput -MinimumBytes 45
        Assert-RomaWindowsFileWithMinimumBytes -Path $dictationLog
        Assert-OutputContains -Output $dictateOutput -Expected "wrote="
        Assert-OutputContains -Output $dictateOutput -Expected "included_pre_roll_seconds="
        Assert-OutputContains -Output $dictateOutput -Expected "processed_transcript_text="
        if ($PasteDictation) {
            Assert-OutputContains -Output $dictateOutput -Expected "paste_sent=true"
        } else {
            Assert-OutputContains -Output $dictateOutput -Expected "paste_sent=false"
        }
    }
} else {
    Write-Host ""
    Write-Host "== agent dictate skipped =="
    Write-Host "rerun with -RunDictation after setting a real transcription endpoint and API key"
}

Write-Host ""
Write-Host "agent_exe=$AgentPath"
Write-Host "config=$ConfigPath"
if (![string]::IsNullOrWhiteSpace($ApiKeyName)) {
    Write-Host "secret_dir=$SecretDir"
    Write-Host "api_key_name=$ApiKeyName"
}
Write-Host "smoke_artifacts=$OutputDir"
Write-Host "run_dictation=$($RunDictation.IsPresent)"
if ($RunDictation) {
    Write-Host "dictation_log=$dictationLog"
}
