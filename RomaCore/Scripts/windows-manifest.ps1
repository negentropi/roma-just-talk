$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Read-RomaWindowsManifest {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (!(Test-Path -LiteralPath $Path)) {
        throw "Manifest was not found: $Path"
    }

    $manifest = @{}
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ([string]::IsNullOrWhiteSpace($line) -or !$line.Contains("=")) {
            continue
        }

        $separator = $line.IndexOf("=")
        $key = $line.Substring(0, $separator)
        $value = $line.Substring($separator + 1)
        $manifest[$key] = $value
    }

    return $manifest
}

function Require-RomaWindowsManifestKey {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Manifest,
        [Parameter(Mandatory = $true)]
        [string]$Key
    )

    if (!$Manifest.ContainsKey($Key) -or [string]::IsNullOrWhiteSpace($Manifest[$Key])) {
        throw "Manifest key was not found: $Key"
    }

    Write-Host "manifest_$Key=$($Manifest[$Key])"
    return [string]$Manifest[$Key]
}

function Resolve-RomaWindowsManifestPath {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Manifest,
        [Parameter(Mandatory = $true)]
        [string]$Key,
        [string]$BaseDir = ""
    )

    $path = Require-RomaWindowsManifestKey -Manifest $Manifest -Key $Key
    if ([System.IO.Path]::IsPathRooted($path)) {
        $fullPath = [System.IO.Path]::GetFullPath($path)
        if ((Test-Path -LiteralPath $fullPath) -or [string]::IsNullOrWhiteSpace($BaseDir)) {
            return $fullPath
        }

        $relocatedPath = Join-Path $BaseDir (Split-Path -Leaf $fullPath)
        if (Test-Path -LiteralPath $relocatedPath) {
            return [System.IO.Path]::GetFullPath($relocatedPath)
        }

        return $fullPath
    }
    if ([string]::IsNullOrWhiteSpace($BaseDir)) {
        return $path
    }

    return [System.IO.Path]::GetFullPath((Join-Path $BaseDir $path))
}

function Require-RomaWindowsManifestFile {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Manifest,
        [Parameter(Mandatory = $true)]
        [string]$Key,
        [string]$BaseDir = ""
    )

    $path = Resolve-RomaWindowsManifestPath -Manifest $Manifest -Key $Key -BaseDir $BaseDir
    if (!(Test-Path -LiteralPath $path)) {
        throw "Manifest file key $Key did not point at an existing file: $path"
    }

    Write-Host ("manifest_{0}_exists=true" -f $Key)
    return $path
}
