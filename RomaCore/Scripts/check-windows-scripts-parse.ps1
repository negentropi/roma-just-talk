param(
    [string]$ScriptsDir = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if ([string]::IsNullOrWhiteSpace($ScriptsDir)) {
    $ScriptsDir = $PSScriptRoot
}

$resolvedScriptsDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ScriptsDir)
if (!(Test-Path -LiteralPath $resolvedScriptsDir)) {
    throw "Windows scripts directory was not found: $resolvedScriptsDir"
}

$scripts = Get-ChildItem -LiteralPath $resolvedScriptsDir -Filter "*.ps1" -File |
    Sort-Object FullName
if (!$scripts) {
    throw "No PowerShell scripts found in: $resolvedScriptsDir"
}

foreach ($script in $scripts) {
    $errors = $null
    [System.Management.Automation.PSParser]::Tokenize(
        (Get-Content -LiteralPath $script.FullName -Raw),
        [ref]$errors
    ) | Out-Null

    if ($null -ne $errors -and $errors.Count -gt 0) {
        $errors | Format-List | Out-String | Write-Host
        throw "PowerShell parse errors in $($script.FullName)"
    }

    Write-Host "parsed=$($script.FullName)"
}

Write-Host "windows_scripts_parse_ok=true"
Write-Host "windows_scripts_parse_count=$($scripts.Count)"
