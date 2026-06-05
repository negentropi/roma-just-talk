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

function Get-RomaWindowsDefaultInstallDir {
    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        throw "LOCALAPPDATA is not set; pass -InstallDir explicitly"
    }

    return Join-Path $env:LOCALAPPDATA "roma-just-talk\agent"
}

function Get-RomaWindowsUserAgentConfigPath {
    if ([string]::IsNullOrWhiteSpace($env:APPDATA)) {
        return ""
    }

    return Join-Path $env:APPDATA "roma-just-talk\windows-agent.json"
}

function Join-RomaWindowsInstalledAgentConfigPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallDir
    )

    return Join-Path $InstallDir "windows-agent.json"
}

function Join-RomaWindowsInstalledSecretDirPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallDir
    )

    return Join-Path $InstallDir "secrets"
}

function Join-RomaWindowsInstalledSmokeDirPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallDir
    )

    return Join-Path $InstallDir "smoke"
}

function Join-RomaWindowsInstallSmokeConfigPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallDir
    )

    return Join-Path (Join-RomaWindowsInstalledSmokeDirPath -InstallDir $InstallDir) "windows-agent-smoke.json"
}

function Join-RomaWindowsInstalledDictationRuntimeLogPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallDir
    )

    return Join-Path (Join-RomaWindowsInstalledSmokeDirPath -InstallDir $InstallDir) "windows-agent-dictate.log"
}

function Join-RomaWindowsInstalledListenerRuntimeLogPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallDir
    )

    return Join-Path (Join-RomaWindowsInstalledSmokeDirPath -InstallDir $InstallDir) "windows-agent-listen.log"
}

function Join-RomaWindowsInstalledNotepadPasteProofPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallDir
    )

    return Join-Path (Join-RomaWindowsInstalledSmokeDirPath -InstallDir $InstallDir) "notepad-paste-proof.txt"
}

function Get-RomaWindowsAgentExecutableFileName {
    return "RomaWindowsAgent.exe"
}

function Get-RomaWindowsProofAgentExecutableFileName {
    return "RomaProofAgent.exe"
}

function Get-RomaWindowsWhisperCLIMockExecutableFileName {
    return "RomaWhisperCLIMock.exe"
}

function Get-RomaWindowsAgentDebugFileName {
    return "RomaWindowsAgent.pdb"
}

function Get-RomaWindowsProofAgentDebugFileName {
    return "RomaProofAgent.pdb"
}

function Get-RomaWindowsAgentArtifactPathSet {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ArtifactDir
    )

    return [ordered]@{
        agent = Join-Path $ArtifactDir (Get-RomaWindowsAgentExecutableFileName)
        proof_agent = Join-Path $ArtifactDir (Get-RomaWindowsProofAgentExecutableFileName)
        whisper_cli_mock = Join-Path $ArtifactDir (Get-RomaWindowsWhisperCLIMockExecutableFileName)
        agent_pdb = Join-Path $ArtifactDir (Get-RomaWindowsAgentDebugFileName)
        proof_agent_pdb = Join-Path $ArtifactDir (Get-RomaWindowsProofAgentDebugFileName)
        smoke_script = Join-Path $ArtifactDir "smoke-windows-agent.ps1"
        run_script = Join-Path $ArtifactDir "run-windows-agent.ps1"
        install_script = Join-Path $ArtifactDir "install-windows-agent.ps1"
        proof_script = Join-Path $ArtifactDir "prove-windows-agent-artifact.ps1"
        laptop_proof_script = Join-Path $ArtifactDir "run-windows-laptop-proof.ps1"
        laptop_proof_guide = Join-Path $ArtifactDir "WINDOWS-LAPTOP-PROOF.txt"
        parse_script = Join-Path $ArtifactDir "check-windows-scripts-parse.ps1"
        package_identity_script = Join-Path $ArtifactDir "windows-package-identity.ps1"
        proof_common_script = Join-Path $ArtifactDir "windows-proof-common.ps1"
        manifest_script = Join-Path $ArtifactDir "windows-manifest.ps1"
        check_report_script = Join-Path $ArtifactDir "check-windows-proof-report.ps1"
        check_set_script = Join-Path $ArtifactDir "check-windows-proof-set.ps1"
        manifest = Join-Path $ArtifactDir "manifest.txt"
        sample_config = Join-Path $ArtifactDir "sample-windows-agent.json"
        sample_local_whisper_config = Join-Path $ArtifactDir "sample-local-whisper-agent.json"
    }
}

function Resolve-RomaWindowsProductExecutable {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BuildDirectory,
        [Parameter(Mandatory = $true)]
        [string]$Configuration,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $preferred = Join-Path $BuildDirectory "$Configuration\$Name.exe"
    if (Test-Path -LiteralPath $preferred) {
        return Get-Item -LiteralPath $preferred
    }

    $matchingConfiguration = Get-ChildItem -Path $BuildDirectory -Filter "$Name.exe" -Recurse |
        Where-Object { $_.FullName -like "*\$Configuration\*" } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($matchingConfiguration) {
        return $matchingConfiguration
    }

    $anyExecutable = Get-ChildItem -Path $BuildDirectory -Filter "$Name.exe" -Recurse |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($anyExecutable) {
        return $anyExecutable
    }

    throw "$Name executable was not found under $BuildDirectory"
}

function Resolve-RomaWindowsSwiftRuntimeDirectory {
    $pathSeparator = [System.IO.Path]::PathSeparator
    $pathDirectories = $env:PATH -split [regex]::Escape($pathSeparator) |
        Where-Object { ![string]::IsNullOrWhiteSpace($_) }

    foreach ($directory in $pathDirectories) {
        $candidate = Join-Path $directory "swiftCore.dll"
        if (Test-Path -LiteralPath $candidate) {
            return Get-Item -LiteralPath $directory
        }
    }

    return $null
}

function Copy-RomaWindowsSwiftRuntimeLibraries {
    param(
        [Parameter(Mandatory = $true)]
        [string]$OutputDir
    )

    $runtimeDirectory = Resolve-RomaWindowsSwiftRuntimeDirectory
    if (!$runtimeDirectory) {
        Write-Host "swift_runtime_dir=not_found"
        Write-Host "swift_runtime_dlls=0"
        return @{
            Directory = ""
            DllCount = 0
        }
    }

    $runtimeLibraries = @(
        Get-ChildItem -LiteralPath $runtimeDirectory.FullName -Filter "*.dll" |
            Sort-Object Name
    )
    foreach ($library in $runtimeLibraries) {
        Copy-Item -LiteralPath $library.FullName -Destination (Join-Path $OutputDir $library.Name) -Force
    }

    Write-Host "swift_runtime_dir=$($runtimeDirectory.FullName)"
    Write-Host "swift_runtime_dlls=$($runtimeLibraries.Count)"

    return @{
        Directory = $runtimeDirectory.FullName
        DllCount = $runtimeLibraries.Count
    }
}

function Assert-RomaWindowsSwiftRuntimePackaged {
    param(
        [Parameter(Mandatory = $true)]
        [string]$OutputDir,
        [Parameter(Mandatory = $true)]
        [hashtable]$SwiftRuntime
    )

    if ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
        return
    }

    if ($SwiftRuntime.DllCount -le 0) {
        throw "Swift runtime DLLs were not copied into the Windows agent artifact"
    }

    $swiftCore = Join-Path $OutputDir "swiftCore.dll"
    if (!(Test-Path -LiteralPath $swiftCore)) {
        throw "swiftCore.dll was not copied into the Windows agent artifact"
    }

    Write-Host "asserted_runtime_dll=swiftCore.dll"
}

function Copy-RomaWindowsAgentArtifactBundle {
    param(
        [Parameter(Mandatory = $true)]
        [object]$AgentSource,
        [Parameter(Mandatory = $true)]
        [object]$ProofAgentSource,
        [Parameter(Mandatory = $true)]
        [object]$WhisperCLIMockSource,
        [Parameter(Mandatory = $true)]
        [object]$SourceArtifactPaths,
        [Parameter(Mandatory = $true)]
        [object]$OutputArtifactPaths
    )

    $agentOutput = $OutputArtifactPaths["agent"]
    Copy-Item -LiteralPath $AgentSource.FullName -Destination $agentOutput -Force
    $agentItem = Get-Item -LiteralPath $agentOutput
    if ($agentItem.Length -le 0) {
        throw "RomaWindowsAgent.exe is empty: $agentOutput"
    }
    Write-Host "agent_exe=$agentOutput"
    Write-Host "bytes=$($agentItem.Length)"

    $pdbSource = [System.IO.Path]::ChangeExtension($AgentSource.FullName, ".pdb")
    if (Test-Path -LiteralPath $pdbSource) {
        $pdbOutput = $OutputArtifactPaths["agent_pdb"]
        Copy-Item -LiteralPath $pdbSource -Destination $pdbOutput -Force
        Write-Host "agent_pdb=$pdbOutput"
    }

    $proofAgentOutput = $OutputArtifactPaths["proof_agent"]
    Copy-Item -LiteralPath $ProofAgentSource.FullName -Destination $proofAgentOutput -Force
    $proofAgentItem = Get-Item -LiteralPath $proofAgentOutput
    if ($proofAgentItem.Length -le 0) {
        throw "RomaProofAgent.exe is empty: $proofAgentOutput"
    }
    Write-Host "proof_agent_exe=$proofAgentOutput"
    Write-Host "proof_agent_bytes=$($proofAgentItem.Length)"

    $proofAgentPdbSource = [System.IO.Path]::ChangeExtension($ProofAgentSource.FullName, ".pdb")
    if (Test-Path -LiteralPath $proofAgentPdbSource) {
        $proofAgentPdbOutput = $OutputArtifactPaths["proof_agent_pdb"]
        Copy-Item -LiteralPath $proofAgentPdbSource -Destination $proofAgentPdbOutput -Force
        Write-Host "proof_agent_pdb=$proofAgentPdbOutput"
    }

    $mockWhisperOutput = $OutputArtifactPaths["whisper_cli_mock"]
    Copy-Item -LiteralPath $WhisperCLIMockSource.FullName -Destination $mockWhisperOutput -Force
    $mockWhisperItem = Get-Item -LiteralPath $mockWhisperOutput
    if ($mockWhisperItem.Length -le 0) {
        throw "RomaWhisperCLIMock.exe is empty: $mockWhisperOutput"
    }
    Write-Host "whisper_cli_mock=$mockWhisperOutput"
    Write-Host "whisper_cli_mock_bytes=$($mockWhisperItem.Length)"

    foreach ($key in Get-RomaWindowsAgentArtifactCopiedProofSurfacePathKeys) {
        $scriptSource = $SourceArtifactPaths[$key]
        $scriptOutput = $OutputArtifactPaths[$key]
        Copy-Item -LiteralPath $scriptSource -Destination $scriptOutput -Force
        Write-Host "$key=$scriptOutput"
    }

    Write-RomaWindowsLaptopProofGuide -OutputPath $OutputArtifactPaths["laptop_proof_guide"]
}

function Get-RomaWindowsAgentArtifactManifestConfigPathKeys {
    return @(
        "sample_config",
        "sample_local_whisper_config"
    )
}

function Get-RomaWindowsAgentArtifactConfigPathKeys {
    return @(
        "manifest"
        Get-RomaWindowsAgentArtifactManifestConfigPathKeys
    )
}

function Get-RomaWindowsAgentArtifactManifestScriptPathKeys {
    return @(
        "smoke_script",
        "run_script",
        "install_script",
        "proof_script",
        "laptop_proof_script",
        "laptop_proof_guide",
        "parse_script",
        "package_identity_script",
        "proof_common_script",
        "manifest_script",
        "check_report_script",
        "check_set_script"
    )
}

function Get-RomaWindowsAgentArtifactCopiedProofSurfacePathKeys {
    return Get-RomaWindowsAgentArtifactManifestScriptPathKeys |
        Where-Object { [string]$_ -ne "laptop_proof_guide" }
}

function Get-RomaWindowsAgentInstallerRequiredPackagePathKeys {
    return @(
        "agent",
        "smoke_script",
        "run_script"
    )
}

function Get-RomaWindowsAgentArtifactManifestPathKeys {
    return @(
        Get-RomaWindowsAgentArtifactManifestConfigPathKeys
        Get-RomaWindowsAgentArtifactManifestScriptPathKeys
    )
}

function Get-RomaWindowsAgentArtifactFileNameForKey {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Key
    )

    $artifactPaths = Get-RomaWindowsAgentArtifactPathSet -ArtifactDir "."
    if (!$artifactPaths.Contains($Key)) {
        throw "Unknown Windows agent artifact key: $Key"
    }

    return Split-Path -Leaf $artifactPaths[$Key]
}

function Get-RomaWindowsAgentArtifactFileNamesForKeys {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Keys
    )

    foreach ($key in $Keys) {
        Get-RomaWindowsAgentArtifactFileNameForKey -Key ([string]$key)
    }
}

function Require-RomaWindowsAgentArtifactPathKeys {
    param(
        [Parameter(Mandatory = $true)]
        [object]$ArtifactPaths,
        [Parameter(Mandatory = $true)]
        [object[]]$Keys
    )

    foreach ($key in $Keys) {
        if (!$ArtifactPaths.Contains([string]$key)) {
            throw "Unknown Windows agent artifact key: $key"
        }
        Require-RomaWindowsFile -Path $ArtifactPaths[[string]$key]
    }
}

function Require-RomaWindowsAgentInstallerPackageArtifacts {
    param(
        [Parameter(Mandatory = $true)]
        [object]$PackageArtifactPaths
    )

    Require-RomaWindowsAgentArtifactPathKeys `
        -ArtifactPaths $PackageArtifactPaths `
        -Keys (Get-RomaWindowsAgentInstallerRequiredPackagePathKeys)
}

function Write-RomaWindowsAgentArtifactManifest {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ManifestPath,
        [Parameter(Mandatory = $true)]
        [string]$Configuration,
        [Parameter(Mandatory = $true)]
        [object]$GitMetadata,
        [Parameter(Mandatory = $true)]
        [object]$AgentSource,
        [Parameter(Mandatory = $true)]
        [object]$OutputArtifactPaths,
        [Parameter(Mandatory = $true)]
        [hashtable]$SwiftRuntime,
        [Parameter(Mandatory = $true)]
        [string]$InstallProofDir,
        [Parameter(Mandatory = $true)]
        [string]$InstallProofConfigPath,
        [Parameter(Mandatory = $true)]
        [string]$ShortcutPath,
        [Parameter(Mandatory = $true)]
        [string]$LocalWhisperInstallProofDir,
        [Parameter(Mandatory = $true)]
        [string]$LocalWhisperInstallConfigPath,
        [Parameter(Mandatory = $true)]
        [string]$LocalWhisperShortcutPath,
        [Parameter(Mandatory = $true)]
        [string]$LaptopNativePreflightCheckerSmokeReport,
        [Parameter(Mandatory = $true)]
        [string]$LaptopPreflightCheckerSmokeReport
    )

    $agentOutput = $OutputArtifactPaths["agent"]
    $agentFile = Get-Item -LiteralPath $agentOutput
    $manifestLines = @(
        "agent=RomaWindowsAgent",
        "configuration=$Configuration",
        "source_repository=$($GitMetadata.Repository)",
        "source_branch=$($GitMetadata.Branch)",
        "source_commit=$($GitMetadata.Commit)",
        "source_dirty=$($GitMetadata.Dirty)",
        "source=$($AgentSource.FullName)",
        "output=$agentOutput",
        "proof_agent=$(Get-RomaWindowsProofAgentExecutableFileName)"
    )
    foreach ($artifactKey in Get-RomaWindowsAgentArtifactManifestConfigPathKeys) {
        $manifestLines += "$artifactKey=$($OutputArtifactPaths[$artifactKey])"
    }

    $manifestLines += @(
        "whisper_cli_mock=$(Get-RomaWindowsWhisperCLIMockExecutableFileName)",
        "install_proof_dir=$InstallProofDir",
        "install_proof_config=$InstallProofConfigPath",
        "install_proof_shortcut=$ShortcutPath",
        "local_whisper_install_proof_dir=$LocalWhisperInstallProofDir",
        "local_whisper_install_config=$LocalWhisperInstallConfigPath",
        "local_whisper_shortcut=$LocalWhisperShortcutPath",
        "laptop_native_preflight_checker_smoke_report=$LaptopNativePreflightCheckerSmokeReport",
        "laptop_preflight_checker_smoke_report=$LaptopPreflightCheckerSmokeReport"
    )
    foreach ($artifactKey in Get-RomaWindowsAgentArtifactManifestScriptPathKeys) {
        $manifestLines += "$artifactKey=$($OutputArtifactPaths[$artifactKey])"
    }

    $manifestLines += @(
        "swift_runtime_dir=$($SwiftRuntime.Directory)",
        "swift_runtime_dlls=$($SwiftRuntime.DllCount)",
        "bytes=$($agentFile.Length)"
    )
    $manifestLines | Set-Content -LiteralPath $ManifestPath -Encoding UTF8
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

function Assert-RomaWindowsFileWithMinimumBytes {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [int64]$MinimumBytes = 1,
        [switch]$WriteProofFileMarkers
    )

    if (!(Test-Path -LiteralPath $Path)) {
        throw "Expected file was not created: $Path"
    }

    $item = Get-Item -LiteralPath $Path
    if ($item.Length -lt $MinimumBytes) {
        throw "Expected file to have at least $MinimumBytes bytes: $Path bytes=$($item.Length)"
    }

    Write-Host "file=$Path"
    Write-Host "bytes=$($item.Length)"
    if ($WriteProofFileMarkers) {
        Write-Host "proof_file=$Path"
        Write-Host "proof_file_bytes=$($item.Length)"
    }
}

function Assert-RomaWindowsProofSessionId {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value,
        [string]$Name = "proof_session_id",
        [string]$ReportName = "",
        [switch]$WriteProofValue
    )

    if ($Value -notmatch "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$") {
        if ([string]::IsNullOrWhiteSpace($ReportName)) {
            throw "Expected $Name to be a GUID, got: $Value"
        }
        throw "Proof set report $ReportName has invalid ${Name}; expected GUID, got: $Value"
    }
    if ($Value -eq "00000000-0000-0000-0000-000000000000") {
        if ([string]::IsNullOrWhiteSpace($ReportName)) {
            throw "Expected $Name to be a non-placeholder GUID"
        }
        throw "Proof set report $ReportName has placeholder $Name"
    }

    $normalizedValue = $Value.ToLowerInvariant()
    if ($WriteProofValue) {
        Write-Host "proof_value=$Name value=$normalizedValue"
    }
    return $normalizedValue
}

function ConvertTo-RomaWindowsProofTimestamp {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value,
        [string]$Name = "generated_at",
        [string]$ReportName = "",
        [switch]$WriteProofValue
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        if ([string]::IsNullOrWhiteSpace($ReportName)) {
            throw "Expected non-empty timestamp: $Name"
        }
        throw "Proof set report $ReportName has empty $Name"
    }

    try {
        $timestamp = [System.DateTimeOffset]::Parse(
            $Value,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::AssumeUniversal
        ).ToUniversalTime()
    } catch {
        if ([string]::IsNullOrWhiteSpace($ReportName)) {
            throw "Expected valid timestamp for $Name, got: $Value"
        }
        throw "Proof set report $ReportName has invalid $Name timestamp: $Value"
    }

    if ($WriteProofValue) {
        Write-Host "proof_value=$Name utc=$($timestamp.ToString("o"))"
    }
    return $timestamp
}

function Require-RomaWindowsObjectProperty {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Object,
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [string]$Context = "proof object"
    )

    if ($null -eq $Object -or !($Object.PSObject.Properties.Name -contains $Name)) {
        throw "$Context is missing property: $Name"
    }

    return $Object.PSObject.Properties[$Name].Value
}

function Require-RomaWindowsProofReportProperty {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Object,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    return Require-RomaWindowsObjectProperty `
        -Object $Object `
        -Name $Name `
        -Context "proof report"
}

function Assert-RomaWindowsProofReportBoolean {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Object,
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [bool]$Expected
    )

    $actual = [bool](Require-RomaWindowsProofReportProperty -Object $Object -Name $Name)
    if ($actual -ne $Expected) {
        throw "Expected $Name to be $Expected, got $actual"
    }

    Write-Host "proof_bool=$Name value=$actual"
}

function Assert-RomaWindowsProofReportNonEmptyString {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Object,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $value = [string](Require-RomaWindowsProofReportProperty -Object $Object -Name $Name)
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "Expected non-empty proof report property: $Name"
    }

    Write-Host "proof_value=$Name value=$value"
}

function Get-RomaWindowsProofReportNonEmptyString {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Object,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    Assert-RomaWindowsProofReportNonEmptyString -Object $Object -Name $Name
    return [string](Require-RomaWindowsProofReportProperty -Object $Object -Name $Name)
}

function Assert-RomaWindowsProofReportStringEquals {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Actual,
        [Parameter(Mandatory = $true)]
        [string]$Expected,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if ($Actual -ne $Expected) {
        throw "Expected $Name to be '$Expected', got '$Actual'"
    }

    Write-Host "proof_value=$Name value=$Actual"
}

function Assert-RomaWindowsProofReportNumberGreaterThan {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Object,
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [double]$Minimum
    )

    $actual = [double](Require-RomaWindowsProofReportProperty -Object $Object -Name $Name)
    if ($actual -le $Minimum) {
        throw "Expected $Name to be greater than $Minimum, got $actual"
    }

    Write-Host "proof_number=$Name value=$actual minimum=$Minimum"
}

function Assert-RomaWindowsProofReportNumberEquals {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Object,
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [double]$Expected
    )

    $actual = [double](Require-RomaWindowsProofReportProperty -Object $Object -Name $Name)
    if ($actual -ne $Expected) {
        throw "Expected $Name to equal $Expected, got $actual"
    }

    Write-Host "proof_number=$Name value=$actual expected=$Expected"
}

function Assert-RomaWindowsProofReportFile {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Proof,
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [int64]$MinimumBytes = 1
    )

    $path = [string](Require-RomaWindowsProofReportProperty -Object $Proof -Name "path")
    $exists = [bool](Require-RomaWindowsProofReportProperty -Object $Proof -Name "exists")
    $bytes = [int64](Require-RomaWindowsProofReportProperty -Object $Proof -Name "bytes")

    if ([string]::IsNullOrWhiteSpace($path)) {
        throw "$Name path is empty"
    }
    if (!$exists) {
        throw "$Name does not exist: $path"
    }
    if ($bytes -lt $MinimumBytes) {
        throw "$Name has too few bytes: $path bytes=$bytes minimum=$MinimumBytes"
    }

    Write-Host "proof_file=$Name path=$path bytes=$bytes"
}

function Assert-RomaWindowsProofReportFileHashEquals {
    param(
        [Parameter(Mandatory = $true)]
        [object]$ActualProof,
        [Parameter(Mandatory = $true)]
        [object]$ExpectedProof,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $actualHash = [string](Require-RomaWindowsProofReportProperty -Object $ActualProof -Name "sha256")
    $expectedHash = [string](Require-RomaWindowsProofReportProperty -Object $ExpectedProof -Name "sha256")
    if ([string]::IsNullOrWhiteSpace($actualHash)) {
        throw "$Name actual sha256 is empty"
    }
    if ([string]::IsNullOrWhiteSpace($expectedHash)) {
        throw "$Name expected sha256 is empty"
    }
    if ($actualHash -ne $expectedHash) {
        throw "Expected $Name sha256 to be $expectedHash, got $actualHash"
    }

    Write-Host "proof_hash=$Name sha256=$actualHash"
}

function Assert-RomaWindowsProofReportShortcut {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Proof,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    Assert-RomaWindowsProofReportFile -Proof $Proof -Name $Name
    Assert-RomaWindowsProofReportNonEmptyString -Object $Proof -Name "target_path"
    Assert-RomaWindowsProofReportNonEmptyString -Object $Proof -Name "arguments"
    Assert-RomaWindowsProofReportNonEmptyString -Object $Proof -Name "working_directory"
    Assert-RomaWindowsProofReportNonEmptyString -Object $Proof -Name "expected_arguments"
    Assert-RomaWindowsProofReportBoolean -Object $Proof -Name "target_is_powershell" -Expected $true
    Assert-RomaWindowsProofReportBoolean -Object $Proof -Name "has_exact_arguments" -Expected $true
    Assert-RomaWindowsProofReportBoolean -Object $Proof -Name "references_run_script" -Expected $true
    Assert-RomaWindowsProofReportNonEmptyString -Object $Proof -Name "expected_file_argument"
    Assert-RomaWindowsProofReportBoolean -Object $Proof -Name "has_exact_file_argument" -Expected $true
    Assert-RomaWindowsProofReportBoolean -Object $Proof -Name "has_install_dir_argument" -Expected $true
    Assert-RomaWindowsProofReportBoolean -Object $Proof -Name "references_install_dir" -Expected $true
    Assert-RomaWindowsProofReportNonEmptyString -Object $Proof -Name "expected_install_dir_argument"
    Assert-RomaWindowsProofReportBoolean -Object $Proof -Name "has_exact_install_dir_argument" -Expected $true
    Assert-RomaWindowsProofReportBoolean -Object $Proof -Name "has_config_path_argument" -Expected $true
    Assert-RomaWindowsProofReportBoolean -Object $Proof -Name "references_config_path" -Expected $true
    Assert-RomaWindowsProofReportNonEmptyString -Object $Proof -Name "expected_config_argument"
    Assert-RomaWindowsProofReportBoolean -Object $Proof -Name "has_exact_config_argument" -Expected $true
    Assert-RomaWindowsProofReportBoolean -Object $Proof -Name "has_no_profile_argument" -Expected $true
    Assert-RomaWindowsProofReportBoolean -Object $Proof -Name "has_execution_policy_bypass" -Expected $true
    Assert-RomaWindowsProofReportBoolean -Object $Proof -Name "runs_listener" -Expected $true
    Assert-RomaWindowsProofReportBoolean -Object $Proof -Name "working_directory_is_install_dir" -Expected $true
}

function Assert-RomaWindowsProofReportDictationRuntimeFields {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Runtime,
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [switch]$RequireExpectedTranscriptText
    )

    $runtime = $Runtime
    Assert-RomaWindowsProofReportFile -Proof $runtime -Name "$Name.log"
    Assert-RomaWindowsProofReportBoolean -Object $runtime -Name "reported_wrote" -Expected $true
    Assert-RomaWindowsProofReportNonEmptyString -Object $runtime -Name "wrote_path"
    Assert-RomaWindowsProofReportFile -Proof (Require-RomaWindowsProofReportProperty -Object $runtime -Name "wrote_file") -Name "$Name.wav"
    Assert-RomaWindowsProofReportBoolean -Object $runtime -Name "reported_positive_duration" -Expected $true
    Assert-RomaWindowsProofReportNumberGreaterThan -Object $runtime -Name "duration_seconds" -Minimum 0
    Assert-RomaWindowsProofReportBoolean -Object $runtime -Name "reported_pre_roll" -Expected $true
    Assert-RomaWindowsProofReportBoolean -Object $runtime -Name "reported_positive_pre_roll" -Expected $true
    Assert-RomaWindowsProofReportNumberGreaterThan -Object $runtime -Name "included_pre_roll_seconds" -Minimum 0
    Assert-RomaWindowsProofReportBoolean -Object $runtime -Name "reported_speech_pcm_contract" -Expected $true
    Assert-RomaWindowsProofReportNumberEquals -Object $runtime -Name "sample_rate" -Expected 16000
    Assert-RomaWindowsProofReportNumberEquals -Object $runtime -Name "channels" -Expected 1
    Assert-RomaWindowsProofReportBoolean -Object $runtime -Name "reported_processed_text" -Expected $true
    Assert-RomaWindowsProofReportBoolean -Object $runtime -Name "reported_positive_raw_transcript" -Expected $true
    Assert-RomaWindowsProofReportBoolean -Object $runtime -Name "reported_positive_processed_transcript" -Expected $true
    Assert-RomaWindowsProofReportNumberGreaterThan -Object $runtime -Name "raw_transcript_length" -Minimum 0
    Assert-RomaWindowsProofReportNumberGreaterThan -Object $runtime -Name "processed_transcript_length" -Minimum 0
    if ($RequireExpectedTranscriptText) {
        Assert-RomaWindowsProofReportBoolean -Object $runtime -Name "expected_transcript_text_required" -Expected $true
        Assert-RomaWindowsProofReportNonEmptyString -Object $runtime -Name "expected_transcript_text"
        Assert-RomaWindowsProofReportBoolean -Object $runtime -Name "processed_transcript_text_present" -Expected $true
        Assert-RomaWindowsProofReportStringEquals `
            -Actual ([string](Require-RomaWindowsProofReportProperty -Object $runtime -Name "expected_transcript_text_source")) `
            -Expected "processed_transcript_text" `
            -Name "expected_transcript_text_source"
        Assert-RomaWindowsProofReportBoolean -Object $runtime -Name "expected_transcript_text_found" -Expected $true
    }

    return $runtime
}

function Assert-RomaWindowsProofReportDictationRuntime {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Report,
        [switch]$RequireExpectedTranscriptText
    )

    return Assert-RomaWindowsProofReportDictationRuntimeFields `
        -Runtime (Require-RomaWindowsProofReportProperty -Object $Report -Name "dictation_runtime") `
        -Name "dictation_runtime" `
        -RequireExpectedTranscriptText:$RequireExpectedTranscriptText.IsPresent
}

function Assert-RomaWindowsProofReportListenerRuntime {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Report,
        [switch]$RequireExpectedTranscriptText
    )

    $runtime = Assert-RomaWindowsProofReportDictationRuntimeFields `
        -Runtime (Require-RomaWindowsProofReportProperty -Object $Report -Name "listener_runtime") `
        -Name "listener_runtime" `
        -RequireExpectedTranscriptText:$RequireExpectedTranscriptText.IsPresent
    Assert-RomaWindowsProofReportBoolean -Object $runtime -Name "mode_listen" -Expected $true
    Assert-RomaWindowsProofReportBoolean -Object $runtime -Name "shared_pre_roll_runtime" -Expected $true
    Assert-RomaWindowsProofReportBoolean -Object $runtime -Name "max_sessions_one" -Expected $true
    Assert-RomaWindowsProofReportBoolean -Object $runtime -Name "session_start_one" -Expected $true
    Assert-RomaWindowsProofReportBoolean -Object $runtime -Name "session_completed_one" -Expected $true
    Assert-RomaWindowsProofReportBoolean -Object $runtime -Name "completed_one_session" -Expected $true
    Write-Host "proof_listener_runtime=installed_listener"

    return $runtime
}

function Assert-RomaWindowsProofReportPasteIntent {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Report,
        [Parameter(Mandatory = $true)]
        [object]$Config
    )

    $restoreClipboard = [bool](Require-RomaWindowsProofReportProperty -Object $Report -Name "restore_clipboard")
    $noRestoreClipboard = [bool](Require-RomaWindowsProofReportProperty -Object $Report -Name "no_restore_clipboard")
    if ($restoreClipboard -and $noRestoreClipboard) {
        throw "Paste proof cannot request both restore_clipboard and no_restore_clipboard"
    }

    if ($restoreClipboard) {
        Assert-RomaWindowsProofReportBoolean -Object $Config -Name "restore_clipboard_after_paste" -Expected $true
    }
    if ($noRestoreClipboard) {
        Assert-RomaWindowsProofReportBoolean -Object $Config -Name "restore_clipboard_after_paste" -Expected $false
    }

    Write-Host "proof_paste_restore_clipboard=$restoreClipboard"
    Write-Host "proof_paste_no_restore_clipboard=$noRestoreClipboard"
}

function Assert-RomaWindowsProofReportHoldHookRuntime {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Runtime
    )

    Assert-RomaWindowsProofReportBoolean -Object $Runtime -Name "reported_hold_mode" -Expected $true
    Assert-RomaWindowsProofReportBoolean -Object $Runtime -Name "reported_waiting_for_hold_key_down" -Expected $true
    Assert-RomaWindowsProofReportBoolean -Object $Runtime -Name "reported_hold_key_down" -Expected $true
    Assert-RomaWindowsProofReportBoolean -Object $Runtime -Name "reported_hold_key_up" -Expected $true
    Assert-RomaWindowsProofReportNumberGreaterThan -Object $Runtime -Name "pre_roll_buffering_line" -Minimum 0
    Assert-RomaWindowsProofReportNumberGreaterThan -Object $Runtime -Name "waiting_for_hold_key_down_line" -Minimum 0
    Assert-RomaWindowsProofReportNumberGreaterThan -Object $Runtime -Name "hold_key_down_line" -Minimum 0
    Assert-RomaWindowsProofReportNumberGreaterThan -Object $Runtime -Name "hold_key_up_line" -Minimum 0
    Assert-RomaWindowsProofReportNumberGreaterThan -Object $Runtime -Name "wrote_line" -Minimum 0
    Assert-RomaWindowsProofReportNumberGreaterThan -Object $Runtime -Name "processed_transcript_text_line" -Minimum 0
    Assert-RomaWindowsProofReportBoolean -Object $Runtime -Name "reported_ordered_hold_sequence" -Expected $true
}

function Get-RomaWindowsPackageIdentityFingerprint {
    param(
        [Parameter(Mandatory = $true)]
        [object]$PackageIdentity,
        [string]$Context = "package_identity",
        [switch]$RequireEntryCount
    )

    $algorithm = [string](Require-RomaWindowsObjectProperty -Object $PackageIdentity -Name "algorithm" -Context $Context)
    if ($algorithm -ne "sha256") {
        throw "$Context has unsupported package identity algorithm: $algorithm"
    }

    $fingerprint = [string](Require-RomaWindowsObjectProperty -Object $PackageIdentity -Name "fingerprint" -Context $Context)
    if ($fingerprint -notmatch "^[0-9a-fA-F]{64}$") {
        throw "$Context fingerprint must be a sha256 hash, got: $fingerprint"
    }
    if ($fingerprint -match "^0{64}$") {
        throw "$Context fingerprint must be non-placeholder"
    }

    if ($RequireEntryCount) {
        $entryCount = [int64](Require-RomaWindowsObjectProperty -Object $PackageIdentity -Name "entry_count" -Context $Context)
        if ($entryCount -le 0) {
            throw "$Context entry_count must be positive, got: $entryCount"
        }
    }

    return $fingerprint.ToLowerInvariant()
}

function Invoke-RomaWindowsGitLines {
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

function Get-RomaWindowsSourceGitMetadata {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepositoryRoot
    )

    Push-Location $RepositoryRoot
    try {
        $commit = (@(Invoke-RomaWindowsGitLines -Arguments @("rev-parse", "--verify", "HEAD")) -join "`n").Trim()
        if ([string]::IsNullOrWhiteSpace($commit)) {
            throw "Could not resolve source git commit"
        }

        $branch = (@(Invoke-RomaWindowsGitLines -Arguments @("rev-parse", "--abbrev-ref", "HEAD")) -join "`n").Trim()
        if ([string]::IsNullOrWhiteSpace($branch)) {
            $branch = "unknown"
        }

        $repository = (@(Invoke-RomaWindowsGitLines -Arguments @("config", "--get", "remote.roma-just-talk.url")) -join "`n").Trim()
        if ([string]::IsNullOrWhiteSpace($repository)) {
            $repository = (@(Invoke-RomaWindowsGitLines -Arguments @("config", "--get", "remote.origin.url")) -join "`n").Trim()
        }
        if ([string]::IsNullOrWhiteSpace($repository)) {
            $repository = "unknown"
        }

        $statusLines = @(Invoke-RomaWindowsGitLines -Arguments @("status", "--porcelain"))
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

function Get-RomaWindowsManifestSourceProvenance {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Manifest,
        [string]$Context = "manifest"
    )

    $repository = [string](Require-RomaWindowsObjectProperty -Object $Manifest -Name "source_repository" -Context $Context)
    $branch = [string](Require-RomaWindowsObjectProperty -Object $Manifest -Name "source_branch" -Context $Context)
    $commit = [string](Require-RomaWindowsObjectProperty -Object $Manifest -Name "source_commit" -Context $Context)
    $dirty = [string](Require-RomaWindowsObjectProperty -Object $Manifest -Name "source_dirty" -Context $Context)

    if ([string]::IsNullOrWhiteSpace($repository) -or $repository -eq "unknown") {
        throw "$Context source_repository must identify the packaged source repository"
    }
    if ([string]::IsNullOrWhiteSpace($branch)) {
        throw "$Context source_branch must be non-empty"
    }
    if ($commit -notmatch "^[0-9a-fA-F]{40}$") {
        throw "$Context source_commit must be a 40-character git SHA, got: $commit"
    }
    if ($dirty -ne "true" -and $dirty -ne "false") {
        throw "$Context source_dirty must be true or false, got: $dirty"
    }

    return [ordered]@{
        Repository = $repository
        Branch = $branch
        Commit = $commit
        Dirty = $dirty
    }
}

function Assert-RomaWindowsCleanManifestSourceProvenance {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Manifest,
        [string]$Context = "manifest",
        [string]$ProofName = "Windows package manifest"
    )

    $source = Get-RomaWindowsManifestSourceProvenance `
        -Manifest $Manifest `
        -Context $Context
    if ([string]$source["Dirty"] -ne "false") {
        throw ("{0} requires a clean packaged source checkout, got source_dirty={1}" -f $ProofName, [string]$source["Dirty"])
    }
    return $source
}

function Get-RomaWindowsProofReportIdentity {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Report,
        [Parameter(Mandatory = $true)]
        [string]$ReportName
    )

    $context = "Proof set report $ReportName"
    $os = Require-RomaWindowsObjectProperty -Object $Report -Name "os" -Context $context
    $packageIdentity = Require-RomaWindowsObjectProperty -Object $Report -Name "package_identity" -Context $context
    $manifest = Require-RomaWindowsObjectProperty -Object $Report -Name "manifest" -Context $context
    $source = Get-RomaWindowsManifestSourceProvenance `
        -Manifest $manifest `
        -Context "$context manifest"

    return [ordered]@{
        Platform = [string](Require-RomaWindowsObjectProperty -Object $os -Name "platform" -Context "$context os")
        Machine = [string](Require-RomaWindowsObjectProperty -Object $os -Name "machine" -Context "$context os")
        UserName = [string](Require-RomaWindowsObjectProperty -Object $os -Name "user_name" -Context "$context os")
        UserDomain = [string](Require-RomaWindowsObjectProperty -Object $os -Name "user_domain" -Context "$context os")
        UserSid = [string](Require-RomaWindowsObjectProperty -Object $os -Name "user_sid" -Context "$context os")
        PackageDir = [string](Require-RomaWindowsObjectProperty -Object $Report -Name "package_dir" -Context $context)
        PackageFingerprint = Get-RomaWindowsPackageIdentityFingerprint `
            -PackageIdentity $packageIdentity `
            -Context "$context package_identity" `
            -RequireEntryCount
        PackageEntryCount = [int64](Require-RomaWindowsObjectProperty -Object $packageIdentity -Name "entry_count" -Context "$context package_identity")
        Source = $source
    }
}

function Assert-RomaWindowsSameProofReportValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$Expected,
        [Parameter(Mandatory = $true)]
        [string]$Actual,
        [Parameter(Mandatory = $true)]
        [string]$ReportName
    )

    if ($Expected -ne $Actual) {
        throw ("Proof set mismatch for {0} in {1}: expected '{2}', got '{3}'" -f $Name, $ReportName, $Expected, $Actual)
    }
}

function Assert-RomaWindowsProofReportIdentityMatches {
    param(
        [Parameter(Mandatory = $true)]
        [object]$ExpectedIdentity,
        [Parameter(Mandatory = $true)]
        [object]$ActualIdentity,
        [Parameter(Mandatory = $true)]
        [string]$ReportName
    )

    $identityFields = @(
        [pscustomobject]@{ Key = "Platform"; Name = "os.platform" },
        [pscustomobject]@{ Key = "Machine"; Name = "os.machine" },
        [pscustomobject]@{ Key = "UserName"; Name = "os.user_name" },
        [pscustomobject]@{ Key = "UserDomain"; Name = "os.user_domain" },
        [pscustomobject]@{ Key = "UserSid"; Name = "os.user_sid" },
        [pscustomobject]@{ Key = "PackageDir"; Name = "package_dir" },
        [pscustomobject]@{ Key = "PackageFingerprint"; Name = "package_identity.fingerprint" }
    )
    foreach ($field in $identityFields) {
        $fieldKey = [string]$field.Key
        Assert-RomaWindowsSameProofReportValue `
            -Name ([string]$field.Name) `
            -Expected ([string]$ExpectedIdentity[$fieldKey]) `
            -Actual ([string]$ActualIdentity[$fieldKey]) `
            -ReportName $ReportName
    }

    $expectedSource = $ExpectedIdentity["Source"]
    $actualSource = $ActualIdentity["Source"]
    $sourceFields = @(
        [pscustomobject]@{ Key = "Repository"; Name = "manifest.source_repository" },
        [pscustomobject]@{ Key = "Branch"; Name = "manifest.source_branch" },
        [pscustomobject]@{ Key = "Commit"; Name = "manifest.source_commit" },
        [pscustomobject]@{ Key = "Dirty"; Name = "manifest.source_dirty" }
    )
    foreach ($sourceField in $sourceFields) {
        $sourceKey = [string]$sourceField.Key
        Assert-RomaWindowsSameProofReportValue `
            -Name ([string]$sourceField.Name) `
            -Expected ([string]$expectedSource[$sourceKey]) `
            -Actual ([string]$actualSource[$sourceKey]) `
            -ReportName $ReportName
    }
}

function Assert-RomaWindowsProofReportIdentityComplete {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Identity,
        [Parameter(Mandatory = $true)]
        [string]$ProofName,
        [switch]$RequireWindows,
        [switch]$RequireCleanSource
    )

    if ($RequireWindows -and [string]$Identity["Platform"] -ne "Win32NT") {
        throw ("{0} must run on Windows, got platform {1}" -f $ProofName, [string]$Identity["Platform"])
    }

    $requiredFields = @(
        [pscustomobject]@{ Key = "Machine"; Message = "machine name" },
        [pscustomobject]@{ Key = "UserName"; Message = "Windows user name" },
        [pscustomobject]@{ Key = "UserSid"; Message = "Windows user SID" },
        [pscustomobject]@{ Key = "PackageDir"; Message = "package_dir" },
        [pscustomobject]@{ Key = "PackageFingerprint"; Message = "package identity fingerprint" }
    )
    foreach ($field in $requiredFields) {
        $fieldKey = [string]$field.Key
        if ([string]::IsNullOrWhiteSpace([string]$Identity[$fieldKey])) {
            throw "$ProofName report is missing $($field.Message)"
        }
    }

    $source = $Identity["Source"]
    if ($RequireCleanSource -and [string]$source["Dirty"] -ne "false") {
        throw ("{0} requires a clean packaged source checkout, got source_dirty={1}" -f $ProofName, [string]$source["Dirty"])
    }
}

function Write-RomaWindowsProofReportIdentityMarkers {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Identity,
        [Parameter(Mandatory = $true)]
        [string]$Prefix
    )

    $source = $Identity["Source"]
    Write-Host ("{0}_machine={1}" -f $Prefix, [string]$Identity["Machine"])
    Write-Host ("{0}_user={1}" -f $Prefix, [string]$Identity["UserName"])
    Write-Host ("{0}_user_sid={1}" -f $Prefix, [string]$Identity["UserSid"])
    Write-Host ("{0}_package_dir={1}" -f $Prefix, [string]$Identity["PackageDir"])
    Write-Host ("{0}_package_fingerprint={1}" -f $Prefix, [string]$Identity["PackageFingerprint"])
    Write-Host ("{0}_source_repository={1}" -f $Prefix, [string]$source["Repository"])
    Write-Host ("{0}_source_branch={1}" -f $Prefix, [string]$source["Branch"])
    Write-Host ("{0}_source_commit={1}" -f $Prefix, [string]$source["Commit"])
    Write-Host ("{0}_source_dirty={1}" -f $Prefix, [string]$source["Dirty"])
}

function Write-RomaWindowsProofReportIdentityProofMarkers {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Identity,
        [switch]$IncludeWindows
    )

    $source = $Identity["Source"]
    Write-Host "proof_value=package_identity.algorithm value=sha256"
    Write-Host ("proof_number=package_identity.entry_count value={0} minimum=0" -f [int64]$Identity["PackageEntryCount"])
    Write-Host ("proof_source_commit={0}" -f [string]$source["Commit"])
    Write-Host ("proof_source_dirty={0}" -f [string]$source["Dirty"])

    if ($IncludeWindows) {
        Write-Host ("proof_windows_platform={0}" -f [string]$Identity["Platform"])
        Write-Host ("proof_windows_user={0}" -f [string]$Identity["UserName"])
    }
}

function Assert-RomaWindowsPathNotPackagedArtifact {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Actual,
        [Parameter(Mandatory = $true)]
        [string]$Blocked,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if (![string]::IsNullOrWhiteSpace($Blocked) -and
        $Actual.Equals($Blocked, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "$Name points at packaged mock artifact: $Actual"
    }
}

function Get-RomaWindowsRealWhisperBackendModelExtensions {
    return @(".bin", ".gguf")
}

function Assert-RomaWindowsWhisperConfigProof {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Config
    )

    Assert-RomaWindowsProofReportBoolean -Object $Config -Name "uses_whisper_cli" -Expected $true
    Assert-RomaWindowsProofReportNonEmptyString -Object $Config -Name "whisper_cli_path"
    Assert-RomaWindowsProofReportNonEmptyString -Object $Config -Name "whisper_model_path"
    Assert-RomaWindowsProofReportFile `
        -Proof (Require-RomaWindowsObjectProperty -Object $Config -Name "whisper_cli_file" -Context "whisper config") `
        -Name "whisper_cli"
    Assert-RomaWindowsProofReportFile `
        -Proof (Require-RomaWindowsObjectProperty -Object $Config -Name "whisper_model_file" -Context "whisper config") `
        -Name "whisper_model"
}

function Assert-RomaWindowsRealWhisperBackendProof {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Config,
        [Parameter(Mandatory = $true)]
        [object]$Files
    )

    $whisperCLIPath = [string](Require-RomaWindowsObjectProperty -Object $Config -Name "whisper_cli_path" -Context "real whisper config")
    $whisperModelPath = [string](Require-RomaWindowsObjectProperty -Object $Config -Name "whisper_model_path" -Context "real whisper config")
    $whisperCLIName = [System.IO.Path]::GetFileName($whisperCLIPath).ToLowerInvariant()
    $whisperModelName = [System.IO.Path]::GetFileName($whisperModelPath).ToLowerInvariant()
    $packagedExecutableNames = @(
        Get-RomaWindowsAgentArtifactExecutableFiles |
            ForEach-Object { ([string]$_).ToLowerInvariant() }
    )

    if ($packagedExecutableNames -contains $whisperCLIName -or $whisperCLIName.Contains("mock")) {
        throw "Local whisper laptop proof cannot use a mock/package whisper CLI: $whisperCLIPath"
    }
    if ($packagedExecutableNames -contains $whisperModelName -or
        $whisperModelName.EndsWith(".exe") -or
        $whisperModelName.Contains("mock")) {
        throw "Local whisper laptop proof must point at a model file, got: $whisperModelPath"
    }
    $allowedModelExtensions = Get-RomaWindowsRealWhisperBackendModelExtensions
    $whisperModelExtension = [System.IO.Path]::GetExtension($whisperModelPath).ToLowerInvariant()
    if ($allowedModelExtensions -notcontains $whisperModelExtension) {
        throw "Local whisper laptop proof model must be a .bin or .gguf file, got: $whisperModelPath"
    }

    $packagedMock = Require-RomaWindowsObjectProperty -Object $Files -Name "packaged_whisper_cli_mock" -Context "real whisper files"
    $packagedAgent = Require-RomaWindowsObjectProperty -Object $Files -Name "packaged_agent" -Context "real whisper files"
    $packagedProofAgent = Require-RomaWindowsObjectProperty -Object $Files -Name "packaged_proof_agent" -Context "real whisper files"
    Assert-RomaWindowsPathNotPackagedArtifact -Actual $whisperCLIPath -Blocked ([string](Require-RomaWindowsObjectProperty -Object $packagedMock -Name "path" -Context "packaged_whisper_cli_mock")) -Name "whisper_cli_path"
    Assert-RomaWindowsPathNotPackagedArtifact -Actual $whisperCLIPath -Blocked ([string](Require-RomaWindowsObjectProperty -Object $packagedAgent -Name "path" -Context "packaged_agent")) -Name "whisper_cli_path"
    Assert-RomaWindowsPathNotPackagedArtifact -Actual $whisperCLIPath -Blocked ([string](Require-RomaWindowsObjectProperty -Object $packagedProofAgent -Name "path" -Context "packaged_proof_agent")) -Name "whisper_cli_path"
    Assert-RomaWindowsPathNotPackagedArtifact -Actual $whisperModelPath -Blocked ([string](Require-RomaWindowsObjectProperty -Object $packagedMock -Name "path" -Context "packaged_whisper_cli_mock")) -Name "whisper_model_path"
    Assert-RomaWindowsPathNotPackagedArtifact -Actual $whisperModelPath -Blocked ([string](Require-RomaWindowsObjectProperty -Object $packagedAgent -Name "path" -Context "packaged_agent")) -Name "whisper_model_path"
    Assert-RomaWindowsPathNotPackagedArtifact -Actual $whisperModelPath -Blocked ([string](Require-RomaWindowsObjectProperty -Object $packagedProofAgent -Name "path" -Context "packaged_proof_agent")) -Name "whisper_model_path"

    Write-Host "proof_real_whisper_backend cli=$whisperCLIPath model=$whisperModelPath"
}

function Get-RomaWindowsCurrentUserSid {
    if ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
        return ""
    }

    try {
        $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        if ($null -ne $identity -and $null -ne $identity.User) {
            return [string]$identity.User.Value
        }
    } catch {
        return ""
    }

    return ""
}

function Require-RomaWindowsCurrentUserSid {
    $userSid = Get-RomaWindowsCurrentUserSid
    if ([string]::IsNullOrWhiteSpace($userSid)) {
        throw "Current Windows user SID was not available"
    }

    return $userSid
}

function Wait-RomaWindowsProcessMainWindow {
    param(
        [Parameter(Mandatory = $true)]
        [System.Diagnostics.Process]$Process,
        [int]$TimeoutSeconds = 10
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $Process.Refresh()
        if ($Process.HasExited) {
            throw "Process exited before creating a main window: pid=$($Process.Id)"
        }
        if ($Process.MainWindowHandle -ne [IntPtr]::Zero) {
            Write-Host "process_window=ready pid=$($Process.Id) handle=$($Process.MainWindowHandle)"
            return
        }
        Start-Sleep -Milliseconds 200
    }

    throw "Timed out waiting for process main window: pid=$($Process.Id)"
}

function Set-RomaWindowsProcessForeground {
    param(
        [Parameter(Mandatory = $true)]
        [System.Diagnostics.Process]$Process,
        [int]$TimeoutSeconds = 5
    )

    $shell = New-Object -ComObject WScript.Shell
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $Process.Refresh()
        if ($Process.HasExited) {
            throw "Process exited before activation: pid=$($Process.Id)"
        }
        if ($shell.AppActivate($Process.Id)) {
            Write-Host "process_foreground=activated pid=$($Process.Id)"
            return $shell
        }
        Start-Sleep -Milliseconds 200
    }

    throw "Timed out activating process: pid=$($Process.Id)"
}

function Get-RomaWindowsDefaultHotkeyDisplayName {
    return "Ctrl+Shift+R"
}

function Get-RomaWindowsWaitingForHoldOutputMarker {
    return "waiting_for_hold=$(Get-RomaWindowsDefaultHotkeyDisplayName)"
}

function Get-RomaWindowsHoldHotkeyOutputMarker {
    return "hold_hotkey=$(Get-RomaWindowsDefaultHotkeyDisplayName)"
}

function Get-RomaWindowsToggleHotkeyOutputMarker {
    return "toggle_hotkey=$(Get-RomaWindowsDefaultHotkeyDisplayName)"
}

function Write-RomaWindowsRegisterHotkeyProofPrompt {
    Write-Host ""
    Write-Host "ACTION_REQUIRED=register_hotkey_proof"
    Write-Host (Get-RomaWindowsToggleHotkeyOutputMarker)
    Write-Host "press_and_release_hotkey=true"
}

function Write-RomaWindowsDictationOperatorPrompt {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [bool]$UseHoldHook = $true,
        [string]$ExpectedTranscriptText = "",
        [int]$HoldTimeoutSeconds = -1,
        [int]$ListenerSessionCount = -1,
        [bool]$PasteDictation = $false
    )

    Write-Host ""
    Write-Host "ACTION_REQUIRED=$Name"
    Write-Host "focus_target=normal_text_field_or_notepad"
    if (![string]::IsNullOrWhiteSpace($ExpectedTranscriptText)) {
        Write-Host "say_expected_phrase_before_hotkey=$ExpectedTranscriptText"
    }
    if ($UseHoldHook) {
        Write-Host (Get-RomaWindowsHoldHotkeyOutputMarker)
        Write-Host "speak_before_pressing_hotkey=true"
        Write-Host "release_hotkey_to_finish=true"
    } else {
        Write-Host (Get-RomaWindowsToggleHotkeyOutputMarker)
        Write-Host "speak_after_hotkey=true"
    }
    if ($HoldTimeoutSeconds -ge 0) {
        Write-Host "hold_timeout_seconds=$HoldTimeoutSeconds"
    }
    if ($ListenerSessionCount -ge 0) {
        Write-Host "listener_session_count=$ListenerSessionCount"
    }
    if ($PasteDictation) {
        Write-Host "paste_focus_required=true"
        Write-Host "paste_focus_target=normal_integrity_text_field"
    }
}

function Write-RomaWindowsHoldDictationPrompt {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [string]$ExpectedTranscriptText = "",
        [int]$HoldTimeoutSeconds = -1,
        [int]$ListenerSessionCount = -1
    )

    Write-RomaWindowsDictationOperatorPrompt `
        -Name $Name `
        -UseHoldHook $true `
        -ExpectedTranscriptText $ExpectedTranscriptText `
        -HoldTimeoutSeconds $HoldTimeoutSeconds `
        -ListenerSessionCount $ListenerSessionCount
}

function Write-RomaWindowsHotkeyDeliveryPreflightPrompt {
    param(
        [int]$HoldTimeoutSeconds = -1
    )

    Write-Host ""
    Write-Host "ACTION_REQUIRED=hotkey_delivery_preflight"
    Write-Host (Get-RomaWindowsHoldHotkeyOutputMarker)
    Write-Host "press_and_release_hotkey=true"
    if ($HoldTimeoutSeconds -ge 0) {
        Write-Host "hold_timeout_seconds=$HoldTimeoutSeconds"
    }
}

function Write-RomaWindowsKeyboardHookProofPrompt {
    param(
        [int]$HoldTimeoutSeconds = -1
    )

    Write-Host ""
    Write-Host "ACTION_REQUIRED=keyboard_hook_proof"
    Write-Host (Get-RomaWindowsHoldHotkeyOutputMarker)
    Write-Host "press_and_release_hotkey=true"
    if ($HoldTimeoutSeconds -ge 0) {
        Write-Host "hold_timeout_seconds=$HoldTimeoutSeconds"
    }
}

function Write-RomaWindowsNotepadPastePrompt {
    Write-Host ""
    Write-Host "ACTION_REQUIRED=local_whisper_notepad_paste"
    Write-Host "notepad=will_open_and_verify_file"
    Write-Host "manual_focus_required=false"
}

function ConvertTo-RomaWindowsPowerShellSingleQuotedString {
    param(
        [string]$Value = ""
    )

    return "'" + $Value.Replace("'", "''") + "'"
}

function Write-RomaWindowsFullLaptopProofRecheckScript {
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
        "    [string]`$PackageDir = $(ConvertTo-RomaWindowsPowerShellSingleQuotedString -Value $PackageDir)",
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
        "`$laptopPreflightReportPath = $(ConvertTo-RomaWindowsPowerShellSingleQuotedString -Value $LaptopPreflightReportPath)",
        "`$cloudDictationReportPath = $(ConvertTo-RomaWindowsPowerShellSingleQuotedString -Value $CloudDictationReportPath)",
        "`$localWhisperDictationReportPath = $(ConvertTo-RomaWindowsPowerShellSingleQuotedString -Value $LocalWhisperDictationReportPath)",
        "`$localWhisperNotepadPasteReportPath = $(ConvertTo-RomaWindowsPowerShellSingleQuotedString -Value $LocalWhisperNotepadPasteReportPath)",
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

function Get-RomaWindowsProofSurfaceFiles {
    return Get-RomaWindowsAgentArtifactFileNamesForKeys -Keys (Get-RomaWindowsAgentArtifactManifestScriptPathKeys)
}

function Get-RomaWindowsAgentArtifactExecutableFiles {
    return @(
        Get-RomaWindowsAgentExecutableFileName,
        Get-RomaWindowsProofAgentExecutableFileName,
        Get-RomaWindowsWhisperCLIMockExecutableFileName
    )
}

function Get-RomaWindowsAgentArtifactDebugFiles {
    return @(
        Get-RomaWindowsAgentDebugFileName,
        Get-RomaWindowsProofAgentDebugFileName
    )
}

function Get-RomaWindowsAgentArtifactConfigFiles {
    return Get-RomaWindowsAgentArtifactFileNamesForKeys -Keys (Get-RomaWindowsAgentArtifactConfigPathKeys)
}

function Get-RomaWindowsAgentArtifactRequiredManifestKeys {
    return @(
        "agent",
        "output",
        "proof_agent",
        "whisper_cli_mock",
        "install_proof_config",
        "install_proof_shortcut",
        "local_whisper_install_config",
        "local_whisper_shortcut",
        "laptop_native_preflight_checker_smoke_report",
        "laptop_preflight_checker_smoke_report",
        "swift_runtime_dlls"
    ) + (Get-RomaWindowsAgentArtifactManifestPathKeys)
}

function Assert-RomaWindowsAgentArtifactManifestKeys {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Manifest
    )

    foreach ($key in Get-RomaWindowsAgentArtifactRequiredManifestKeys) {
        Require-RomaWindowsManifestKey -Manifest $Manifest -Key $key | Out-Null
    }
}

function Require-RomaWindowsPackagedNativePreflightCheckerSmokeReport {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Manifest,
        [string]$BaseDir = ""
    )

    return Require-RomaWindowsManifestFile -Manifest $Manifest -Key "laptop_native_preflight_checker_smoke_report" -BaseDir $BaseDir
}

function Require-RomaWindowsPackagedLocalWhisperPreflightCheckerSmokeReport {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Manifest,
        [string]$BaseDir = ""
    )

    return Require-RomaWindowsManifestFile -Manifest $Manifest -Key "laptop_preflight_checker_smoke_report" -BaseDir $BaseDir
}

function Require-RomaWindowsPackagedProofScript {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Manifest,
        [string]$BaseDir = ""
    )

    return Require-RomaWindowsManifestFile -Manifest $Manifest -Key "proof_script" -BaseDir $BaseDir
}

function Require-RomaWindowsPackagedCheckSetScript {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Manifest,
        [string]$BaseDir = ""
    )

    return Require-RomaWindowsManifestFile -Manifest $Manifest -Key "check_set_script" -BaseDir $BaseDir
}

function Require-RomaWindowsPackagedProofAgent {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Manifest,
        [string]$BaseDir = ""
    )

    return Require-RomaWindowsManifestFile -Manifest $Manifest -Key "proof_agent" -BaseDir $BaseDir
}

function Require-RomaWindowsPackagedProofCommonScript {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Manifest,
        [string]$BaseDir = ""
    )

    return Require-RomaWindowsManifestFile -Manifest $Manifest -Key "proof_common_script" -BaseDir $BaseDir
}

function Require-RomaWindowsPackagedWhisperCLIMock {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Manifest,
        [string]$BaseDir = ""
    )

    return Require-RomaWindowsManifestFile -Manifest $Manifest -Key "whisper_cli_mock" -BaseDir $BaseDir
}

function Get-RomaWindowsPackageIdentityFiles {
    $files = @()
    $files += Get-RomaWindowsAgentArtifactExecutableFiles
    $files += Get-RomaWindowsProofSurfaceFiles
    $files += Get-RomaWindowsAgentArtifactFileNameForKey -Key "manifest"
    return $files
}

function Get-RomaWindowsAgentArtifactInstallFiles {
    $files = @()
    $files += Get-RomaWindowsAgentArtifactExecutableFiles
    $files += Get-RomaWindowsAgentArtifactDebugFiles
    $files += Get-RomaWindowsProofSurfaceFiles
    $files += Get-RomaWindowsAgentArtifactConfigFiles
    return $files
}

function Get-RomaWindowsProofSurfaceScriptCount {
    return @(
        Get-RomaWindowsProofSurfaceFiles |
            Where-Object { [string]$_ -like "*.ps1" }
    ).Count
}

function Get-RomaWindowsInstalledProofSurfaceFileMap {
    foreach ($key in Get-RomaWindowsAgentArtifactManifestScriptPathKeys) {
        @{
            ReportProperty = "installed_$key"
            PackageFile = Get-RomaWindowsAgentArtifactFileNameForKey -Key $key
        }
    }
}

function Get-RomaWindowsInstalledProofSurfaceScriptCount {
    return @(
        Get-RomaWindowsInstalledProofSurfaceFileMap |
            Where-Object { [string]$_.PackageFile -like "*.ps1" }
    ).Count
}

function Require-RomaWindowsInstalledProofSurfaceFiles {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallDir
    )

    foreach ($proofSurfaceFile in Get-RomaWindowsInstalledProofSurfaceFileMap) {
        $packageFile = [string]$proofSurfaceFile.PackageFile
        Require-RomaWindowsFile -Path (Join-Path $InstallDir $packageFile)
    }
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

function Get-RomaWindowsScriptParseCount {
    param(
        [string]$Output = ""
    )

    $match = [regex]::Match($Output, "(?m)^windows_scripts_parse_count=(\d+)\s*$")
    if (!$match.Success) {
        return $null
    }

    return [int]::Parse(
        $match.Groups[1].Value,
        [System.Globalization.CultureInfo]::InvariantCulture
    )
}

function Get-RomaWindowsScriptParseOutputMarkers {
    return [ordered]@{
        ok = "windows_scripts_parse_ok=true"
        count_present = "windows_scripts_parse_count="
    }
}

function Get-RomaWindowsScriptParseOutputProof {
    param(
        [string]$Output = ""
    )

    $count = Get-RomaWindowsScriptParseCount -Output $Output
    $proof = [ordered]@{
        output_present = ![string]::IsNullOrWhiteSpace($Output)
        count = $count
    }
    Add-RomaWindowsProofFields -Proof $proof -Fields (Get-RomaWindowsOutputMarkerProof -Output $Output -Markers (Get-RomaWindowsScriptParseOutputMarkers)) | Out-Null
    return $proof
}

function Assert-RomaWindowsScriptParseCount {
    param(
        [string]$Output = "",
        [Parameter(Mandatory = $true)]
        [int]$ExpectedCount,
        [string]$Name = "scripts"
    )

    Assert-RomaWindowsOutputContains -Output $Output -Expected "windows_scripts_parse_ok=true"
    $actualCount = Get-RomaWindowsScriptParseCount -Output $Output
    if ($null -eq $actualCount) {
        throw "Windows script parse count was not found for $Name"
    }
    if ($actualCount -ne $ExpectedCount) {
        throw "Expected $Name script parse count to be $ExpectedCount, got $actualCount"
    }

    Write-Host "asserted_script_parse_count=$Name count=$actualCount expected=$ExpectedCount"
}

function Get-RomaWindowsDefaultRecordSecondsProofValue {
    return "2.0"
}

function Get-RomaWindowsDefaultHoldTimeoutSecondsProofValue {
    return "15.0"
}

function Get-RomaWindowsDefaultHoldTimeoutMillisecondsProofValue {
    return "15000"
}

function Get-RomaWindowsDefaultClipboardRestoreDelaySecondsProofValue {
    return "2.0"
}

function Get-RomaWindowsMaximumClipboardRestoreDelaySecondsProofValue {
    return "4294967.295"
}

function Get-RomaWindowsRuntimeDefaultOutputMarkers {
    return [ordered]@{
        default_record_seconds = "default_record_seconds=$(Get-RomaWindowsDefaultRecordSecondsProofValue)"
        default_hold_timeout_seconds = "default_hold_timeout_seconds=$(Get-RomaWindowsDefaultHoldTimeoutSecondsProofValue)"
        default_hold_timeout_milliseconds = "default_hold_timeout_milliseconds=$(Get-RomaWindowsDefaultHoldTimeoutMillisecondsProofValue)"
        default_clipboard_restore_delay_seconds = "default_clipboard_restore_delay_seconds=$(Get-RomaWindowsDefaultClipboardRestoreDelaySecondsProofValue)"
        maximum_clipboard_restore_delay_seconds = "maximum_clipboard_restore_delay_seconds=$(Get-RomaWindowsMaximumClipboardRestoreDelaySecondsProofValue)"
    }
}

function Get-RomaWindowsHoldTimeoutDefaultOutputMarkers {
    return [ordered]@{
        default_hold_timeout_seconds = "default_timeout_seconds=$(Get-RomaWindowsDefaultHoldTimeoutSecondsProofValue)"
        default_hold_timeout_milliseconds = "default_timeout_milliseconds=$(Get-RomaWindowsDefaultHoldTimeoutMillisecondsProofValue)"
    }
}

function Get-RomaWindowsClipboardRestoreDefaultOutputMarkers {
    return [ordered]@{
        default_clipboard_restore_delay_seconds = "default_clipboard_restore_delay_seconds=$(Get-RomaWindowsDefaultClipboardRestoreDelaySecondsProofValue)"
        maximum_clipboard_restore_delay_seconds = "maximum_clipboard_restore_delay_seconds=$(Get-RomaWindowsMaximumClipboardRestoreDelaySecondsProofValue)"
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

function Get-RomaWindowsProofAgentSourceOutputMarkers {
    return [ordered]@{
        windows_register_hotkey_adapter_source = "windows_register_hotkey_adapter_source=true"
        windows_low_level_keyboard_hook_source = "windows_low_level_keyboard_hook_source=true"
        windows_paste_adapter_source = "windows_paste_adapter_source=true"
        windows_permission_surface_source = "windows_permission_surface_source=true"
        windows_dpapi_secret_store_source = "windows_dpapi_secret_store_source=true"
        miniaudio_capture_adapter_source = "miniaudio_capture_adapter_source=true"
        openai_compatible_transcription_source = "openai_compatible_transcription_source=true"
        whisper_cli_transcription_source = "whisper_cli_transcription_source=true"
        roma_transcription_client_source = "roma_transcription_client_source=true"
        transcription_output_filter_source = "transcription_output_filter_source=true"
        word_replacement_processor_source = "word_replacement_processor_source=true"
        windows_dictation_runtime_source = "windows_dictation_runtime_source=true"
        windows_dictation_runtime_uses_pipeline_source = "windows_dictation_runtime_uses_pipeline_source=true"
        windows_listener_output_isolation_source = "windows_listener_output_isolation_source=true"
        windows_listener_pre_roll_runtime_source = "windows_listener_pre_roll_runtime_source=true"
        windows_hold_hook_single_window_source = "windows_hold_hook_single_window_source=true"
        windows_dictation_proof_source = "windows_dictation_proof_source=true"
        windows_proof_args_shared_source = "windows_proof_args_shared_source=true"
    }
}

function Get-RomaWindowsNativeDoctorSpecs {
    return [ordered]@{
        register_hotkey = [ordered]@{
            label = "register hotkey"
            command = "windows-hotkey-doctor"
            expected_marker = "windows_hotkey_runtime=true"
        }
        register_hotkey_available = [ordered]@{
            label = "register hotkey availability"
            command = "windows-hotkey-availability-proof"
            expected_marker = "hotkey_registration_available=true"
        }
        keyboard_hook = [ordered]@{
            label = "keyboard hook"
            command = "windows-keyboard-hook-doctor"
            expected_marker = "runtime=true"
        }
        paste = [ordered]@{
            label = "paste"
            command = "windows-paste-doctor"
            expected_marker = "windows_paste_runtime=true"
        }
        dpapi_secret = [ordered]@{
            label = "dpapi secret"
            command = "windows-secret-doctor"
            expected_marker = "dpapi_runtime=true"
        }
        miniaudio_capture = [ordered]@{
            label = "miniaudio capture"
            command = "miniaudio-capture-doctor"
            expected_marker = "native_capture_adapter=true"
        }
    }
}

function Get-RomaWindowsNativeDoctorSpec {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $specs = Get-RomaWindowsNativeDoctorSpecs
    if (!$specs.Contains($Name)) {
        throw "Unknown Windows native doctor proof name: $Name"
    }
    return $specs[$Name]
}

function Get-RomaWindowsNativeDoctorExpectedMarkers {
    $markers = [ordered]@{}
    $specs = Get-RomaWindowsNativeDoctorSpecs
    foreach ($name in $specs.Keys) {
        $markers[$name] = [string]$specs[$name]["expected_marker"]
    }
    return $markers
}

function Get-RomaWindowsNativeDoctorExpectedMarker {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $spec = Get-RomaWindowsNativeDoctorSpec -Name $Name
    return [string]$spec["expected_marker"]
}

function New-RomaWindowsNativeDoctorOutputTable {
    $outputs = [ordered]@{}
    $specs = Get-RomaWindowsNativeDoctorSpecs
    foreach ($name in $specs.Keys) {
        $outputs[$name] = ""
    }
    return $outputs
}

function Get-RomaWindowsProofProfileSpecs {
    return [ordered]@{
        doctor_only = [ordered]@{
            profile = "doctor-only"
            expected_mode = "doctor-only"
            read_as_laptop_preflight = $false
            requirements = @(
                "windows_platform",
                "windows_user",
                "permission_surface",
                "agent_runtime_wiring",
                "proof_agent_source_surface",
                "shared_windows_transcription_path",
                "shared_windows_proof_args",
                "listener_pre_roll_runtime_source",
                "hold_hook_single_window_source",
                "native_doctor_surface",
                "packaged_listener",
                "listener_shared_pre_roll_runtime"
            )
            assertions = @(
                "windows_platform",
                "permission_surface",
                "proof_agent_surface",
                "native_doctor_surface",
                "packaged_listener"
            )
        }
        cloud_dictation = [ordered]@{
            profile = "cloud-dictation"
            expected_mode = "cloud"
            read_as_laptop_preflight = $false
            requirements = Join-RomaWindowsProofRequirements `
                -Base (Get-RomaWindowsInstalledProofProfileRequirements -IncludeShortcutProof $true) `
                -Extra @(
                    "cloud_config",
                    "real_cloud_backend",
                    "dictation_runtime",
                    "pre_roll_audio",
                    "speech_pcm_contract",
                    "expected_transcript_text",
                    "paste_restore_intent",
                    "paste_sent"
            )
            assertions = Join-RomaWindowsProofAssertions `
                -Base (Get-RomaWindowsInstalledProofProfileAssertions -IncludeShortcutProof $true) `
                -Extra @(
                    "cloud_config",
                    "real_cloud_backend",
                    "dictation",
                    "expected_transcript_text",
                    "paste"
            )
        }
        local_whisper_dictation = [ordered]@{
            profile = "local-whisper-dictation"
            expected_mode = "local-whisper"
            read_as_laptop_preflight = $false
            requirements = Join-RomaWindowsProofRequirements `
                -Base (Get-RomaWindowsInstalledProofProfileRequirements -IncludeShortcutProof $true) `
                -Extra @(
                    "local_whisper_config",
                    "real_whisper_backend",
                    "dictation_runtime",
                    "listener_runtime",
                    "pre_roll_audio",
                    "speech_pcm_contract",
                    "expected_transcript_text",
                    "paste_restore_intent",
                    "paste_sent"
            )
            assertions = Join-RomaWindowsProofAssertions `
                -Base (Get-RomaWindowsInstalledProofProfileAssertions -IncludeShortcutProof $true) `
                -Extra @(
                    "whisper_config",
                    "real_whisper_backend",
                    "dictation",
                    "listener_runtime",
                    "expected_transcript_text",
                    "paste"
            )
        }
        local_whisper_notepad_paste = [ordered]@{
            profile = "local-whisper-notepad-paste"
            expected_mode = "local-whisper"
            read_as_laptop_preflight = $false
            requirements = Join-RomaWindowsProofRequirements `
                -Base (Get-RomaWindowsInstalledProofProfileRequirements) `
                -Extra @(
                    "local_whisper_config",
                    "real_whisper_backend",
                    "notepad_paste"
            )
            assertions = Join-RomaWindowsProofAssertions `
                -Base (Get-RomaWindowsInstalledProofProfileAssertions) `
                -Extra @(
                    "whisper_config",
                    "real_whisper_backend",
                    "notepad_paste"
            )
        }
        laptop_preflight = [ordered]@{
            profile = "laptop-preflight"
            expected_mode = "windows-laptop-preflight"
            read_as_laptop_preflight = $true
            requirements = @(
                "windows_platform",
                "windows_user",
                "clean_source_provenance",
                "package_identity",
                "minimum_permission_surface",
                "hotkey_delivery_preflight",
                "microphone_preflight",
                "optional_local_whisper_preflight"
            )
            assertions = @()
        }
        packaged_whisper_mock_install = [ordered]@{
            profile = "packaged-whisper-mock-install"
            expected_mode = "packaged-whisper-mock"
            read_as_laptop_preflight = $false
            requirements = Join-RomaWindowsProofRequirements `
                -Base (Get-RomaWindowsInstalledProofProfileRequirements -IncludeShortcutProof $true) `
                -Extra @(
                    "packaged_whisper_mock",
                    "local_whisper_config"
            )
            assertions = Join-RomaWindowsProofAssertions `
                -Base (Get-RomaWindowsInstalledProofProfileAssertions -IncludeShortcutProof $true) `
                -Extra @(
                    "packaged_mock",
                    "whisper_config"
            )
        }
    }
}

function Get-RomaWindowsProofProfileName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $spec = Get-RomaWindowsProofProfileSpecByName -Name $Name
    return [string]$spec["profile"]
}

function Get-RomaWindowsProofProfileSpecByName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $profiles = Get-RomaWindowsProofProfileSpecs
    if (!$profiles.Contains($Name)) {
        throw "Unknown Windows proof profile name: $Name"
    }
    return $profiles[$Name]
}

function Get-RomaWindowsProofProfileSpecByProfile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Profile
    )

    $profiles = Get-RomaWindowsProofProfileSpecs
    foreach ($name in $profiles.Keys) {
        if ([string]$profiles[$name]["profile"] -eq $Profile) {
            return $profiles[$name]
        }
    }
    throw "Unknown Windows proof profile: $Profile"
}

function Get-RomaWindowsProofProfileExpectedMode {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Profile
    )

    $spec = Get-RomaWindowsProofProfileSpecByProfile -Profile $Profile
    return [string]$spec["expected_mode"]
}

function Get-RomaWindowsProofProfileExpectedModeByName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $spec = Get-RomaWindowsProofProfileSpecByName -Name $Name
    return [string]$spec["expected_mode"]
}

function Get-RomaWindowsProofProfileOkMarkerByName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    return "proof_profile_ok=$(Get-RomaWindowsProofProfileName -Name $Name)"
}

function Join-RomaWindowsProofRequirements {
    param(
        [string[]]$Base = @(),
        [string[]]$Extra = @()
    )

    return @($Base + $Extra)
}

function Get-RomaWindowsInstalledProofProfileRequirements {
    param(
        [bool]$IncludeShortcutProof = $false
    )

    $requirements = @(
        "windows_platform",
        "windows_user",
        "install",
        "installed_hash_match"
    )
    if ($IncludeShortcutProof) {
        $requirements += @(
            "shortcut",
            "startup_shortcut"
        )
    }
    $requirements += @(
        "permission_surface",
        "agent_runtime_wiring",
        "proof_agent_source_surface",
        "shared_windows_transcription_path",
        "shared_windows_proof_args",
        "listener_pre_roll_runtime_source",
        "hold_hook_single_window_source",
        "native_doctor_surface",
        "packaged_listener",
        "installed_listener",
        "listener_shared_pre_roll_runtime",
        "config_doctor",
        "installed_listener_agent_path",
        "hold_hook_config"
    )

    return $requirements
}

function Get-RomaWindowsProofProfileRequirements {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Profile
    )

    $spec = Get-RomaWindowsProofProfileSpecByProfile -Profile $Profile
    return @($spec["requirements"])
}

function Join-RomaWindowsProofAssertions {
    param(
        [string[]]$Base = @(),
        [string[]]$Extra = @()
    )

    return @($Base + $Extra)
}

function Get-RomaWindowsInstalledProofProfileAssertions {
    param(
        [bool]$IncludeShortcutProof = $false
    )

    $assertions = @(
        "windows_platform",
        "install",
        "permission_surface",
        "proof_agent_surface",
        "native_doctor_surface",
        "packaged_listener",
        "installed_listener",
        "config_doctor",
        "hold_hook"
    )
    if ($IncludeShortcutProof) {
        $assertions += @(
            "shortcut",
            "startup_shortcut"
        )
    }

    return $assertions
}

function Get-RomaWindowsProofProfileAssertions {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Profile
    )

    $spec = Get-RomaWindowsProofProfileSpecByProfile -Profile $Profile
    return @($spec["assertions"])
}

function Get-RomaWindowsProofReportProfileChecks {
    param(
        [hashtable]$Paths = @{},
        [hashtable]$Required = @{}
    )

    $checks = @()
    $profiles = Get-RomaWindowsProofProfileSpecs
    foreach ($name in $profiles.Keys) {
        $path = ""
        if ($Paths.ContainsKey($name)) {
            $path = [string]$Paths[$name]
        }

        $isRequired = $false
        if ($Required.ContainsKey($name)) {
            $isRequired = [bool]$Required[$name]
        }

        $checks += [pscustomobject]@{
            Name = [string]$name
            Profile = [string]$profiles[$name]["profile"]
            Path = $path
            Required = $isRequired
            ReadAsLaptopPreflight = [bool]$profiles[$name]["read_as_laptop_preflight"]
        }
    }

    return $checks
}

function Add-RomaWindowsProofReportPathRequiredProfiles {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Required,
        [Parameter(Mandatory = $true)]
        [hashtable]$Paths
    )

    $profiles = Get-RomaWindowsProofProfileSpecs
    foreach ($profileName in $profiles.Keys) {
        if ($Paths.ContainsKey($profileName) -and ![string]::IsNullOrWhiteSpace([string]$Paths[$profileName])) {
            $Required[$profileName] = $true
        }
    }
    return $Required
}

function Get-RomaWindowsProofSetSpecs {
    return [ordered]@{
        artifact_smoke = [ordered]@{
            profiles = @("doctor_only", "packaged_whisper_mock_install")
            ok_marker = "proof_set_ok=artifact-smoke"
        }
        full_laptop = [ordered]@{
            profiles = @("cloud_dictation", "local_whisper_dictation", "local_whisper_notepad_paste", "laptop_preflight")
            ok_marker = "proof_set_ok=full-laptop"
        }
        laptop_preflight = [ordered]@{
            profiles = @("laptop_preflight")
            ok_marker = "proof_set_ok=laptop-preflight"
        }
        custom = [ordered]@{
            profiles = @()
            ok_marker = "proof_set_ok=custom"
        }
    }
}

function Get-RomaWindowsProofSetSpec {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $proofSets = Get-RomaWindowsProofSetSpecs
    if (!$proofSets.Contains($Name)) {
        throw "Unknown Windows proof set: $Name"
    }
    return $proofSets[$Name]
}

function Get-RomaWindowsProofSetProfileNames {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $spec = Get-RomaWindowsProofSetSpec -Name $Name
    return @($spec["profiles"])
}

function Get-RomaWindowsProofSetOkMarker {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $spec = Get-RomaWindowsProofSetSpec -Name $Name
    return [string]$spec["ok_marker"]
}

function Add-RomaWindowsProofSetRequiredProfiles {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Required,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    foreach ($profileName in (Get-RomaWindowsProofSetProfileNames -Name $Name)) {
        $Required[$profileName] = $true
    }
    return $Required
}

function Get-RomaWindowsLaptopProofReportFileNames {
    return [ordered]@{
        laptop_preflight = "preflight-proof.json"
        cloud_dictation = "cloud-dictation-proof.json"
        local_whisper_dictation = "local-whisper-dictation-proof.json"
        local_whisper_notepad_paste = "local-whisper-notepad-paste-proof.json"
    }
}

function Get-RomaWindowsLaptopProofReportFileName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $fileNames = Get-RomaWindowsLaptopProofReportFileNames
    if (!$fileNames.Contains($Name)) {
        throw "Unknown Windows laptop proof report: $Name"
    }
    return [string]$fileNames[$Name]
}

function Join-RomaWindowsLaptopProofReportPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProofDir,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    return Join-Path $ProofDir (Get-RomaWindowsLaptopProofReportFileName -Name $Name)
}

function Get-RomaWindowsLaptopProofPathSet {
    param(
        [string]$ProofDir = "C:\tmp\roma-windows-laptop-proof",
        [string]$StartupShortcutDir = ""
    )

    $reports = [ordered]@{}
    foreach ($name in (Get-RomaWindowsLaptopProofReportFileNames).Keys) {
        $reports[$name] = Join-RomaWindowsLaptopProofReportPath -ProofDir $ProofDir -Name $name
    }

    $cloudInstallDir = Join-Path $ProofDir "cloud-install"
    $localWhisperInstallDir = Join-Path $ProofDir "local-whisper-install"
    $localWhisperNotepadInstallDir = Join-Path $ProofDir "local-whisper-notepad-install"
    $startupShortcutBaseDir = $StartupShortcutDir
    if ([string]::IsNullOrWhiteSpace($startupShortcutBaseDir)) {
        $startupShortcutBaseDir = Join-Path $ProofDir "startup-shortcuts"
    }

    return [ordered]@{
        reports = $reports
        recheck_script = Join-Path $ProofDir "recheck-full-laptop-proof.ps1"
        mic_preflight_wav = Join-Path $ProofDir "mic-preflight.wav"
        cloud_install_dir = $cloudInstallDir
        cloud_config_path = Join-RomaWindowsInstalledAgentConfigPath -InstallDir $cloudInstallDir
        cloud_shortcut_dir = Join-Path $ProofDir "cloud-shortcuts"
        cloud_startup_shortcut_dir = Join-Path $startupShortcutBaseDir "cloud"
        local_whisper_install_dir = $localWhisperInstallDir
        local_whisper_config_path = Join-RomaWindowsInstalledAgentConfigPath -InstallDir $localWhisperInstallDir
        local_whisper_shortcut_dir = Join-Path $ProofDir "local-whisper-shortcuts"
        local_whisper_startup_shortcut_dir = Join-Path $startupShortcutBaseDir "local-whisper"
        local_whisper_notepad_install_dir = $localWhisperNotepadInstallDir
        local_whisper_notepad_config_path = Join-RomaWindowsInstalledAgentConfigPath -InstallDir $localWhisperNotepadInstallDir
        startup_shortcut_base_dir = $startupShortcutBaseDir
    }
}

function Get-RomaWindowsLaptopProofGuideReportPaths {
    param(
        [string]$ProofDir = "C:\tmp\roma-windows-laptop-proof"
    )

    $pathSet = Get-RomaWindowsLaptopProofPathSet -ProofDir $ProofDir
    return $pathSet["reports"]
}

function Get-RomaWindowsLaptopPreflightGuideMarkers {
    $guideReportPaths = Get-RomaWindowsLaptopProofGuideReportPaths
    return [ordered]@{
        laptop_preflight_proof_set = Get-RomaWindowsProofSetOkMarker -Name "laptop_preflight"
        laptop_preflight_ok = "windows_laptop_preflight_ok=true"
        laptop_preflight_report = "windows_laptop_preflight_report=$($guideReportPaths["laptop_preflight"])"
        package_fingerprint = "proof_set_laptop_preflight_package_fingerprint="
        source_dirty = "proof_set_laptop_preflight_source_dirty=false"
        permission_surface = "proof_set_laptop_preflight_permission_surface=true"
        local_whisper_disabled = "proof_set_laptop_preflight_local_whisper=False"
        microphone_duration = "microphone_preflight_duration_seconds="
        microphone_pre_roll = "microphone_preflight_included_pre_roll_seconds="
        positive_pre_roll = "proof_bool=reported_positive_pre_roll value=True"
        included_pre_roll_seconds = "proof_number=included_pre_roll_seconds value="
        laptop_preflight_profile = Get-RomaWindowsProofProfileOkMarkerByName -Name "laptop_preflight"
    }
}

function Get-RomaWindowsLaptopPreflightLocalWhisperGuideMarkers {
    return [ordered]@{
        local_whisper_enabled = "proof_set_laptop_preflight_local_whisper=True"
    }
}

function Get-RomaWindowsLaptopProofOperatorGuideLines {
    $hotkeyDisplayName = Get-RomaWindowsDefaultHotkeyDisplayName
    return @(
        "Operator actions during proof:",
        "",
        "1. When ACTION_REQUIRED=hotkey_delivery_preflight appears, press and release $hotkeyDisplayName once.",
        "2. Before cloud dictation, focus a normal text field, say 'cloud pre roll proof' before pressing the hotkey, then hold $hotkeyDisplayName while speaking and release to finish.",
        "3. Before local whisper dictation, focus a normal text field, say 'local whisper pre roll proof' before pressing the hotkey, then hold $hotkeyDisplayName while speaking and release to finish.",
        "4. The local whisper Notepad paste proof opens and verifies Notepad itself; no manual focus step should be required.",
        "",
        "The transcript checker matches the expected phrase against processed_transcript_text, so say the phrase clearly and do not substitute another phrase unless you pass -CloudExpectedTranscriptText or -LocalWhisperExpectedTranscriptText."
    )
}

function Get-RomaWindowsLaptopProofPrerequisiteGuideLines {
    return @(
        "Prerequisites before full proof:",
        "",
        "1. Run on the target Windows laptop from the unpacked artifact directory, not from the source checkout.",
        "2. Ensure microphone access is enabled; the permission doctor prints microphone_settings_uri=ms-settings:privacy-microphone when Windows blocks capture.",
        "3. For cloud dictation, set GROQ_API_KEY or pass another -ApiKeyEnv / -ApiKeyName pair before the full proof command.",
        "4. For local whisper, pass real whisper-cli.exe plus .bin or .gguf model paths; RomaWhisperCLIMock.exe is CI-only and is rejected by real laptop proof profiles.",
        "5. Package from a clean source checkout; final laptop proof rejects source_dirty=true."
    )
}

function Get-RomaWindowsLaptopProofClaimGuideLines {
    return @(
        "Full proof validates four JSON reports: preflight, cloud dictation, local whisper dictation, and local whisper Notepad paste.",
        "The final proof-set checker must print proof_set_ok=full-laptop and the archived recheck script must print windows_laptop_recheck_ok=true.",
        "Do not claim Windows support until the full laptop proof passes on the target Windows machine."
    )
}

function Get-RomaWindowsFullLaptopProofSetOutputMarkers {
    $markers = Get-RomaWindowsProofSetProfileOkMarkers -Name "full_laptop"
    $markers["full_laptop_proof_set"] = Get-RomaWindowsProofSetOkMarker -Name "full_laptop"
    return $markers
}

function Get-RomaWindowsProofSetProfileOkMarkers {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $markers = [ordered]@{}
    foreach ($profileName in (Get-RomaWindowsProofSetProfileNames -Name $Name)) {
        $markers["${profileName}_profile"] = Get-RomaWindowsProofProfileOkMarkerByName -Name $profileName
    }
    return $markers
}

function Get-RomaWindowsFullLaptopProofGuideMarkers {
    $guidePaths = Get-RomaWindowsLaptopProofPathSet
    $markers = [ordered]@{
        laptop_preflight_matches_full = "proof_set_laptop_preflight_matches_full=true"
        generated_at_window_minutes = "proof_set_generated_at_window_minutes="
    }

    $proofSetMarkers = Get-RomaWindowsFullLaptopProofSetOutputMarkers
    foreach ($key in $proofSetMarkers.Keys) {
        $markers[$key] = $proofSetMarkers[$key]
    }

    $markers["listener_runtime"] = "proof_listener_runtime=installed_listener"
    $markers["listen_completed_sessions"] = "listen_completed_sessions=1"
    $markers["source_dirty"] = "proof_set_source_dirty=false"
    $markers["recheck_script"] = "windows_laptop_recheck_script=$($guidePaths["recheck_script"])"
    $markers["proof_ok"] = "windows_laptop_proof_ok=true"
    return $markers
}

function Write-RomaWindowsLaptopProofGuide {
    param(
        [Parameter(Mandatory = $true)]
        [string]$OutputPath
    )

    $preflightMarkers = @((Get-RomaWindowsLaptopPreflightGuideMarkers).Values) -join [System.Environment]::NewLine
    $localWhisperPreflightMarkers = @((Get-RomaWindowsLaptopPreflightLocalWhisperGuideMarkers).Values) -join [System.Environment]::NewLine
    $fullProofMarkers = @((Get-RomaWindowsFullLaptopProofGuideMarkers).Values) -join [System.Environment]::NewLine
    $operatorGuide = @(Get-RomaWindowsLaptopProofOperatorGuideLines) -join [System.Environment]::NewLine
    $prerequisiteGuide = @(Get-RomaWindowsLaptopProofPrerequisiteGuideLines) -join [System.Environment]::NewLine
    $claimGuide = @(Get-RomaWindowsLaptopProofClaimGuideLines) -join [System.Environment]::NewLine
    $guidePaths = Get-RomaWindowsLaptopProofPathSet
    $guideReportPaths = $guidePaths["reports"]
    $laptopPreflightReportPath = $guideReportPaths["laptop_preflight"]
    $cloudDictationReportPath = $guideReportPaths["cloud_dictation"]
    $localWhisperDictationReportPath = $guideReportPaths["local_whisper_dictation"]
    $localWhisperNotepadPasteReportPath = $guideReportPaths["local_whisper_notepad_paste"]
    $recheckScriptPath = $guidePaths["recheck_script"]

    @"
Roma Just Talk Windows laptop proof

Run these commands from this artifact directory.

$operatorGuide

$prerequisiteGuide

Native preflight only, before cloud credentials or local whisper setup:

powershell -ExecutionPolicy Bypass -File .\run-windows-laptop-proof.ps1 -PackageDir . -ProofDir C:\tmp\roma-windows-laptop-proof -PreflightOnly -NativePreflightOnly

Local whisper preflight, before cloud credentials:

powershell -ExecutionPolicy Bypass -File .\run-windows-laptop-proof.ps1 -PackageDir . -ProofDir C:\tmp\roma-windows-laptop-proof -PreflightOnly -WhisperCLI C:\path\whisper-cli.exe -WhisperModel C:\path\ggml-base.en.bin

Full laptop proof, after cloud credentials and local whisper are ready:

powershell -ExecutionPolicy Bypass -File .\run-windows-laptop-proof.ps1 -PackageDir . -ProofDir C:\tmp\roma-windows-laptop-proof -Endpoint https://api.groq.com/openai/v1/audio/transcriptions -Model whisper-large-v3-turbo -ApiKeyEnv GROQ_API_KEY -ApiKeyName groq -WhisperCLI C:\path\whisper-cli.exe -WhisperModel C:\path\ggml-base.en.bin

Expected preflight-only proof markers:

$preflightMarkers

Local whisper preflight also prints:

$localWhisperPreflightMarkers

Archived preflight report recheck, without rerunning hotkey or microphone proof:

powershell -ExecutionPolicy Bypass -File .\check-windows-proof-report.ps1 -ProofReportPath $laptopPreflightReportPath -RequireProofProfile laptop-preflight

Expected full-proof markers:

$fullProofMarkers

Archived full-proof recheck, without rerunning capture, transcription, listener, or paste:

powershell -ExecutionPolicy Bypass -File .\check-windows-proof-set.ps1 -LaptopPreflightReportPath $laptopPreflightReportPath -CloudDictationReportPath $cloudDictationReportPath -LocalWhisperDictationReportPath $localWhisperDictationReportPath -LocalWhisperNotepadPasteReportPath $localWhisperNotepadPasteReportPath -RequireLaptopPreflight -RequireFullLaptopProof

Or run the proof-dir script written by the full laptop proof:

powershell -ExecutionPolicy Bypass -File $recheckScriptPath

That recheck script asserts the four profile markers and prints:

windows_laptop_recheck_ok=true

$claimGuide
"@ | Set-Content -LiteralPath $OutputPath -Encoding UTF8
    Write-Host "laptop_proof_guide=$OutputPath"
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

function Assert-RomaWindowsProofAgentSourceOutput {
    param(
        [string]$Output = ""
    )

    Assert-RomaWindowsOutputMarkers `
        -Output $Output `
        -Markers (Get-RomaWindowsProofAgentSourceOutputMarkers)
}

function Assert-RomaWindowsAgentDoctorOutput {
    param(
        [string]$Output = "",
        [switch]$RequireRuntimeAvailable
    )

    Assert-RomaWindowsOutputContains -Output $Output -Expected "agent=roma-windows-agent"
    Assert-RomaWindowsOutputContains -Output $Output -Expected "runtime_available="
    if ($RequireRuntimeAvailable) {
        Assert-RomaWindowsOutputContains -Output $Output -Expected "runtime_available=true"
    }

    $markers = Get-RomaWindowsAgentDoctorOutputMarkers
    foreach ($key in $markers.Keys) {
        if ($key -ne "runtime_available") {
            Assert-RomaWindowsOutputContains -Output $Output -Expected $markers[$key]
        }
    }

    Assert-RomaWindowsRuntimeDefaultOutput -Output $Output
    Assert-RomaWindowsMinimumPermissionOutput -Output $Output
}

function Assert-RomaWindowsProofAgentDoctorOutput {
    param(
        [string]$Output = "",
        [switch]$RequireNativeWindowsAdapters
    )

    Assert-RomaWindowsOutputContains -Output $Output -Expected "platform="
    Assert-RomaWindowsOutputContains -Output $Output -Expected "native_windows_adapters="

    $markers = Get-RomaWindowsProofAgentDoctorOutputMarkers
    foreach ($key in $markers.Keys) {
        if ($key -ne "native_windows_adapters") {
            Assert-RomaWindowsOutputContains -Output $Output -Expected $markers[$key]
        }
    }
    if ($RequireNativeWindowsAdapters) {
        Assert-RomaWindowsOutputContains -Output $Output -Expected $markers["native_windows_adapters"]
    }

    Assert-RomaWindowsRuntimeDefaultOutput -Output $Output
    Assert-RomaWindowsProofAgentSourceOutput -Output $Output
}

function Assert-RomaWindowsNativeDoctorOutput {
    param(
        [string]$Output = "",
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    Assert-RomaWindowsOutputContains `
        -Output $Output `
        -Expected (Get-RomaWindowsNativeDoctorExpectedMarker -Name $Name)

    if ($Name -eq "keyboard_hook") {
        Assert-RomaWindowsHoldTimeoutDefaultOutput -Output $Output
    }
    if ($Name -eq "paste") {
        Assert-RomaWindowsClipboardRestoreDefaultOutput -Output $Output
    }
}

function Get-RomaWindowsLaptopPreflightCommonOutputMarkers {
    param(
        [bool]$ExpectLocalWhisper = $true
    )

    return [ordered]@{
        permission_surface = "proof_set_laptop_preflight_permission_surface=true"
        local_whisper = "proof_set_laptop_preflight_local_whisper=$($ExpectLocalWhisper.ToString())"
        source_dirty = "proof_set_laptop_preflight_source_dirty=false"
    }
}

function Assert-RomaWindowsLaptopPreflightProfileOutput {
    param(
        [string]$Output = "",
        [bool]$ExpectLocalWhisper = $true
    )

    $markers = [ordered]@{
        profile = Get-RomaWindowsProofProfileOkMarkerByName -Name "laptop_preflight"
        report_ok = "proof_report_ok="
    }

    $commonMarkers = Get-RomaWindowsLaptopPreflightCommonOutputMarkers -ExpectLocalWhisper $ExpectLocalWhisper
    foreach ($key in $commonMarkers.Keys) {
        $markers[$key] = $commonMarkers[$key]
    }

    Assert-RomaWindowsOutputMarkers -Output $Output -Markers $markers
}

function Assert-RomaWindowsLaptopPreflightSetOutput {
    param(
        [string]$Output = "",
        [bool]$ExpectLocalWhisper = $true
    )

    $markers = Get-RomaWindowsLaptopPreflightCommonOutputMarkers -ExpectLocalWhisper $ExpectLocalWhisper
    $markers["profile"] = Get-RomaWindowsProofProfileOkMarkerByName -Name "laptop_preflight"
    $markers["proof_set"] = Get-RomaWindowsProofSetOkMarker -Name "laptop_preflight"

    Assert-RomaWindowsOutputMarkers -Output $Output -Markers $markers
}

function Assert-RomaWindowsFullLaptopProofSetOutput {
    param(
        [string]$Output = ""
    )

    Assert-RomaWindowsOutputMarkers `
        -Output $Output `
        -Markers (Get-RomaWindowsFullLaptopProofSetOutputMarkers)
}

function Assert-RomaWindowsListenerSmokeOutput {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Output,
        [bool]$RequireLauncherMode = $false
    )

    if ($RequireLauncherMode) {
        Assert-RomaWindowsOutputContains -Output $Output -Expected "mode=RomaWindowsAgent listen"
    }
    Assert-RomaWindowsOutputContains -Output $Output -Expected "mode=listen"
    Assert-RomaWindowsOutputContains -Output $Output -Expected "listener_capture_lifecycle=shared_pre_roll_runtime"
    Assert-RomaWindowsOutputContains -Output $Output -Expected "listen_completed_sessions=0"
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

function Get-RomaWindowsProofAgentSourceOutputProof {
    param(
        [string]$Output = ""
    )

    return Get-RomaWindowsOutputMarkerProof `
        -Output $Output `
        -Markers (Get-RomaWindowsProofAgentSourceOutputMarkers)
}

function Get-RomaWindowsAgentDoctorOutputMarkers {
    return [ordered]@{
        runtime_available = "runtime_available=true"
        dictation_runtime = "dictation_runtime=WindowsDictationRuntime"
        recorder_miniaudio = "recorder=miniaudio"
        paste_win32_clipboard_sendinput = "paste=win32_clipboard_sendinput"
        secret_store_dpapi = "secret_store=dpapi"
    }
}

function Get-RomaWindowsProofAgentDoctorOutputMarkers {
    return [ordered]@{
        swift_core = "swift_core=true"
        native_windows_adapters = "native_windows_adapters=true"
        pre_roll_config = "pre_roll_seconds="
    }
}

function Get-RomaWindowsAgentDoctorOutputProof {
    param(
        [string]$Output = ""
    )

    $proof = [ordered]@{
        output_present = ![string]::IsNullOrWhiteSpace($Output)
    }
    Add-RomaWindowsProofFields -Proof $proof -Fields (Get-RomaWindowsOutputMarkerProof -Output $Output -Markers (Get-RomaWindowsAgentDoctorOutputMarkers)) | Out-Null
    Add-RomaWindowsProofFields -Proof $proof -Fields (Get-RomaWindowsMinimumPermissionOutputProof -Output $Output) | Out-Null
    Add-RomaWindowsProofFields -Proof $proof -Fields (Get-RomaWindowsRuntimeDefaultOutputProof -Output $Output) | Out-Null
    return $proof
}

function Get-RomaWindowsProofAgentDoctorOutputProof {
    param(
        [string]$Output = ""
    )

    $proof = [ordered]@{
        output_present = ![string]::IsNullOrWhiteSpace($Output)
    }
    Add-RomaWindowsProofFields -Proof $proof -Fields (Get-RomaWindowsOutputMarkerProof -Output $Output -Markers (Get-RomaWindowsProofAgentDoctorOutputMarkers)) | Out-Null
    Add-RomaWindowsProofFields -Proof $proof -Fields (Get-RomaWindowsProofAgentSourceOutputProof -Output $Output) | Out-Null
    Add-RomaWindowsProofFields -Proof $proof -Fields (Get-RomaWindowsRuntimeDefaultOutputProof -Output $Output) | Out-Null
    return $proof
}

function Get-RomaWindowsNativeDoctorOutputMarkers {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $expectedMarker = Get-RomaWindowsNativeDoctorExpectedMarker -Name $Name
    return [ordered]@{
        platform_windows = "platform=windows"
        expected_marker_present = $expectedMarker
        register_hotkey_available = Get-RomaWindowsNativeDoctorExpectedMarker -Name "register_hotkey_available"
    }
}

function Get-RomaWindowsNativeDoctorOutputProof {
    param(
        [string]$Output = "",
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $expectedMarker = Get-RomaWindowsNativeDoctorExpectedMarker -Name $Name
    $proof = [ordered]@{
        output_present = ![string]::IsNullOrWhiteSpace($Output)
        expected_marker = $expectedMarker
    }
    Add-RomaWindowsProofFields -Proof $proof -Fields (Get-RomaWindowsOutputMarkerProof -Output $Output -Markers (Get-RomaWindowsNativeDoctorOutputMarkers -Name $Name)) | Out-Null
    Add-RomaWindowsProofFields -Proof $proof -Fields (Get-RomaWindowsHoldTimeoutDefaultOutputProof -Output $Output) | Out-Null
    Add-RomaWindowsProofFields -Proof $proof -Fields (Get-RomaWindowsClipboardRestoreDefaultOutputProof -Output $Output) | Out-Null
    return $proof
}

function Get-RomaWindowsNativeDoctorOutputProofs {
    param(
        [object]$Outputs
    )

    $proofs = [ordered]@{}
    $specs = Get-RomaWindowsNativeDoctorSpecs
    foreach ($name in $specs.Keys) {
        $output = ""
        if ($null -ne $Outputs -and $Outputs.Contains($name)) {
            $output = $Outputs[$name]
        }
        $proofs[$name] = Get-RomaWindowsNativeDoctorOutputProof -Output $output -Name $name
    }
    return $proofs
}

function Get-RomaWindowsHotkeyDeliveryPreflightOutputMarkers {
    return [ordered]@{
        waiting_for_hold = Get-RomaWindowsWaitingForHoldOutputMarker
        key_down = "key_down=true"
        key_up = "key_up=true"
        observed_events_present = "observed_events="
    }
}

function Get-RomaWindowsHotkeyDeliveryPreflightOutputProof {
    param(
        [string]$Output = ""
    )

    $proof = [ordered]@{
        output_present = ![string]::IsNullOrWhiteSpace($Output)
    }
    Add-RomaWindowsProofFields -Proof $proof -Fields (Get-RomaWindowsOutputMarkerProof -Output $Output -Markers (Get-RomaWindowsHotkeyDeliveryPreflightOutputMarkers)) | Out-Null
    return $proof
}

function Get-RomaWindowsPermissionPreflightOutputProof {
    param(
        [string]$Output = ""
    )

    $proof = [ordered]@{
        output_present = ![string]::IsNullOrWhiteSpace($Output)
    }
    Add-RomaWindowsProofFields -Proof $proof -Fields (Get-RomaWindowsMinimumPermissionOutputProof -Output $Output) | Out-Null
    return $proof
}

function Get-RomaWindowsMicrophonePreflightOutputMarkers {
    return [ordered]@{
        wrote_present = "wrote="
        reported_duration = "duration_seconds="
        reported_pre_roll = "included_pre_roll_seconds="
        sample_rate_16000 = "sample_rate=16000"
        channels_mono = "channels=1"
    }
}

function Get-RomaWindowsMicrophonePreflightOutputProof {
    param(
        [string]$Output = ""
    )

    $durationSeconds = Get-RomaWindowsOutputNumber -Output $Output -Name "duration_seconds"
    $includedPreRollSeconds = Get-RomaWindowsOutputNumber -Output $Output -Name "included_pre_roll_seconds"

    $proof = [ordered]@{
        output_present = ![string]::IsNullOrWhiteSpace($Output)
        duration_seconds = $durationSeconds
        reported_positive_duration = ($null -ne $durationSeconds) -and ($durationSeconds -gt 0)
        included_pre_roll_seconds = $includedPreRollSeconds
        reported_positive_pre_roll = ($null -ne $includedPreRollSeconds) -and ($includedPreRollSeconds -gt 0)
    }
    Add-RomaWindowsProofFields -Proof $proof -Fields (Get-RomaWindowsOutputMarkerProof -Output $Output -Markers (Get-RomaWindowsMicrophonePreflightOutputMarkers)) | Out-Null
    return $proof
}

function Get-RomaWindowsLocalWhisperPreflightOutputMarkers {
    return [ordered]@{
        transcription_client_whisper = "transcription_client=whisper.cpp-cli"
        network_required_false = "network_required=false"
        executable_present = "executable="
        model_file_present = "model_file="
    }
}

function Get-RomaWindowsLocalWhisperPreflightOutputProof {
    param(
        [string]$Output = ""
    )

    $proof = [ordered]@{
        output_present = ![string]::IsNullOrWhiteSpace($Output)
    }
    Add-RomaWindowsProofFields -Proof $proof -Fields (Get-RomaWindowsOutputMarkerProof -Output $Output -Markers (Get-RomaWindowsLocalWhisperPreflightOutputMarkers)) | Out-Null
    return $proof
}

function New-RomaWindowsLaptopPreflightOutputProofs {
    param(
        [string]$PermissionSurfaceOutput = "",
        [string]$HotkeyDeliveryOutput = "",
        [string]$MicrophoneOutput = "",
        [string]$LocalWhisperOutput = ""
    )

    return [ordered]@{
        permission_surface = Get-RomaWindowsPermissionPreflightOutputProof -Output $PermissionSurfaceOutput
        hotkey_delivery = Get-RomaWindowsHotkeyDeliveryPreflightOutputProof -Output $HotkeyDeliveryOutput
        microphone = Get-RomaWindowsMicrophonePreflightOutputProof -Output $MicrophoneOutput
        local_whisper = Get-RomaWindowsLocalWhisperPreflightOutputProof -Output $LocalWhisperOutput
    }
}

function New-RomaWindowsLaptopPreflightSyntheticOutputProofs {
    param(
        [bool]$IncludeLocalWhisper = $true
    )

    return [ordered]@{
        permission_surface = [ordered]@{
            output_present = $true
            os_permission_grants_microphone = $true
            microphone_settings_uri = $true
            desktop_app_microphone_access_required = $true
            native_capabilities_register_hotkey = $true
            no_accessibility_permission_prompt = $true
            no_automation_permission_prompt = $true
            no_admin_required = $true
            startup_launcher_run_script = $true
            startup_launch_mode_listen = $true
            no_startup_permission_prompt = $true
            no_screen_capture_required = $true
            no_screen_recording_permission_prompt = $true
        }
        hotkey_delivery = [ordered]@{
            output_present = $true
            waiting_for_hold = $true
            key_down = $true
            key_up = $true
            observed_events_present = $true
        }
        microphone = [ordered]@{
            output_present = $true
            wrote_present = $true
            reported_duration = $true
            duration_seconds = 1.0
            reported_positive_duration = $true
            reported_pre_roll = $true
            included_pre_roll_seconds = 0.5
            reported_positive_pre_roll = $true
            sample_rate_16000 = $true
            channels_mono = $true
        }
        local_whisper = [ordered]@{
            output_present = $IncludeLocalWhisper
            transcription_client_whisper = $IncludeLocalWhisper
            network_required_false = $IncludeLocalWhisper
            executable_present = $IncludeLocalWhisper
            model_file_present = $IncludeLocalWhisper
        }
    }
}

function Get-RomaWindowsOSReportProof {
    param(
        [switch]$RequireUserSid
    )

    $userSid = if ($RequireUserSid) {
        Require-RomaWindowsCurrentUserSid
    } else {
        Get-RomaWindowsCurrentUserSid
    }

    return [ordered]@{
        platform = [System.Environment]::OSVersion.Platform.ToString()
        version = [System.Environment]::OSVersion.VersionString
        machine = $env:COMPUTERNAME
        user_name = $env:USERNAME
        user_domain = $env:USERDOMAIN
        user_sid = $userSid
    }
}

function New-RomaWindowsLaptopPreflightReport {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProofSessionId,
        [Parameter(Mandatory = $true)]
        [string]$PackageDir,
        [Parameter(Mandatory = $true)]
        [string]$ProofDir,
        [object]$Manifest = $null,
        [object]$PackageIdentity = $null,
        [Parameter(Mandatory = $true)]
        [object]$PreflightOutputs,
        [Parameter(Mandatory = $true)]
        [object]$FileProofs,
        [bool]$IncludeLocalWhisper = $false,
        [switch]$RequireUserSid
    )

    if ($null -eq $Manifest) {
        $Manifest = [ordered]@{}
    }
    if ($null -eq $PackageIdentity) {
        $PackageIdentity = [ordered]@{}
    }

    return [ordered]@{
        generated_at = (Get-Date).ToUniversalTime().ToString("o")
        proof_session_id = $ProofSessionId
        proof_mode = Get-RomaWindowsProofProfileExpectedModeByName -Name "laptop_preflight"
        preflight_only = $true
        package_dir = $PackageDir
        proof_dir = $ProofDir
        manifest = $Manifest
        package_identity = $PackageIdentity
        os = Get-RomaWindowsOSReportProof -RequireUserSid:$RequireUserSid
        preflights = [ordered]@{
            permission_surface = $true
            hotkey_delivery = $true
            microphone = $true
            local_whisper = $IncludeLocalWhisper
        }
        preflight_outputs = $PreflightOutputs
        files = $FileProofs
    }
}

function New-RomaWindowsLaptopPreflightSyntheticReport {
    param(
        [string]$ProofSessionId = "",
        [Parameter(Mandatory = $true)]
        [string]$PackageDir,
        [Parameter(Mandatory = $true)]
        [string]$ProofDir,
        [Parameter(Mandatory = $true)]
        [string]$ProofAgentPath,
        [Parameter(Mandatory = $true)]
        [string]$MicPreflightPath,
        [string]$WhisperCLIPath = "",
        [string]$WhisperModelPath = "",
        [object]$Manifest = $null,
        [object]$PackageIdentity = $null,
        [bool]$IncludeLocalWhisper = $true,
        [switch]$RequireUserSid
    )

    if ([string]::IsNullOrWhiteSpace($ProofSessionId)) {
        $ProofSessionId = [guid]::NewGuid().ToString("D")
    }

    $whisperCLIProof = if ($IncludeLocalWhisper) {
        Require-RomaWindowsFileProof -Path $WhisperCLIPath
    } else {
        Get-RomaWindowsEmptyFileProof
    }
    $whisperModelProof = if ($IncludeLocalWhisper) {
        Require-RomaWindowsFileProof -Path $WhisperModelPath
    } else {
        Get-RomaWindowsEmptyFileProof
    }

    return New-RomaWindowsLaptopPreflightReport `
        -ProofSessionId $ProofSessionId `
        -PackageDir $PackageDir `
        -ProofDir $ProofDir `
        -Manifest $Manifest `
        -PackageIdentity $PackageIdentity `
        -PreflightOutputs (New-RomaWindowsLaptopPreflightSyntheticOutputProofs -IncludeLocalWhisper $IncludeLocalWhisper) `
        -FileProofs ([ordered]@{
            proof_agent = Require-RomaWindowsFileProof -Path $ProofAgentPath
            mic_preflight_wav = Require-RomaWindowsFileProof -Path $MicPreflightPath
            whisper_cli = $whisperCLIProof
            whisper_model = $whisperModelProof
        }) `
        -IncludeLocalWhisper $IncludeLocalWhisper `
        -RequireUserSid:$RequireUserSid
}

function Write-RomaWindowsLaptopPreflightCheckerSmokeReport {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ReportPath,
        [Parameter(Mandatory = $true)]
        [string]$PackageDir,
        [Parameter(Mandatory = $true)]
        [string]$ProofDir,
        [Parameter(Mandatory = $true)]
        [string]$ProofAgentPath,
        [Parameter(Mandatory = $true)]
        [string]$WhisperCLIPath,
        [Parameter(Mandatory = $true)]
        [string]$WhisperModelPath,
        [Parameter(Mandatory = $true)]
        [hashtable]$GitMetadata,
        [Parameter(Mandatory = $true)]
        [object]$PackageIdentity,
        [bool]$IncludeLocalWhisper = $true
    )

    New-Item -ItemType Directory -Force -Path $ProofDir | Out-Null
    $micPreflightPath = Join-Path $ProofDir "ci-mic-preflight.wav"
    $wavBytes = [byte[]]::new(46)
    $riffBytes = [System.Text.Encoding]::ASCII.GetBytes("RIFF")
    [System.Array]::Copy($riffBytes, $wavBytes, $riffBytes.Length)
    [System.IO.File]::WriteAllBytes($micPreflightPath, $wavBytes)

    $report = New-RomaWindowsLaptopPreflightSyntheticReport `
        -PackageDir $PackageDir `
        -ProofDir $ProofDir `
        -Manifest ([ordered]@{
            source_repository = $GitMetadata.Repository
            source_branch = $GitMetadata.Branch
            source_commit = $GitMetadata.Commit
            source_dirty = $GitMetadata.Dirty
        }) `
        -PackageIdentity $PackageIdentity `
        -ProofAgentPath $ProofAgentPath `
        -MicPreflightPath $micPreflightPath `
        -WhisperCLIPath $WhisperCLIPath `
        -WhisperModelPath $WhisperModelPath `
        -IncludeLocalWhisper $IncludeLocalWhisper `
        -RequireUserSid

    $report |
        ConvertTo-Json -Depth 6 |
        Set-Content -LiteralPath $ReportPath -Encoding UTF8
    Write-Host "laptop_preflight_checker_smoke_report=$ReportPath"
}

function Invoke-RomaWindowsLaptopPreflightReportProfileSmoke {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CheckerScriptPath,
        [Parameter(Mandatory = $true)]
        [string]$ReportPath,
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [bool]$ExpectLocalWhisper
    )

    $profileOutputText = & $CheckerScriptPath `
        -ProofReportPath $ReportPath `
        -RequireProofProfile laptop-preflight 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        Write-Host $profileOutputText
        throw "$Name laptop preflight report profile smoke failed"
    }

    Write-Host $profileOutputText
    Assert-RomaWindowsLaptopPreflightProfileOutput `
        -Output $profileOutputText `
        -ExpectLocalWhisper $ExpectLocalWhisper
    return $profileOutputText
}

function Invoke-RomaWindowsLaptopPreflightCheckerSmoke {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ReportPath,
        [Parameter(Mandatory = $true)]
        [string]$PackageDir,
        [Parameter(Mandatory = $true)]
        [string]$ProofDir,
        [Parameter(Mandatory = $true)]
        [string]$ProofAgentPath,
        [Parameter(Mandatory = $true)]
        [string]$WhisperCLIPath,
        [Parameter(Mandatory = $true)]
        [string]$WhisperModelPath,
        [Parameter(Mandatory = $true)]
        [hashtable]$GitMetadata,
        [Parameter(Mandatory = $true)]
        [object]$PackageIdentity,
        [Parameter(Mandatory = $true)]
        [string]$ReportCheckerScriptPath,
        [Parameter(Mandatory = $true)]
        [string]$SetCheckerScriptPath,
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [bool]$IncludeLocalWhisper = $true
    )

    Write-RomaWindowsLaptopPreflightCheckerSmokeReport `
        -ReportPath $ReportPath `
        -PackageDir $PackageDir `
        -ProofDir $ProofDir `
        -ProofAgentPath $ProofAgentPath `
        -WhisperCLIPath $WhisperCLIPath `
        -WhisperModelPath $WhisperModelPath `
        -GitMetadata $GitMetadata `
        -PackageIdentity $PackageIdentity `
        -IncludeLocalWhisper $IncludeLocalWhisper

    Invoke-RomaWindowsLaptopPreflightReportProfileSmoke `
        -CheckerScriptPath $ReportCheckerScriptPath `
        -ReportPath $ReportPath `
        -Name $Name `
        -ExpectLocalWhisper $IncludeLocalWhisper | Out-Null

    $checkerOutputText = & $SetCheckerScriptPath `
        -LaptopPreflightReportPath $ReportPath `
        -RequireLaptopPreflight 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        Write-Host $checkerOutputText
        throw "$Name laptop preflight report checker smoke failed"
    }

    Write-Host $checkerOutputText
    Assert-RomaWindowsLaptopPreflightSetOutput `
        -Output $checkerOutputText `
        -ExpectLocalWhisper $IncludeLocalWhisper
    return $checkerOutputText
}

function Get-RomaWindowsListenerSmokeOutputMarkers {
    return [ordered]@{
        mode_listen = "mode=listen"
        launcher_mode_listen = "mode=RomaWindowsAgent listen"
        shared_pre_roll_runtime = "listener_capture_lifecycle=shared_pre_roll_runtime"
        zero_session = "max_sessions=0"
        completed_zero_sessions = "listen_completed_sessions=0"
    }
}

function Get-RomaWindowsListenerSmokeOutputProof {
    param(
        [string]$Output = ""
    )

    $proof = [ordered]@{
        output_present = ![string]::IsNullOrWhiteSpace($Output)
    }
    Add-RomaWindowsProofFields -Proof $proof -Fields (Get-RomaWindowsOutputMarkerProof -Output $Output -Markers (Get-RomaWindowsListenerSmokeOutputMarkers)) | Out-Null
    return $proof
}

function Get-RomaWindowsInstalledListenerSmokeOutputProof {
    param(
        [string]$Output = ""
    )

    $configPath = Get-RomaWindowsOutputValue -Content $Output -Name "config"
    $agentPath = Get-RomaWindowsOutputValue -Content $Output -Name "agent_exe"
    $proof = Get-RomaWindowsListenerSmokeOutputProof -Output $Output
    $proof["config_path"] = $configPath
    $proof["config_path_present"] = ![string]::IsNullOrWhiteSpace($configPath)
    $proof["agent_path"] = $agentPath
    $proof["agent_path_present"] = ![string]::IsNullOrWhiteSpace($agentPath)
    return $proof
}

function Get-RomaWindowsOutputValue {
    param(
        [Alias("Content")]
        [Parameter(Mandatory = $true)]
        [string]$Output,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $escapedName = [regex]::Escape($Name)
    $match = [regex]::Match($Output, "(?m)^$escapedName=(.+?)\s*$")
    if (!$match.Success) {
        return ""
    }

    return $match.Groups[1].Value
}

function Get-RomaWindowsOutputNumber {
    param(
        [Alias("Content")]
        [Parameter(Mandatory = $true)]
        [string]$Output,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $escapedName = [regex]::Escape($Name)
    $match = [regex]::Match($Output, "(?m)^$escapedName=([+-]?\d+(?:\.\d+)?)\s*$")
    if (!$match.Success) {
        return $null
    }

    return [double]::Parse(
        $match.Groups[1].Value,
        [System.Globalization.CultureInfo]::InvariantCulture
    )
}

function Get-RomaWindowsOutputLineNumber {
    param(
        [Alias("Content")]
        [Parameter(Mandatory = $true)]
        [string]$Output,
        [Parameter(Mandatory = $true)]
        [string]$Needle
    )

    $lines = $Output -split "\r?\n"
    for ($index = 0; $index -lt $lines.Count; $index += 1) {
        if ($lines[$index].Contains($Needle)) {
            return $index + 1
        }
    }

    return 0
}

function Test-RomaWindowsContainsText {
    param(
        [string]$Text = "",
        [string]$Needle = ""
    )

    if ([string]::IsNullOrEmpty($Needle)) {
        return $false
    }

    return $Text.IndexOf($Needle, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
}

function Get-RomaWindowsDictationRuntimeLogOutputMarkers {
    return [ordered]@{
        reported_wrote = "wrote="
        reported_pre_roll = "included_pre_roll_seconds="
        reported_paste_sent = "paste_sent=true"
        reported_paste_not_sent = "paste_sent=false"
        reported_hold_mode = "recording_mode=hold"
        reported_waiting_for_hold_key_down = "waiting_for_key_down="
        reported_hold_key_down = "hold_key_down=true"
        reported_hold_key_up = "hold_key_up=true"
    }
}

function Get-RomaWindowsListenerRuntimeLogOutputMarkers {
    return [ordered]@{
        launcher_mode_listen = "mode=RomaWindowsAgent listen"
        agent_mode_listen = "mode=listen"
        shared_pre_roll_runtime = "listener_capture_lifecycle=shared_pre_roll_runtime"
        max_sessions_one = "max_sessions=1"
        session_start_one = "listen_session_start=1"
        session_completed_one = "listen_session_completed=1"
        completed_one_session = "listen_completed_sessions=1"
    }
}

function Assert-RomaWindowsListenerRuntimeLogOutput {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Output
    )

    Assert-RomaWindowsOutputMarkers -Output $Output -Markers (Get-RomaWindowsListenerRuntimeLogOutputMarkers)
}

function Get-RomaWindowsDictationRuntimeLogProof {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogPath,
        [string]$ExpectedText = ""
    )

    $proof = Get-RomaWindowsFileProof -Path $LogPath
    if (!$proof["exists"]) {
        return $proof
    }

    $content = Get-Content -LiteralPath $LogPath -Raw
    $wrotePath = Get-RomaWindowsOutputValue -Content $content -Name "wrote"
    $durationSeconds = Get-RomaWindowsOutputNumber -Content $content -Name "duration_seconds"
    $includedPreRollSeconds = Get-RomaWindowsOutputNumber -Content $content -Name "included_pre_roll_seconds"
    $sampleRate = Get-RomaWindowsOutputNumber -Content $content -Name "sample_rate"
    $channelCount = Get-RomaWindowsOutputNumber -Content $content -Name "channels"
    $rawTranscriptLength = Get-RomaWindowsOutputNumber -Content $content -Name "raw_transcript_length"
    $processedTranscriptLength = Get-RomaWindowsOutputNumber -Content $content -Name "processed_transcript_length"
    $processedTranscriptText = Get-RomaWindowsOutputValue -Content $content -Name "processed_transcript_text"
    $preRollBufferingLine = Get-RomaWindowsOutputLineNumber -Content $content -Needle "pre_roll_buffering=true"
    $waitingForHoldLine = Get-RomaWindowsOutputLineNumber -Content $content -Needle "waiting_for_key_down="
    $holdKeyDownLine = Get-RomaWindowsOutputLineNumber -Content $content -Needle "hold_key_down=true"
    $holdKeyUpLine = Get-RomaWindowsOutputLineNumber -Content $content -Needle "hold_key_up=true"
    $wroteLine = Get-RomaWindowsOutputLineNumber -Content $content -Needle "wrote="
    $processedTextLine = Get-RomaWindowsOutputLineNumber -Content $content -Needle "processed_transcript_text="
    Add-RomaWindowsProofFields -Proof $proof -Fields (Get-RomaWindowsOutputMarkerProof -Output $content -Markers (Get-RomaWindowsDictationRuntimeLogOutputMarkers)) | Out-Null
    $proof["wrote_path"] = $wrotePath
    if (![string]::IsNullOrWhiteSpace($wrotePath)) {
        $proof["wrote_file"] = Get-RomaWindowsFileProof -Path $wrotePath
    }
    $proof["duration_seconds"] = $durationSeconds
    $proof["included_pre_roll_seconds"] = $includedPreRollSeconds
    $proof["reported_positive_duration"] = ($null -ne $durationSeconds) -and ($durationSeconds -gt 0)
    $proof["reported_positive_pre_roll"] = ($null -ne $includedPreRollSeconds) -and ($includedPreRollSeconds -gt 0)
    $proof["sample_rate"] = $sampleRate
    $proof["channels"] = $channelCount
    $proof["reported_speech_pcm_contract"] = (
        ($null -ne $sampleRate) -and
        ($null -ne $channelCount) -and
        ($sampleRate -eq 16000) -and
        ($channelCount -eq 1)
    )
    $proof["raw_transcript_length"] = $rawTranscriptLength
    $proof["processed_transcript_length"] = $processedTranscriptLength
    $proof["reported_positive_raw_transcript"] = ($null -ne $rawTranscriptLength) -and ($rawTranscriptLength -gt 0)
    $proof["reported_positive_processed_transcript"] = ($null -ne $processedTranscriptLength) -and ($processedTranscriptLength -gt 0)
    $proof["reported_processed_text"] = ![string]::IsNullOrWhiteSpace($processedTranscriptText)
    $proof["processed_transcript_text_present"] = ![string]::IsNullOrWhiteSpace($processedTranscriptText)
    $proof["pre_roll_buffering_line"] = $preRollBufferingLine
    $proof["waiting_for_hold_key_down_line"] = $waitingForHoldLine
    $proof["hold_key_down_line"] = $holdKeyDownLine
    $proof["hold_key_up_line"] = $holdKeyUpLine
    $proof["wrote_line"] = $wroteLine
    $proof["processed_transcript_text_line"] = $processedTextLine
    $proof["reported_ordered_hold_sequence"] = (
        $preRollBufferingLine -gt 0 -and
        $waitingForHoldLine -gt $preRollBufferingLine -and
        $holdKeyDownLine -gt $waitingForHoldLine -and
        $holdKeyUpLine -gt $holdKeyDownLine -and
        $wroteLine -gt $holdKeyUpLine -and
        $processedTextLine -gt $wroteLine
    )
    $expectedTranscriptTextFound = $false
    if (![string]::IsNullOrWhiteSpace($ExpectedText)) {
        $expectedTranscriptTextFound = Test-RomaWindowsContainsText `
            -Text $processedTranscriptText `
            -Needle $ExpectedText
    }
    $proof["expected_transcript_text"] = $ExpectedText
    $proof["expected_transcript_text_required"] = ![string]::IsNullOrWhiteSpace($ExpectedText)
    $proof["expected_transcript_text_source"] = "processed_transcript_text"
    $proof["expected_transcript_text_found"] = $expectedTranscriptTextFound

    return $proof
}

function Get-RomaWindowsListenerRuntimeLogProof {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogPath,
        [string]$ExpectedText = ""
    )

    $proof = Get-RomaWindowsDictationRuntimeLogProof `
        -LogPath $LogPath `
        -ExpectedText $ExpectedText
    if (!$proof["exists"]) {
        return $proof
    }

    $content = Get-Content -LiteralPath $LogPath -Raw
    Add-RomaWindowsProofFields -Proof $proof -Fields (Get-RomaWindowsOutputMarkerProof -Output $content -Markers (Get-RomaWindowsListenerRuntimeLogOutputMarkers)) | Out-Null
    $proof["mode_listen"] = $proof["launcher_mode_listen"] -and $proof["agent_mode_listen"]

    return $proof
}

function Get-RomaWindowsInstalledDictationRuntimeLogProof {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallDir,
        [string]$ExpectedText = ""
    )

    return Get-RomaWindowsDictationRuntimeLogProof `
        -LogPath (Join-RomaWindowsInstalledDictationRuntimeLogPath -InstallDir $InstallDir) `
        -ExpectedText $ExpectedText
}

function Get-RomaWindowsInstalledListenerRuntimeLogProof {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallDir,
        [string]$ExpectedText = ""
    )

    return Get-RomaWindowsListenerRuntimeLogProof `
        -LogPath (Join-RomaWindowsInstalledListenerRuntimeLogPath -InstallDir $InstallDir) `
        -ExpectedText $ExpectedText
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

function Get-RomaWindowsConfigDoctorOutputMarkers {
    return [ordered]@{
        config_valid = "config_valid=true"
        transcription_client_present = "transcription_client="
    }
}

function Get-RomaWindowsCloudConfigDoctorOutputMarkers {
    return [ordered]@{
        uses_cloud = "transcription_client=openai-compatible"
        api_key_resolved = "api_key_resolved=true"
    }
}

function Get-RomaWindowsWhisperConfigDoctorOutputMarkers {
    return [ordered]@{
        uses_whisper_cli = "transcription_client=whisper.cpp-cli"
        whisper_cli_exists = "whisper_cli_exists=true"
        whisper_model_exists = "whisper_model_exists=true"
    }
}

function Assert-RomaWindowsConfigDoctorOutput {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Output,
        [bool]$RequireCloud = $false,
        [bool]$RequireWhisperCLI = $false
    )

    if ($RequireCloud -and $RequireWhisperCLI) {
        throw "RequireCloud and RequireWhisperCLI are mutually exclusive"
    }

    Assert-RomaWindowsOutputMarkers -Output $Output -Markers (Get-RomaWindowsConfigDoctorOutputMarkers)
    if ($RequireCloud) {
        Assert-RomaWindowsOutputMarkers -Output $Output -Markers (Get-RomaWindowsCloudConfigDoctorOutputMarkers)
    }
    if ($RequireWhisperCLI) {
        Assert-RomaWindowsOutputMarkers -Output $Output -Markers (Get-RomaWindowsWhisperConfigDoctorOutputMarkers)
    }
}

function Assert-RomaWindowsAgentConfigWriteOutput {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Output,
        [string]$ConfigPath = "",
        [bool]$RequireCloud = $false,
        [bool]$RequireWhisperCLI = $false,
        [string]$ExpectedEndpoint = "",
        [string]$ExpectedWhisperCLI = "",
        [bool]$RequireClipboardRestoreFields = $false
    )

    if ($RequireCloud -and $RequireWhisperCLI) {
        throw "RequireCloud and RequireWhisperCLI are mutually exclusive"
    }

    Assert-RomaWindowsOutputContains -Output $Output -Expected "written=true"
    if (![string]::IsNullOrWhiteSpace($ConfigPath)) {
        Assert-RomaWindowsOutputContains -Output $Output -Expected "config=$ConfigPath"
    }
    if ($RequireCloud) {
        Assert-RomaWindowsOutputContains -Output $Output -Expected "transcription_client=openai-compatible"
        if (![string]::IsNullOrWhiteSpace($ExpectedEndpoint)) {
            Assert-RomaWindowsOutputContains -Output $Output -Expected "endpoint=$ExpectedEndpoint"
        }
    }
    if ($RequireWhisperCLI) {
        Assert-RomaWindowsOutputContains -Output $Output -Expected "transcription_client=whisper.cpp-cli"
        if (![string]::IsNullOrWhiteSpace($ExpectedWhisperCLI)) {
            Assert-RomaWindowsOutputContains -Output $Output -Expected "whisper_cli=$ExpectedWhisperCLI"
        }
    }
    if ($RequireClipboardRestoreFields) {
        Assert-RomaWindowsOutputContains -Output $Output -Expected "restore_clipboard_after_paste="
        Assert-RomaWindowsOutputContains -Output $Output -Expected "clipboard_restore_delay_seconds="
    }
}

function Assert-RomaWindowsAgentScriptCommonOptions {
    param(
        [bool]$UseHoldHook = $false,
        [bool]$UseToggle = $false,
        [bool]$PasteDictation = $false,
        [bool]$NoPaste = $false,
        [bool]$RestoreClipboard = $false,
        [bool]$NoRestoreClipboard = $false,
        [bool]$HasClipboardRestoreDelay = $false,
        [double]$ClipboardRestoreDelaySeconds = 2
    )

    if ($UseHoldHook -and $UseToggle) {
        throw "UseHoldHook and UseToggle are mutually exclusive"
    }

    if ($PasteDictation -and $NoPaste) {
        throw "PasteDictation and NoPaste are mutually exclusive"
    }

    if ($RestoreClipboard -and $NoRestoreClipboard) {
        throw "RestoreClipboard and NoRestoreClipboard are mutually exclusive"
    }

    if ($NoRestoreClipboard -and $HasClipboardRestoreDelay) {
        throw "NoRestoreClipboard and ClipboardRestoreDelaySeconds are mutually exclusive"
    }

    if ($ClipboardRestoreDelaySeconds -lt 0) {
        throw "ClipboardRestoreDelaySeconds must be non-negative"
    }
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

function Get-RomaWindowsConfigDoctorOutputProof {
    param(
        [string]$Output = ""
    )

    $configPath = Get-RomaWindowsOutputValue -Content $Output -Name "config"
    $transcriptionClient = Get-RomaWindowsOutputValue -Content $Output -Name "transcription_client"
    $proof = [ordered]@{
        output_present = ![string]::IsNullOrWhiteSpace($Output)
        config_path = $configPath
        config_path_present = ![string]::IsNullOrWhiteSpace($configPath)
        transcription_client = $transcriptionClient
    }
    Add-RomaWindowsProofFields -Proof $proof -Fields (Get-RomaWindowsOutputMarkerProof -Output $Output -Markers (Get-RomaWindowsConfigDoctorOutputMarkers)) | Out-Null
    Add-RomaWindowsProofFields -Proof $proof -Fields (Get-RomaWindowsOutputMarkerProof -Output $Output -Markers (Get-RomaWindowsCloudConfigDoctorOutputMarkers)) | Out-Null
    Add-RomaWindowsProofFields -Proof $proof -Fields (Get-RomaWindowsOutputMarkerProof -Output $Output -Markers (Get-RomaWindowsWhisperConfigDoctorOutputMarkers)) | Out-Null
    return $proof
}

function Get-RomaWindowsAgentConfigFileProof {
    param(
        [string]$ConfigPath = ""
    )

    if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
        return [ordered]@{
            path = ""
            exists = $false
        }
    }

    $proof = Get-RomaWindowsFileProof -Path $ConfigPath
    if (!$proof["exists"]) {
        return $proof
    }

    $config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
    if ($config.PSObject.Properties.Name -contains "outputPath") {
        $outputPath = [string]$config.outputPath
        $proof["output_path"] = $outputPath
        if (![string]::IsNullOrWhiteSpace($outputPath)) {
            $proof["output_file"] = Get-RomaWindowsFileProof -Path $outputPath
        }
    }
    if ($config.PSObject.Properties.Name -contains "usesHoldHook") {
        $proof["uses_hold_hook"] = [bool]$config.usesHoldHook
    }
    if ($config.PSObject.Properties.Name -contains "shouldPaste") {
        $proof["should_paste"] = [bool]$config.shouldPaste
    }
    if ($config.PSObject.Properties.Name -contains "restoreClipboardAfterPaste") {
        $proof["restore_clipboard_after_paste"] = [bool]$config.restoreClipboardAfterPaste
    }
    if ($config.PSObject.Properties.Name -contains "whisperCLIPath" -and
        ![string]::IsNullOrWhiteSpace([string]$config.whisperCLIPath)) {
        $proof["uses_whisper_cli"] = $true
        $proof["whisper_cli_path"] = [string]$config.whisperCLIPath
        $proof["whisper_cli_file"] = Get-RomaWindowsFileProof -Path ([string]$config.whisperCLIPath)
        if ($config.PSObject.Properties.Name -contains "whisperModelPath") {
            $proof["whisper_model_path"] = [string]$config.whisperModelPath
            $proof["whisper_model_file"] = Get-RomaWindowsFileProof -Path ([string]$config.whisperModelPath)
        }
    } else {
        $proof["uses_whisper_cli"] = $false
    }
    if ($config.PSObject.Properties.Name -contains "endpoint") {
        $proof["endpoint"] = [string]$config.endpoint
    }
    if ($config.PSObject.Properties.Name -contains "model") {
        $proof["model"] = [string]$config.model
    }

    return $proof
}

function Get-RomaWindowsAgentShortcutFileName {
    return "Roma Just Talk Agent.lnk"
}

function Join-RomaWindowsAgentShortcutPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ShortcutDir,
        [string]$ShortcutName = ""
    )

    if ([string]::IsNullOrWhiteSpace($ShortcutName)) {
        $ShortcutName = Get-RomaWindowsAgentShortcutFileName
    }

    return Join-Path $ShortcutDir $ShortcutName
}

function Get-RomaWindowsAgentShortcutTargetPath {
    return "powershell.exe"
}

function New-RomaWindowsAgentShortcutArguments {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RunScriptPath,
        [Parameter(Mandatory = $true)]
        [string]$InstallDir,
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath
    )

    return "-NoProfile -ExecutionPolicy Bypass -File `"$RunScriptPath`" -InstallDir `"$InstallDir`" -ConfigPath `"$ConfigPath`" -Listen"
}

function Assert-RomaWindowsAgentShortcutContract {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Shortcut,
        [Parameter(Mandatory = $true)]
        [string]$RunScriptPath,
        [Parameter(Mandatory = $true)]
        [string]$InstallDir,
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath
    )

    $targetPath = [string]$Shortcut.TargetPath
    $arguments = [string]$Shortcut.Arguments
    $workingDirectory = [string]$Shortcut.WorkingDirectory
    $expectedTargetPath = Get-RomaWindowsAgentShortcutTargetPath
    $expectedArguments = New-RomaWindowsAgentShortcutArguments `
        -RunScriptPath $RunScriptPath `
        -InstallDir $InstallDir `
        -ConfigPath $ConfigPath

    if (!$targetPath.EndsWith($expectedTargetPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Shortcut target path does not launch $expectedTargetPath`: $targetPath"
    }
    if (!$arguments.Equals($expectedArguments, [System.StringComparison]::Ordinal)) {
        throw "Shortcut arguments did not match installed listener contract: expected=$expectedArguments actual=$arguments"
    }
    if (!$workingDirectory.Equals($InstallDir, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Shortcut working directory did not match install dir: expected=$InstallDir actual=$workingDirectory"
    }

    return $true
}

function New-RomaWindowsAgentShortcut {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ShortcutPath,
        [Parameter(Mandatory = $true)]
        [string]$RunScriptPath,
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath,
        [Parameter(Mandatory = $true)]
        [string]$InstallDir,
        [Parameter(Mandatory = $true)]
        [string]$Description
    )

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($ShortcutPath)
    $shortcut.TargetPath = Get-RomaWindowsAgentShortcutTargetPath
    $shortcut.Arguments = New-RomaWindowsAgentShortcutArguments `
        -RunScriptPath $RunScriptPath `
        -InstallDir $InstallDir `
        -ConfigPath $ConfigPath
    $shortcut.WorkingDirectory = $InstallDir
    $shortcut.Description = $Description
    $shortcut.WindowStyle = 7
    $shortcut.Save()

    Require-RomaWindowsFile -Path $ShortcutPath
    $savedShortcut = $shell.CreateShortcut($ShortcutPath)
    Assert-RomaWindowsAgentShortcutContract `
        -Shortcut $savedShortcut `
        -RunScriptPath $RunScriptPath `
        -InstallDir $InstallDir `
        -ConfigPath $ConfigPath |
        Out-Null

    return $savedShortcut
}

function Join-RomaWindowsInstalledAgentPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallDir
    )

    return Join-Path $InstallDir (Get-RomaWindowsAgentExecutableFileName)
}

function Join-RomaWindowsInstalledProofAgentPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallDir
    )

    return Join-Path $InstallDir (Get-RomaWindowsProofAgentExecutableFileName)
}

function Join-RomaWindowsInstalledRunScriptPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallDir
    )

    return Join-Path $InstallDir "run-windows-agent.ps1"
}

function Get-RomaWindowsAgentShortcutReportPaths {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallDir,
        [string]$ShortcutDir = "",
        [string]$StartupShortcutDir = "",
        [bool]$CreateStartupShortcut = $false,
        [string]$ShortcutName = "",
        [string]$StartupShortcutName = ""
    )

    if ([string]::IsNullOrWhiteSpace($ShortcutName)) {
        $ShortcutName = Get-RomaWindowsAgentShortcutFileName
    }
    if ([string]::IsNullOrWhiteSpace($StartupShortcutName)) {
        $StartupShortcutName = Get-RomaWindowsAgentShortcutFileName
    }

    $shortcutPath = ""
    if (![string]::IsNullOrWhiteSpace($ShortcutDir)) {
        $shortcutPath = Join-RomaWindowsAgentShortcutPath -ShortcutDir $ShortcutDir -ShortcutName $ShortcutName
    }

    $startupShortcutPath = ""
    if (![string]::IsNullOrWhiteSpace($StartupShortcutDir)) {
        $startupShortcutPath = Join-RomaWindowsAgentShortcutPath -ShortcutDir $StartupShortcutDir -ShortcutName $StartupShortcutName
    } elseif ($CreateStartupShortcut) {
        $startup = [System.Environment]::GetFolderPath("Startup")
        if (![string]::IsNullOrWhiteSpace($startup)) {
            $startupShortcutPath = Join-RomaWindowsAgentShortcutPath -ShortcutDir $startup -ShortcutName $StartupShortcutName
        }
    }

    return [ordered]@{
        installed_run_script_path = Join-RomaWindowsInstalledRunScriptPath -InstallDir $InstallDir
        shortcut_path = $shortcutPath
        startup_shortcut_path = $startupShortcutPath
    }
}

function Get-RomaWindowsShortcutProof {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$RunScriptPath,
        [string]$ConfigPath = "",
        [Parameter(Mandatory = $true)]
        [string]$WorkingDirectory
    )

    $proof = Get-RomaWindowsFileProof -Path $Path
    if (!$proof["exists"] -or
        [System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
        return $proof
    }

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($Path)
    $targetPath = [string]$shortcut.TargetPath
    $arguments = [string]$shortcut.Arguments
    $savedWorkingDirectory = [string]$shortcut.WorkingDirectory
    $expectedArguments = New-RomaWindowsAgentShortcutArguments `
        -RunScriptPath $RunScriptPath `
        -InstallDir $WorkingDirectory `
        -ConfigPath $ConfigPath
    $expectedFileArgument = "-File `"$RunScriptPath`""
    $expectedInstallDirArgument = "-InstallDir `"$WorkingDirectory`""
    $expectedConfigArgument = "-ConfigPath `"$ConfigPath`""

    $proof["target_path"] = $targetPath
    $proof["arguments"] = $arguments
    $proof["working_directory"] = $savedWorkingDirectory
    $proof["description"] = [string]$shortcut.Description
    $proof["window_style"] = [int]$shortcut.WindowStyle
    $proof["expected_arguments"] = $expectedArguments
    $proof["target_is_powershell"] = $targetPath.EndsWith((Get-RomaWindowsAgentShortcutTargetPath), [System.StringComparison]::OrdinalIgnoreCase)
    $proof["has_exact_arguments"] = $arguments.Equals($expectedArguments, [System.StringComparison]::Ordinal)
    $proof["references_run_script"] = ![string]::IsNullOrWhiteSpace($RunScriptPath) -and (Test-RomaWindowsContainsText -Text $arguments -Needle $RunScriptPath)
    $proof["references_install_dir"] = ![string]::IsNullOrWhiteSpace($WorkingDirectory) -and (Test-RomaWindowsContainsText -Text $arguments -Needle $WorkingDirectory)
    $proof["references_config_path"] = ![string]::IsNullOrWhiteSpace($ConfigPath) -and (Test-RomaWindowsContainsText -Text $arguments -Needle $ConfigPath)
    $proof["expected_file_argument"] = $expectedFileArgument
    $proof["expected_install_dir_argument"] = $expectedInstallDirArgument
    $proof["expected_config_argument"] = $expectedConfigArgument
    $proof["has_exact_file_argument"] = Test-RomaWindowsContainsText -Text $arguments -Needle $expectedFileArgument
    $proof["has_install_dir_argument"] = Test-RomaWindowsContainsText -Text $arguments -Needle "-InstallDir"
    $proof["has_exact_install_dir_argument"] = Test-RomaWindowsContainsText -Text $arguments -Needle $expectedInstallDirArgument
    $proof["has_config_path_argument"] = Test-RomaWindowsContainsText -Text $arguments -Needle "-ConfigPath"
    $proof["has_exact_config_argument"] = Test-RomaWindowsContainsText -Text $arguments -Needle $expectedConfigArgument
    $proof["has_no_profile_argument"] = Test-RomaWindowsContainsText -Text $arguments -Needle "-NoProfile"
    $proof["has_execution_policy_bypass"] = Test-RomaWindowsContainsText -Text $arguments -Needle "-ExecutionPolicy Bypass"
    $proof["runs_listener"] = Test-RomaWindowsContainsText -Text $arguments -Needle "-Listen"
    $proof["working_directory_is_install_dir"] = $savedWorkingDirectory.Equals($WorkingDirectory, [System.StringComparison]::OrdinalIgnoreCase)

    return $proof
}

function New-RomaWindowsNotepadPasteProof {
    param(
        [bool]$Requested = $false,
        [string]$Text = "",
        [string]$Path = ""
    )

    return [ordered]@{
        requested = $Requested
        text = $Text
        output_present = $false
        target_process_id = 0
        paste_sent = $false
        text_found = $false
        verified = $false
        file = Get-RomaWindowsFileProof -Path $Path
    }
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

function Resolve-RomaWindowsAgentSecretDir {
    param(
        [string]$SecretDir = "",
        [string]$DefaultSecretDir = "",
        [string]$ApiKeyName = ""
    )

    $resolvedSecretDir = $SecretDir
    if ([string]::IsNullOrWhiteSpace($resolvedSecretDir) -and
        ![string]::IsNullOrWhiteSpace($ApiKeyName)) {
        $resolvedSecretDir = $DefaultSecretDir
    }
    if ([string]::IsNullOrWhiteSpace($resolvedSecretDir)) {
        return ""
    }

    return Resolve-RomaWindowsFullPath -Path $resolvedSecretDir
}

function New-RomaWindowsAgentSaveKeyArgs {
    param(
        [object[]]$ArgumentList = @("save-key-from-env"),
        [Parameter(Mandatory = $true)]
        [string]$ApiKeyName,
        [Parameter(Mandatory = $true)]
        [string]$ApiKeyEnv,
        [Parameter(Mandatory = $true)]
        [string]$SecretDir
    )

    $saveKeyArgs = @($ArgumentList)
    $saveKeyArgs += @(
        "--key", $ApiKeyName,
        "--value-env", $ApiKeyEnv,
        "--secret-dir", (Resolve-RomaWindowsFullPath -Path $SecretDir)
    )

    return $saveKeyArgs
}

function Get-RomaWindowsAgentTranscriptionConfigMode {
    param(
        [string]$Endpoint = "",
        [string]$Model = "",
        [string]$WhisperCLI = "",
        [string]$WhisperModel = "",
        [bool]$RequireConfig = $false,
        [string]$MissingConfigMessage = "Pass cloud Endpoint/Model/API key or local WhisperCLI/WhisperModel",
        [bool]$RequireCloudApiKey = $false,
        [string]$ApiKeyEnv = "",
        [string]$ApiKeyName = "",
        [string]$CloudApiKeyMessage = "Cloud proof requires ApiKeyEnv or ApiKeyName"
    )

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
    if ($RequireConfig -and !$usesCloud -and !$usesWhisper) {
        throw $MissingConfigMessage
    }
    if ($RequireCloudApiKey -and $usesCloud -and
        [string]::IsNullOrWhiteSpace($ApiKeyEnv) -and
        [string]::IsNullOrWhiteSpace($ApiKeyName)) {
        throw $CloudApiKeyMessage
    }

    return [ordered]@{
        has_endpoint = $hasEndpoint
        has_model = $hasModel
        has_whisper_cli = $hasWhisperCLI
        has_whisper_model = $hasWhisperModel
        uses_cloud = $usesCloud
        uses_whisper = $usesWhisper
        has_config_input = ($usesCloud -or $usesWhisper)
    }
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

function Add-RomaWindowsAgentScriptCloudArgs {
    param(
        [object[]]$ArgumentList = @(),
        [Parameter(Mandatory = $true)]
        [string]$Endpoint,
        [Parameter(Mandatory = $true)]
        [string]$Model,
        [string]$ApiKeyEnv = "",
        [string]$ApiKeyName = "",
        [string]$SecretDir = ""
    )

    $scriptArgs = @($ArgumentList)
    $scriptArgs += @("-Endpoint", $Endpoint, "-Model", $Model)
    if (![string]::IsNullOrWhiteSpace($ApiKeyEnv)) {
        $scriptArgs += @("-ApiKeyEnv", $ApiKeyEnv)
    }
    if (![string]::IsNullOrWhiteSpace($ApiKeyName)) {
        $scriptArgs += @("-ApiKeyName", $ApiKeyName)
    }
    if (![string]::IsNullOrWhiteSpace($SecretDir)) {
        $scriptArgs += @("-SecretDir", (Resolve-RomaWindowsFullPath -Path $SecretDir))
    }

    return $scriptArgs
}

function Add-RomaWindowsAgentScriptLocalWhisperArgs {
    param(
        [object[]]$ArgumentList = @(),
        [Parameter(Mandatory = $true)]
        [string]$WhisperCLI,
        [Parameter(Mandatory = $true)]
        [string]$WhisperModel,
        [string]$WhisperOutputDir = "",
        [string[]]$WhisperArgument = @()
    )

    $scriptArgs = @($ArgumentList)
    $scriptArgs += @("-WhisperCLI", $WhisperCLI, "-WhisperModel", $WhisperModel)
    if (![string]::IsNullOrWhiteSpace($WhisperOutputDir)) {
        $scriptArgs += @("-WhisperOutputDir", (Resolve-RomaWindowsFullPath -Path $WhisperOutputDir))
    }

    $whisperArguments = @(
        $WhisperArgument |
            Where-Object { ![string]::IsNullOrWhiteSpace($_) }
    )
    if ($whisperArguments.Count -gt 0) {
        $scriptArgs += "-WhisperArgument"
        $scriptArgs += $whisperArguments
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

function Get-RomaWindowsEmptyFileProof {
    return [ordered]@{
        path = ""
        exists = $false
        bytes = 0
    }
}

function Get-RomaWindowsOptionalFileProof {
    param(
        [string]$Path = ""
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return Get-RomaWindowsEmptyFileProof
    }

    return Get-RomaWindowsFileProof -Path $Path
}

function Require-RomaWindowsFileProof {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    Require-RomaWindowsFile -Path $Path
    return Get-RomaWindowsFileProof -Path $Path
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

function Get-RomaWindowsAgentArtifactFileProofs {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AgentPath,
        [Parameter(Mandatory = $true)]
        [string]$ProofAgentPath,
        [Parameter(Mandatory = $true)]
        [string]$WhisperCLIMockPath,
        [Parameter(Mandatory = $true)]
        [string]$InstallDir
    )

    $proofs = [ordered]@{
        packaged_agent = (Get-RomaWindowsFileHashProof -Path $AgentPath)
        packaged_proof_agent = (Get-RomaWindowsFileHashProof -Path $ProofAgentPath)
        packaged_whisper_cli_mock = (Get-RomaWindowsFileHashProof -Path $WhisperCLIMockPath)
        installed_agent = (Get-RomaWindowsFileHashProof -Path (Join-RomaWindowsInstalledAgentPath -InstallDir $InstallDir))
        installed_proof_agent = (Get-RomaWindowsFileHashProof -Path (Join-RomaWindowsInstalledProofAgentPath -InstallDir $InstallDir))
    }
    Add-RomaWindowsProofFields `
        -Proof $proofs `
        -Fields (Get-RomaWindowsInstalledProofSurfaceFileProofs -InstallDir $InstallDir) |
        Out-Null

    return $proofs
}
