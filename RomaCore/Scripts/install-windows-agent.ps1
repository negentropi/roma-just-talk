param(
    [string]$PackageDir = "",
    [string]$InstallDir = "",
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
    [switch]$RunDictation,
    [switch]$SkipSmoke,
    [switch]$CreateShortcut,
    [switch]$CreateStartupShortcut,
    [switch]$AllowSmokeShortcut,
    [string]$ShortcutDir = "",
    [string]$ShortcutName = "",
    [string]$StartupShortcutDir = "",
    [string]$StartupShortcutName = ""
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

if ([string]::IsNullOrWhiteSpace($ShortcutName)) {
    $ShortcutName = Get-RomaWindowsAgentShortcutFileName
}
if ([string]::IsNullOrWhiteSpace($StartupShortcutName)) {
    $StartupShortcutName = Get-RomaWindowsAgentShortcutFileName
}

function Get-ProcessExecutablePath {
    param(
        [Parameter(Mandatory = $true)]
        [System.Diagnostics.Process]$Process
    )

    try {
        return [string]$Process.MainModule.FileName
    } catch {
        return ""
    }
}

function Assert-InstalledAgentNotRunning {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstalledAgentPath
    )

    if ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
        return
    }
    if (!(Test-Path -LiteralPath $InstalledAgentPath)) {
        return
    }

    $resolvedAgentPath = Resolve-FullPath -Path $InstalledAgentPath
    foreach ($process in @(Get-Process -Name "RomaWindowsAgent" -ErrorAction SilentlyContinue)) {
        $processPath = Get-ProcessExecutablePath -Process $process
        if (![string]::IsNullOrWhiteSpace($processPath) -and
            $processPath.Equals($resolvedAgentPath, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Installed RomaWindowsAgent is running from $resolvedAgentPath pid=$($process.Id); close the listener before reinstalling or upgrading"
        }
    }

    Write-Host "installed_agent_not_running=true"
}

if ([string]::IsNullOrWhiteSpace($PackageDir)) {
    $PackageDir = $PSScriptRoot
}
$PackageDir = Resolve-FullPath -Path $PackageDir

if ([string]::IsNullOrWhiteSpace($InstallDir)) {
    $InstallDir = Get-RomaWindowsDefaultInstallDir
}
$InstallDir = Resolve-FullPath -Path $InstallDir

$hasExplicitEndpoint = $PSBoundParameters.ContainsKey("Endpoint")
$hasExplicitModel = $PSBoundParameters.ContainsKey("Model")
$hasExplicitConfigPath = $PSBoundParameters.ContainsKey("ConfigPath") -and ![string]::IsNullOrWhiteSpace($ConfigPath)
$hasExplicitWhisperCLI = $PSBoundParameters.ContainsKey("WhisperCLI")
$hasExplicitWhisperModel = $PSBoundParameters.ContainsKey("WhisperModel")
$hasWhisperCLIValue = ![string]::IsNullOrWhiteSpace($WhisperCLI)
$hasWhisperModelValue = ![string]::IsNullOrWhiteSpace($WhisperModel)
$hasExplicitApiKeyEnv = $PSBoundParameters.ContainsKey("ApiKeyEnv") -and ![string]::IsNullOrWhiteSpace($ApiKeyEnv)
$hasExplicitApiKeyName = ![string]::IsNullOrWhiteSpace($ApiKeyName)
$hasExplicitClipboardRestoreDelay = $PSBoundParameters.ContainsKey("ClipboardRestoreDelaySeconds")
$hasCloudShortcutConfig = $hasExplicitEndpoint -and $hasExplicitModel -and ($hasExplicitApiKeyEnv -or $hasExplicitApiKeyName)
$hasWhisperShortcutConfig = $hasWhisperCLIValue -and $hasWhisperModelValue
$hasExistingShortcutConfig = $SkipSmoke -and $hasExplicitConfigPath
$shortcutHasRunnableConfig = $hasCloudShortcutConfig -or $hasWhisperShortcutConfig -or $hasExistingShortcutConfig

if (($hasExplicitWhisperCLI -or $hasExplicitWhisperModel) -and
    (!$hasWhisperCLIValue -or !$hasWhisperModelValue)) {
    throw "WhisperCLI and WhisperModel must be provided together"
}

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $userConfigPath = Get-RomaWindowsUserAgentConfigPath
    if (($hasExplicitEndpoint -or $hasExplicitModel -or $hasExplicitWhisperCLI -or $hasExplicitWhisperModel -or $RunDictation) -and
        ![string]::IsNullOrWhiteSpace($userConfigPath)) {
        $ConfigPath = $userConfigPath
    } else {
        $ConfigPath = Join-RomaWindowsInstallSmokeConfigPath -InstallDir $InstallDir
    }
}
$ConfigPath = Resolve-FullPath -Path $ConfigPath

Assert-RomaWindowsAgentScriptCommonOptions `
    -UseHoldHook $UseHoldHook.IsPresent `
    -UseToggle $UseToggle.IsPresent `
    -PasteDictation $PasteDictation.IsPresent `
    -RestoreClipboard $RestoreClipboard.IsPresent `
    -NoRestoreClipboard $NoRestoreClipboard.IsPresent `
    -HasClipboardRestoreDelay $hasExplicitClipboardRestoreDelay `
    -ClipboardRestoreDelaySeconds $ClipboardRestoreDelaySeconds

if ([string]::IsNullOrWhiteSpace($SecretDir) -and
    ![string]::IsNullOrWhiteSpace($ApiKeyName)) {
    $SecretDir = Join-RomaWindowsInstalledSecretDirPath -InstallDir $InstallDir
}
if (![string]::IsNullOrWhiteSpace($SecretDir)) {
    $SecretDir = Resolve-FullPath -Path $SecretDir
}

$packageArtifactPaths = Get-RomaWindowsAgentArtifactPathSet -ArtifactDir $PackageDir
$agentSource = $packageArtifactPaths["agent"]
$smokeSource = $packageArtifactPaths["smoke_script"]
$runSource = $packageArtifactPaths["run_script"]
Require-File -Path $agentSource
Require-File -Path $smokeSource
Require-File -Path $runSource
$installedArtifactPaths = Get-RomaWindowsAgentArtifactPathSet -ArtifactDir $InstallDir
$installedAgent = Join-RomaWindowsInstalledAgentPath -InstallDir $InstallDir
$installedProofAgent = Join-RomaWindowsInstalledProofAgentPath -InstallDir $InstallDir
$installedRun = Join-RomaWindowsInstalledRunScriptPath -InstallDir $InstallDir
Assert-InstalledAgentNotRunning -InstalledAgentPath $installedAgent

Invoke-Step "copy package files" {
    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

    $knownFiles = Get-RomaWindowsAgentArtifactInstallFiles
    foreach ($file in $knownFiles) {
        $source = Join-Path $PackageDir $file
        if (Test-Path -LiteralPath $source) {
            Copy-Item -LiteralPath $source -Destination (Join-Path $InstallDir $file) -Force
        }
    }

    $runtimeLibraries = @(
        Get-ChildItem -LiteralPath $PackageDir -Filter "*.dll" |
            Sort-Object Name
    )
    foreach ($library in $runtimeLibraries) {
        Copy-Item -LiteralPath $library.FullName -Destination (Join-Path $InstallDir $library.Name) -Force
    }

    Require-File -Path $installedAgent
    Require-File -Path $installedProofAgent
    Require-RomaWindowsInstalledProofSurfaceFiles -InstallDir $InstallDir
    Write-Host "install_dir=$InstallDir"
    Write-Host "runtime_dlls=$($runtimeLibraries.Count)"
}

$packageWhisperMock = $packageArtifactPaths["whisper_cli_mock"]
$installedWhisperMock = $installedArtifactPaths["whisper_cli_mock"]
if ($hasExplicitWhisperCLI -and
    (Resolve-FullPath -Path $WhisperCLI) -eq (Resolve-FullPath -Path $packageWhisperMock) -and
    (Test-Path -LiteralPath $installedWhisperMock)) {
    $WhisperCLI = $installedWhisperMock
    Write-Host "installed_whisper_cli_mock=$WhisperCLI"
}
if ($hasExplicitWhisperModel -and
    (Resolve-FullPath -Path $WhisperModel) -eq (Resolve-FullPath -Path $agentSource) -and
    (Test-Path -LiteralPath $installedAgent)) {
    $WhisperModel = $installedAgent
    Write-Host "installed_whisper_model_mock=$WhisperModel"
}

if (!$SkipSmoke) {
    Invoke-Step "installed agent smoke" {
        $installedSmoke = $installedArtifactPaths["smoke_script"]
        $smokeArgs = @(
            "-PackageDir", $InstallDir,
            "-OutputDir", (Join-Path $InstallDir "smoke"),
            "-ConfigPath", $ConfigPath
        )
        $smokeApiKeyEnv = ""
        if ($hasExplicitApiKeyEnv) {
            $smokeApiKeyEnv = $ApiKeyEnv
        }
        $smokeArgs = Add-RomaWindowsAgentScriptCloudArgs `
            -ArgumentList $smokeArgs `
            -Endpoint $Endpoint `
            -Model $Model `
            -ApiKeyEnv $smokeApiKeyEnv `
            -ApiKeyName $ApiKeyName `
            -SecretDir $SecretDir
        $whisperArguments = @(
            $WhisperArgument |
                Where-Object { ![string]::IsNullOrWhiteSpace($_) }
        )
        if ($hasWhisperShortcutConfig) {
            $smokeArgs = Add-RomaWindowsAgentScriptLocalWhisperArgs `
                -ArgumentList $smokeArgs `
                -WhisperCLI $WhisperCLI `
                -WhisperModel $WhisperModel `
                -WhisperOutputDir $WhisperOutputDir `
                -WhisperArgument $whisperArguments
        }
        $smokeArgs = Add-RomaWindowsAgentScriptCommonArgs `
            -ArgumentList $smokeArgs `
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
            $smokeArgs += "-RunDictation"
        }

        & $installedSmoke @smokeArgs
    }

    Invoke-Step "installed launcher doctor" {
        Require-File -Path $installedRun
        & $installedRun `
            -InstallDir $InstallDir `
            -ConfigPath $ConfigPath `
            -DoctorOnly
    }
}

if ($CreateShortcut -or $CreateStartupShortcut) {
    Invoke-Step "create user shortcut" {
        if (!$shortcutHasRunnableConfig -and !$AllowSmokeShortcut) {
            throw "Shortcut creation requires cloud Endpoint/Model with ApiKeyEnv/ApiKeyName, local WhisperCLI/WhisperModel, or -SkipSmoke with -ConfigPath"
        }
        if ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
            throw "Shortcut creation is only available on Windows"
        }
        $runScript = $installedRun
        Require-File -Path $runScript

        if ($CreateShortcut) {
            if ([string]::IsNullOrWhiteSpace($ShortcutDir)) {
                $programs = [System.Environment]::GetFolderPath("Programs")
                if ([string]::IsNullOrWhiteSpace($programs)) {
                    throw "Start Menu Programs folder was not found"
                }
                $ShortcutDir = Join-Path $programs "Roma Just Talk"
            }
            $ShortcutDir = Resolve-FullPath -Path $ShortcutDir
            New-Item -ItemType Directory -Force -Path $ShortcutDir | Out-Null

            $shortcutPath = Join-RomaWindowsAgentShortcutPath -ShortcutDir $ShortcutDir -ShortcutName $ShortcutName
            $savedShortcut = New-RomaWindowsAgentShortcut `
                -ShortcutPath $shortcutPath `
                -RunScriptPath $runScript `
                -ConfigPath $ConfigPath `
                -InstallDir $InstallDir `
                -Description "Start roma-just-talk Windows dictation agent"
            Write-Host "shortcut=$shortcutPath"
            Write-Host "shortcut_args=$($savedShortcut.Arguments)"
        }

        if ($CreateStartupShortcut) {
            if ([string]::IsNullOrWhiteSpace($StartupShortcutDir)) {
                $startup = [System.Environment]::GetFolderPath("Startup")
                if ([string]::IsNullOrWhiteSpace($startup)) {
                    throw "Startup folder was not found"
                }
                $StartupShortcutDir = $startup
            }
            $StartupShortcutDir = Resolve-FullPath -Path $StartupShortcutDir
            New-Item -ItemType Directory -Force -Path $StartupShortcutDir | Out-Null

            $startupShortcutPath = Join-RomaWindowsAgentShortcutPath -ShortcutDir $StartupShortcutDir -ShortcutName $StartupShortcutName
            $savedStartupShortcut = New-RomaWindowsAgentShortcut `
                -ShortcutPath $startupShortcutPath `
                -RunScriptPath $runScript `
                -ConfigPath $ConfigPath `
                -InstallDir $InstallDir `
                -Description "Start roma-just-talk Windows dictation agent at login"
            Write-Host "startup_shortcut=$startupShortcutPath"
            Write-Host "startup_shortcut_args=$($savedStartupShortcut.Arguments)"
        }
    }
}

Write-Host ""
$installedSmoke = $installedArtifactPaths["smoke_script"]
Write-Host "installed_agent=$installedAgent"
Write-Host "installed_smoke=$installedSmoke"
Write-Host "installed_run=$installedRun"
Write-Host "config=$ConfigPath"
