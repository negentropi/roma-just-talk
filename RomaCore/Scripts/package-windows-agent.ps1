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

function Invoke-GitLines {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    try {
        $output = & git @Arguments 2>$null
        if ($LASTEXITCODE -ne 0) {
            return @()
        }

        return @($output)
    } catch {
        return @()
    }
}

function Get-GitMetadata {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepositoryRoot
    )

    Push-Location $RepositoryRoot
    try {
        $commit = (@(Invoke-GitLines -Arguments @("rev-parse", "--verify", "HEAD")) -join "`n").Trim()
        if ([string]::IsNullOrWhiteSpace($commit)) {
            throw "Could not resolve source git commit"
        }

        $branch = (@(Invoke-GitLines -Arguments @("rev-parse", "--abbrev-ref", "HEAD")) -join "`n").Trim()
        if ([string]::IsNullOrWhiteSpace($branch)) {
            $branch = "unknown"
        }

        $repository = (@(Invoke-GitLines -Arguments @("config", "--get", "remote.roma-just-talk.url")) -join "`n").Trim()
        if ([string]::IsNullOrWhiteSpace($repository)) {
            $repository = (@(Invoke-GitLines -Arguments @("config", "--get", "remote.origin.url")) -join "`n").Trim()
        }
        if ([string]::IsNullOrWhiteSpace($repository)) {
            $repository = "unknown"
        }

        $statusLines = @(Invoke-GitLines -Arguments @("status", "--porcelain"))
        return @{
            Commit = $commit
            Branch = $branch
            Repository = $repository
            Dirty = ($statusLines.Count -gt 0).ToString().ToLowerInvariant()
        }
    } finally {
        Pop-Location
    }
}

function Invoke-ManifestNestedRelocationSmoke {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ManifestPath,
        [Parameter(Mandatory = $true)]
        [string]$PackageDir,
        [Parameter(Mandatory = $true)]
        [string[]]$Keys
    )

    $manifest = Read-RomaWindowsManifest -Path $ManifestPath
    $staleRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("roma-stale-artifact-" + [guid]::NewGuid().ToString("N"))
    $proofs = @()
    foreach ($key in $Keys) {
        $expectedPath = Require-RomaWindowsManifestFile -Manifest $manifest -Key $key -BaseDir $PackageDir
        $expectedFullPath = [System.IO.Path]::GetFullPath($expectedPath)
        $leaf = Split-Path -Leaf $expectedFullPath
        $parentPath = Split-Path -Parent $expectedFullPath
        $parentLeaf = Split-Path -Leaf $parentPath
        if ([string]::IsNullOrWhiteSpace($parentLeaf)) {
            throw "Manifest relocation smoke could not resolve parent directory for $key"
        }

        $proofs += [pscustomobject]@{
            Key = $key
            ExpectedFullPath = $expectedFullPath
            Leaf = $leaf
            ParentLeaf = $parentLeaf
        }
    }

    $uniqueLeaves = @($proofs | ForEach-Object { $_.Leaf } | Sort-Object -Unique)
    if ($uniqueLeaves.Count -ne 1) {
        throw "Manifest nested relocation smoke expected duplicate leaf names, got: $($uniqueLeaves -join ', ')"
    }
    Write-Host "manifest_nested_relocation_duplicate_leaf=$($uniqueLeaves[0])"

    foreach ($proof in $proofs) {
        $key = [string]$proof.Key
        $expectedFullPath = [string]$proof.ExpectedFullPath
        $leaf = [string]$proof.Leaf
        $parentLeaf = [string]$proof.ParentLeaf
        $relocatedManifest = @{}
        foreach ($manifestKey in $manifest.Keys) {
            $relocatedManifest[$manifestKey] = $manifest[$manifestKey]
        }

        $stalePath = Join-Path (Join-Path $staleRoot $parentLeaf) $leaf
        if (Test-Path -LiteralPath $stalePath) {
            throw "Manifest relocation smoke stale path unexpectedly exists: $stalePath"
        }
        $relocatedManifest[$key] = $stalePath

        $actualPath = Require-RomaWindowsManifestFile -Manifest $relocatedManifest -Key $key -BaseDir $PackageDir
        $actualFullPath = [System.IO.Path]::GetFullPath($actualPath)
        if ($actualFullPath -ne $expectedFullPath) {
            throw "Manifest relocation smoke resolved $key to $actualFullPath, expected $expectedFullPath"
        }

        Write-Host "manifest_nested_relocation_key=$key"
        Write-Host "manifest_nested_relocation_path=$actualFullPath"
    }

    Write-Host "manifest_nested_relocation_ok=true"
}

$packageRoot = Resolve-Path "$PSScriptRoot\.."
if ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
    throw "package-windows-agent.ps1 must run on Windows so packaged executables and Swift runtime DLLs are Windows artifacts"
}

$gitMetadata = Get-GitMetadata -RepositoryRoot $packageRoot
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
    $smokeScriptSource = $sourceArtifactPaths["smoke_script"]
    $smokeScriptOutput = $outputArtifactPaths["smoke_script"]
    $runScriptSource = $sourceArtifactPaths["run_script"]
    $runScriptOutput = $outputArtifactPaths["run_script"]
    $installScriptSource = $sourceArtifactPaths["install_script"]
    $installScriptOutput = $outputArtifactPaths["install_script"]
    $proofScriptSource = $sourceArtifactPaths["proof_script"]
    $proofScriptOutput = $outputArtifactPaths["proof_script"]
    $laptopProofScriptSource = $sourceArtifactPaths["laptop_proof_script"]
    $laptopProofScriptOutput = $outputArtifactPaths["laptop_proof_script"]
    $parseScriptSource = $sourceArtifactPaths["parse_script"]
    $parseScriptOutput = $outputArtifactPaths["parse_script"]
    $identityScriptSource = $sourceArtifactPaths["package_identity_script"]
    $identityScriptOutput = $outputArtifactPaths["package_identity_script"]
    $proofCommonScriptSource = $sourceArtifactPaths["proof_common_script"]
    $proofCommonScriptOutput = $outputArtifactPaths["proof_common_script"]
    $manifestScriptSource = $sourceArtifactPaths["manifest_script"]
    $manifestScriptOutput = $outputArtifactPaths["manifest_script"]
    $checkReportScriptSource = $sourceArtifactPaths["check_report_script"]
    $checkReportScriptOutput = $outputArtifactPaths["check_report_script"]
    $checkSetScriptSource = $sourceArtifactPaths["check_set_script"]
    $checkSetScriptOutput = $outputArtifactPaths["check_set_script"]
    $laptopProofGuideOutput = $outputArtifactPaths["laptop_proof_guide"]
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
        Copy-Item -LiteralPath $agentSource.FullName -Destination $agentOutput -Force
        $agentItem = Get-Item -LiteralPath $agentOutput
        if ($agentItem.Length -le 0) {
            throw "RomaWindowsAgent.exe is empty: $agentOutput"
        }
        Write-Host "agent_exe=$agentOutput"
        Write-Host "bytes=$($agentItem.Length)"

        $pdbSource = [System.IO.Path]::ChangeExtension($agentSource.FullName, ".pdb")
        if (Test-Path -LiteralPath $pdbSource) {
            $pdbOutput = $outputArtifactPaths["agent_pdb"]
            Copy-Item -LiteralPath $pdbSource -Destination $pdbOutput -Force
            Write-Host "agent_pdb=$pdbOutput"
        }

        Copy-Item -LiteralPath $proofAgentSource.FullName -Destination $proofAgentOutput -Force
        $proofAgentItem = Get-Item -LiteralPath $proofAgentOutput
        if ($proofAgentItem.Length -le 0) {
            throw "RomaProofAgent.exe is empty: $proofAgentOutput"
        }
        Write-Host "proof_agent_exe=$proofAgentOutput"
        Write-Host "proof_agent_bytes=$($proofAgentItem.Length)"

        $proofAgentPdbSource = [System.IO.Path]::ChangeExtension($proofAgentSource.FullName, ".pdb")
        if (Test-Path -LiteralPath $proofAgentPdbSource) {
            $proofAgentPdbOutput = $outputArtifactPaths["proof_agent_pdb"]
            Copy-Item -LiteralPath $proofAgentPdbSource -Destination $proofAgentPdbOutput -Force
            Write-Host "proof_agent_pdb=$proofAgentPdbOutput"
        }

        Copy-Item -LiteralPath $mockWhisperSource.FullName -Destination $mockWhisperOutput -Force
        $mockWhisperItem = Get-Item -LiteralPath $mockWhisperOutput
        if ($mockWhisperItem.Length -le 0) {
            throw "RomaWhisperCLIMock.exe is empty: $mockWhisperOutput"
        }
        Write-Host "whisper_cli_mock=$mockWhisperOutput"
        Write-Host "whisper_cli_mock_bytes=$($mockWhisperItem.Length)"

        Copy-Item -LiteralPath $smokeScriptSource -Destination $smokeScriptOutput -Force
        Write-Host "smoke_script=$smokeScriptOutput"
        Copy-Item -LiteralPath $runScriptSource -Destination $runScriptOutput -Force
        Write-Host "run_script=$runScriptOutput"
        Copy-Item -LiteralPath $installScriptSource -Destination $installScriptOutput -Force
        Write-Host "install_script=$installScriptOutput"
        Copy-Item -LiteralPath $proofScriptSource -Destination $proofScriptOutput -Force
        Write-Host "proof_script=$proofScriptOutput"
        Copy-Item -LiteralPath $laptopProofScriptSource -Destination $laptopProofScriptOutput -Force
        Write-Host "laptop_proof_script=$laptopProofScriptOutput"
        Copy-Item -LiteralPath $parseScriptSource -Destination $parseScriptOutput -Force
        Write-Host "parse_script=$parseScriptOutput"
        Copy-Item -LiteralPath $identityScriptSource -Destination $identityScriptOutput -Force
        Write-Host "package_identity_script=$identityScriptOutput"
        Copy-Item -LiteralPath $proofCommonScriptSource -Destination $proofCommonScriptOutput -Force
        Write-Host "proof_common_script=$proofCommonScriptOutput"
        Copy-Item -LiteralPath $manifestScriptSource -Destination $manifestScriptOutput -Force
        Write-Host "manifest_script=$manifestScriptOutput"
        Copy-Item -LiteralPath $checkReportScriptSource -Destination $checkReportScriptOutput -Force
        Write-Host "check_report_script=$checkReportScriptOutput"
        Copy-Item -LiteralPath $checkSetScriptSource -Destination $checkSetScriptOutput -Force
        Write-Host "check_set_script=$checkSetScriptOutput"
        Write-RomaWindowsLaptopProofGuide -OutputPath $laptopProofGuideOutput
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
    $agentFile = Get-Item -LiteralPath $agentOutput
    @(
        "agent=RomaWindowsAgent",
        "configuration=$Configuration",
        "source_repository=$($gitMetadata.Repository)",
        "source_branch=$($gitMetadata.Branch)",
        "source_commit=$($gitMetadata.Commit)",
        "source_dirty=$($gitMetadata.Dirty)",
        "source=$($agentSource.FullName)",
        "output=$agentOutput",
        "proof_agent=$(Get-RomaWindowsProofAgentExecutableFileName)",
        "sample_config=$configPath",
        "sample_local_whisper_config=$localWhisperConfigPath",
        "whisper_cli_mock=$(Get-RomaWindowsWhisperCLIMockExecutableFileName)",
        "install_proof_dir=$installProofDir",
        "install_proof_config=$installProofConfigPath",
        "install_proof_shortcut=$shortcutPath",
        "local_whisper_install_proof_dir=$localWhisperInstallProofDir",
        "local_whisper_install_config=$localWhisperInstallConfigPath",
        "local_whisper_shortcut=$localWhisperShortcutPath",
        "laptop_native_preflight_checker_smoke_report=$laptopNativePreflightCheckerSmokeReport",
        "laptop_preflight_checker_smoke_report=$laptopPreflightCheckerSmokeReport",
        "smoke_script=$smokeScriptOutput",
        "run_script=$runScriptOutput",
        "install_script=$installScriptOutput",
        "proof_script=$proofScriptOutput",
        "laptop_proof_script=$laptopProofScriptOutput",
        "laptop_proof_guide=$laptopProofGuideOutput",
        "parse_script=$parseScriptOutput",
        "package_identity_script=$identityScriptOutput",
        "proof_common_script=$proofCommonScriptOutput",
        "manifest_script=$manifestScriptOutput",
        "check_report_script=$checkReportScriptOutput",
        "check_set_script=$checkSetScriptOutput",
        "swift_runtime_dir=$($swiftRuntime.Directory)",
        "swift_runtime_dlls=$($swiftRuntime.DllCount)",
        "bytes=$($agentFile.Length)"
    ) | Set-Content -LiteralPath $manifestPath -Encoding UTF8

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
        Invoke-ManifestNestedRelocationSmoke `
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
