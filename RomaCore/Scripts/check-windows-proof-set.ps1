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

function New-ProofReportProfilePathMap {
    return @{
        doctor_only = $DoctorOnlyReportPath
        cloud_dictation = $CloudDictationReportPath
        local_whisper_dictation = $LocalWhisperDictationReportPath
        local_whisper_notepad_paste = $LocalWhisperNotepadPasteReportPath
        laptop_preflight = $LaptopPreflightReportPath
        packaged_whisper_mock_install = $PackagedWhisperMockInstallReportPath
    }
}

function New-ProofReportProfileRequiredMap {
    param(
        [hashtable]$Paths = @{},
        [bool]$IncludePathRequirements = $false
    )

    $required = @{
        doctor_only = [bool]$RequireDoctorOnly
        cloud_dictation = [bool]$RequireCloudDictation
        local_whisper_dictation = [bool]$RequireLocalWhisperDictation
        local_whisper_notepad_paste = [bool]$RequireLocalWhisperNotepadPaste
        laptop_preflight = [bool]$RequireLaptopPreflight
        packaged_whisper_mock_install = [bool]$RequirePackagedWhisperMockInstall
    }
    if ($IncludePathRequirements) {
        Add-RomaWindowsProofReportPathRequiredProfiles -Required $required -Paths $Paths | Out-Null
    }
    if ($RequireArtifactSmokeProof) {
        Add-RomaWindowsProofSetRequiredProfiles -Required $required -Name "artifact_smoke" | Out-Null
    }
    if ($RequireFullLaptopProof) {
        Add-RomaWindowsProofSetRequiredProfiles -Required $required -Name "full_laptop" | Out-Null
    }
    return $required
}

function Get-ProofReportProfileChecks {
    param(
        [bool]$IncludePathRequirements = $false
    )

    $paths = New-ProofReportProfilePathMap
    return Get-RomaWindowsProofReportProfileChecks `
        -Paths $paths `
        -Required (New-ProofReportProfileRequiredMap -Paths $paths -IncludePathRequirements $IncludePathRequirements)
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
        [string]$Path,
        [string]$Name = "report"
    )

    $resolvedPath = Resolve-RequiredReportPath -Path $Path -Name $Name
    return Get-Content -LiteralPath $resolvedPath -Raw | ConvertFrom-Json -ErrorAction Stop
}

function Get-ProofSetReportEntries {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [hashtable]$Paths,
        [string[]]$ExcludedProfileNames = @()
    )

    $reports = @()
    foreach ($profileName in (Get-RomaWindowsProofSetProfileNames -Name $Name)) {
        if ($ExcludedProfileNames -contains $profileName) {
            continue
        }
        if (!$Paths.ContainsKey($profileName)) {
            throw "Proof set $Name path map is missing profile: $profileName"
        }

        $reports += @{
            Name = $profileName
            Report = (Read-ProofReport -Path ([string]$Paths[$profileName]) -Name $profileName)
        }
    }

    return $reports
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

    return Require-RomaWindowsObjectProperty `
        -Object $Report `
        -Name $Name `
        -Context "Proof set report $ReportName"
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

    Assert-RomaWindowsSameProofReportValue `
        -Name $Name `
        -Expected $Expected `
        -Actual $Actual `
        -ReportName $ReportName
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

function Get-ReportGeneratedAt {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Report,
        [Parameter(Mandatory = $true)]
        [string]$ReportName
    )

    $value = [string](Require-ReportProperty -Report $Report -Name "generated_at" -ReportName $ReportName)
    return ConvertTo-RomaWindowsProofTimestamp `
        -Value $value `
        -Name "generated_at" `
        -ReportName $ReportName
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

function Assert-SameArtifactSmokeProofSet {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DoctorOnlyReportPath,
        [Parameter(Mandatory = $true)]
        [string]$PackagedWhisperMockInstallReportPath
    )

    $reports = Get-ProofSetReportEntries `
        -Name "artifact_smoke" `
        -Paths @{
            doctor_only = $DoctorOnlyReportPath
            packaged_whisper_mock_install = $PackagedWhisperMockInstallReportPath
        }

    $first = $reports[0]
    $firstName = [string]$first["Name"]
    $firstReport = $first["Report"]
    $expectedIdentity = Get-RomaWindowsProofReportIdentity -Report $firstReport -ReportName $firstName
    Assert-RomaWindowsProofReportIdentityComplete `
        -Identity $expectedIdentity `
        -ProofName "Artifact smoke proof" `
        -RequireWindows `
        -RequireCleanSource

    foreach ($entry in $reports) {
        $reportName = $entry["Name"]
        $report = $entry["Report"]
        $identity = Get-RomaWindowsProofReportIdentity -Report $report -ReportName $reportName
        Assert-RomaWindowsProofReportIdentityMatches `
            -ExpectedIdentity $expectedIdentity `
            -ActualIdentity $identity `
            -ReportName $reportName
    }

    Write-RomaWindowsProofReportIdentityMarkers `
        -Identity $expectedIdentity `
        -Prefix "proof_set_artifact_smoke"
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
        [object]$ExpectedIdentity
    )

    $reportName = "laptop_preflight"
    Assert-SameReportValue `
        -Name "proof_session_id" `
        -Expected $ExpectedProofSessionId `
        -Actual ([string](Require-ReportProperty -Report $PreflightReport -Name "proof_session_id" -ReportName $reportName)) `
        -ReportName $reportName

    $identity = Get-RomaWindowsProofReportIdentity -Report $PreflightReport -ReportName $reportName
    Assert-RomaWindowsProofReportIdentityMatches `
        -ExpectedIdentity $ExpectedIdentity `
        -ActualIdentity $identity `
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

    $reports = Get-ProofSetReportEntries `
        -Name "full_laptop" `
        -Paths @{
            cloud_dictation = $CloudReportPath
            local_whisper_dictation = $LocalWhisperReportPath
            local_whisper_notepad_paste = $NotepadReportPath
        } `
        -ExcludedProfileNames @("laptop_preflight")

    $first = $reports[0]
    $firstName = [string]$first["Name"]
    $firstReport = $first["Report"]
    $expectedProofSessionId = Assert-RomaWindowsProofSessionId `
        -Value ([string](Require-ReportProperty -Report $firstReport -Name "proof_session_id" -ReportName $firstName)) `
        -Name "proof_session_id" `
        -ReportName $firstName
    $expectedIdentity = Get-RomaWindowsProofReportIdentity -Report $firstReport -ReportName $firstName
    Assert-RomaWindowsProofReportIdentityComplete `
        -Identity $expectedIdentity `
        -ProofName "Full laptop proof" `
        -RequireWindows `
        -RequireCleanSource

    if ($null -ne $LaptopPreflightReport) {
        Assert-SameLaptopPreflightProof `
            -PreflightReport $LaptopPreflightReport `
            -ExpectedProofSessionId $expectedProofSessionId `
            -ExpectedIdentity $expectedIdentity
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

        $identity = Get-RomaWindowsProofReportIdentity -Report $report -ReportName $reportName
        Assert-RomaWindowsProofReportIdentityMatches `
            -ExpectedIdentity $expectedIdentity `
            -ActualIdentity $identity `
            -ReportName $reportName
    }

    Write-Host "proof_set_session_id=$expectedProofSessionId"
    Write-RomaWindowsProofReportIdentityMarkers `
        -Identity $expectedIdentity `
        -Prefix "proof_set"
}

$script:checkReportScript = Join-Path $PSScriptRoot "check-windows-proof-report.ps1"
if (!(Test-Path -LiteralPath $script:checkReportScript)) {
    throw "check-windows-proof-report.ps1 was not found next to this script: $script:checkReportScript"
}

$profileChecks = Get-ProofReportProfileChecks
$hasExplicitRequirement = Test-AnyRequiredProofReportProfile -Checks $profileChecks

if (!$hasExplicitRequirement) {
    $profileChecks = Get-ProofReportProfileChecks -IncludePathRequirements $true
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
    Write-Host (Get-RomaWindowsProofSetOkMarker -Name "full_laptop")
} elseif ($RequireArtifactSmokeProof) {
    Assert-SameArtifactSmokeProofSet `
        -DoctorOnlyReportPath $DoctorOnlyReportPath `
        -PackagedWhisperMockInstallReportPath $PackagedWhisperMockInstallReportPath
    Write-Host (Get-RomaWindowsProofSetOkMarker -Name "artifact_smoke")
} elseif ($RequireLaptopPreflight) {
    Write-Host (Get-RomaWindowsProofSetOkMarker -Name "laptop_preflight")
} else {
    Write-Host (Get-RomaWindowsProofSetOkMarker -Name "custom")
}
