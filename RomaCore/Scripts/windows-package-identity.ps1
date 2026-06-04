$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Get-RomaPackageIdentityFileProof {
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

function Get-RomaPackageIdentityFileHashProof {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $proof = Get-RomaPackageIdentityFileProof -Path $Path
    $proof["sha256"] = ""
    if ($proof["exists"]) {
        $proof["sha256"] = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    }

    return $proof
}

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
        "RomaWhisperCLIMock.exe",
        "smoke-windows-agent.ps1",
        "run-windows-agent.ps1",
        "install-windows-agent.ps1",
        "prove-windows-agent-artifact.ps1",
        "run-windows-laptop-proof.ps1",
        "WINDOWS-LAPTOP-PROOF.txt",
        "check-windows-proof-report.ps1",
        "check-windows-proof-set.ps1",
        "windows-manifest.ps1",
        "windows-package-identity.ps1",
        "manifest.txt"
    )

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
        $proof = Get-RomaPackageIdentityFileHashProof -Path $path
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
