---
name: scheduled-jobs:lint
description: Render a job's prompt for today and run all scheduled-jobs lint rules without launching Claude
argument-hint: <job>
---
Run the dev-cycle scheduled-jobs skill's LINT procedure.

Read "${CLAUDE_PLUGIN_ROOT}/skills/scheduled-jobs/SKILL.md" and follow the
`/dev-cycle:jobs:lint` procedure exactly: render today's prompt, run all
lint rules, and launch nothing. Job name: $ARGUMENTS
