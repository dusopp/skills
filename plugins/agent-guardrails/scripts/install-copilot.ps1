# agent-guardrails install-copilot.ps1
# Wires GitHub Copilot (VS Code agent mode + Copilot CLI) to the same guard.ps1 that the
# Claude Code plugin hook uses. Run this from the INSTALLED plugin's scripts directory
# (paths are resolved from $PSScriptRoot and written as absolute paths).
#
#   .\install-copilot.ps1                 # write %USERPROFILE%\.copilot\hooks\agent-guardrails.json
#   .\install-copilot.ps1 -Uninstall      # remove the hook file
#   .\install-copilot.ps1 -OutPath x.json # dry run: write the hook JSON elsewhere, skip prereq checks
#
# IMPORTANT: Copilot CLI preToolUse hooks FAIL CLOSED - any hook error (missing pwsh,
# bad path) denies EVERY tool call. That is why this script refuses to install without
# PowerShell 7+ (pwsh) present. The guard itself always fails open (exit 0) internally.

[CmdletBinding()]
param(
    [switch]$Uninstall,
    [string]$OutPath
)

$ErrorActionPreference = 'Stop'

$hookDir  = Join-Path $env:USERPROFILE '.copilot\hooks'
$hookFile = Join-Path $hookDir 'agent-guardrails.json'
if (-not [string]::IsNullOrEmpty($OutPath)) { $hookFile = $OutPath }

if ($Uninstall) {
    if (Test-Path -LiteralPath $hookFile) {
        Remove-Item -LiteralPath $hookFile -Force
        Write-Host ('Removed ' + $hookFile)
    } else {
        Write-Host ('Nothing to remove: ' + $hookFile + ' does not exist')
    }
    return
}

$guardPath = Join-Path $PSScriptRoot 'guard.ps1'
if (-not (Test-Path -LiteralPath $guardPath)) { throw ('guard.ps1 not found next to this script: ' + $guardPath) }
$guardPath = (Resolve-Path -LiteralPath $guardPath).Path

if ([string]::IsNullOrEmpty($OutPath)) {
    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($null -eq $pwsh) {
        Write-Host 'ABORT: PowerShell 7+ (pwsh) is not installed.' -ForegroundColor Red
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
