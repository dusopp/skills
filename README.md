# dusopp/skills

My personal skills that apply to **any project I work on** - packaged as a
[Claude Code plugin marketplace](https://code.claude.com/docs/en/plugin-marketplaces),
with every skill also consumable by GitHub Copilot (VS Code agent mode + Copilot CLI)
via the open [Agent Skills](https://agentskills.io) standard. Windows / .NET / Azure /
Azure DevOps focused.

## Catalog

| Plugin | What it does | Invocation |
|---|---|---|
| [agent-guardrails](#agent-guardrails) | Block-only PreToolUse guard: stops catastrophic az/azd/DevOps/git/disk commands and destructive MCP calls before any agent runs them | always on (hook); ops guide via `/agent-guardrails` |
| [git-worktree](#git-worktree) | Parallel coding agents without collisions: one task = one worktree = one agent session (.NET bootstrap, ports/LocalDB deconfliction, ADO PR flow) | explicit: `/git-worktree` |
| [goal-loop](#goal-loop) | Goal contracts for persistent self-checking agent loops: Claude Code `/goal`, Copilot CLI `/autopilot`, VS Code Autopilot, cloud agent | explicit: `/goal-loop` |
| [setup-help](#setup-help) | Step-by-step setup walkthroughs: one atomic step per response plus a glanceable max-8-item list of remaining steps | explicit: `/setup-help` |
| all-skills | Bundle that installs everything above at once | - |

## Install

Register the marketplace once:

```
/plugin marketplace add dusopp/skills
```

**One skill:**

```
/plugin install agent-guardrails@dusopp-skills     # or git-worktree@dusopp-skills
```

**Everything at once:**

```
/plugin install all-skills@dusopp-skills
```

The bundle auto-installs all plugins it depends on. (Uninstalling the bundle leaves the
dependencies installed; `claude plugin prune` removes orphans.)

**GitHub Copilot side** (hooks + skills for VS Code agent mode and Copilot CLI): after
installing, run ONE script from the installed all-skills plugin:

```powershell
cd <installed all-skills plugin>\scripts
.\install-copilot.ps1            # wires every plugin: guard hook + skill junctions
.\install-copilot.ps1 -Uninstall # removes everything it wired
```

(Each plugin also has its own `scripts\install-copilot.ps1` if you installed just one.)

**Update:** bump happens via `/plugin update <name>` after a push - plugin versions are
pinned, so installed copies refresh only when `plugin.json` versions change.

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
`.\install-copilot.ps1` - writes the hook file (requires PowerShell 7+ for Copilot CLI
hooks) and junctions the ops-guide skill into `~/.copilot/skills`.

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

### git-worktree

A playbook skill for running **parallel coding agents without collisions**: one task =
one worktree = one agent session. Tailored for Windows/.NET/Azure DevOps - Claude Code
native worktrees (`claude --worktree`, subagent `isolation: worktree`, `.worktreeinclude`
bootstrap), manual worktrees for GitHub Copilot (VS Code agent mode + CLI), the light
.NET bootstrap (NuGet cache and user secrets are shared per-user; the two real collisions
are ports and LocalDB/EF migrations), and merging back on personal repos vs
policy-protected Azure DevOps repos (`az repos pr create`). Explicit invocation only:
`/git-worktree`.

**Install (Claude Code):**

```
/plugin install git-worktree@dusopp-skills
```

**Install (GitHub Copilot):** from the installed plugin's `scripts` dir run
`.\install-copilot.ps1` - it junctions the skill into `~/.copilot/skills`, which Copilot
CLI and VS Code agent mode read automatically. (`-Uninstall` removes it. Visual Studio
IDE has no skills support.)

Skill source: [`plugins/git-worktree/skills/git-worktree/SKILL.md`](plugins/git-worktree/skills/git-worktree/SKILL.md)

### goal-loop

A playbook skill for **goal-driven autonomous runs**: turn a task into a 5-part contract
(objective, constraints, validation command, verifiable stop condition, documentation)
and launch it as a persistent self-checking loop - Claude Code `/goal <condition>`,
Copilot CLI autopilot (Shift+Tab or `--autopilot` + `--max-autopilot-continues`; the
`/autopilot`/`/goal` slash commands are experimental-mode only), VS Code
Autopilot mode, or the Copilot cloud agent for walk-away runs (**GitHub repos only - not
Azure Repos**; for ADO work use local CLI autopilot). Includes anti-reward-hacking rules
("do not delete, skip, weaken, or narrow tests"), .NET validation commands, the
meta-prompting trick for drafting contracts, and drift management. Explicit invocation
only: `/goal-loop`.

**Install (Claude Code):**

```
/plugin install goal-loop@dusopp-skills
```

**Install (GitHub Copilot):** from the installed plugin's `scripts` dir run
`.\install-copilot.ps1` - junctions the skill into `~/.copilot/skills`.

Skill source: [`plugins/goal-loop/skills/goal-loop/SKILL.md`](plugins/goal-loop/skills/goal-loop/SKILL.md)

### setup-help

A conversation-format skill for **guided setup walkthroughs**: every response gives ONE
atomic current step (a single click, field, or command), a divider, then a numbered
"Still remaining" list of headline-only items - never more than 8, with later steps
merged into phase-level items so the list stays glanceable. Detail appears only when an
item becomes the current step. Ported verbatim from
[davidondrej/skills](https://github.com/davidondrej/skills) `ops-and-setup/setup-help`.
Explicit invocation only: `/setup-help`.

**Install (Claude Code):**

```
/plugin install setup-help@dusopp-skills
```

**Install (GitHub Copilot):** from the installed plugin's `scripts` dir run
`.\install-copilot.ps1` - junctions the skill into `~/.copilot/skills`.

Skill source: [`plugins/setup-help/skills/setup-help/SKILL.md`](plugins/setup-help/skills/setup-help/SKILL.md)

Inspired by [davidondrej/skills](https://github.com/davidondrej/skills)
`ops-and-setup/global-agent-guardrails` (bash, multi-agent), rebuilt for Windows,
PowerShell 5.1+, Azure, Azure DevOps, .NET, and the Claude Code + GitHub Copilot pair.
