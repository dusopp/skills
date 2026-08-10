# agent-guardrails guard.ps1
# PreToolUse command guard shared by Claude Code, VS Code Copilot agent mode, and Copilot CLI.
# Contract: hook JSON arrives on stdin. Exit 2 + stderr message = block the tool call. Exit 0 = allow.
# Fail-open on internal errors: this script must never break tool calls by accident.
# Compatible with Windows PowerShell 5.1 and PowerShell 7+. ASCII only. No module imports.
#
# Input dialects handled:
#   Claude Code / VS Code Copilot:  { "tool_name": "Bash",  "tool_input": { "command": "..." } }
#   Copilot CLI:                    { "toolName":  "bash",  "toolArgs":   { "command": "..." } }
#
# Pattern sources (later files add to, and can never disable, earlier ones):
#   <this dir>\dangerous-patterns.txt          shipped deny list (sections [shell] / [mcp-tool] / [mcp-command])
#   %USERPROFILE%\.claude\guardrails-local.txt optional machine-local additions (survives plugin updates);
#                                              path overridable via AGENT_GUARDRAILS_LOCAL (used by tests)

# --- read stdin (dual path; order matters, do not "simplify" - see SKILL.md gotchas) ---
$raw = @($input) -join "`n"
if ($raw.Length -eq 0) {
    if (-not [Console]::IsInputRedirected) { exit 0 }
    try {
        $reader = New-Object System.IO.StreamReader([Console]::OpenStandardInput(), (New-Object System.Text.UTF8Encoding($false)))
        $raw = $reader.ReadToEnd()
    } catch { exit 0 }
}
$raw = $raw.Trim([char[]]@([char]0xFEFF, [char]32, [char]9, [char]13, [char]10))
# A UTF-8 BOM decoded through the OEM console codepage (the $input path) arrives as
# the three-char mojibake 0x2229 0x2557 0x2510; strip it so JSON parsing still works.
if ($raw.Length -ge 3 -and [int]$raw[0] -eq 8745 -and [int]$raw[1] -eq 9559 -and [int]$raw[2] -eq 9488) {
    $raw = $raw.Substring(3).TrimStart([char[]]@([char]32, [char]9))
}
if ($raw.Length -eq 0) { exit 0 }

function Test-GuardPattern {
    param([string]$Text, [string]$Pattern)
    try {
        $opts = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor `
                [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
        return [System.Text.RegularExpressions.Regex]::IsMatch($Text, $Pattern, $opts, [timespan]::FromMilliseconds(250))
    } catch {
        # Invalid pattern or regex timeout: skip this pattern only, never disable the guard.
        return $false
    }
}

function Read-PatternFile {
    param([string]$Path, [string]$Label, [System.Collections.ArrayList]$Into)
    if ([string]::IsNullOrEmpty($Path)) { return }
    try {
        if (-not [System.IO.File]::Exists($Path)) { return }
        $section = 'shell'
        foreach ($line in [System.IO.File]::ReadAllLines($Path, [System.Text.Encoding]::UTF8)) {
            $t = $line.Trim([char[]]@([char]0xFEFF, [char]32, [char]9))
            if ($t.Length -eq 0 -or $t.StartsWith('#')) { continue }
            if ($t -eq '[shell]' -or $t -eq '[mcp-tool]' -or $t -eq '[mcp-command]') {
                $section = $t.Substring(1, $t.Length - 2)
                continue
            }
            [void]$Into.Add((New-Object PSObject -Property @{ Pattern = $t; Section = $section; Source = $Label }))
        }
    } catch { }
}

function Deny {
    param([string]$ToolName, $Rule)
    $lines = @(
        'BLOCKED by agent-guardrails (PreToolUse deny list).',
        ('Tool: ' + $ToolName),
        ('Matched pattern: ' + $Rule.Pattern),
        ('Rule class: [' + $Rule.Section + ']  Defined in: ' + $Rule.Source),
        'This operation is deny-listed on this machine. Do NOT retry it, and do NOT attempt an equivalent, rephrased, encoded, or split-up variant of it.',
        'Instead: tell the user exactly what you wanted to run and why, then stop and wait for their decision. The user can run it manually, or adjust the rules in %USERPROFILE%\.claude\guardrails-local.txt.'
    )
    [Console]::Error.WriteLine(($lines -join [Environment]::NewLine))
    exit 2
}

# Collect every string value stored under a property named 'command', at any depth.
# Deliberately narrow: free-text fields (work item descriptions, wiki content) are never scanned.
$script:CommandStrings = New-Object System.Collections.ArrayList
function Walk-Args {
    param($Node, [int]$Depth)
    if ($null -eq $Node -or $Depth -gt 16) { return }
    if ($Node -is [string] -or $Node -is [System.ValueType]) { return }
    if ($Node -is [System.Collections.IDictionary]) {
        foreach ($key in @($Node.Keys)) {
            $value = $Node[$key]
            if (($key -is [string]) -and ($key -eq 'command') -and ($value -is [string])) {
                [void]$script:CommandStrings.Add($value)
            }
            Walk-Args -Node $value -Depth ($Depth + 1)
        }
        return
    }
    if ($Node -is [System.Collections.IEnumerable]) {
        foreach ($item in $Node) { Walk-Args -Node $item -Depth ($Depth + 1) }
        return
    }
    foreach ($prop in $Node.PSObject.Properties) {
        if (($prop.Name -eq 'command') -and ($prop.Value -is [string])) {
            [void]$script:CommandStrings.Add($prop.Value)
        }
        Walk-Args -Node $prop.Value -Depth ($Depth + 1)
    }
}

try {
    $rules = New-Object System.Collections.ArrayList
    Read-PatternFile -Path (Join-Path $PSScriptRoot 'dangerous-patterns.txt') -Label 'dangerous-patterns.txt' -Into $rules
    $localPath = $env:AGENT_GUARDRAILS_LOCAL
    if ([string]::IsNullOrEmpty($localPath)) { $localPath = Join-Path $env:USERPROFILE '.claude\guardrails-local.txt' }
    Read-PatternFile -Path $localPath -Label 'guardrails-local.txt' -Into $rules
    if ($rules.Count -eq 0) { exit 0 }

    $payload = $null
    try { $payload = ConvertFrom-Json -InputObject $raw } catch { $payload = $null }

    if ($null -eq $payload) {
        # Unparseable input must not become a bypass: scan the raw text with the [shell] rules.
        # JSON quoting/escaping would defeat token-end patterns like --force(?!\S), so scan a
        # de-quoted copy (quotes and backslashes become spaces). Best-effort by design.
        $haystack = $raw -replace '["\\]', ' '
        foreach ($rule in $rules) {
            if ($rule.Section -eq 'shell' -and (Test-GuardPattern -Text $haystack -Pattern $rule.Pattern)) {
                Deny -ToolName '(unparsed hook input)' -Rule $rule
            }
        }
        exit 0
    }

    $toolName = ''
    try {
        if ($payload.PSObject.Properties['tool_name'] -and ($payload.tool_name -is [string])) { $toolName = $payload.tool_name }
        elseif ($payload.PSObject.Properties['toolName'] -and ($payload.toolName -is [string])) { $toolName = $payload.toolName }
    } catch { }

    $toolArgs = $null
    try {
        if ($payload.PSObject.Properties['tool_input']) { $toolArgs = $payload.tool_input }
        elseif ($payload.PSObject.Properties['toolArgs']) { $toolArgs = $payload.toolArgs }
    } catch { }

    Walk-Args -Node $toolArgs -Depth 0
    $commands = @($script:CommandStrings)

    foreach ($cmd in $commands) {
        foreach ($rule in $rules) {
            if ($rule.Section -eq 'shell' -and (Test-GuardPattern -Text $cmd -Pattern $rule.Pattern)) {
                Deny -ToolName $toolName -Rule $rule
            }
        }
    }

    if ($toolName.IndexOf('__') -ge 0) {
        foreach ($rule in $rules) {
            if ($rule.Section -eq 'mcp-tool' -and (Test-GuardPattern -Text $toolName -Pattern $rule.Pattern)) {
                Deny -ToolName $toolName -Rule $rule
            }
        }
        foreach ($cmd in $commands) {
            foreach ($rule in $rules) {
                if ($rule.Section -eq 'mcp-command' -and (Test-GuardPattern -Text $cmd -Pattern $rule.Pattern)) {
                    Deny -ToolName $toolName -Rule $rule
                }
            }
        }
    }

    exit 0
} catch {
    # Fail-open: a broken guard must never block normal work.
    exit 0
}
