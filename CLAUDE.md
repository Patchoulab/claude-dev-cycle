# CLAUDE.md — working on the dev-cycle plugin

This repo IS the `dev-cycle` Claude Code plugin (and its own marketplace): ten
workflow skills plus their commands, hooks, and scripts. You are editing the
plugin's source, not using it.

## Layout

- `skills/<name>/SKILL.md` (+ `references/`, `templates/`) — the ten skills.
- `commands/**/*.md` — thin `/dev-cycle:...` slash-command entry points.
- `hooks/hooks.json` — the ONE hooks manifest (PreCompact + PostToolUse); scripts live in `hooks/<name>/`.
- `scripts/` — shipped executables; `scripts/tests/<name>/` — test runners + fixtures.
- `docs/` — `architecture.md` (conventions, house rules, dependency graph, hook wiring), `configuration.md` (the `.claude/dev-cycle.json` schema), `skills/<name>.md` (per-skill contracts). Read these before changing a skill's contract.
- `.claude-plugin/` — `plugin.json` (name `dev-cycle`, v1.0.0) and `marketplace.json` (name `dev-cycle-plugins`). Publishing org: `Patchoulab`.

## How to verify (do this before claiming anything works)

- `bash scripts/tests/run_all.sh` — the full suite. It MUST stay green. It is the gate.
- `bash scripts/tests/validate_plugin.sh` — structural checks + the scrub sweeps (also run in CI).
- Prereqs (all expected on PATH): `git`, `gh` (authed), `jq`, `python3`, `pytest`, `node`.

## Hard rules (CI enforces the first two)

1. **No personal literals** — no personal names/handles, homelab hostnames, private repo names, or absolute machine paths anywhere in the tree. `Patchoulab` is the only allowed identity, and only on the manifests, README install lines, and LICENSE. The personal-literal sweep (in `scripts/tests/validate_plugin.sh` and CI) fails the build on any other.
2. **No old vocabulary** — this plugin was renamed from an internal one. Never reintroduce the old metaphor names: forge, land-slice, cron-forge, plan-forge, session-relay, pr-babysit, review-harness, session-lifecycle, skill-smith, or "seed"/"ledger"/"gitlink dance" as user-facing terms. Current names: dev-cycle, finish-branch, scheduled-jobs, project-planning, session-handoff, pr-monitor, review-gate, worktree-sessions, capture-workflow. Config file is `.claude/dev-cycle.json`; per-repo state is `.git/dev-cycle/<name>/`. The old-vocabulary sweep fails the build on any of the old tokens.
3. **Skills are generic engines** — user-specific data lives in `.claude/dev-cycle.json` or per-user state, never baked into shipped files. Templates use placeholders.
4. **Code and tests move in lockstep** — especially `hooks/review-gate/gate.sh` ↔ `scripts/tests/review-gate/test_gate.sh`, and any state-dir path (`.git/dev-cycle/...`) referenced by both a script and its test. Change them together and run the suite.
5. **One `git`/`gh` command per interactive Bash call** — never chain with `&&`, `||`, `;`, `&` in interactive or subagent calls (shipped script internals are exempt). Use absolute paths (`git -C <abs>`), and give any spawned agent the absolute repo root.
6. **Cross-plugin references stay optional** — anything referencing superpowers, commit-commands, claude-speak, codex, cloudflare, frontend-design, or an MCP must be phrased "if installed, else <fallback>". None is a hard dependency.

## When you change the skill set

Update the count and tables in `README.md` and `docs/architecture.md` (both say "ten skills"), add/remove the matching `docs/skills/<name>.md`, and keep `commands/` command stems 1:1 with skill names.

## Cadence

Branch off `main`, keep `run_all.sh` green, and open a PR. Cheap wins: `bash scripts/tests/run_all.sh` after every change; if it fails, fix before moving on.
