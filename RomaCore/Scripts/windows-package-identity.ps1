$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$proofCommonScript = Join-Path $PSScriptRoot "windows-proof-common.ps1"
if (!(Test-Path -LiteralPath $proofCommonScript)) {
    throw "Windows proof common helper was not found: $proofCommonScript"
}
. $proofCommonScript

function Get-RomaPackageIdentityHash {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Entries
    )

    $inputText = [string]::Join("`n", $Entries)
    $inputBytes = [System.Text.Encoding]::UTF8.GetBytes($inputText)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hashBytes = $sha256.ComputeHash($inputBytes)
    } finally {
        $sha256.Dispose()
    }

    return [System.BitConverter]::ToString($hashBytes).Replace("-", "").ToLowerInvariant()
}

function Get-RomaPackageIdentityProof {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackageDir
    )

    $relativePaths = @(
        "RomaWindowsAgent.exe",
        "RomaProofAgent.exe",
        "RomaWhisperCLIMock.exe"
    )
    $relativePaths += Get-RomaWindowsProofSurfaceFiles
    $relativePaths += "manifest.txt"

    $dlls = @(
        Get-ChildItem -LiteralPath $PackageDir -Filter "*.dll" |
            Sort-Object Name
    )
    foreach ($dll in $dlls) {
        $relativePaths += $dll.Name
    }

    $files = [ordered]@{}
    $entries = @()
    foreach ($relativePath in $relativePaths) {
        $path = Join-Path $PackageDir $relativePath
        $proof = Get-RomaWindowsFileHashProof -Path $path
        $files[$relativePath] = $proof
        if (!$proof["exists"] -or [string]::IsNullOrWhiteSpace([string]$proof["sha256"])) {
            throw "Package identity file was not hashable: $path"
        }

        $entries += ("{0}|{1}|{2}" -f $relativePath, $proof["bytes"], $proof["sha256"])
    }

    return [ordered]@{
        algorithm = "sha256"
        fingerprint = (Get-RomaPackageIdentityHash -Entries $entries)
        entry_count = $entries.Count
        entries = $entries
        files = $files
    }
}
