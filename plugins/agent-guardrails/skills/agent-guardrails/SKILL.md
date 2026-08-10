---
name: agent-guardrails
description: 'One shared block-only denylist of catastrophic commands (az group delete, keyvault purge, azd down, Complete-mode deployments, Azure DevOps project/repo/pipeline deletes, git push --force, dotnet nuget push, disk/registry wipes, destructive MCP tool calls) enforced as a PreToolUse guard for Claude Code and GitHub Copilot (VS Code agent mode + Copilot CLI) on Windows. Use when adding or tuning blocked-command patterns, installing or wiring the guard, debugging why a command was (or was not) blocked, or when the user mentions guardrails, dangerous command hook, PreToolUse safety, or protecting Azure resources from agents.'
---

# Agent Guardrails (Windows / .NET / Azure)

A "bouncer" that blocks catastrophic commands before any coding agent runs them. One
PowerShell guard + one patterns file is the single source of truth; Claude Code consumes it
as a plugin hook, GitHub Copilot (VS Code agent mode and Copilot CLI) via a `~/.copilot/hooks`
file pointing at the same script. It is a seatbelt against ACCIDENTS, NOT a security boundary:
regex can be bypassed by encoding, splitting, or obfuscation.

Tailored for:
Windows 11, PowerShell 5.1+, Azure (az/azd/azcopy/Az PowerShell/Azure MCP), Azure DevOps
(az devops + Azure DevOps MCP), .NET. Visual Studio IDE Copilot is NOT covered (it has no
hook mechanism - manual approvals only).

## File map

```
<repo>/plugins/agent-guardrails/
  hooks/hooks.json               # Claude Code PreToolUse wiring (auto-applied on plugin install)
  scripts/guard.ps1              # THE guard: hook JSON on stdin -> exit 2 blocks, exit 0 allows
  scripts/dangerous-patterns.txt # THE denylist: .NET regex per line, sections [shell]/[mcp-tool]/[mcp-command]
  scripts/test-guard.ps1         # test suite: run after ANY pattern change, must end "failed: 0"
  scripts/install-copilot.ps1    # writes ~/.copilot/hooks/agent-guardrails.json (absolute paths)

Installed (Claude):  ~/.claude/plugins/... (${CLAUDE_PLUGIN_ROOT} resolves to it)
Installed (Copilot): ~/.copilot/hooks/agent-guardrails.json -> points at the installed guard.ps1
Local overrides:     ~/.claude/guardrails-local.txt  # optional extra patterns, ALL consumers,
                                                     # survives plugin updates (additive only:
                                                     # it can add rules, never disable shipped ones)
```

## State check (is it installed and working?)

- Claude Code: plugin visible in `/plugin`, hook entry visible in `/hooks`.
- Copilot: `~/.copilot/hooks/agent-guardrails.json` exists and points at an existing guard.ps1.
- Both: from the installed `scripts` dir run `.\test-guard.ps1` - must end `failed: 0`.
- Direct probe (expect exit 2 and a BLOCKED message):

```powershell
'{"tool_name":"Bash","tool_input":{"command":"rm -rf /"}}' |
  powershell -NoProfile -ExecutionPolicy Bypass -File .\guard.ps1; $LASTEXITCODE
```

## Add or tune a pattern

1. Edit `scripts/dangerous-patterns.txt` in the REPO clone (not the installed copy).
   Rules are .NET regex, matched case-insensitively. Read the header comments first:
   no POSIX classes (`[[:alpha:]]` fails silently), `(?!\S)` = end-of-token,
   `[^\n;&|]*` = stay within one shell statement.
2. Add a block case AND an allow case to `test-guard.ps1`, run it, require `failed: 0`.
3. Push, then `/plugin update agent-guardrails` in Claude Code. The Copilot hook points at
   the same installed scripts, so it updates with the plugin.
4. For instant machine-local rules (no push/update cycle): add lines to
   `~/.claude/guardrails-local.txt` (same format, applies immediately - patterns are re-read
   on every call). Keep shipped rules in the repo so they are versioned and tested.

Design rule: block only IRREVERSIBLE or CATASTROPHIC operations - mass data loss
(resource group / storage account / SQL server / Cosmos account deletes), purges that defeat
soft-delete (`az keyvault purge`, `-InRemovedState`, `--permanent-delete`, `azd down --purge`),
silent mass-deleters (`--mode Complete` deployments, `--action-on-unmanage delete*`, azcopy rm,
delete-batch), safety-net removal (locks, branch policies, immutability, legal hold, backups),
identity destruction (`az ad app/sp delete`), irreversible publishes (`dotnet nuget push`,
universal packages), and history destruction (force push, reflog expire).
Deliberately ALLOWED - do not "fix": `az webapp/functionapp delete`, `az sql db delete`,
`az keyvault delete` (soft delete is recoverable), single container/blob deletes,
`dotnet ef database drop`, `git push --force-with-lease`, `rm -rf node_modules`, `git clean`,
and all Azure DevOps MCP `*_write` tools (daily workflow; that server ships no delete tools
by design as of v2.9).

## Install (Claude Code)

```
/plugin marketplace add dusopp/skills
/plugin install agent-guardrails@dusopp-skills
```

Restart Claude Code (or `/reload-plugins`), then run the state check. Manual fallback: merge
the `hooks/hooks.json` entry into `~/.claude/settings.json` with absolute paths - but never
BOTH plugin and settings.json (the guard would fire twice per call). Do not additionally wire
Copilot through `.claude/settings.json` compatibility loading for the same reason.

## Install (GitHub Copilot)

From the installed plugin's `scripts` dir: `.\install-copilot.ps1`
- Prereq: PowerShell 7+ (`pwsh`). The script refuses to install without it, because
  Copilot CLI preToolUse hooks FAIL CLOSED: a broken hook denies EVERY tool call.
- Copilot CLI picks the hook up on next start.
- VS Code agent mode additionally needs `"chat.hooks.enabled": true` (hooks are Preview);
  it reads the same `~/.copilot/hooks` directory. Until enabled, VS Code enforcement is
  limited to the optional `chat.tools.terminal.autoApprove` advisory entries the installer
  prints (those force a manual approval prompt; the user can still click Allow).
- Uninstall: `.\install-copilot.ps1 -Uninstall`

## Gotchas (hard-won - do not rediscover)

- **GPO ExecutionPolicy can silently neuter the guard.** On managed Windows (AllSigned/
  Restricted via policy), `-ExecutionPolicy Bypass` loses and the hook exits 1 = allow in
  Claude Code (fail-open). ALWAYS run `test-guard.ps1` after install to prove blocking works.
- **Copilot CLI fails CLOSED, Claude Code fails open.** Same guard, opposite host semantics
  on hook errors. The guard itself always exits 0 on internal errors; keep it that way.
- **Stdin encoding is treacherous in Windows PowerShell.** The guard reads `$input` first,
  then a UTF-8 StreamReader - do not "simplify" this. `$input`/`[Console]::In` decode via the
  OEM codepage (UTF-8 becomes mojibake; a BOM becomes `∩╗┐`, which the guard strips
  explicitly). All shipped patterns are ASCII so codepage mangling cannot cause a miss.
- **Unparseable hook JSON is scanned raw** (de-quoted) with the [shell] rules - a parse
  failure (PS 5.1 chokes on case-duplicate keys and >100 nesting) must not become a bypass.
- **One bad user pattern cannot kill the guard**: each pattern is compiled in its own
  try/catch with a 250 ms regex timeout; invalid or catastrophic patterns are skipped.
- **stdout must stay EMPTY on allow.** Claude Code parses exit-0 stdout as a decision JSON;
  a leaked PowerShell expression value (e.g. un-voided `ArrayList.Add`) corrupts it.
- **Matcher is anchored** (`^(Bash|PowerShell|mcp__.*)$`): an unanchored one would also fire
  on `BashOutput` polls and burn ~300 ms per call. Expect ~300-450 ms powershell.exe overhead
  per GUARDED call; that is the price of a 5.1-compatible zero-dependency guard.
- **Plugin hook edits need `/reload-plugins`** (or restart). Patterns-file edits apply
  instantly - the file is re-read on every call.
- **MCP: the verb often hides in `tool_input.command`, not the tool name.** Azure MCP
  namespace mode (default) routes everything through namespace tools; that is what the
  `[mcp-command]` section exists for. Free-text fields (work item descriptions, wiki
  content) are deliberately NEVER scanned - only properties literally named `command`.
- **Azure DevOps MCP ships NO delete tools** (v2.9, by design) - its `*_write` tools are
  daily workflow and stay allowed. The az CLI escape hatches (`az devops invoke
  --http-method DELETE`, `az boards work-item delete --destroy`) are blocked instead.
- **Cheapest Azure guard of all:** run the Azure MCP server with `--read-only` where feasible.
- **False-positive class:** a harmless command whose ARGUMENT text contains a dangerous-looking
  string (e.g. a commit message quoting `git push --force`) can match. Workaround: put the
  text in a file and reference it, or add a narrowing local pattern.
- **VS Code caveats:** `chat.tools.terminal.autoApprove: false` entries are advisory
  (approval prompt, not a block) and a TRUSTED workspace's `.vscode/settings.json` can
  override user-level entries per key; wrapper commands (`bash -c "..."`) can hide inner
  commands from its subcommand splitter (microsoft/vscode#318347). The PreToolUse hook is
  the real enforcement there.
- **Not coverable:** Visual Studio IDE Copilot (no hooks), Copilot cloud coding agent
  (sandboxed on GitHub Actions; would need repo-level `.github/hooks` with a bash guard).

## E2E verification recipe

Safe probe - run from a NON-git temp directory, so even a miss is harmless:

```powershell
cd (New-Item -ItemType Directory -Path (Join-Path $env:TEMP ([guid]::NewGuid()))).FullName
claude -p 'Run exactly: git push --force. Report the result in one line.' --permission-mode bypassPermissions
copilot -p 'Run exactly: git push --force. Report the result in one line.'
```

Blocked = guard works. "not a git repository" = guard NOT firing (but no harm done) - re-check
the state check section. Direct script probes (expect exit 2, then exit 0):

```powershell
'{"tool_name":"Bash","tool_input":{"command":"az group delete -n prod --yes"}}' |
  powershell -NoProfile -ExecutionPolicy Bypass -File .\guard.ps1; $LASTEXITCODE
'{"toolName":"bash","toolArgs":{"command":"az group list"}}' |
  powershell -NoProfile -ExecutionPolicy Bypass -File .\guard.ps1; $LASTEXITCODE
```
