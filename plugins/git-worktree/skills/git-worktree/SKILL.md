---
name: git-worktree
description: Use git worktrees to run multiple coding agents in parallel on one repo without collisions. Use when starting a task in a shared repo, when the user says "worktree", "parallel agents", "one worktree per task", or when agents keep overwriting each other's changes. Covers Claude Code native worktrees (--worktree, subagent isolation, .worktreeinclude), manual worktrees for GitHub Copilot, making a .NET worktree complete (NuGet, user secrets, ports, LocalDB/EF), merging back on personal repos vs policy-protected Azure DevOps repos, and Windows-specific cleanup gotchas.
disable-model-invocation: true
---

# Git Worktrees for Parallel Agents (Windows / .NET / Azure DevOps)

One repo, multiple folders. `git worktree add` creates an extra checkout of the same
repository in a separate directory, on its own branch. All worktrees share one `.git`
history, but each has its own files. Two agents in two worktrees physically cannot
overwrite each other's work.

Targets Claude Code (native worktree support) and GitHub Copilot (VS Code agent mode +
Copilot CLI; this skill auto-loads from `~/.copilot/skills` once installed there).
Visual Studio IDE has no skills support - the knowledge here still applies, apply it by hand.

## Start here (before any task work)

Detect where you are. PowerShell:

```powershell
if ((git rev-parse --path-format=absolute --git-dir) -eq (git rev-parse --path-format=absolute --git-common-dir)) { 'primary checkout' } else { 'worktree' }
```

Git Bash:

```bash
[ "$(git rev-parse --path-format=absolute --git-dir)" = "$(git rev-parse --path-format=absolute --git-common-dir)" ] \
  && echo "primary checkout" || echo "worktree"
```

- **Primary checkout** -> do NOT start editing here. Create a worktree named after the
  task, bootstrap it (see "Making the worktree complete"), and do ALL task work there.
- **Worktree** -> proceed with the task.

## The working model

- **One task = one worktree = one agent session.** Never let two agents share a working
  directory.
- **The primary checkout is the integration point.** It stays on the main branch and is
  used only to review, merge, and push. It is not a scratchpad.
- **Nothing auto-merges.** The human reviews each worktree's diff, then merges it (or
  discards it), then deletes the worktree.
- **Worktree branches are local and short-lived.** Exception: on Azure DevOps repos with
  branch policies, task branches ARE pushed - as PR source branches (see "Merging back").
- Merge one worktree at a time. Rebase a stale worktree onto main before merging if main
  moved.
- A branch can be checked out in only ONE worktree at a time (including main).

## Claude Code (preferred path)

Claude Code manages worktrees natively - prefer this over manual `git worktree` calls:

- `claude --worktree <task>` (or `-w <task>`) starts the session in a fresh worktree at
  `.claude/worktrees/<task>/` on branch `worktree-<task>`. Omit the name to get a
  generated one. Add `.claude/worktrees/` to the repo's `.gitignore`.
- Inside a running session, the `EnterWorktree` tool switches the session into a new (or
  existing) worktree; `ExitWorktree` returns.
- Parallel subagents: ask Claude to "use worktrees for your agents" or give subagents
  `isolation: worktree` - each gets its own worktree, and unchanged ones are removed
  automatically when the agent finishes.
- Cleanup semantics: clean worktrees are auto-removed; worktrees with uncommitted changes
  or unpushed commits are kept (periodic sweep skips them). Commit early - commits live in
  the shared repo even after a worktree folder is deleted.
- Bootstrap automation: a `.worktreeinclude` file at the repo root (gitignore syntax)
  lists gitignored files to auto-copy into every worktree Claude creates - e.g.:

  ```
  .env
  *.env
  docker-compose.override.yml
  ```

  Only files that are BOTH matched and gitignored get copied.
- Base branch: worktrees branch from the remote default branch by default; set
  `worktree.baseRef: "head"` in settings to branch from the current HEAD instead.

## GitHub Copilot

Copilot has no worktree orchestration - create the worktree yourself, then point Copilot
at it:

```powershell
git worktree add C:/Repos/myrepo-task-x -b task-x main
```

- VS Code agent mode: open `C:/Repos/myrepo-task-x` as the workspace folder.
- Copilot CLI: `cd C:/Repos/myrepo-task-x` and start `copilot` there.
- Run the bootstrap checklist below manually (Copilot does not read `.worktreeinclude`).

## Manual commands + Windows notes

```powershell
git worktree add C:/Repos/myrepo-task-x            # new worktree + branch "myrepo-task-x"
git worktree add C:/Repos/fix-y -b fix-y main      # explicit branch off main
git worktree list                                  # see all worktrees
git worktree remove C:/Repos/myrepo-task-x         # delete when merged/abandoned
git worktree prune                                 # clean up stale registrations
```

- Use forward slashes in paths - they work in PowerShell AND Git Bash (backslashes are
  escape characters in Git Bash).
- Prefer SHORT sibling paths (`C:/Repos/myrepo-task-x`) over nesting inside the repo.
  Windows MAX_PATH (260) plus deep `obj/Debug/net8.0/...` trees bites early; NuGet
  hard-fails at 260. If you nest (e.g. `.claude/worktrees/`), set
  `git config --global core.longpaths true`.
- Worktrees on a different drive work fine (objects stay in the main repo's `.git`).

## Making the worktree complete (.NET edition)

A fresh worktree contains ONLY tracked files. The good news: most .NET local state is
per-user and shared across worktrees automatically - the bootstrap is much lighter than
in node repos.

FREE (shared per-user, zero bootstrap):
- NuGet packages (`%USERPROFILE%\.nuget\packages` global cache) - restore is cheap.
- User secrets (`%APPDATA%\Microsoft\UserSecrets\<UserSecretsId>\secrets.json`, keyed by
  the tracked csproj) - every worktree sees the same secrets.
- HTTPS dev certificate; Azure Artifacts credential provider.
- `appsettings.Development.json` and `launchSettings.json` are normally TRACKED - they
  arrive with the checkout.

DO in every new worktree:
1. `dotnet restore` (rebuilds `obj/` assets; packages come from the shared cache).
2. Copy gitignored local files from the primary checkout: `.env` / `*.env`
   (docker-compose), any team-invented `*.local.json` overrides, local `*.mdf`/`*.ldf`
   databases if used. Copy, never symlink - an agent editing a symlinked file corrupts
   the original.
3. Docker Compose: pin a top-level `name:` in the compose file - otherwise the project
   name comes from the FOLDER name and every worktree spawns its own duplicate container
   fighting over the same host port.
4. Build once (`dotnet build`) so the agent does not trip over an empty `bin/`.

Automate it: `.worktreeinclude` (Claude-created worktrees) or keep a
`scripts/setup-worktree.ps1` in the target repo and run it first in any new worktree:

```powershell
# scripts/setup-worktree.ps1 - run from inside a fresh worktree
$primary = Split-Path -Parent (git rev-parse --path-format=absolute --git-common-dir)
Copy-Item (Join-Path $primary '.env') . -ErrorAction SilentlyContinue
dotnet restore
dotnet build
```

## Ports and databases - the two REAL cross-worktree collisions

Files are isolated; machine state is not. Two things actually collide:

**Ports.** `launchSettings.json` pins fixed ports, so two worktrees running the same app
collide on bind. Override per worktree:

```powershell
dotnet run --urls http://localhost:5111
```

Gotchas: environment values set in `launchSettings.json` OVERRIDE the system environment,
so setting `ASPNETCORE_URLS` in the shell silently loses - use `--urls` (command line wins)
or `--no-launch-profile`. `ASPNETCORE_HTTPS_PORT` only configures the HTTPS *redirect*,
not the listening endpoint. Or simply run one app at a time across worktrees.

**Databases.** `(localdb)\MSSQLLocalDB` is per-user machine state: a connection string
with a `Database=` name hits ONE shared database from every worktree. Two worktrees on
divergent EF Core migrations will fight over its schema (EF9's migration lock serializes
concurrent applies; it does not isolate divergent branches). Mitigations, best first:
- Per-worktree database name: `$env:ConnectionStrings__Default = '...Database=myapp_taskx...'`
  for runtime, `dotnet ef database update --connection "<cs>"` for migrations.
- SQLite file inside the worktree (gitignored) for tests/dev.
- A LocalDB instance per worktree: `sqllocaldb create task-x`.

Do NOT put per-worktree values in user secrets - secrets are shared by ALL worktrees of
the repo (same UserSecretsId); changing one changes them all.

## Merging back - two models, pick by repo

**(a) Personal / unprotected repos** (direct push to main allowed) - upstream flow:

```powershell
# from the primary checkout, after reviewing the worktree's diff:
git merge --no-ff task-x        # or: git merge --squash task-x
git push origin main
git worktree remove C:/Repos/myrepo-task-x
git branch -d task-x
```

**(b) Azure DevOps repos with branch policies** (direct push to main is REJECTED -
error TF402455 "you must use a pull request"). Push the task branch and open a PR:

```powershell
git push origin task-x
az repos pr create --source-branch task-x --target-branch main `
  --title "Task X" --draft            # drop --draft when ready
# when ready to merge on policy pass:
az repos pr update --id <id> --auto-complete true
# after completion:
git worktree remove C:/Repos/myrepo-task-x
git branch -d task-x
```

(`az repos pr create` also takes `--squash`, `--delete-source-branch`,
`--required-reviewers`, `--auto-complete` directly.)

How to pick: if `git push origin main` from the primary checkout gets rejected with a
pull-request policy error, you are in model (b) - and worktree branches ARE pushed there.

## Cleanup + gotchas

- **`git worktree remove` failing with access-denied is a Windows file-lock problem,**
  not a git problem - `--force` does NOT bypass OS locks. Fix order: stop the app or
  debugger, close (or unload the solution in) Visual Studio, run
  `dotnet build-server shutdown` (stops MSBuild/Razor/compiler daemons holding bin/obj),
  then remove. `git worktree prune` cleans metadata if the folder was deleted manually.
- `--force` semantics: needed for worktrees with untracked/modified tracked files; twice
  for locked worktrees. Gitignored `bin/`/`obj/` do not count as unclean.
- Uncommitted work in a deleted worktree is GONE. Commit in the worktree early and often;
  commits survive folder deletion in the shared repo.
- Two Visual Studio instances can open the same `.sln` from two worktrees safely - `.vs/`,
  `bin/`, `obj/` are per-worktree and gitignored. VS has no worktree UI; open the worktree
  FOLDER'S solution file. What still collides is runtime state (ports, LocalDB - above).
- Disk and antivirus: each worktree is a full extra checkout that Defender scans on first
  build. Delete merged worktrees promptly; a Dev Drive (Defender performance mode) helps
  if you keep many.
- Long-lived worktrees rot. If a task stalls for days, rebase onto main or restart it.
- One shared stash list, one shared config, one shared refs namespace - worktrees isolate
  files, not git state.
