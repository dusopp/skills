# goal-loop install-copilot.ps1
# Makes the goal-loop skill available to GitHub Copilot (Copilot CLI + VS Code agent
# mode) by linking it into the user-level Copilot skills directory, which both read:
#   %USERPROFILE%\.copilot\skills\goal-loop  ->  <this plugin>\skills\goal-loop
#
# Run from the INSTALLED plugin's scripts directory. Prefers an NTFS junction (no admin
# rights needed, stays in sync with plugin updates); falls back to a plain copy.
#
#   .\install-copilot.ps1                     # install (junction or copy)
#   .\install-copilot.ps1 -Uninstall          # remove the link/copy
#   .\install-copilot.ps1 -TargetRoot <dir>   # dry-run against a different skills root

[CmdletBinding()]
param(
    [switch]$Uninstall,
    [string]$TargetRoot
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrEmpty($TargetRoot)) { $TargetRoot = Join-Path $env:USERPROFILE '.copilot\skills' }
$target = Join-Path $TargetRoot 'goal-loop'

# Deleting a junction with Remove-Item -Recurse in PS 5.1 can recurse INTO the target
# and delete the real files. Junctions must be deleted as links, never recursively.
# Detection is attribute-based via Get-Item (NOT Test-Path, which resolves through the
# reparse point and reports $false for a DANGLING junction, leaving it stuck forever).
# Returns $true if something was removed.
function Remove-TargetSafely {
    param([string]$Path)
    $item = $null
    try { $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop } catch { return $false }
    if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        [System.IO.Directory]::Delete($Path, $false)   # deletes the junction itself only
    } else {
        Remove-Item -LiteralPath $Path -Recurse -Force
    }
    return $true
}

if ($Uninstall) {
    if (Remove-TargetSafely -Path $target) {
        Write-Host ('Removed ' + $target)
    } else {
        Write-Host ('Nothing to remove: ' + $target + ' does not exist')
    }
    return
}

$source = Join-Path (Split-Path -Parent $PSScriptRoot) 'skills\goal-loop'
if (-not (Test-Path -LiteralPath (Join-Path $source 'SKILL.md'))) {
    throw ('Skill source not found: ' + $source)
}
$source = (Resolve-Path -LiteralPath $source).Path

if (-not (Test-Path -LiteralPath $TargetRoot)) { [void](New-Item -ItemType Directory -Force -Path $TargetRoot) }
[void](Remove-TargetSafely -Path $target)

$linked = $false
try {
    [void](New-Item -ItemType Junction -Path $target -Value $source)
    $linked = $true
} catch {
    Copy-Item -LiteralPath $source -Destination $target -Recurse -Force
}

if ($linked) {
    Write-Host ('Junction created: ' + $target + ' -> ' + $source)
    Write-Host 'Stays in sync with plugin updates automatically.'
} else {
    Write-Host ('Copied skill to ' + $target + ' (junction not available).')
    Write-Host 'Re-run this script after /plugin update to refresh the copy.'
}
Write-Host ''
Write-Host 'Copilot CLI and VS Code agent mode load user skills from this directory'
Write-Host 'automatically on next start. Uninstall: .\install-copilot.ps1 -Uninstall'
