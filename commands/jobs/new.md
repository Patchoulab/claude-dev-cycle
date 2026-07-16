---
name: scheduled-jobs:new
description: Scaffold a new recurring headless Claude job — interview, wire from templates, lint, schedule, and offer an attended first run
argument-hint: <job-name>
---
Run the dev-cycle scheduled-jobs skill's NEW procedure.

Read "${CLAUDE_PLUGIN_ROOT}/skills/scheduled-jobs/SKILL.md" and follow the
`/dev-cycle:jobs:new` procedure exactly: interview, scaffold from
`templates/`, lint, wire the schedule, and offer an attended first run.
Job name (and any pre-filled answers) come from: $ARGUMENTS
