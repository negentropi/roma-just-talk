param(
    [string]$DoctorOnlyReportPath = "",
    [string]$CloudDictationReportPath = "",
    [string]$LocalWhisperDictationReportPath = "",
    [string]$LocalWhisperNotepadPasteReportPath = "",
    [string]$LaptopPreflightReportPath = "",
    [string]$PackagedWhisperMockInstallReportPath = "",
    [switch]$RequireDoctorOnly,
    [switch]$RequireCloudDictation,
    [switch]$RequireLocalWhisperDictation,
    [switch]$RequireLocalWhisperNotepadPaste,
    [switch]$RequireLaptopPreflight,
    [switch]$RequirePackagedWhisperMockInstall,
    [switch]$RequireArtifactSmokeProof,
    [switch]$RequireFullLaptopProof
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$proofCommonScript = Join-Path $PSScriptRoot "windows-proof-common.ps1"
if (!(Test-Path -LiteralPath $proofCommonScript)) {
    throw "Windows proof common helper was not found: $proofCommonScript"
}
. $proofCommonScript

function Resolve-RequiredReportPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw "Missing proof report path for $Name"
    }

    $resolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    if (!(Test-Path -LiteralPath $resolvedPath)) {
        throw ("Proof report was not found for {0}: {1}" -f $Name, $resolvedPath)
    }

    return $resolvedPath
}

function Invoke-ProofReportProfileCheck {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$Profile,
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $resolvedPath = Resolve-RequiredReportPath -Path $Path -Name $Name
    Write-Host ""
    Write-Host "== proof_set_check=$Name profile=$Profile =="
    & $script:checkReportScript `
        -ProofReportPath $resolvedPath `
        -RequireProofProfile $Profile
    Write-Host "proof_set_requirement=$Name status=pass report=$resolvedPath"
}

function Get-ProofReportProfileChecks {
    $profiles = Get-RomaWindowsProofProfileSpecs
    return @(
        [pscustomobject]@{
            Name = "doctor_only"
            Profile = [string]$profiles["doctor_only"]["profile"]
            Path = $DoctorOnlyReportPath
            Required = [bool]$RequireDoctorOnly
            ReadAsLaptopPreflight = [bool]$profiles["doctor_only"]["read_as_laptop_preflight"]
        },
        [pscustomobject]@{
            Name = "cloud_dictation"
            Profile = [string]$profiles["cloud_dictation"]["profile"]
            Path = $CloudDictationReportPath
            Required = [bool]$RequireCloudDictation
            ReadAsLaptopPreflight = [bool]$profiles["cloud_dictation"]["read_as_laptop_preflight"]
        },
        [pscustomobject]@{
            Name = "local_whisper_dictation"
            Profile = [string]$profiles["local_whisper_dictation"]["profile"]
            Path = $LocalWhisperDictationReportPath
            Required = [bool]$RequireLocalWhisperDictation
            ReadAsLaptopPreflight = [bool]$profiles["local_whisper_dictation"]["read_as_laptop_preflight"]
        },
        [pscustomobject]@{
            Name = "local_whisper_notepad_paste"
            Profile = [string]$profiles["local_whisper_notepad_paste"]["profile"]
            Path = $LocalWhisperNotepadPasteReportPath
            Required = [bool]$RequireLocalWhisperNotepadPaste
            ReadAsLaptopPreflight = [bool]$profiles["local_whisper_notepad_paste"]["read_as_laptop_preflight"]
        },
        [pscustomobject]@{
            Name = "laptop_preflight"
            Profile = [string]$profiles["laptop_preflight"]["profile"]
            Path = $LaptopPreflightReportPath
            Required = [bool]$RequireLaptopPreflight
            ReadAsLaptopPreflight = [bool]$profiles["laptop_preflight"]["read_as_laptop_preflight"]
        },
        [pscustomobject]@{
            Name = "packaged_whisper_mock_install"
            Profile = [string]$profiles["packaged_whisper_mock_install"]["profile"]
            Path = $PackagedWhisperMockInstallReportPath
            Required = [bool]$RequirePackagedWhisperMockInstall
            ReadAsLaptopPreflight = [bool]$profiles["packaged_whisper_mock_install"]["read_as_laptop_preflight"]
        }
    )
}

function Test-AnyRequiredProofReportProfile {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Checks
    )

    foreach ($check in $Checks) {
        if ([bool]$check.Required) {
            return $true
        }
    }

    return $false
}

function Invoke-RequiredProofReportProfileChecks {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Checks
    )

    foreach ($check in $Checks) {
        if (!([bool]$check.Required)) {
            continue
        }

        Invoke-ProofReportProfileCheck `
            -Name ([string]$check.Name) `
            -Profile ([string]$check.Profile) `
            -Path ([string]$check.Path)

        if ([bool]$check.ReadAsLaptopPreflight) {
            $script:laptopPreflightReport = Read-ProofReport -Path ([string]$check.Path)
        }
    }
}

function Read-ProofReport {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $resolvedPath = Resolve-RequiredReportPath -Path $Path -Name "report"
    return Get-Content -LiteralPath $resolvedPath -Raw | ConvertFrom-Json -ErrorAction Stop
}

function Require-ReportProperty {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Report,
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$ReportName
    )

    if ($null -eq $Report -or !($Report.PSObject.Properties.Name -contains $Name)) {
        throw "Proof set report $ReportName is missing property: $Name"
    }

    return $Report.PSObject.Properties[$Name].Value
}

function Assert-SameReportValue {
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

function Assert-NonEmptyReportString {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Report,
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$ReportName
    )

    $value = [string](Require-ReportProperty -Report $Report -Name $Name -ReportName $ReportName)
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "Proof set report $ReportName has empty property: $Name"
    }

    Write-Host "proof_set_value=$ReportName.$Name value=$value"
    return $value
}

function Assert-ProofSessionId {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value,
        [Parameter(Mandatory = $true)]
        [string]$ReportName
    )

    if ($Value -notmatch "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$") {
        throw "Proof set report $ReportName has invalid proof_session_id; expected GUID, got: $Value"
    }
    if ($Value -eq "00000000-0000-0000-0000-000000000000") {
        throw "Proof set report $ReportName has placeholder proof_session_id"
    }

    return $Value.ToLowerInvariant()
}

function Get-ReportGeneratedAt {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Report,
        [Parameter(Mandatory = $true)]
        [string]$ReportName
    )

    $value = [string](Require-ReportProperty -Report $Report -Name "generated_at" -ReportName $ReportName)
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "Proof set report $ReportName has empty generated_at"
    }

    try {
        return [System.DateTimeOffset]::Parse(
            $value,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::AssumeUniversal
        ).ToUniversalTime()
    } catch {
        throw "Proof set report $ReportName has invalid generated_at timestamp: $value"
    }
}

function Assert-ReportsGeneratedWithinWindow {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Reports,
        [int]$WindowMinutes = 120,
        [string]$ProofName = "proof set"
    )

    if ($Reports.Count -lt 2) {
        throw "$ProofName needs at least two reports for generated_at window validation"
    }

    $timestamps = @()
    foreach ($entry in $Reports) {
        $name = [string]$entry.Name
        $report = $entry.Report
        $timestamps += [pscustomobject]@{
            Name = $name
            GeneratedAt = Get-ReportGeneratedAt -Report $report -ReportName $name
        }
    }

    $orderedTimestamps = @($timestamps | Sort-Object -Property GeneratedAt)
    $first = $orderedTimestamps[0]
    $last = $orderedTimestamps[$orderedTimestamps.Count - 1]
    $window = $last.GeneratedAt - $first.GeneratedAt
    $windowTotalMinutes = [System.Math]::Round($window.TotalMinutes, 3)
    if ($window.TotalMinutes -gt $WindowMinutes) {
        throw "$ProofName reports must be generated within $WindowMinutes minutes; got $windowTotalMinutes minutes between $($first.Name) and $($last.Name)"
    }

    Write-Host ("proof_set_generated_at_first={0} utc={1}" -f $first.Name, $first.GeneratedAt.ToString("o"))
    Write-Host ("proof_set_generated_at_last={0} utc={1}" -f $last.Name, $last.GeneratedAt.ToString("o"))
    Write-Host "proof_set_generated_at_window_minutes=$windowTotalMinutes"
}

function Assert-ReportBoolean {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Report,
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [bool]$Expected,
        [Parameter(Mandatory = $true)]
        [string]$ReportName
    )

    $actual = [bool](Require-ReportProperty -Report $Report -Name $Name -ReportName $ReportName)
    if ($actual -ne $Expected) {
        throw "Proof set report $ReportName expected $Name to be $Expected, got $actual"
    }

    Write-Host "proof_set_bool=$ReportName.$Name value=$actual"
}

function Assert-ReportFileProof {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Proof,
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [int64]$MinimumBytes = 1
    )

    $path = [string](Require-ReportProperty -Report $Proof -Name "path" -ReportName $Name)
    $exists = [bool](Require-ReportProperty -Report $Proof -Name "exists" -ReportName $Name)
    $bytes = [int64](Require-ReportProperty -Report $Proof -Name "bytes" -ReportName $Name)

    if ([string]::IsNullOrWhiteSpace($path)) {
        throw "Proof set file proof $Name has empty path"
    }
    if (!$exists) {
        throw "Proof set file proof $Name does not exist: $path"
    }
    if ($bytes -lt $MinimumBytes) {
        throw "Proof set file proof $Name has too few bytes: $path bytes=$bytes minimum=$MinimumBytes"
    }

    Write-Host "proof_set_file=$Name path=$path bytes=$bytes"
}

function Get-ReportPackageFingerprint {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Report,
        [Parameter(Mandatory = $true)]
        [string]$ReportName
    )

    $packageIdentity = Require-ReportProperty -Report $Report -Name "package_identity" -ReportName $ReportName
    $algorithm = [string](Require-ReportProperty -Report $packageIdentity -Name "algorithm" -ReportName $ReportName)
    if ($algorithm -ne "sha256") {
        throw "Proof set report $ReportName has unsupported package identity algorithm: $algorithm"
    }

    $fingerprint = [string](Require-ReportProperty -Report $packageIdentity -Name "fingerprint" -ReportName $ReportName)
    if ($fingerprint -notmatch "^[0-9a-fA-F]{64}$") {
        throw "Proof set report $ReportName has invalid package identity fingerprint: $fingerprint"
    }
    if ($fingerprint -match "^0{64}$") {
        throw "Proof set report $ReportName has placeholder package identity fingerprint"
    }

    return $fingerprint.ToLowerInvariant()
}

function Get-ReportSourceProvenance {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Report,
        [Parameter(Mandatory = $true)]
        [string]$ReportName
    )

    $manifest = Require-ReportProperty -Report $Report -Name "manifest" -ReportName $ReportName
    $repository = [string](Require-ReportProperty -Report $manifest -Name "source_repository" -ReportName $ReportName)
    $branch = [string](Require-ReportProperty -Report $manifest -Name "source_branch" -ReportName $ReportName)
    $commit = [string](Require-ReportProperty -Report $manifest -Name "source_commit" -ReportName $ReportName)
    $dirty = [string](Require-ReportProperty -Report $manifest -Name "source_dirty" -ReportName $ReportName)

    if ([string]::IsNullOrWhiteSpace($repository) -or $repository -eq "unknown") {
        throw "Proof set report $ReportName is missing source repository provenance"
    }
    if ([string]::IsNullOrWhiteSpace($branch)) {
        throw "Proof set report $ReportName is missing source branch provenance"
    }
    if ($commit -notmatch "^[0-9a-fA-F]{40}$") {
        throw "Proof set report $ReportName has invalid source commit provenance: $commit"
    }
    if ($dirty -ne "true" -and $dirty -ne "false") {
        throw "Proof set report $ReportName has invalid source dirty provenance: $dirty"
    }

    return [ordered]@{
        Repository = $repository
        Branch = $branch
        Commit = $commit
        Dirty = $dirty
    }
}

function Assert-SameArtifactSmokeProofSet {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DoctorOnlyReportPath,
        [Parameter(Mandatory = $true)]
        [string]$PackagedWhisperMockInstallReportPath
    )

    $reports = @(
        @{
            Name = "doctor_only"
            Report = (Read-ProofReport -Path $DoctorOnlyReportPath)
        },
        @{
            Name = "packaged_whisper_mock_install"
            Report = (Read-ProofReport -Path $PackagedWhisperMockInstallReportPath)
        }
    )

    $first = $reports[0]
    $firstName = [string]$first["Name"]
    $firstReport = $first["Report"]
    $firstOS = Require-ReportProperty -Report $firstReport -Name "os" -ReportName $firstName
    $expectedPlatform = [string](Require-ReportProperty -Report $firstOS -Name "platform" -ReportName $firstName)
    $expectedMachine = [string](Require-ReportProperty -Report $firstOS -Name "machine" -ReportName $firstName)
    $expectedUserName = [string](Require-ReportProperty -Report $firstOS -Name "user_name" -ReportName $firstName)
    $expectedUserDomain = [string](Require-ReportProperty -Report $firstOS -Name "user_domain" -ReportName $firstName)
    $expectedUserSid = [string](Require-ReportProperty -Report $firstOS -Name "user_sid" -ReportName $firstName)
    $expectedPackageDir = [string](Require-ReportProperty -Report $firstReport -Name "package_dir" -ReportName $firstName)
    $expectedPackageFingerprint = Get-ReportPackageFingerprint -Report $firstReport -ReportName $firstName
    $expectedSource = Get-ReportSourceProvenance -Report $firstReport -ReportName $firstName

    if ($expectedPlatform -ne "Win32NT") {
        throw "Artifact smoke proof must run on Windows, got platform $expectedPlatform"
    }
    if ([string]::IsNullOrWhiteSpace($expectedMachine)) {
        throw "Artifact smoke proof report is missing machine name"
    }
    if ([string]::IsNullOrWhiteSpace($expectedUserName)) {
        throw "Artifact smoke proof report is missing Windows user name"
    }
    if ([string]::IsNullOrWhiteSpace($expectedUserSid)) {
        throw "Artifact smoke proof report is missing Windows user SID"
    }
    if ([string]::IsNullOrWhiteSpace($expectedPackageDir)) {
        throw "Artifact smoke proof report is missing package_dir"
    }
    if ([string]::IsNullOrWhiteSpace($expectedPackageFingerprint)) {
        throw "Artifact smoke proof report is missing package identity fingerprint"
    }
    if ([string]$expectedSource['Dirty'] -ne "false") {
        throw "Artifact smoke proof requires a clean packaged source checkout, got source_dirty=$($expectedSource['Dirty'])"
    }

    foreach ($entry in $reports) {
        $reportName = $entry["Name"]
        $report = $entry["Report"]
        $reportOS = Require-ReportProperty -Report $report -Name "os" -ReportName $reportName
        Assert-SameReportValue `
            -Name "os.platform" `
            -Expected $expectedPlatform `
            -Actual ([string](Require-ReportProperty -Report $reportOS -Name "platform" -ReportName $reportName)) `
            -ReportName $reportName
        Assert-SameReportValue `
            -Name "os.machine" `
            -Expected $expectedMachine `
            -Actual ([string](Require-ReportProperty -Report $reportOS -Name "machine" -ReportName $reportName)) `
            -ReportName $reportName
        Assert-SameReportValue `
            -Name "os.user_name" `
            -Expected $expectedUserName `
            -Actual ([string](Require-ReportProperty -Report $reportOS -Name "user_name" -ReportName $reportName)) `
            -ReportName $reportName
        Assert-SameReportValue `
            -Name "os.user_domain" `
            -Expected $expectedUserDomain `
            -Actual ([string](Require-ReportProperty -Report $reportOS -Name "user_domain" -ReportName $reportName)) `
            -ReportName $reportName
        Assert-SameReportValue `
            -Name "os.user_sid" `
            -Expected $expectedUserSid `
            -Actual ([string](Require-ReportProperty -Report $reportOS -Name "user_sid" -ReportName $reportName)) `
            -ReportName $reportName
        Assert-SameReportValue `
            -Name "package_dir" `
            -Expected $expectedPackageDir `
            -Actual ([string](Require-ReportProperty -Report $report -Name "package_dir" -ReportName $reportName)) `
            -ReportName $reportName
        Assert-SameReportValue `
            -Name "package_identity.fingerprint" `
            -Expected $expectedPackageFingerprint `
            -Actual (Get-ReportPackageFingerprint -Report $report -ReportName $reportName) `
            -ReportName $reportName
        $source = Get-ReportSourceProvenance -Report $report -ReportName $reportName
        Assert-SameReportValue `
            -Name "manifest.source_repository" `
            -Expected ([string]$expectedSource['Repository']) `
            -Actual ([string]$source['Repository']) `
            -ReportName $reportName
        Assert-SameReportValue `
            -Name "manifest.source_branch" `
            -Expected ([string]$expectedSource['Branch']) `
            -Actual ([string]$source['Branch']) `
            -ReportName $reportName
        Assert-SameReportValue `
            -Name "manifest.source_commit" `
            -Expected ([string]$expectedSource['Commit']) `
            -Actual ([string]$source['Commit']) `
            -ReportName $reportName
        Assert-SameReportValue `
            -Name "manifest.source_dirty" `
            -Expected ([string]$expectedSource['Dirty']) `
            -Actual ([string]$source['Dirty']) `
            -ReportName $reportName
    }

    Write-Host "proof_set_artifact_smoke_machine=$expectedMachine"
    Write-Host "proof_set_artifact_smoke_user=$expectedUserName"
    Write-Host "proof_set_artifact_smoke_user_sid=$expectedUserSid"
    Write-Host "proof_set_artifact_smoke_package_dir=$expectedPackageDir"
    Write-Host "proof_set_artifact_smoke_package_fingerprint=$expectedPackageFingerprint"
    Write-Host "proof_set_artifact_smoke_source_repository=$($expectedSource['Repository'])"
    Write-Host "proof_set_artifact_smoke_source_branch=$($expectedSource['Branch'])"
    Write-Host "proof_set_artifact_smoke_source_commit=$($expectedSource['Commit'])"
    Write-Host "proof_set_artifact_smoke_source_dirty=$($expectedSource['Dirty'])"
}

function Assert-LaptopPreflightIncludesLocalWhisper {
    param(
        [Parameter(Mandatory = $true)]
        [object]$PreflightReport
    )

    $reportName = "laptop_preflight"
    $preflights = Require-ReportProperty -Report $PreflightReport -Name "preflights" -ReportName $reportName
    Assert-ReportBoolean -Report $preflights -Name "local_whisper" -Expected $true -ReportName $reportName
    Write-Host "proof_set_laptop_preflight_local_whisper_required=true"
}

function Assert-SameLaptopPreflightProof {
    param(
        [Parameter(Mandatory = $true)]
        [object]$PreflightReport,
        [Parameter(Mandatory = $true)]
        [string]$ExpectedProofSessionId,
        [Parameter(Mandatory = $true)]
        [string]$ExpectedPlatform,
        [Parameter(Mandatory = $true)]
        [string]$ExpectedMachine,
        [Parameter(Mandatory = $true)]
        [string]$ExpectedUserName,
        [Parameter(Mandatory = $true)]
        [string]$ExpectedUserDomain,
        [Parameter(Mandatory = $true)]
        [string]$ExpectedUserSid,
        [Parameter(Mandatory = $true)]
        [string]$ExpectedPackageDir,
        [Parameter(Mandatory = $true)]
        [string]$ExpectedPackageFingerprint,
        [Parameter(Mandatory = $true)]
        [object]$ExpectedSource
    )

    $reportName = "laptop_preflight"
    Assert-SameReportValue `
        -Name "proof_session_id" `
        -Expected $ExpectedProofSessionId `
        -Actual ([string](Require-ReportProperty -Report $PreflightReport -Name "proof_session_id" -ReportName $reportName)) `
        -ReportName $reportName
    $reportOS = Require-ReportProperty -Report $PreflightReport -Name "os" -ReportName $reportName
    Assert-SameReportValue `
        -Name "os.platform" `
        -Expected $ExpectedPlatform `
        -Actual ([string](Require-ReportProperty -Report $reportOS -Name "platform" -ReportName $reportName)) `
        -ReportName $reportName
    Assert-SameReportValue `
        -Name "os.machine" `
        -Expected $ExpectedMachine `
        -Actual ([string](Require-ReportProperty -Report $reportOS -Name "machine" -ReportName $reportName)) `
        -ReportName $reportName
    Assert-SameReportValue `
        -Name "os.user_name" `
        -Expected $ExpectedUserName `
        -Actual ([string](Require-ReportProperty -Report $reportOS -Name "user_name" -ReportName $reportName)) `
        -ReportName $reportName
    Assert-SameReportValue `
        -Name "os.user_domain" `
        -Expected $ExpectedUserDomain `
        -Actual ([string](Require-ReportProperty -Report $reportOS -Name "user_domain" -ReportName $reportName)) `
        -ReportName $reportName
    Assert-SameReportValue `
        -Name "os.user_sid" `
        -Expected $ExpectedUserSid `
        -Actual ([string](Require-ReportProperty -Report $reportOS -Name "user_sid" -ReportName $reportName)) `
        -ReportName $reportName
    Assert-SameReportValue `
        -Name "package_dir" `
        -Expected $ExpectedPackageDir `
        -Actual ([string](Require-ReportProperty -Report $PreflightReport -Name "package_dir" -ReportName $reportName)) `
        -ReportName $reportName
    Assert-SameReportValue `
        -Name "package_identity.fingerprint" `
        -Expected $ExpectedPackageFingerprint `
        -Actual (Get-ReportPackageFingerprint -Report $PreflightReport -ReportName $reportName) `
        -ReportName $reportName
    $source = Get-ReportSourceProvenance -Report $PreflightReport -ReportName $reportName
    Assert-SameReportValue `
        -Name "manifest.source_repository" `
        -Expected ([string]$ExpectedSource['Repository']) `
        -Actual ([string]$source['Repository']) `
        -ReportName $reportName
    Assert-SameReportValue `
        -Name "manifest.source_branch" `
        -Expected ([string]$ExpectedSource['Branch']) `
        -Actual ([string]$source['Branch']) `
        -ReportName $reportName
    Assert-SameReportValue `
        -Name "manifest.source_commit" `
        -Expected ([string]$ExpectedSource['Commit']) `
        -Actual ([string]$source['Commit']) `
        -ReportName $reportName
    Assert-SameReportValue `
        -Name "manifest.source_dirty" `
        -Expected ([string]$ExpectedSource['Dirty']) `
        -Actual ([string]$source['Dirty']) `
        -ReportName $reportName
    Write-Host "proof_set_laptop_preflight_matches_full=true"
}

function Assert-SameLaptopProofSet {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CloudReportPath,
        [Parameter(Mandatory = $true)]
        [string]$LocalWhisperReportPath,
        [Parameter(Mandatory = $true)]
        [string]$NotepadReportPath,
        [object]$LaptopPreflightReport = $null
    )

    $reports = @(
        @{
            Name = "cloud_dictation"
            Report = (Read-ProofReport -Path $CloudReportPath)
        },
        @{
            Name = "local_whisper_dictation"
            Report = (Read-ProofReport -Path $LocalWhisperReportPath)
        },
        @{
            Name = "local_whisper_notepad_paste"
            Report = (Read-ProofReport -Path $NotepadReportPath)
        }
    )

    $first = $reports[0]
    $firstName = [string]$first["Name"]
    $firstReport = $first["Report"]
    $expectedProofSessionId = Assert-ProofSessionId `
        -Value ([string](Require-ReportProperty -Report $firstReport -Name "proof_session_id" -ReportName $firstName)) `
        -ReportName $firstName
    $firstOS = Require-ReportProperty -Report $firstReport -Name "os" -ReportName $firstName
    $expectedPlatform = [string](Require-ReportProperty -Report $firstOS -Name "platform" -ReportName $firstName)
    $expectedMachine = [string](Require-ReportProperty -Report $firstOS -Name "machine" -ReportName $firstName)
    $expectedUserName = [string](Require-ReportProperty -Report $firstOS -Name "user_name" -ReportName $firstName)
    $expectedUserDomain = [string](Require-ReportProperty -Report $firstOS -Name "user_domain" -ReportName $firstName)
    $expectedUserSid = [string](Require-ReportProperty -Report $firstOS -Name "user_sid" -ReportName $firstName)
    $expectedPackageDir = [string](Require-ReportProperty -Report $firstReport -Name "package_dir" -ReportName $firstName)
    $expectedPackageFingerprint = Get-ReportPackageFingerprint -Report $firstReport -ReportName $firstName
    $expectedSource = Get-ReportSourceProvenance -Report $firstReport -ReportName $firstName

    if ($expectedPlatform -ne "Win32NT") {
        throw "Full laptop proof must run on Windows, got platform $expectedPlatform"
    }
    if ([string]::IsNullOrWhiteSpace($expectedProofSessionId)) {
        throw "Full laptop proof report is missing proof_session_id; use run-windows-laptop-proof.ps1 or pass one shared ProofSessionId"
    }
    if ([string]::IsNullOrWhiteSpace($expectedMachine)) {
        throw "Full laptop proof report is missing machine name"
    }
    if ([string]::IsNullOrWhiteSpace($expectedUserName)) {
        throw "Full laptop proof report is missing Windows user name"
    }
    if ([string]::IsNullOrWhiteSpace($expectedUserSid)) {
        throw "Full laptop proof report is missing Windows user SID"
    }
    if ([string]::IsNullOrWhiteSpace($expectedPackageDir)) {
        throw "Full laptop proof report is missing package_dir"
    }
    if ([string]::IsNullOrWhiteSpace($expectedPackageFingerprint)) {
        throw "Full laptop proof report is missing package identity fingerprint"
    }
    if ([string]$expectedSource['Dirty'] -ne "false") {
        throw "Full laptop proof requires a clean packaged source checkout, got source_dirty=$($expectedSource['Dirty'])"
    }

    if ($null -ne $LaptopPreflightReport) {
        Assert-SameLaptopPreflightProof `
            -PreflightReport $LaptopPreflightReport `
            -ExpectedProofSessionId $expectedProofSessionId `
            -ExpectedPlatform $expectedPlatform `
            -ExpectedMachine $expectedMachine `
            -ExpectedUserName $expectedUserName `
            -ExpectedUserDomain $expectedUserDomain `
            -ExpectedUserSid $expectedUserSid `
            -ExpectedPackageDir $expectedPackageDir `
            -ExpectedPackageFingerprint $expectedPackageFingerprint `
            -ExpectedSource $expectedSource
        Assert-LaptopPreflightIncludesLocalWhisper -PreflightReport $LaptopPreflightReport
    }

    $reportsWithTimestamps = @()
    if ($null -ne $LaptopPreflightReport) {
        $reportsWithTimestamps += [pscustomobject]@{
            Name = "laptop_preflight"
            Report = $LaptopPreflightReport
        }
    }
    foreach ($entry in $reports) {
        $reportsWithTimestamps += [pscustomobject]@{
            Name = [string]$entry["Name"]
            Report = $entry["Report"]
        }
    }
    Assert-ReportsGeneratedWithinWindow `
        -Reports $reportsWithTimestamps `
        -WindowMinutes 120 `
        -ProofName "Full laptop proof"

    foreach ($entry in $reports) {
        $reportName = $entry["Name"]
        $report = $entry["Report"]
        Assert-SameReportValue `
            -Name "proof_session_id" `
            -Expected $expectedProofSessionId `
            -Actual ([string](Require-ReportProperty -Report $report -Name "proof_session_id" -ReportName $reportName)) `
            -ReportName $reportName
        $reportOS = Require-ReportProperty -Report $report -Name "os" -ReportName $reportName
        Assert-SameReportValue `
            -Name "os.platform" `
            -Expected $expectedPlatform `
            -Actual ([string](Require-ReportProperty -Report $reportOS -Name "platform" -ReportName $reportName)) `
            -ReportName $reportName
        Assert-SameReportValue `
            -Name "os.machine" `
            -Expected $expectedMachine `
            -Actual ([string](Require-ReportProperty -Report $reportOS -Name "machine" -ReportName $reportName)) `
            -ReportName $reportName
        Assert-SameReportValue `
            -Name "os.user_name" `
            -Expected $expectedUserName `
            -Actual ([string](Require-ReportProperty -Report $reportOS -Name "user_name" -ReportName $reportName)) `
            -ReportName $reportName
        Assert-SameReportValue `
            -Name "os.user_domain" `
            -Expected $expectedUserDomain `
            -Actual ([string](Require-ReportProperty -Report $reportOS -Name "user_domain" -ReportName $reportName)) `
            -ReportName $reportName
        Assert-SameReportValue `
            -Name "os.user_sid" `
            -Expected $expectedUserSid `
            -Actual ([string](Require-ReportProperty -Report $reportOS -Name "user_sid" -ReportName $reportName)) `
            -ReportName $reportName
        Assert-SameReportValue `
            -Name "package_dir" `
            -Expected $expectedPackageDir `
            -Actual ([string](Require-ReportProperty -Report $report -Name "package_dir" -ReportName $reportName)) `
            -ReportName $reportName
        Assert-SameReportValue `
            -Name "package_identity.fingerprint" `
            -Expected $expectedPackageFingerprint `
            -Actual (Get-ReportPackageFingerprint -Report $report -ReportName $reportName) `
            -ReportName $reportName
        $source = Get-ReportSourceProvenance -Report $report -ReportName $reportName
        Assert-SameReportValue `
            -Name "manifest.source_repository" `
            -Expected ([string]$expectedSource['Repository']) `
            -Actual ([string]$source['Repository']) `
            -ReportName $reportName
        Assert-SameReportValue `
            -Name "manifest.source_branch" `
            -Expected ([string]$expectedSource['Branch']) `
            -Actual ([string]$source['Branch']) `
            -ReportName $reportName
        Assert-SameReportValue `
            -Name "manifest.source_commit" `
            -Expected ([string]$expectedSource['Commit']) `
            -Actual ([string]$source['Commit']) `
            -ReportName $reportName
        Assert-SameReportValue `
            -Name "manifest.source_dirty" `
            -Expected ([string]$expectedSource['Dirty']) `
            -Actual ([string]$source['Dirty']) `
            -ReportName $reportName
    }

    Write-Host "proof_set_session_id=$expectedProofSessionId"
    Write-Host "proof_set_machine=$expectedMachine"
    Write-Host "proof_set_user=$expectedUserName"
    Write-Host "proof_set_user_sid=$expectedUserSid"
    Write-Host "proof_set_package_dir=$expectedPackageDir"
    Write-Host "proof_set_package_fingerprint=$expectedPackageFingerprint"
    Write-Host "proof_set_source_repository=$($expectedSource['Repository'])"
    Write-Host "proof_set_source_branch=$($expectedSource['Branch'])"
    Write-Host "proof_set_source_commit=$($expectedSource['Commit'])"
    Write-Host "proof_set_source_dirty=$($expectedSource['Dirty'])"
}

$script:checkReportScript = Join-Path $PSScriptRoot "check-windows-proof-report.ps1"
if (!(Test-Path -LiteralPath $script:checkReportScript)) {
    throw "check-windows-proof-report.ps1 was not found next to this script: $script:checkReportScript"
}

if ($RequireArtifactSmokeProof) {
    $RequireDoctorOnly = $true
    $RequirePackagedWhisperMockInstall = $true
}

if ($RequireFullLaptopProof) {
    $RequireCloudDictation = $true
    $RequireLocalWhisperDictation = $true
    $RequireLocalWhisperNotepadPaste = $true
    $RequireLaptopPreflight = $true
}

$profileChecks = Get-ProofReportProfileChecks
$hasExplicitRequirement = Test-AnyRequiredProofReportProfile -Checks $profileChecks

if (!$hasExplicitRequirement) {
    $RequireDoctorOnly = ![string]::IsNullOrWhiteSpace($DoctorOnlyReportPath)
    $RequireCloudDictation = ![string]::IsNullOrWhiteSpace($CloudDictationReportPath)
    $RequireLocalWhisperDictation = ![string]::IsNullOrWhiteSpace($LocalWhisperDictationReportPath)
    $RequireLocalWhisperNotepadPaste = ![string]::IsNullOrWhiteSpace($LocalWhisperNotepadPasteReportPath)
    $RequireLaptopPreflight = ![string]::IsNullOrWhiteSpace($LaptopPreflightReportPath)
    $RequirePackagedWhisperMockInstall = ![string]::IsNullOrWhiteSpace($PackagedWhisperMockInstallReportPath)
    $profileChecks = Get-ProofReportProfileChecks
}

$hasRequirement = Test-AnyRequiredProofReportProfile -Checks $profileChecks

if (!$hasRequirement) {
    throw "Pass at least one proof report path or require a proof set"
}

Invoke-RequiredProofReportProfileChecks -Checks $profileChecks

if ($RequireFullLaptopProof) {
    Assert-SameLaptopProofSet `
        -CloudReportPath $CloudDictationReportPath `
        -LocalWhisperReportPath $LocalWhisperDictationReportPath `
        -NotepadReportPath $LocalWhisperNotepadPasteReportPath `
        -LaptopPreflightReport $script:laptopPreflightReport
    Write-Host "proof_set_ok=full-laptop"
} elseif ($RequireArtifactSmokeProof) {
    Assert-SameArtifactSmokeProofSet `
        -DoctorOnlyReportPath $DoctorOnlyReportPath `
        -PackagedWhisperMockInstallReportPath $PackagedWhisperMockInstallReportPath
    Write-Host "proof_set_ok=artifact-smoke"
} elseif ($RequireLaptopPreflight) {
    Write-Host "proof_set_ok=laptop-preflight"
} else {
    Write-Host "proof_set_ok=custom"
}
