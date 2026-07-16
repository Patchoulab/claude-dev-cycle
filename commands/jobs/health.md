---
name: scheduled-jobs:health
description: Run the scheduled-jobs watchdog to flag silent failures, stale artifacts, schedule gaps, launch failures, repeated failures, or jobs that never ran
argument-hint: [job]
---
Run the dev-cycle scheduled-jobs skill's HEALTH procedure.

Read "${CLAUDE_PLUGIN_ROOT}/skills/scheduled-jobs/SKILL.md" and follow the
`/dev-cycle:jobs:health` procedure exactly: run `bin/scheduled-jobs-health.sh`
and relay its findings. Optional job name to scope the check: $ARGUMENTS
