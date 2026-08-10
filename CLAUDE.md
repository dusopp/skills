# dusopp/skills - Claude Code plugin marketplace

Personal marketplace of Claude Code plugins (Windows 11 / PowerShell 5.1 / .NET / Azure /
Azure DevOps). Consumers install via `/plugin marketplace add dusopp/skills`. The reference
implementation is `plugins/agent-guardrails/` - copy its shape when adding anything new.

## Repo rules

- **Never install or wire anything on this machine as a side effect of authoring.** No writes
  to `~/.claude/settings.json`, `~/.claude/skills/`, `~/.copilot/`. Authoring and installing
  are separate, user-triggered steps.
- **Do not push without explicit user approval.** Known blocker: the stored Windows credential
  is for `jurajglavasdev`, which has no write access to `dusopp/skills` (403). Commit locally
  and ask.
- Every plugin must pass `claude plugin validate .` (run at repo root) and its own test
  script before committing.
- Scripts and pattern files: **ASCII only, Windows PowerShell 5.1 compatible** (no ternary,
  no `??`, no `-AsHashtable`, no pipeline chain operators). pwsh 7 is NOT installed here -
  5.1-safe code runs on both.
- Docs (SKILL.md, README.md) may use UTF-8.

## Layout for a new plugin

```
.claude-plugin/marketplace.json      <- register the plugin here (name, source, description)
plugins/<plugin-name>/
  .claude-plugin/plugin.json         <- name (required), version, description, author
  hooks/hooks.json                   <- only if the plugin ships hooks (auto-discovered)
  scripts/                           <- implementation + its test script
  skills/<skill-name>/SKILL.md       <- the operations/maintenance guide (see below)
```

kebab-case names everywhere. Plugin `version` lives in plugin.json only (marketplace entry
would silently lose). Relative `source` paths resolve against the repo root.

## Workflow: create a similar skill/plugin

1. **Research before writing - never trust memory for schemas.** Claude Code hook/plugin/
   marketplace schemas, VS Code Copilot settings, Copilot CLI hook formats, MCP server tool
   lists, and az CLI syntax all drift. Verify against:
   - https://code.claude.com/docs/en/hooks-guide.md , /plugins.md , /plugin-marketplaces.md
   - https://docs.github.com/en/copilot/reference/hooks-reference (Copilot CLI + VS Code)
   - the target MCP server's GitHub repo (tool names change release to release)
2. **Ask the user the shape questions early**: which agents to cover, strictness (block vs
   ask vs advisory), packaging. Defaults established here: plugin-marketplace packaging,
   block-only guards, Claude Code + GitHub Copilot coverage (VS/IDE Copilot has no hooks).
3. **Scaffold** per the layout above; register in marketplace.json.
4. **Write the test script first-class** (see `scripts/test-guard.ps1`): table-driven cases,
   spawn real child processes for anything hook-shaped, summary line `passed: N failed: 0`,
   nonzero exit on failure. A pattern/behavior change without a matching test case is not done.
5. **Validate**: all JSON parses (`ConvertFrom-Json`), `claude plugin validate .`, test
   script green under 5.1 (and pwsh if present).
6. **Commit locally** (message + `Co-Authored-By: Claude ...` trailer). Do not push (rule above).

## SKILL.md conventions

Frontmatter `name` + a trigger-rich `description` (concrete commands, error phrases, and
user vocabulary - it is the retrieval key). Body sections that earn their place: what it is
(one paragraph, state what it is NOT), file map, state check (fast "is it installed/working"
probes), how to change/tune it, design rules incl. deliberate non-goals, gotchas
(hard-won, each one paragraph), E2E verification recipe with expected outputs.

## Hard-won environment facts (reuse, do not rediscover)

Details and rationale live in `plugins/agent-guardrails/scripts/guard.ps1` comments and
`plugins/agent-guardrails/skills/agent-guardrails/SKILL.md` gotchas. Headlines:

- **Hook stdin on Windows**: read `$input` first, then a UTF-8 `StreamReader` over
  `OpenStandardInput()` gated on `[Console]::IsInputRedirected`; both `$input` and
  `[Console]::In` decode via the OEM codepage (UTF-8 mojibake; BOM arrives as chars
  8745,9559,9488). Keep hook-scanned patterns ASCII so mangling cannot cause a miss.
- **PS 5.1 test harnesses**: `Process.StandardInput` flushes the console encoding's BOM
  preamble into the pipe on creation - pin `[Console]::InputEncoding` to BOM-less UTF-8
  and write bytes to `BaseStream`, else every child receives a spurious BOM.
- **5.1 `ConvertFrom-Json`** throws on case-duplicate keys and >100 nesting; parse failures
  in a guard must fall back to raw-text scanning, not silent allow.
- **Regex in guards**: `[regex]::IsMatch` with `IgnoreCase,CultureInvariant` + 250 ms
  timeout, per-pattern try/catch. Never `-match` in the hot loop; one bad user pattern must
  not disable or stall anything. No POSIX classes (they fail silently in .NET).
- **Hook matchers must be anchored** (`^(Bash|PowerShell|mcp__.*)$`) - unanchored regexes
  substring-match tools like `BashOutput`. Always set an explicit `timeout` (default 600 s).
- **Host semantics differ**: Claude Code PreToolUse fails OPEN on hook errors; Copilot CLI
  fails CLOSED (any nonzero exit denies every tool call - check `pwsh` exists before wiring).
- **stdout discipline in hooks**: exit-0 stdout is parsed as decision JSON; `[void]` every
  expression that produces output.
- **GPO ExecutionPolicy** (Windows 11 Enterprise) can override `-ExecutionPolicy Bypass`;
  post-install verification (run the test script) is mandatory, not optional.
- **MCP guarding**: destructive intent often lives in `tool_input.command` values (Azure MCP
  namespace mode), not tool names; scan only properties literally named `command`, never
  free-text fields (work item descriptions cause false blocks).
