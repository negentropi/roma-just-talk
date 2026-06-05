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

        $leaf = Split-Path -Leaf $fullPath
        $parentPath = Split-Path -Parent $fullPath
        $parentLeaf = ""
        if (![string]::IsNullOrWhiteSpace($parentPath)) {
            $parentLeaf = Split-Path -Leaf $parentPath
        }

        if (![string]::IsNullOrWhiteSpace($parentLeaf)) {
            $relocatedSubdirPath = Join-Path (Join-Path $BaseDir $parentLeaf) $leaf
            if (Test-Path -LiteralPath $relocatedSubdirPath) {
                return [System.IO.Path]::GetFullPath($relocatedSubdirPath)
            }
        }

        $relocatedPath = Join-Path $BaseDir $leaf
        if (Test-Path -LiteralPath $relocatedPath) {
            return [System.IO.Path]::GetFullPath($relocatedPath)
        }

        $candidateFiles = @()
        try {
            $candidateFiles = @(Get-ChildItem -LiteralPath $BaseDir -Filter $leaf -Recurse -File -ErrorAction Stop)
        } catch {
            $candidateFiles = @()
        }

        if (![string]::IsNullOrWhiteSpace($parentLeaf)) {
            $parentMatchedCandidates = @(
                $candidateFiles | Where-Object {
                    (Split-Path -Leaf $_.DirectoryName) -eq $parentLeaf
                }
            )
            if ($parentMatchedCandidates.Count -eq 1) {
                return [System.IO.Path]::GetFullPath($parentMatchedCandidates[0].FullName)
            }
        }

        if ($candidateFiles.Count -eq 1) {
            return [System.IO.Path]::GetFullPath($candidateFiles[0].FullName)
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

function Invoke-RomaWindowsManifestNestedRelocationSmoke {
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
