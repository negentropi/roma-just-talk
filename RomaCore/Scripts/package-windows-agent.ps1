param(
    [string]$OutputDir = "$PSScriptRoot\..\proof-artifacts\windows-agent",
    [ValidateSet("debug", "release")]
    [string]$Configuration = "release"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$proofCommonScript = Join-Path $PSScriptRoot "windows-proof-common.ps1"
if (!(Test-Path -LiteralPath $proofCommonScript)) {
    throw "Windows proof common helper was not found: $proofCommonScript"
}
. $proofCommonScript
Set-Alias -Name Invoke-Step -Value Invoke-RomaWindowsProofStep -Scope Local -Force

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

$packageRoot = Resolve-Path "$PSScriptRoot\.."
if ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
    throw "package-windows-agent.ps1 must run on Windows so packaged executables and Swift runtime DLLs are Windows artifacts"
}

$gitMetadata = Get-RomaWindowsSourceGitMetadata -RepositoryRoot $packageRoot
$OutputDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDir)
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

Push-Location $packageRoot
try {
    Invoke-Step "build RomaWindowsAgent" {
        swift build -c $Configuration --product RomaWindowsAgent
    }

    Invoke-Step "build RomaProofAgent" {
        swift build -c $Configuration --product RomaProofAgent
    }

    Invoke-Step "build RomaWhisperCLIMock" {
        swift build -c $Configuration --product RomaWhisperCLIMock
    }

    $buildDirectory = Join-Path $packageRoot ".build"
    $agentSource = Resolve-RomaWindowsProductExecutable -BuildDirectory $buildDirectory -Configuration $Configuration -Name "RomaWindowsAgent"
    $proofAgentSource = Resolve-RomaWindowsProductExecutable -BuildDirectory $buildDirectory -Configuration $Configuration -Name "RomaProofAgent"
    $mockWhisperSource = Resolve-RomaWindowsProductExecutable -BuildDirectory $buildDirectory -Configuration $Configuration -Name "RomaWhisperCLIMock"
    $sourceArtifactPaths = Get-RomaWindowsAgentArtifactPathSet -ArtifactDir $PSScriptRoot
    $outputArtifactPaths = Get-RomaWindowsAgentArtifactPathSet -ArtifactDir $OutputDir
    $agentOutput = $outputArtifactPaths["agent"]
    $proofAgentOutput = $outputArtifactPaths["proof_agent"]
    $mockWhisperOutput = $outputArtifactPaths["whisper_cli_mock"]
    $smokeScriptOutput = $outputArtifactPaths["smoke_script"]
    $installScriptOutput = $outputArtifactPaths["install_script"]
    $parseScriptOutput = $outputArtifactPaths["parse_script"]
    $checkReportScriptOutput = $outputArtifactPaths["check_report_script"]
    $checkSetScriptOutput = $outputArtifactPaths["check_set_script"]
    $configPath = $outputArtifactPaths["sample_config"]
    $localWhisperConfigPath = $outputArtifactPaths["sample_local_whisper_config"]
    $installProofDir = Join-Path $OutputDir "install-proof"
    $installProofConfigPath = Join-Path $installProofDir "windows-agent.json"
    $shortcutDir = Join-Path $OutputDir "shortcuts"
    $shortcutPath = Join-RomaWindowsAgentShortcutPath -ShortcutDir $shortcutDir
    $localWhisperInstallProofDir = Join-Path $OutputDir "install-proof-local-whisper"
    $localWhisperInstallConfigPath = Join-Path $localWhisperInstallProofDir "windows-agent.json"
    $localWhisperShortcutDir = Join-Path $OutputDir "shortcuts-local-whisper"
    $localWhisperShortcutPath = Join-RomaWindowsAgentShortcutPath -ShortcutDir $localWhisperShortcutDir
    $laptopPreflightCheckerSmokeDir = Join-Path $OutputDir "laptop-preflight-checker-smoke"
    $laptopPreflightCheckerSmokeReport = Join-RomaWindowsLaptopProofReportPath -ProofDir $laptopPreflightCheckerSmokeDir -Name "laptop_preflight"
    $laptopNativePreflightCheckerSmokeDir = Join-Path $OutputDir "laptop-native-preflight-checker-smoke"
    $laptopNativePreflightCheckerSmokeReport = Join-RomaWindowsLaptopProofReportPath -ProofDir $laptopNativePreflightCheckerSmokeDir -Name "laptop_preflight"

    Invoke-Step "copy agent executable" {
        Copy-RomaWindowsAgentArtifactBundle `
            -AgentSource $agentSource `
            -ProofAgentSource $proofAgentSource `
            -WhisperCLIMockSource $mockWhisperSource `
            -SourceArtifactPaths $sourceArtifactPaths `
            -OutputArtifactPaths $outputArtifactPaths
    }

    Invoke-Step "packaged script parse check" {
        $packagedScriptParseOutput = & $parseScriptOutput -ScriptsDir $OutputDir 2>&1 | Out-String
        Write-Host $packagedScriptParseOutput
        Assert-RomaWindowsScriptParseCount `
            -Output $packagedScriptParseOutput `
            -ExpectedCount (Get-RomaWindowsProofSurfaceScriptCount) `
            -Name "packaged"
    }

    $swiftRuntime = @{}
    Invoke-Step "copy Swift runtime libraries" {
        $script:swiftRuntime = Copy-RomaWindowsSwiftRuntimeLibraries -OutputDir $OutputDir
        Assert-RomaWindowsSwiftRuntimePackaged -OutputDir $OutputDir -SwiftRuntime $script:swiftRuntime
    }

    Invoke-Step "packaged agent smoke" {
        & $smokeScriptOutput `
            -AgentPath $agentOutput `
            -OutputDir $OutputDir `
            -ConfigPath $configPath `
            -RestoreClipboard `
            -ClipboardRestoreDelaySeconds 0
    }

    Invoke-Step "packaged proof agent smoke" {
        $proofAgentOutputText = & $proofAgentOutput doctor 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) {
            Write-Host $proofAgentOutputText
            throw "RomaProofAgent doctor failed"
        }
        Write-Host $proofAgentOutputText
        Assert-RomaWindowsProofAgentDoctorOutput `
            -Output $proofAgentOutputText `
            -RequireNativeWindowsAdapters
    }

    Invoke-Step "packaged listener smoke" {
        $listenerOutputText = & $agentOutput listen `
            --config $configPath `
            --max-sessions 0 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) {
            Write-Host $listenerOutputText
            throw "RomaWindowsAgent listen smoke failed"
        }
        Write-Host $listenerOutputText
        Assert-RomaWindowsListenerSmokeOutput -Output $listenerOutputText
    }

    Invoke-Step "packaged local whisper config smoke" {
        & $smokeScriptOutput `
            -AgentPath $agentOutput `
            -OutputDir (Join-Path $OutputDir "local-whisper-smoke") `
            -ConfigPath $localWhisperConfigPath `
            -WhisperCLI $mockWhisperOutput `
            -WhisperModel $agentOutput `
            -RestoreClipboard `
            -ClipboardRestoreDelaySeconds 0
    }

    Invoke-Step "packaged agent install smoke" {
        & $installScriptOutput `
            -PackageDir $OutputDir `
            -InstallDir $installProofDir `
            -ConfigPath $installProofConfigPath `
            -RestoreClipboard `
            -ClipboardRestoreDelaySeconds 0 `
            -CreateShortcut `
            -AllowSmokeShortcut `
            -ShortcutDir $shortcutDir
    }

    Invoke-Step "packaged local whisper install smoke" {
        & $installScriptOutput `
            -PackageDir $OutputDir `
            -InstallDir $localWhisperInstallProofDir `
            -ConfigPath $localWhisperInstallConfigPath `
            -WhisperCLI $mockWhisperOutput `
            -WhisperModel $agentOutput `
            -RestoreClipboard `
            -ClipboardRestoreDelaySeconds 0 `
            -CreateShortcut `
            -ShortcutDir $localWhisperShortcutDir
    }

    $manifestPath = $outputArtifactPaths["manifest"]
    Write-RomaWindowsAgentArtifactManifest `
        -ManifestPath $manifestPath `
        -Configuration $Configuration `
        -GitMetadata $gitMetadata `
        -AgentSource $agentSource `
        -OutputArtifactPaths $outputArtifactPaths `
        -SwiftRuntime $swiftRuntime `
        -InstallProofDir $installProofDir `
        -InstallProofConfigPath $installProofConfigPath `
        -ShortcutPath $shortcutPath `
        -LocalWhisperInstallProofDir $localWhisperInstallProofDir `
        -LocalWhisperInstallConfigPath $localWhisperInstallConfigPath `
        -LocalWhisperShortcutPath $localWhisperShortcutPath `
        -LaptopNativePreflightCheckerSmokeReport $laptopNativePreflightCheckerSmokeReport `
        -LaptopPreflightCheckerSmokeReport $laptopPreflightCheckerSmokeReport

    $packageIdentityProof = Get-RomaPackageIdentityProof -PackageDir $OutputDir

    Invoke-Step "native laptop preflight report checker smoke" {
        Invoke-RomaWindowsLaptopPreflightCheckerSmoke `
            -ReportPath $laptopNativePreflightCheckerSmokeReport `
            -PackageDir $OutputDir `
            -ProofDir $laptopNativePreflightCheckerSmokeDir `
            -ProofAgentPath $proofAgentOutput `
            -WhisperCLIPath $mockWhisperOutput `
            -WhisperModelPath $agentOutput `
            -GitMetadata $gitMetadata `
            -PackageIdentity $packageIdentityProof `
            -ReportCheckerScriptPath $checkReportScriptOutput `
            -SetCheckerScriptPath $checkSetScriptOutput `
            -Name "Native" `
            -IncludeLocalWhisper $false | Out-Null
    }

    Invoke-Step "local whisper laptop preflight report checker smoke" {
        Invoke-RomaWindowsLaptopPreflightCheckerSmoke `
            -ReportPath $laptopPreflightCheckerSmokeReport `
            -PackageDir $OutputDir `
            -ProofDir $laptopPreflightCheckerSmokeDir `
            -ProofAgentPath $proofAgentOutput `
            -WhisperCLIPath $mockWhisperOutput `
            -WhisperModelPath $agentOutput `
            -GitMetadata $gitMetadata `
            -PackageIdentity $packageIdentityProof `
            -ReportCheckerScriptPath $checkReportScriptOutput `
            -SetCheckerScriptPath $checkSetScriptOutput `
            -Name "Local whisper" `
            -IncludeLocalWhisper $true | Out-Null
    }

    Invoke-Step "manifest nested relocation smoke" {
        Invoke-RomaWindowsManifestNestedRelocationSmoke `
            -ManifestPath $manifestPath `
            -PackageDir $OutputDir `
            -Keys @(
                "laptop_native_preflight_checker_smoke_report",
                "laptop_preflight_checker_smoke_report"
            )
    }

    Write-Host ""
    Write-Host "package_artifacts=$OutputDir"
    Write-Host "source_commit=$($gitMetadata.Commit)"
    Write-Host "source_dirty=$($gitMetadata.Dirty)"
    Write-Host "manifest=$manifestPath"
} finally {
    Pop-Location
}
