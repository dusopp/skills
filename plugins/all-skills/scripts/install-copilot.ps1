# all-skills install-copilot.ps1
# One-shot GitHub Copilot wiring for EVERY plugin in the dusopp-skills marketplace:
# discovers each sibling plugin's scripts\install-copilot.ps1 and runs it (guardrails
# hook file, skill junctions, ...). Works from the repo clone AND from the installed
# plugin cache - both preserve the plugins\<name>\scripts layout under the marketplace
# root (the directory containing .claude-plugin\marketplace.json).
#
#   .\install-copilot.ps1               # run every plugin's Copilot installer
#   .\install-copilot.ps1 -Uninstall    # run every installer with -Uninstall
#   .\install-copilot.ps1 -ListOnly     # print what would run, run nothing

[CmdletBinding()]
param(
    [switch]$Uninstall,
    [switch]$ListOnly
)

$ErrorActionPreference = 'Stop'

# Walk up from this script to the marketplace root.
$root = $PSScriptRoot
while ($null -ne $root -and -not (Test-Path (Join-Path $root '.claude-plugin\marketplace.json'))) {
    $parent = Split-Path -Parent $root
    if ([string]::IsNullOrEmpty($parent) -or $parent -eq $root) { $root = $null } else { $root = $parent }
}
if ($null -eq $root) { throw 'Could not locate the marketplace root (.claude-plugin\marketplace.json) above this script.' }

$ownPluginDir = Split-Path -Parent $PSScriptRoot   # plugins\all-skills
$installers = @(Get-ChildItem -Path (Join-Path $root 'plugins') -Directory |
    Where-Object { $_.FullName -ne $ownPluginDir } |
    ForEach-Object { Join-Path $_.FullName 'scripts\install-copilot.ps1' } |
    Where-Object { Test-Path -LiteralPath $_ })

if ($installers.Count -eq 0) { throw ('No plugin Copilot installers found under ' + (Join-Path $root 'plugins')) }

Write-Host ('Marketplace root: ' + $root)
Write-Host ('Found ' + $installers.Count + ' plugin installer(s):')
foreach ($i in $installers) { Write-Host ('  ' + $i) }
if ($ListOnly) { return }

$failed = 0
foreach ($installer in $installers) {
    Write-Host ''
    Write-Host ('=== ' + (Split-Path -Parent (Split-Path -Parent $installer) | Split-Path -Leaf) + ' ===')
    try {
        if ($Uninstall) { & $installer -Uninstall } else { & $installer }
        if ($LASTEXITCODE -is [int] -and $LASTEXITCODE -ne 0) { $failed++ }
    } catch {
        $failed++
        Write-Host ('FAILED: ' + $_.Exception.Message) -ForegroundColor Red
    }
}

Write-Host ''
if ($failed -gt 0) {
    Write-Host ($failed.ToString() + ' installer(s) failed - see above.') -ForegroundColor Red
    exit 1
}
Write-Host 'All plugin Copilot installers completed.'
