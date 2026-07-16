---
name: scheduled-jobs:migrate
description: Retrofit legacy hand-rolled cron or launchd wrappers onto the managed scheduled-jobs job pattern
---
Run the dev-cycle scheduled-jobs skill's MIGRATE procedure.

Read "${CLAUDE_PLUGIN_ROOT}/skills/scheduled-jobs/SKILL.md" and follow the
`/dev-cycle:jobs:migrate` procedure exactly, per
`references/migrating-existing-jobs.md`. $ARGUMENTS is unused; migrate
always retrofits the full legacy set per the playbook.
