# Architecture & shared conventions

dev-cycle is one plugin of ten skills that share a small set of conventions.
This document describes what they have in common; each skill's own contract
lives in `docs/skills/<name>.md`.

## Design principle

Skills are **generic engines; user-specific data lives outside the plugin** — in
a per-repo `.claude/dev-cycle.json` or per-user state, never baked into shipped
files. That is what makes the plugin shareable as-is. Shipped templates use
placeholders; real values live in the consuming repo's config.

## The config manifest

Per-repo settings live in `.claude/dev-cycle.json` at the repo root. It is
optional — a skill with no manifest uses documented defaults and says so. See
[configuration.md](configuration.md) for the full schema. Precedence for any
value: explicit command argument → manifest key → documented default.

## Handoff file and progress log

Two shared files carry work across sessions:

- **Handoff file** (`handoffFile`, default `.claude/dev-cycle/next-session.md`) —
  a schema-validated snapshot a fresh session boots from. Written by
  `handoff:save` and by `project-planning`'s split bundles; read by
  `handoff:resume`, worktree-sessions, and capture-workflow. Schema:
  [docs/skills/session-handoff.md](skills/session-handoff.md).
- **Progress log** (`progressFile`, default `.claude/dev-cycle/progress.md`) — an
  append-only running ledger. Written by session-handoff; read by finish-branch
  (staleness check) and capture-workflow.

## Runtime state

- **Per-repo state** lives under `.git/dev-cycle/<skill>/`, resolved via
  `git rev-parse --git-common-dir` so linked worktrees share it. Examples:
  `.git/dev-cycle/review/` (review-gate dedup locks), `.git/dev-cycle/pr-monitor/`
  (pr-monitor watch state), `.git/dev-cycle/session/` (worktree-sessions markers).
- **Per-user state** for scheduled-jobs lives under `~/.claude/dev-cycle/jobs/`
  (job manifests, run history, installed runtime scripts).

## Preauthorized actions

The `preauthorized` array in the manifest is a registry of standing-grant class
names. Before an outward action (push, merge, branch cleanup, committing an
approved artifact), a skill checks this list: if the class is present it performs
the action and reports; otherwise it asks. History rewrites (rebase -i,
filter-repo, force-push to shared branches) are never a valid class. This lets
unattended and semi-attended flows proceed without a prompt for exactly the
actions the user has pre-granted, and nothing more.

## Secret detection

One shared pattern source, `scripts/secret_patterns.grep`, backs every skill that
scans for credentials (review-gate advisories, repo-whitepaper sensitivity sweep,
demo-prep audit). Policy: use gitleaks when installed, fall back to the shared
patterns otherwise. No skill maintains its own divergent list.

## Skill dependency graph

```
worktree-sessions:open ─┐
                        ├─ enters a fresh worktree, may seed from a handoff file
project-planning:split ─┘   (bundles are valid handoff files)

worktree-sessions:close ─→ finish-branch ─→ offers handoff:save
pr-monitor ──────────────→ finish-branch   (pr-monitor never merges directly)

session-handoff ── handoff:save writes the handoff file + progress log
                └─ handoff:resume boots the next session from it
capture-workflow ─ reads handoff file / progress log as extraction sources
review-gate ─────── writes security findings the handoff flow can surface
```

finish-branch is the merge hub (called by worktree-sessions:close and offered by
pr-monitor). session-handoff is the continuity hub. Changing either contract
ripples widest.

## Hook wiring

The plugin ships one hooks manifest, `hooks/hooks.json`, with two entries:

- **PreCompact** → `hooks/session-handoff/handoff-precompact.sh` — writes an
  emergency snapshot beside the handoff file before compaction; always exits 0 so
  it never blocks compaction.
- **PostToolUse** (matcher `Bash`) → `hooks/review-gate/gate.sh hook-posttooluse` —
  the per-commit security-review gate entry point.

Both resolve their script paths via `${CLAUDE_PLUGIN_ROOT}`.

## House rules baked into every skill

1. **One command per Bash call** in interactive/subagent calls — never chain with
   `&&`, `||`, `;`, or `&`. (Shipped script internals are ordinary code, exempt.)
2. **Absolute paths for spawned agents** — subagent prompts state the canonical
   repo root explicitly.
3. **Secrets never in chat** — values come from env names or a secret store, never
   echoed.
4. **Evidence before assertion** — verify against docs/code/live state before
   agreeing with a reviewer, confirming a fix, or patching automation.
5. **Timeouts on every remote call** — long operations run in the background with a
   stall threshold, never silent for minutes.
6. **Artifacts to the repo, not the terminal** — reports, plans, and diagrams are
   files; visual outputs are rendered/screenshotted, never dumped as raw JSON.
7. **Batch open questions** — one question with all pending decisions beats a
   drip-feed.
8. **Scoped writes** — patch only what is proven wrong; log every change and why.

## Optional integrations

Skills detect and use these when installed, and degrade gracefully when not:
superpowers (planning/skill-authoring/worktrees/code-review), commit-commands
(commit/PR helpers), claude-speak (spoken notifications), Cloudflare publishing
skills (whitepaper deploy), frontend-design (visual direction), gitleaks (secret
scanning), and the Playwright MCP (runtime visual verification). None is required.
