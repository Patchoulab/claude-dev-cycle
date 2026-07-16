# scheduled-jobs

**Purpose** — Scaffold and operate recurring headless Claude jobs on your own machine: launchd on macOS, cron on Linux. Every job ships as a managed triplet (state file, wrapper script, guardrailed prompt template) wrapped in an anti-silent-failure runtime, so a run that finds nothing new exits as a logged no-op and a run that dies before producing output leaves a record instead of vanishing. A health watchdog audits the fleet, and a migration path retrofits hand-rolled cron or launchd wrappers onto the managed pattern.

## Invocation

| Command | What it does |
|---|---|
| `/dev-cycle:jobs:new <job>` | Interviews you once, scaffolds the job from templates, lints the rendered prompt, wires the schedule, and offers an attended first run. On the machine's first-ever job it also offers (once) to schedule the watchdog. |
| `/dev-cycle:jobs:health [job]` | Runs the watchdog across all jobs (or one) and prints a flag per job. |
| `/dev-cycle:jobs:lint <job>` | Renders today's prompt and runs every lint rule without launching Claude. |
| `/dev-cycle:jobs:list` | Lists registered jobs with schedule, last run, and last status. |
| `/dev-cycle:jobs:migrate` | Retrofits a legacy hand-rolled wrapper onto the managed job pattern. |

## Contract

Every job lives at `~/.claude/dev-cycle/jobs/jobs/<name>/` and owns:

- `job.json` — the manifest (schedule, TTL, allowed writes, notify rules).
- `state.json` — per-item state with `last_verified` dates, plus `ignored` and `seen` buckets for detection memory.
- `run.sh` — the wrapper: detect → render → lint → launch → record → diff → notify.
- `prompt.tmpl.md` and `settings.json` — the prompt template and the job's permission recipe.
- `reports/` — dated report files, a machine summary, a diff against the prior report, and a `latest.md` symlink. Dated files are never overwritten across days.
- `runs.jsonl` — one record per attempt, including no-ops and launch failures.
- `logs/` — per-run logs, rendered prompts, and raw results.

Shared runtime (the render/lint helper, the health script, the notifier) lives once at `~/.claude/dev-cycle/jobs/bin/`. There is no central registry file: the set of `jobs/*/job.json` *is* the registry, so there is nothing central to corrupt.

**job.json** carries `name`, `description`, a `schedule` block (`backend`, calendar fields, `period_hours`, unit path), `ttl_days` (default item staleness), `max_runtime_s` (the wrapper kills Claude past this), `writes_allowed` (the exact paths the job may patch; empty means report-only), `inputs` (checked for existence before launch), `expected_artifacts` (mtime-checked by the watchdog), a `health` block (`min_duration_s`, `min_turns`, `max_gap_factor`), a `notify` block (events and channels), and a `claude` block (model and extra args).

**The run record** in `runs.jsonl` carries `run_id`, start/end timestamps, `duration_s`, `status`, `exit_code`, `num_turns`, and a note. Status is one of `SUCCESS`, `PARTIAL`, `FAILED`, `NOTHING_TO_DO`, `LINT_FAIL`, or `LAUNCH_FAIL`. The `NOTHING_TO_DO` record is the audit trail proving detection ran and found nothing — the exact evidence that is missing when a job fires vacuously and no one notices.

**Watchdog flag classes:**

| Flag | Meaning |
|---|---|
| `OK` | Recent successful run within the expected schedule window. |
| `NEVER_RAN` | Scheduled, but no run record exists. |
| `LAUNCH_FAIL` / `LINT_FAIL` | The two invisible deaths: the runtime never started, or the prompt failed lint before launch. |
| `SILENT_FAILURE` | Exited 0 but finished suspiciously fast (below `min_duration_s` or `min_turns`) — "ran" without doing the work. |
| `STALE_ARTIFACT` | Expected report or summary exists but its mtime is older than the schedule allows. |
| `SCHEDULE_GAP` | The gap since the last run exceeds `period_hours × max_gap_factor`. |
| `REPEATED_FAILURE` | Consecutive failed runs. |

## Config keys

There are no scheduled-jobs keys in `dev-cycle.json` by design — the fleet is discovered from the jobs directory, not from central config. All per-job configuration lives in that job's `job.json` (the fields above). One environment override exists: `SCHEDULED_JOBS_ROOT` relocates the jobs root away from `~/.claude/dev-cycle/jobs/` (useful for testing or a non-default home).

## Prerequisites

- `python3` — renders and lints the prompt.
- `jq` — detection, state math, and run-record writing.
- A scheduler: launchd on macOS, or cron on Linux.
- A headless `claude` CLI on `PATH` (the wrapper's first preflight check fails loudly with `LAUNCH_FAIL` if it is missing).

**Parity note.** The job contract is identical on both platforms; only the schedule unit differs. On macOS the backend is launchd (a `StartCalendarInterval` plist under `~/Library/LaunchAgents/`); on Linux it is a cron entry. Because current jobs and the watchdog all read and write local disk, they must run on a local scheduler — cloud routines are not a substitute here. The most common cross-environment failure is a scheduler PATH or credential environment that differs from your interactive shell, which is exactly what the launch preflight and `LAUNCH_FAIL` flag are there to catch.

## Failure modes & remediation

- **`LAUNCH_FAIL`** — `claude` or `jq` not on the scheduler's PATH, or a missing state/template file. Resolve the absolute PATH in the schedule unit and confirm the runtime is reachable from a non-interactive shell.
- **`LINT_FAIL`** — the rendered prompt has unrendered `{{tokens}}`, dangling separators, a missing input path, or a wrong date. Run `/dev-cycle:jobs:lint <job>` to see the exact rule that failed, then fix the template or inputs.
- **`SILENT_FAILURE`** — the run exited 0 but was too short to have done real work. Inspect the run's log and result; usually the prompt lost its footing or the model returned early. Tighten the template or the item state feeding the render.
- **`STALE_ARTIFACT`** — the job "succeeds" but its report stops advancing. Check that detection is actually surfacing due items and that the run is writing to the dated report path rather than a stale one.
- **`SCHEDULE_GAP`** — the job has not fired on time. Verify the schedule unit is loaded and enabled, and that the machine was awake at the scheduled moment.

## Optional integrations

- **Delivery.** Jobs notify only on material change or failure. Channels are macOS notifications or claude-speak text-to-speech (or both), configured in each job's `notify` block — so a headless run can still reach you audibly or on-screen when something actually changed.
- **Lighter alternatives.** For simple recurrence that needs no local state, no dated report history, and no watchdog, the `loop` skill (same-session interval polling) or the `schedule` skill (cloud routines) are the smaller tools. Reach for scheduled-jobs when a recurring job needs persistent per-item state, non-overwriting report history, and protection against silent failure.
