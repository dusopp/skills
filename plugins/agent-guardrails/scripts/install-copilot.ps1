# agent-guardrails install-copilot.ps1
# Wires GitHub Copilot (VS Code agent mode + Copilot CLI) to the same guard.ps1 that the
# Claude Code plugin hook uses, and junctions the agent-guardrails skill (ops guide) into
# the user-level Copilot skills directory. Run from the INSTALLED plugin's scripts
# directory (paths are resolved from $PSScriptRoot and written as absolute paths).
#
#   .\install-copilot.ps1                          # hook file + skill junction
#   .\install-copilot.ps1 -Uninstall               # remove both
#   .\install-copilot.ps1 -OutPath x.json          # hook dry-run only: write hook JSON
#                                                  #   elsewhere, skip pwsh check and
#                                                  #   (unless -SkillsRoot given) the skill
#   .\install-copilot.ps1 -SkillsRoot <dir>        # override %USERPROFILE%\.copilot\skills
#
# IMPORTANT: Copilot CLI preToolUse hooks FAIL CLOSED - any hook error (missing pwsh,
# bad path) denies EVERY tool call. That is why this script refuses to wire the hook
# without PowerShell 7+ present. The guard itself always fails open (exit 0) internally.

[CmdletBinding()]
param(
    [switch]$Uninstall,
    [string]$OutPath,
    [string]$SkillsRoot
)

$ErrorActionPreference = 'Stop'

$hookDir  = Join-Path $env:USERPROFILE '.copilot\hooks'
$hookFile = Join-Path $hookDir 'agent-guardrails.json'
if (-not [string]::IsNullOrEmpty($OutPath)) { $hookFile = $OutPath }

$skillsRootGiven = -not [string]::IsNullOrEmpty($SkillsRoot)
if (-not $skillsRootGiven) { $SkillsRoot = Join-Path $env:USERPROFILE '.copilot\skills' }
$skillTarget = Join-Path $SkillsRoot 'agent-guardrails'
$pluginRoot  = Split-Path -Parent $PSScriptRoot
$skillSource = Join-Path $pluginRoot 'skills\agent-guardrails'
# With -OutPath (hook dry-run) the skill step only runs when -SkillsRoot is explicit,
# so a pure hook dry-run never touches the real ~/.copilot/skills.
$doSkill = ([string]::IsNullOrEmpty($OutPath)) -or $skillsRootGiven

# Deleting a junction with Remove-Item -Recurse in PS 5.1 can recurse INTO the target
# and delete the real files. Junctions must be deleted as links, never recursively.
function Remove-TargetSafely {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $item = Get-Item -LiteralPath $Path -Force
    if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        [System.IO.Directory]::Delete($Path, $false)   # deletes the junction itself only
    } else {
        Remove-Item -LiteralPath $Path -Recurse -Force
    }
}

if ($Uninstall) {
    if (Test-Path -LiteralPath $hookFile) {
        Remove-Item -LiteralPath $hookFile -Force
        Write-Host ('Removed ' + $hookFile)
    } else {
        Write-Host ('Nothing to remove: ' + $hookFile + ' does not exist')
    }
    if ($doSkill) {
        if (Test-Path -LiteralPath $skillTarget) {
            Remove-TargetSafely -Path $skillTarget
            Write-Host ('Removed ' + $skillTarget)
        } else {
            Write-Host ('Nothing to remove: ' + $skillTarget + ' does not exist')
        }
    }
    return
}

# --- 1. Skill junction (no pwsh required) ---------------------------------
if ($doSkill) {
    if (-not (Test-Path -LiteralPath (Join-Path $skillSource 'SKILL.md'))) {
        throw ('Skill source not found: ' + $skillSource)
    }
    $skillSource = (Resolve-Path -LiteralPath $skillSource).Path
    if (-not (Test-Path -LiteralPath $SkillsRoot)) { [void](New-Item -ItemType Directory -Force -Path $SkillsRoot) }
    Remove-TargetSafely -Path $skillTarget
    $linked = $false
    try {
        [void](New-Item -ItemType Junction -Path $skillTarget -Value $skillSource)
        $linked = $true
    } catch {
        Copy-Item -LiteralPath $skillSource -Destination $skillTarget -Recurse -Force
    }
    if ($linked) {
        Write-Host ('Skill junction created: ' + $skillTarget + ' -> ' + $skillSource)
    } else {
        Write-Host ('Skill copied to ' + $skillTarget + ' (junction not available; re-run after /plugin update).')
    }
}

# --- 2. Hook wiring (needs pwsh 7+; fail-closed host) ---------------------
$guardPath = Join-Path $PSScriptRoot 'guard.ps1'
if (-not (Test-Path -LiteralPath $guardPath)) { throw ('guard.ps1 not found next to this script: ' + $guardPath) }
$guardPath = (Resolve-Path -LiteralPath $guardPath).Path

if ([string]::IsNullOrEmpty($OutPath)) {
    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($null -eq $pwsh) {
        Write-Host 'ABORT (hook wiring): PowerShell 7+ (pwsh) is not installed.' -ForegroundColor Red
        Write-Host 'Copilot CLI hooks on Windows require PowerShell 7+, and a broken hook DENIES every tool call (fail-closed).'
        Write-Host 'Install it first (winget install Microsoft.PowerShell), then re-run this script.'
        exit 1
    }
    Write-Host ('pwsh found: ' + $pwsh.Source)
}

# Build the hook JSON via a template: full control over escaping, no ConvertTo-Json
# array-flattening quirks. The "powershell" value is a PowerShell command line; the
# host pipes the hook JSON to its stdin, which guard.ps1 reads.
# (.NET replacement strings treat backslash literally: '\\' below inserts exactly two.)
$psPath   = $guardPath -replace "'", "''"             # PS single-quote escaping (paranoia)
$psCommand = "& '" + $psPath + "'"
$psCommandJson = $psCommand -replace '\\', '\\'
$hookJson = @"
{
  "version": 1,
  "hooks": {
    "preToolUse": [
      {
        "type": "command",
        "powershell": "$psCommandJson",
        "timeoutSec": 10
      }
    ]
  }
}
"@

$targetDir = Split-Path -Parent $hookFile
if (-not (Test-Path -LiteralPath $targetDir)) { [void](New-Item -ItemType Directory -Force -Path $targetDir) }
[System.IO.File]::WriteAllText($hookFile, $hookJson, (New-Object System.Text.UTF8Encoding($false)))
Write-Host ('Wrote ' + $hookFile)
Write-Host ('Guard: ' + $guardPath)

# No "matcher" on purpose: it must fire for MCP tools too, and the guard exits fast
# (allow) for tools that carry no command strings.

Write-Host ''
Write-Host '--- Next steps -------------------------------------------------------'
Write-Host '1. Copilot CLI picks the hook up on next start (hooks load from ~/.copilot/hooks/*.json).'
Write-Host '2. VS Code Copilot agent mode: hooks are Preview. In VS Code settings enable:'
Write-Host '     "chat.hooks.enabled": true'
Write-Host '   (VS Code reads the same ~/.copilot/hooks directory.)'
Write-Host '3. OPTIONAL advisory belt for VS Code (auto-approve denial = manual approval'
Write-Host '   prompt, not a hard block). Merge into %APPDATA%\Code\User\settings.json:'
Write-Host ''
Write-Host '   "chat.tools.terminal.autoApprove": {'
Write-Host '     "az group delete": false,'
Write-Host '     "az resource delete": false,'
Write-Host '     "az keyvault purge": false,'
Write-Host '     "azd down": false,'
Write-Host '     "Remove-AzResourceGroup": false,'
Write-Host '     "dotnet nuget push": false,'
Write-Host '     "/git\\s+push\\b.*\\s(--force|-f)(?!\\S)/i": { "approve": false, "matchCommandLine": true }'
Write-Host '   }'
Write-Host ''
Write-Host '4. VERIFY the wiring (from a NON-git temp directory):'
Write-Host '     copilot -p "Run exactly: git push --force. Report the result in one line."'
Write-Host '   Blocked = guard works. "not a git repository" = hook not firing (but harmless).'
Write-Host '5. Visual Studio IDE Copilot has NO hook support - it stays on manual approvals.'
Write-Host '----------------------------------------------------------------------'
