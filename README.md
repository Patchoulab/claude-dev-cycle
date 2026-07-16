# dev-cycle

Development-cycle workflow skills for Claude Code, distilled from real session
history. Ten skills covering the loop a change travels through: plan it, open an
isolated session, gate every commit with a security review, watch the PR, merge
and sync, hand off to the next session, and capture what worked into something
reusable — plus scheduled headless jobs, whitepaper sites, and demo prep.

## Skills

| Skill | Invocation | Purpose |
|---|---|---|
| session-handoff | `/dev-cycle:handoff:save`, `/dev-cycle:handoff:resume` | Carry work across sessions with a schema-validated handoff file, a progress log, and a PreCompact emergency snapshot |
| finish-branch | `/dev-cycle:finish-branch` | Close out a branch: merge the PR, update the submodule pointer, run a verification sweep, sync main, clean up |
| review-gate | hook-driven | Hardened unattended per-commit security review: triage, dedup, submodule-aware, permission-preseeded |
| pr-monitor | `/dev-cycle:pr-monitor` | Watch a PR for a time window: triage comments, reply, push fixes, re-arm the watch, report on close |
| scheduled-jobs | `/dev-cycle:jobs:new`, `:health`, `:migrate`, `:lint`, `:list` | Scaffold and operate recurring headless Claude jobs (cron/launchd) with an anti-silent-failure wrapper and watchdog |
| project-planning | `/dev-cycle:plan:survey`, `:write`, `:split` | Portfolio survey, executor-targeted planning, and splitting a plan into bundles for parallel worktree sessions |
| repo-whitepaper | `/dev-cycle:repo-whitepaper` | Turn a repo's markdown corpus into a dark, editorial, interactive narrative site — verified live before it's called done |
| demo-prep | `/dev-cycle:demo-prep`, `/dev-cycle:demo-prep:new-repo` | In-app presentation layer, localization with key-hygiene enforcement, pre-demo ship audit, and new-repo bootstrap |
| capture-workflow | `/dev-cycle:capture-workflow` | Turn a completed session into the right reusable artifact — command, skill, playbook, or scheduled job — literals parameterized |
| worktree-sessions | `/dev-cycle:session:open`, `/dev-cycle:session:close` | Worktree-per-session bookends: open enters a fresh worktree; close finishes the branch and returns to a synced main |

## Install

This repo ships its own marketplace manifest (`.claude-plugin/marketplace.json`)
at its root, so the GitHub repo is itself a valid marketplace source:

```
/plugin marketplace add Patchoulab/claude-dev-cycle
/plugin install dev-cycle@dev-cycle-plugins
```

`dev-cycle` is the plugin name (`plugin.json`); `dev-cycle-plugins` is the
marketplace name (`marketplace.json`). Restart (or run `/doctor`) to confirm all
ten skills and their commands registered.

A local clone is also a valid marketplace source:

```
/plugin marketplace add /absolute/path/to/claude-dev-cycle
/plugin install dev-cycle@dev-cycle-plugins
```

## Quickstart

Most skills read per-repo settings from `.claude/dev-cycle.json`. It is optional —
every skill falls back to documented defaults and tells you when it does. See
[docs/configuration.md](docs/configuration.md) for the full schema.

## Prerequisites

- `git` and the `gh` CLI (authenticated) — the PR/merge stack depends on it
- `python3` and `jq` — used by the shell/Python helpers
- `node` — only for demo-prep's localization parity check
- launchd (macOS) or cron (Linux) — only for scheduled-jobs

## Documentation

- [docs/architecture.md](docs/architecture.md) — shared conventions: config manifest, handoff/progress files, runtime state, hook wiring
- [docs/configuration.md](docs/configuration.md) — the full `.claude/dev-cycle.json` schema
- `docs/skills/<name>.md` — per-skill contract, config keys, prerequisites, failure modes

## License

MIT — see [LICENSE](LICENSE).
