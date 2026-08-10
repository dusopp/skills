# dusopp/skills

Personal [Claude Code plugin marketplace](https://code.claude.com/docs/en/plugin-marketplaces)
- Windows / .NET / Azure focused.

```
/plugin marketplace add dusopp/skills
```

## Plugins

### agent-guardrails

A block-only PreToolUse guard that stops catastrophic commands **before** a coding agent runs
them: `az group delete`, `az keyvault purge`, `azd down`, Complete-mode ARM deployments,
Azure DevOps project/repo/pipeline deletes, `az devops invoke --http-method DELETE`,
`Remove-AzResourceGroup`, `dotnet nuget push`, `git push --force`, disk/registry wipes,
`azcopy rm`, and destructive MCP tool calls (tool names and MCP-carried `command` fields).
Everything else - including the daily dev loop (`az webapp delete`, `dotnet ef database drop`,
`git push --force-with-lease`) - stays untouched.

One PowerShell guard + one regex denylist, consumed by:

| Consumer | Wiring | Enforcement |
|---|---|---|
| Claude Code | plugin hook (auto on install) | hard block (exit 2) |
| GitHub Copilot CLI | `~/.copilot/hooks/agent-guardrails.json` via bundled `install-copilot.ps1` | hard block (fail-closed host) |
| VS Code Copilot agent mode | same `~/.copilot/hooks` file + `"chat.hooks.enabled": true` (Preview) | hard block; plus optional advisory auto-approve denials |
| Visual Studio IDE Copilot | not supported (no hook mechanism) | manual approvals only |

**Install (Claude Code):**

```
/plugin marketplace add dusopp/skills
/plugin install agent-guardrails@dusopp-skills
```

then restart / `/reload-plugins` and verify:

```powershell
cd <installed plugin>\scripts
.\test-guard.ps1          # must end: failed: 0
```

**Install (GitHub Copilot):** from the installed plugin's `scripts` dir run
`.\install-copilot.ps1` (requires PowerShell 7+ for Copilot CLI hooks).

**Tune:** edit `plugins/agent-guardrails/scripts/dangerous-patterns.txt` (add tests in
`test-guard.ps1`), push, `/plugin update agent-guardrails`. Machine-local additions that
survive updates: `~/.claude/guardrails-local.txt`.

**Update / uninstall:** `/plugin update agent-guardrails` - `/plugin uninstall agent-guardrails`
and `.\install-copilot.ps1 -Uninstall` for the Copilot side.

> **This is a seatbelt, not a sandbox.** It guards against *accidental* destructive commands.
> A determined or compromised agent can bypass regex matching via encoding, splitting, or
> obfuscation. Keep permission prompts on for anything you would not want to run unreviewed,
> and prefer running the Azure MCP server with `--read-only` where feasible.

Full operations guide (state checks, pattern conventions, gotchas, E2E verification):
[`plugins/agent-guardrails/skills/agent-guardrails/SKILL.md`](plugins/agent-guardrails/skills/agent-guardrails/SKILL.md)

Inspired by [davidondrej/skills](https://github.com/davidondrej/skills)
`ops-and-setup/global-agent-guardrails` (bash, multi-agent), rebuilt for Windows,
PowerShell 5.1+, Azure, Azure DevOps, .NET, and the Claude Code + GitHub Copilot pair.
