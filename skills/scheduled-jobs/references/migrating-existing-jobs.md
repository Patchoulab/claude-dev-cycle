# Migration playbook

Retrofits an existing hand-rolled cron/launchd job onto the managed
scheduled-jobs pattern. Core invariant: **the job's existing domain files
(registries, update scripts, data the job reads or writes) stay exactly where
they are and remain the source of truth**; scheduled-jobs state only
*references* them and adds the bookkeeping they lack. Nothing is deleted until
the final step.

Apply these steps per legacy job.

1. **Inventory (read-only).** Locate the existing wrapper scripts and schedule
   units: `crontab -l`, and on macOS `~/Library/LaunchAgents/*.plist` (grep for
   the job's keywords). Read the prompt/command templates out of the wrappers.
   Capture `launchctl print` (or the crontab line) for each unit. Save
   everything to `~/.claude/dev-cycle/jobs/migration-backup-<date>/` before
   touching anything.
2. **Diagnose the silent-failure cause** while the evidence exists: run the
   wrapper once by hand and once via the scheduler (`launchctl kickstart`, or
   wait for a cron fire); compare. Record the finding (common culprits: PATH or
   credential environment differing under the scheduler, or a wrapper
   conditional short-circuiting).
3. **Scaffold the managed job** with `/dev-cycle:jobs:new` (non-interactive: a
   pre-filled answer record derived from the legacy wrapper). Carry over the
   schedule, the detection/due logic, and the set of files the job is allowed
   to write. Port the legacy prompt's procedure verbatim into the template's
   `{{PER_ITEM_PROCEDURE}}` / `{{REMEDIATION_STEP}}` slots — the template's
   mandatory clauses already supply the anti-silent-failure guardrails.
4. **Seed state.** Populate the new job's `state.json` from the legacy job's
   current reality so the first managed run is a true no-op unless there is
   genuinely new work: carry over any "already seen / already handled" sets and
   ignore lists verbatim. For TTL jobs, seed each item `status: "UNKNOWN"`,
   `last_verified: null` so the first run researches everything once and
   thereafter only revisits stale/failed items.
5. **Preserve report history.** Copy the legacy job's last report into the new
   job's `reports/` as the diff baseline and point `reports/latest.md` at it.
   Leave a symlink at the legacy report path → the new `reports/latest.md` so
   any legacy reader keeps working.
6. **Cut over.** Remove the legacy schedule unit (`launchctl bootout` or edit
   the crontab); install the new managed unit (with a resolved absolute PATH).
   Run the new job once attended; confirm `runs.jsonl` shows a real-duration
   run. Run `/dev-cycle:jobs:health` — the job must be `OK`.
7. **Decommission after soak.** Rename legacy wrappers to `*.migrated-<date>.bak`.
   After several clean days of `runs.jsonl` plus one clean scheduled watchdog
   cycle, delete the `.bak` files and legacy schedule units. Keep the backup
   dir from step 1 permanently.

Acceptance for a migration: the job's domain files are byte-identical before
and after (except changes made by real findings); the first managed run does
the full work once and a subsequent run within TTL logs `NOTHING_TO_DO`; the
job no longer launches a Claude session on days with no new work; and a
deliberately induced launch failure (e.g. temporarily renaming `claude`)
produces a `LAUNCH_FAIL` record and a notification within one scheduled cycle.
