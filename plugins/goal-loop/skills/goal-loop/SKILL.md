---
name: goal-loop
description: Write effective goal contracts for persistent self-checking agent loops (plan -> act -> test -> review -> iterate until a verifiable stop condition) and launch them in Claude Code (/goal) or GitHub Copilot (CLI /autopilot with /goal alias, VS Code Autopilot mode, cloud agent). Use when the user mentions /goal, goal loop, autopilot, a long-running autonomous run, wants a goal prompt drafted, needs a verifiable stop condition, or complains the agent stops too early or drifts on long tasks.
disable-model-invocation: true
---

# Goal Loops (Claude Code + GitHub Copilot)

A goal loop turns a prompt into a **persistent agent** that keeps iterating
plan -> act -> test -> review until a stop condition is met, instead of ending its turn
and waiting for input. It is a **contract enforcer with a verification loop** - NOT a
budget command, a safety boundary, or a "run forever" button.

Native support today:

| Surface | Mechanism |
|---|---|
| Claude Code | `/goal <condition>` - persistent completion condition, checked by a small fast model each turn |
| Copilot CLI | autopilot mode: Shift+Tab or `--autopilot` flag; `/autopilot` + `/goal` slash commands (experimental mode only) |
| VS Code agent mode | Autopilot approval level (default-on in recent VS Code); Advanced Autopilot adds an external completion judge |
| Copilot cloud agent | assign a GitHub issue / `/delegate` - runs remotely, opens a draft PR (GitHub repos ONLY) |

## When to use

Only when ALL three are true:
1. The task is >30 min of mostly mechanical work.
2. There is a **verifiable stop condition** (tests pass, coverage >= X, build green with
   zero warnings).
3. The repo is agent-ready: working build, decent tests, standing instructions present
   (CLAUDE.md / copilot-instructions.md).

Fits: framework/library migrations, coverage lifts, TDD feature builds, refactors guarded
by contract tests, analyzer/warning cleanups, EF model refactors with a green migration
suite. Bad fits: exploratory work, vague "improve this", anything without a "done"
definition, production credentials, destructive shared-infra operations. (The
agent-guardrails plugin keeps catastrophic az/git/disk commands hard-blocked even during
unattended runs - keep it installed.)

## The 5-part contract (every goal needs this)

1. **Objective** - one sentence, one concrete outcome.
2. **Constraints** - what must NOT change (public API, files, libs, conventions).
3. **Validation command** - the exact shell command that proves progress.
4. **Stop condition** - verifiable: "stop when X passes" OR "when further changes need
   human/product input".
5. **Documentation** - one sentence committing the agent to concise, targeted docs for
   every change (new `.md` files or focused updates).

Plus: tell the agent what to read first, and ask for checkpoints with a short progress log.

Template (emit only the contract body - the user adds the slash command themselves):

```
**Objective:** <one-sentence objective>
**Read first:** <files / PLAN.md / work item>
**Constraints:** <what not to change, libs, conventions>
**Validate:** `<exact command>` after each change
**Document:** Write concise, targeted documentation for all changes - new .md files or focused updates to existing docs.
**Checkpoints:** work in checkpoints and log progress briefly
**Stop when:** <verifiable condition>, OR when further changes require human/product input
```

### Example: migration (.NET)

```
**Objective:** Migrate this solution from Newtonsoft.Json to System.Text.Json.
**Read first:** Directory.Packages.props, src/, tests/
**Constraints:** no public API changes; keep custom converters behaviorally identical; no new dependencies
**Validate:** `dotnet build -warnaserror` then `dotnet test` after each change
**Document:** Write concise, targeted documentation for all changes - update existing docs where they exist.
**Checkpoints:** work in checkpoints; log progress briefly
**Stop when:** full test suite passes with zero build warnings, OR when a serialization behavior difference requires a product decision
```

### Example: coverage lift (.NET, coverlet)

```
**Objective:** Raise line coverage in src/Auth/ from ~40% to >=75%.
**Read first:** src/Auth/, tests/Auth.Tests/, CLAUDE.md
**Constraints:** no new dependencies; mirror existing xUnit test style; do not modify production code unless strictly required for testability
**Validate:** `dotnet test /p:CollectCoverage=true /p:Include="[*]MyApp.Auth.*"` (coverlet.msbuild)
**Checkpoints:** work in checkpoints; log the coverage delta each one
**Stop when:** coverage >=75% AND all tests pass, OR when uncovered code needs design changes
```

### Writing rules

- **One objective, one stop condition.** Not a backlog.
- **Documentation is mandatory** - one sentence in every contract.
- **Never instruct the agent to create ADRs** - those need explicit user approval.
- **Forbid reward-hacking explicitly:** "Do not delete, skip, weaken, or narrow tests to
  make the goal pass." Otherwise the agent may game the stop condition.
- **Keep the goal compact.** Long detail goes in a file (`PLAN.md` / `GOAL_BRIEF.md`)
  the goal points to.
- Use **literal strings** for paths, commands, work-item numbers - exact.
- Forbid scope creep explicitly: "Do not refactor unrelated code. Do not add dependencies."
- Tell the agent when to pause: "If <condition>, pause and ask before proceeding."
- Short, vague goals burn tokens for no extra value over a normal prompt.

## Launching - Claude Code

The **contract goes in the prompt; the condition goes in `/goal`**:

1. Send the task message containing the 5-part contract.
2. Set the completion condition: `/goal dotnet test passes with zero build warnings`.
   Claude keeps working across turns until a small fast model confirms the condition.
3. `/goal` alone = status. `/goal clear` kills it. States: active / achieved / cleared.

Headless (scripted): `claude -p "/goal <condition>"` works; add
`--output-format stream-json --verbose` to watch progress, `--continue` / `--resume` to
carry a session forward.

Unattended permissions: prefer `--permission-mode auto` (classifier blocks
destructive/external actions, allows routine work). Never `bypassPermissions` outside an
isolated, no-internet VM. Recurring variants: `/loop` (interval or self-paced re-runs)
and `/schedule` (cloud routines). DIY hard verifier: a `Stop` hook that runs the
validation command and returns `{"decision": "block", "reason": "<what still fails>"}`
until it passes - the loop then cannot end on an unverified claim of success.

## Launching - Copilot CLI

- Interactive: **Shift+Tab** cycles standard / plan / autopilot modes (the GA path).
  The `/autopilot <objective>` and `/goal <objective>` slash commands exist but are
  **experimental-mode only** - without experimental mode enabled they won't appear.
  Autopilot continues until the model judges the task complete, progress is blocked,
  Ctrl+C, or the continue limit is hit.
- Scripted:
  `copilot -p "<contract>" --autopilot --max-autopilot-continues 25 --no-ask-user`
  plus the permission flags you actually need (`--allow-tool ...`); the docs recommend a
  sandbox/container for anything as permissive as `--allow-all`.
- Guardrails: `--max-autopilot-continues` is the infinite-loop guard; a spend ceiling
  for an objective is `/autopilot --max-ai-credits <n>` (pauses when reached; the
  separate `/limits set max-ai-credits` is only a soft PER-RESPONSE limit);
  `/keep-alive on` prevents machine sleep on long runs; the `stayInAutopilot` setting
  controls whether autopilot persists between tasks. Resume later with `copilot --resume`.
- DIY hard verifier: an `agentStop` hook (Claude-compatible alias `Stop`) that returns
  `{"decision": "block", "reason": "..."}` until the validation command passes. Note the
  cap: after 8 consecutive blocks the CLI overrides the hook and ends the turn (the
  payload's `stop_hook_active` lets the hook self-limit) - re-arm longer horizons with
  `copilot --resume` or the `/every` recurring prompt (also experimental-mode only).

## Launching - VS Code agent mode

- Pick **Autopilot** in the approvals/permissions dropdown (Default Approvals / Bypass
  Approvals / Autopilot). Governed by `chat.autopilot.enabled` - default-on in recent
  VS Code Stable. It auto-approves tools, retries on errors, and keeps going until the
  agent signals completion.
- `chat.autopilot.advanced.enabled` (experimental) adds an **external completion judge** -
  a separate model verifies your request is actually complete after each turn. Closest
  thing to a verified stop condition in VS Code.
- Raise `chat.agent.maxRequests` (default 25) or you will babysit "Continue to iterate?"
  prompts on long runs.

## Walk-away runs - Copilot cloud agent (GitHub repos ONLY)

Assign a GitHub issue to Copilot, or `/delegate <task>` from Copilot CLI / VS Code. It
runs in an ephemeral Actions environment, opens a draft PR, and iterates on batched
`@copilot` PR review comments. Hard cap: **59 minutes per session** - scope tasks to fit
or chain sessions via review comments. Customize its environment (SDKs, services) in
`.github/workflows/copilot-setup-steps.yml`.

**Azure DevOps repos are NOT supported** by the cloud agent (Azure Boards can hand work
to it, but the repo must live on GitHub). For ADO work, the walk-away surface is local
Copilot CLI autopilot, or Claude Code `/goal` in a spare terminal.

## When a goal drifts

- **Minor drift:** type a correction - it folds in and continues.
- **Loose objective:** stop it (`/goal clear` in Claude Code; leave autopilot / Ctrl+C in
  Copilot), read the state, re-issue a TIGHTER contract. Do not pile instructions onto a
  vague goal.
- **Bad mess:** kill it, `git status` / `git stash`, meta-prompt a better contract
  (below), restart. Combine with the git-worktree skill: a goal loop inside its own
  worktree cannot damage your main checkout, and a failed run is one
  `git worktree remove` away from gone.

Do not let a drifting loop keep running "to see where it goes" - tokens burn and diffs
compound.

## Meta-prompting trick (highest leverage)

Hand-written goals under-specify. Ask a second session with the codebase loaded to:
(1) inspect the code, (2) surface hidden assumptions/constraints/edge cases, (3) emit the
structured contract block using the template above. Paste that into the real run.
Order-of-magnitude better than writing the contract cold. You can also do it inline:
"Inspect this repo, draft yourself a goal contract with a verifiable stop condition, ask
clarifying questions if the intent is underspecified, then pursue it."

## Operational tips

- **Always review the diff before merging.** Long autonomy means MORE code to validate,
  not less.
- First run: pick a 30-minute scoped task and watch how the loop actually stops before
  trusting it overnight.
- Bake recurring policy into standing instructions so every goal inherits it without
  restating: adversarial self-review before declaring done, an extra QA pass even when
  tests pass, the standard validation command. Claude Code reads **CLAUDE.md** (it does
  NOT read AGENTS.md - import it with a `@AGENTS.md` line if you keep one); Copilot reads
  `.github/copilot-instructions.md` and AGENTS.md.
- Keep permission prompts / sandboxing tight; a goal loop with `--yolo` and no sandbox is
  how unattended mistakes scale.

## Mental model

Stop writing prompts; start writing **specifications with stop conditions**. Spend the
time upfront defining "done" - the run takes care of itself.
