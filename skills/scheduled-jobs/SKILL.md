---
name: scheduled-jobs
description: Use when creating or wiring up a recurring headless Claude job (cron, launchd, scheduled agent), when an existing scheduled job silently stopped producing output or finishes suspiciously fast, when a recurring job re-researches the same items every run, when its report file is overwritten with no history or delivery, or when migrating hand-rolled cron wrappers onto a managed pattern. Triggers: "cron", "scheduled job", "headless", "runs every day", "silent failure", "no-op run", "watchdog", "stale state".
---

# scheduled-jobs

## Overview

Scaffolds and maintains recurring headless Claude jobs as a managed triplet —
state file + wrapper script + guardrailed prompt template — with per-item
staleness so runs skip fresh items, dated diffed reports with notification
delivery, and a watchdog that flags silent failures. Jobs are generic engines;
all domain data lives in each job's own state files.

## When to use

- Turning any recurring chore into an unattended Claude job
- A scheduled job "runs" but its artifacts never change (silent failure)
- A job re-does identical research every run (no state persistence)
- Reports are overwritten and never reach the user
- Retrofitting existing hand-rolled cron wrappers

When NOT to use: interactive same-session polling (use the loop skill);
one-off tasks; cloud-only routines with no local job directory (use the
schedule skill directly).

## Layout

Every job lives at `~/.claude/dev-cycle/jobs/jobs/<name>/`:
`job.json` (manifest) · `state.json` (per-item state, last_verified dates) ·
`run.sh` (wrapper: detect → render → lint → launch → record → diff → notify) ·
`prompt.tmpl.md` · `settings.json` · `reports/` (dated, never overwritten) ·
`runs.jsonl` (one record per attempt, including no-ops and launch failures) ·
`logs/`. Shared runtime in `~/.claude/dev-cycle/jobs/bin/`. The set of
`jobs/*/job.json` IS the registry; there is no central file to corrupt.

## Commands

| Command | Action |
|---|---|
| `/dev-cycle:jobs:new <job>` | Interview (ONE batched AskUserQuestion; a pre-filled answer record skips the questions it already answers), scaffold from `templates/`, lint, wire schedule, offer attended first run. On the machine's FIRST-ever job, also offer (once ever) to schedule the watchdog — daily 08:30, `--notify`; the answer is recorded in `defaults.json` so the question never repeats |
| `/dev-cycle:jobs:health [job]` | Run `bin/scheduled-jobs-health.sh`; flags SILENT_FAILURE, STALE_ARTIFACT, SCHEDULE_GAP, LAUNCH_FAIL, REPEATED_FAILURE, NEVER_RAN |
| `/dev-cycle:jobs:migrate` | Retrofit legacy jobs per `references/migrating-existing-jobs.md` |
| `/dev-cycle:jobs:lint <job>` | Render today's prompt, run all lint rules, launch nothing |
| `/dev-cycle:jobs:list` | Registered jobs with schedule, last run, last status |

## Scheduling backend

launchd (macOS) / cron (Linux) by default. Scheduled cloud agents (schedule
skill) ONLY if the job touches no local files, local credentials, or LAN.
Both current jobs and the watchdog need local disk: launchd.

## Scaffold invariants (every generated job)

1. Detection diffs against `state.json` — a job that finds nothing new and
   nothing stale exits as a LOGGED no-op without launching Claude.
2. Per-item state carries `last_verified`, `status`, `source_url`; the
   rendered prompt embeds ONLY stale/new/failed items plus prior state.
3. Prompt template contains all mandatory clauses (see
   `templates/prompt.tmpl.md` header checklist): role framing, absolute
   paths, numbered steps, status enums, conservative-fallback clause,
   "only patch what's proven wrong", "log every change and why", state
   write-back, dated report + machine summary contract, source-URL evidence.
4. Rendered prompts are linted before launch: no unrendered `{{tokens}}`,
   no dangling separators (the `vercel,bun,` class), referenced input paths
   exist, output parent dirs exist, date substitution equals today.
5. Reports are dated files under `reports/`; the wrapper diffs against the
   previous report and notifies only on material changes or failures.
6. Every attempt appends to `runs.jsonl` — including lint failures and
   `claude` launch failures, the two ways jobs die invisibly.
7. Job settings start from the review-gate unattended recipe; grant
   WebSearch/WebFetch only when the interview says the job researches.

## House rules (binding on generated prompts and this skill's own runs)

One command per Bash call; absolute paths everywhere; secrets never in
prompts (env names / Infisical paths only); evidence before assertion with
conservative fallback when uncertain; timeouts on remote calls; artifacts to
files, not the terminal; batch open questions; scoped writes with change log.

## Common mistakes

| Mistake | Fix |
|---|---|
| Detection that re-finds the same items daily | Persist seen/ignored sets in state.json; diff, don't scan-and-fire |
| Trusting exit code 0 as "it ran" | runs.jsonl records duration + num_turns; health flags <5s or <3 turns |
| Overwriting the report path | Dated `reports/report-YYYY-MM-DD.md`; `latest.md` is a symlink |
| Baking domain data into the prompt template | Template holds procedure; items and knowledge come from state.json at render time |
| Granting broad write access to an unattended job | `job.json.writes_allowed` lists exact patchable paths; prompt repeats them |
