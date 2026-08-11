# Claude Code plugins & plugin marketplaces - a practical tutorial

A hands-on guide to how Claude Code plugins and plugin marketplaces work, using this
repo (`dusopp/skills`, marketplace name `dusopp-skills`) as the running example. Covers
the concepts, the schemas, installing, day-to-day skill management, updating,
uninstalling, and the GitHub Copilot side that this repo ships alongside.

All commands and schema fields below were verified against the official docs:
[plugins](https://code.claude.com/docs/en/plugins.md),
[plugin marketplaces](https://code.claude.com/docs/en/plugin-marketplaces.md),
[plugins reference](https://code.claude.com/docs/en/plugins-reference.md),
[skills](https://code.claude.com/docs/en/skills.md).

## 1. Concepts: skill vs plugin vs marketplace

- A **skill** is one folder with a `SKILL.md` file: instructions Claude loads when the
  skill is invoked. On its own it can live in `~/.claude/skills/` or `.claude/skills/`.
- A **plugin** is a distributable directory that can bundle many component types:
  **skills** (`skills/<name>/SKILL.md`), flat **commands** (`commands/*.md`),
  **agents** (`agents/`), **hooks** (`hooks/hooks.json`), **MCP servers** (`.mcp.json`),
  **LSP servers** (`.lsp.json`), **output styles**, and **executables** (`bin/`, added
  to the Bash tool PATH). A plugin is the unit you install, version, and uninstall.
- A **marketplace** is a catalog of plugins: a repo (or URL) containing
  `.claude-plugin/marketplace.json` that tells Claude Code which plugins exist and
  where to fetch each one. You register a marketplace once, then install plugins
  from it by name.

How this repo maps to that:

| Concept | Here |
|---|---|
| Marketplace | this repo; catalog at `.claude-plugin/marketplace.json`, name `dusopp-skills` |
| Plugin with hooks + skill | `plugins/agent-guardrails/` (PreToolUse guard + ops-guide skill) |
| Skill-only plugins | `plugins/git-worktree/`, `plugins/goal-loop/`, `plugins/setup-help/` |
| Meta/bundle plugin | `plugins/all-skills/` (no components of its own; only `dependencies`) |

## 2. Anatomy of a plugin

Minimal skill-only layout (this is `plugins/setup-help/`, verbatim):

```
plugins/setup-help/
  .claude-plugin/plugin.json        <- the manifest (only this goes in .claude-plugin/)
  skills/setup-help/SKILL.md        <- the skill; folder name must match frontmatter name
  scripts/install-copilot.ps1       <- repo convention, not a Claude Code concept (see 9.)
```

The manifest, `plugins/setup-help/.claude-plugin/plugin.json`:

```json
{
  "name": "setup-help",
  "description": "Guided step-by-step setup walkthroughs: ...",
  "author": { "name": "dusopp", "url": "https://github.com/dusopp" }
}
```

Note there is no `version` field - that is deliberate, see the versioning note below.

Key manifest fields (all optional except `name`):

| Field | Meaning |
|---|---|
| `name` | kebab-case identifier; also the namespace for the plugin's skills (`/setup-help:setup-help`) |
| `version` | semantic version. **If set, installed users only ever receive updates when this field is bumped.** If omitted, the version resolves to the git commit SHA, so every push is an update - this repo omits it everywhere for exactly that reason |
| `description` | shown in the `/plugin` UI and listings |
| `author` | `{ "name", "email"?, "url"? }` |
| `dependencies` | other plugins to auto-install alongside this one (see 8.) - how `all-skills` works |
| `defaultEnabled` | whether the plugin starts enabled after install (default `true`) |
| `homepage`, `repository`, `license`, `keywords` | metadata for discovery |

Version resolution order: `plugin.json` `version` -> marketplace entry `version` -> git
commit SHA -> archive digest. This repo deliberately omits `version` everywhere, so every
plugin's version **is** the marketplace repo's commit SHA: push == release, and `/plugin
update` always delivers the latest pushed commit with nothing to bump. CLAUDE.md makes
this a hard rule: *never add a `version` field - a stray one re-pins that plugin and
silently stops updates.*

A richer plugin, `plugins/agent-guardrails/`, additionally ships `hooks/hooks.json`
(auto-discovered - no manifest key needed) and its test script. Hooks, MCP servers, and
agents all ride along in the same install: installing the plugin wires them, uninstalling
removes them.

## 3. Anatomy of a marketplace

A marketplace is just `.claude-plugin/marketplace.json` at the root of a repo:

```json
{
  "name": "dusopp-skills",
  "owner": { "name": "dusopp", "url": "https://github.com/dusopp" },
  "description": "Personal Claude Code plugin marketplace (Windows / .NET / Azure focused)",
  "plugins": [
    {
      "name": "setup-help",
      "source": "./plugins/setup-help",
      "description": "Guided step-by-step setup walkthroughs - ...",
      "author": { "name": "dusopp" },
      "category": "workflow",
      "keywords": ["setup", "onboarding", "walkthrough"]
    }
  ]
}
```

Required: `name` (users type it after `@`), `owner.name`, and `plugins[]` where each
entry needs `name` + `source`. Everything else (`description`, `author`, `category`,
`keywords`) is catalog metadata.

`source` tells Claude Code where to fetch the plugin. Supported forms:

| Source | Example | Notes |
|---|---|---|
| Relative path | `"./plugins/setup-help"` | must start with `./`; resolves against the marketplace repo root. This repo uses only this form |
| GitHub repo | `{ "source": "github", "repo": "owner/repo", "ref": "v1.2" }` | optional `ref` (branch/tag) or `sha` (exact commit; wins over ref) |
| Git URL | `{ "source": "url", "url": "https://gitlab.com/x/y.git" }` | GitLab, Bitbucket, Azure DevOps, etc. |
| Git subdirectory | `{ "source": "git-subdir", "url": "owner/repo", "path": "tools/plugin" }` | sparse checkout for monorepos |
| npm package | `{ "source": "npm", "package": "@scope/plugin", "version": "^2.0.0" }` | |
| Zip archive | `{ "source": "archive", "url": "https://...", "sha256": "..." }` | HTTPS only, max 256 MiB |

Two conveniences worth knowing (not used here, but useful as the catalog grows):
`metadata.pluginRoot: "./plugins"` lets entries write `"source": "setup-help"` instead
of the full relative path; and the per-entry `strict` flag (default `true`) controls
authority - `true` means the plugin's own `plugin.json` defines its components and the
marketplace entry only supplements it, `false` means the marketplace entry is the entire
definition.

If `version` is set in both the marketplace entry and `plugin.json`, `plugin.json` wins.
This repo sets it in **neither** - commit-SHA versioning only works when both places omit
it, because an explicit version in either one pins that plugin and stops SHA-based updates.

## 4. Installing

**Step 1 - register the marketplace** (once per machine):

```
/plugin marketplace add dusopp/skills
```

The argument can be GitHub `owner/repo` shorthand, a full git URL, a direct URL to a
`marketplace.json`, or a local path (handy for testing before pushing:
`/plugin marketplace add C:\Repos\skills`). Private repos work if your git credentials
(`gh auth login`, SSH agent, credential manager) can clone them.

**Step 2 - install plugins.** Everything at once via the bundle:

```
/plugin install all-skills@dusopp-skills
```

or each skill separately:

```
/plugin install agent-guardrails@dusopp-skills
/plugin install git-worktree@dusopp-skills
/plugin install goal-loop@dusopp-skills
/plugin install setup-help@dusopp-skills
```

The `@dusopp-skills` suffix is only required when the plugin name is ambiguous across
your registered marketplaces, but it is good habit to always write it.

**Scopes.** Installs are recorded per scope, and the CLI takes `--scope`:

| Scope | Settings file written | Use for |
|---|---|---|
| `user` (default) | `~/.claude/settings.json` | your personal tooling, every project |
| `project` | `.claude/settings.json` (committed) | team-shared plugins for one repo |
| `local` | `.claude/settings.local.json` (gitignored) | personal, this repo only |

The settings key is `enabledPlugins`, a map of `"plugin@marketplace": true|false`.
A project can also pre-register marketplaces for teammates via
`extraKnownMarketplaces` in its committed `.claude/settings.json`.

**The interactive UI.** `/plugin` with no arguments opens a manager with three tabs:
**Discover** (browse/search all registered marketplaces), **Installed** (versions,
enable/disable toggles), and **Errors** (plugin load failures, hook errors - your first
stop when something does not work).

**CLI from outside a session** (same verbs, scriptable):

```
claude plugin marketplace add dusopp/skills
claude plugin install setup-help@dusopp-skills --scope user
claude plugin list --json
```

After installing or changing plugins mid-session, run `/reload-plugins` (or restart)
so skills and hooks load.

## 5. What lands on disk

| Path | Contents |
|---|---|
| `~/.claude/plugins/known_marketplaces.json` | registry of marketplaces you added |
| `~/.claude/plugins/marketplaces/<marketplace>/` | cached clone of each marketplace repo |
| `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/` | the installed plugin, one directory per version |
| `~/.claude/settings.json` (and project/local variants) | `enabledPlugins`, `pluginConfigs` |

When a plugin updates, the old version directory is marked orphaned and auto-deleted
after roughly 14 days (a grace period for sessions still running the old version).

One sharp edge: after install, a plugin runs from that cache directory, and it **cannot
reference files outside its own folder** - a `../shared-utils` path that worked in the
source repo breaks in the cache. Keep every file a plugin needs inside the plugin.

## 6. Managing skills day-to-day

**How skills surface.** A plugin skill is addressable as `/plugin-name:skill-name`.
In this repo every skill folder is named the same as its plugin, and names are unique,
so the short forms work: `/agent-guardrails`, `/git-worktree`, `/goal-loop`,
`/setup-help`.

**Two invocation paths**, controlled by frontmatter:

- *Model-invoked*: Claude reads every installed skill's `description` and loads a skill
  automatically when the task matches. That is why descriptions here are written
  trigger-rich.
- *Explicit-only*: `disable-model-invocation: true` in the frontmatter turns
  auto-invocation off; the skill fires only when you type its slash command.
  `git-worktree`, `goal-loop`, and `setup-help` are all explicit-only by design;
  `agent-guardrails`' ops-guide skill is model-invocable.

Other useful frontmatter switches: `user-invocable: false` (hide the slash command,
model-only) and `argument-hint` (placeholder text in the composer).

**Seeing what you have:**

```
/help                                  # Custom commands tab lists every available skill
/plugin list                           # installed plugins + enabled/disabled state
claude plugin details setup-help@dusopp-skills   # component inventory + token cost
```

**Turning things off without uninstalling.** Disabling keeps the plugin on disk but
unloads its skills and hooks - the right tool when you suspect a plugin is interfering
or you want to silence it temporarily:

```
claude plugin disable agent-guardrails@dusopp-skills
claude plugin enable agent-guardrails@dusopp-skills
```

(or the toggle in `/plugin` -> Installed). There is no per-skill disable switch for an
installed plugin - disable operates on the whole plugin. If you want only some skills
from a multi-skill plugin, that is a reason to keep plugins small, as this repo does
(one skill per plugin).

## 7. Updating

Because no plugin here sets an explicit `version`, versions resolve to the marketplace
repo's **commit SHA** - updates are pull-based, with nothing to bump:

1. Author pushes changes. That is the whole release step.
2. Consumer refreshes the catalog: `/plugin marketplace update dusopp-skills`
   (re-pulls the marketplace repo; does *not* touch installed plugins).
3. Consumer updates the plugin: `/plugin update setup-help@dusopp-skills`
   (fetches the new commit into the cache and switches to it).

Every push changes the repo SHA, so step 3 always delivers the latest pushed state -
for **all** plugins, since the SHA is repo-wide (untouched plugins get a harmless
re-copy). If step 3 reports "already at the latest version" despite a push, step 2 was
skipped or the commit was never pushed. The flip side: push == release, so unfinished
work can be committed locally but must not be pushed.

`/plugin marketplace update` with no name refreshes all marketplaces. A background
refresh also runs after startup, but do not rely on it for immediate delivery - run the
two commands above when you actually want an update now.

## 8. Uninstalling

**One plugin:**

```
/plugin uninstall setup-help@dusopp-skills
```

CLI form with the useful flags:

```
claude plugin uninstall setup-help@dusopp-skills --scope user
claude plugin uninstall all-skills@dusopp-skills --prune   # also remove orphaned deps
claude plugin uninstall setup-help@dusopp-skills --keep-data
```

What uninstall actually does: removes the entry from `enabledPlugins` in the chosen
scope; when that was the last scope using the plugin, it also deletes the plugin's data
directory (`~/.claude/plugins/data/...`) unless you pass `--keep-data`. The cached
version directory is orphaned and cleaned up automatically (~14 days). If the plugin is
installed at several scopes, each scope must be uninstalled separately.

**Dependencies and the bundle - worked example.** `all-skills` declares

```json
"dependencies": ["agent-guardrails", "git-worktree", "goal-loop", "setup-help"]
```

so installing it auto-installs all four at the same scope. Uninstalling `all-skills`
does **not** cascade - the four dependencies stay installed. To remove dependencies
that no remaining plugin requires:

```
claude plugin prune --dry-run    # show what would be removed
claude plugin prune              # remove orphaned dependencies (asks to confirm)
```

or do both in one step with `claude plugin uninstall all-skills@dusopp-skills --prune`.

**Full teardown** of everything from this repo, in order:

```
claude plugin uninstall all-skills@dusopp-skills --prune
/plugin marketplace remove dusopp-skills
```

Removing the marketplace deletes its cached clone and de-registers it; installed
plugins from it should be uninstalled first (the `--prune` line above covers all five).

**Disable vs uninstall:** prefer `disable` when you may want the plugin back (state
kept, one command to restore); `uninstall` when you want it gone from settings and disk.

## 9. The GitHub Copilot side (this repo's convention)

Claude Code's plugin management never touches GitHub Copilot. This repo additionally
delivers every skill to Copilot (VS Code agent mode + Copilot CLI) by convention: each
plugin ships `scripts/install-copilot.ps1`, which junctions the skill folder into
`%USERPROFILE%\.copilot\skills\<name>` (falls back to a copy where junctions are
unavailable). `agent-guardrails`' installer also writes its hook file to
`%USERPROFILE%\.copilot\hooks\`.

One caveat: the junction targets the **installed version's cache directory**
(`~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/`). Every `/plugin update`
switches to a new directory - with commit-SHA versioning, that is every pushed commit -
and the old one is auto-deleted after ~14 days, leaving the junction dangling. Re-run
`install-copilot.ps1` after updating.

```powershell
# wire everything at once (from the installed all-skills plugin's scripts dir):
.\install-copilot.ps1              # discovers and runs every sibling plugin's installer
.\install-copilot.ps1 -ListOnly    # dry-run: show which installers would run
.\install-copilot.ps1 -Uninstall   # unwire everything

# or per plugin, from that plugin's scripts dir:
.\install-copilot.ps1
.\install-copilot.ps1 -Uninstall
```

So a **complete** uninstall on a machine that wired both ecosystems is two steps:
the Claude Code teardown from section 8, **plus** `install-copilot.ps1 -Uninstall`
(bundle or per plugin). Neither step performs the other.

## 10. Authoring & publishing (this repo's checklist)

Condensed from `CLAUDE.md` - all four in the same commit when adding a plugin:

1. Create `plugins/<name>/` (copy the shape of `plugins/setup-help/` for skill-only,
   `plugins/agent-guardrails/` for hooks). Frontmatter `name` must equal the skill
   folder name; `description` is the retrieval trigger - make it concrete.
2. Register the entry in `.claude-plugin/marketplace.json`.
3. Add the plugin to `plugins/all-skills/.claude-plugin/plugin.json` `dependencies`.
4. Add the README catalog row + section (and an install line in the Install section).

Then: `claude plugin validate .` at the repo root must pass. Expect one "No version
specified" warning per plugin - that is the commit-SHA versioning choice, not a defect
(which also means `--strict` cannot be used here, as it would turn those warnings into
errors). Run the plugin's test script if it has hook-shaped behavior;
commit locally; push only with explicit approval. After the push, consumers get the
new plugin via `/plugin marketplace update dusopp-skills` + `/plugin install`, and
changed plugins via `/plugin update` - every push is delivered (commit-SHA versioning,
section 7).

Scaffolding shortcut for greenfield plugins: `claude plugin init <name>` generates a
starting structure (this repo prefers copying its own reference plugins instead, to
keep the Copilot installer and conventions).

## 11. Troubleshooting & gotchas

- **"/plugin update did nothing"** - the catalog was not refreshed or the commit was
  never pushed (section 7). Run `/plugin marketplace update dusopp-skills` first, then
  `/plugin update`. Also check no `version` field crept into a plugin.json or
  marketplace entry - an explicit version re-pins the plugin and blocks SHA updates.
- **Copilot skill junction is dangling after an update** - junctions target the old
  version's cache directory (section 9). Re-run `install-copilot.ps1`.
- **Skill does not fire automatically** - check for `disable-model-invocation: true`
  (explicit-only by design here), and that the `description` actually mentions the
  vocabulary you used.
- **Something broke after install** - `/plugin` -> **Errors** tab shows load failures,
  hook errors, and validation warnings. Then `claude plugin validate <path> --strict`
  against the source.
- **New/changed skills not visible mid-session** - `/reload-plugins`.
- **Files missing after install** - the plugin referenced files outside its directory;
  everything must live inside the plugin folder (section 5).
- **Testing before publishing** - add the repo as a *local* marketplace
  (`/plugin marketplace add C:\Repos\skills`), install from it, iterate, then remove it
  and re-add the GitHub form. Never wire dev copies into `~/.claude` or `~/.copilot`
  by hand.

## 12. Command cheat sheet

| Task | In-session | CLI |
|---|---|---|
| Add marketplace | `/plugin marketplace add dusopp/skills` | `claude plugin marketplace add dusopp/skills` |
| List marketplaces | `/plugin marketplace list` | `claude plugin marketplace list --json` |
| Refresh catalog | `/plugin marketplace update [name]` | `claude plugin marketplace update [name]` |
| Remove marketplace | `/plugin marketplace remove <name>` | `claude plugin marketplace remove <name>` |
| Install plugin | `/plugin install <name>@<mkt>` | `claude plugin install <name>@<mkt> --scope user` |
| Update plugin | `/plugin update <name>@<mkt>` | `claude plugin update <name>@<mkt>` |
| Enable / disable | `/plugin` UI toggle | `claude plugin enable\|disable <name>@<mkt>` |
| Uninstall plugin | `/plugin uninstall <name>@<mkt>` | `claude plugin uninstall <name>@<mkt> [--prune] [--keep-data]` |
| Remove orphaned deps | - | `claude plugin prune [--dry-run]` |
| List installed | `/plugin list` | `claude plugin list --json` |
| Inspect a plugin | `/plugin` -> select | `claude plugin details <name>@<mkt>` |
| List skills | `/help` (Custom commands) | - |
| Validate | `/plugin validate <path>` | `claude plugin validate <path> [--strict]` |
| Reload after changes | `/reload-plugins` | - |
| Copilot wire/unwire | - | `.\install-copilot.ps1 [-Uninstall]` (`-ListOnly` on the all-skills one) |
