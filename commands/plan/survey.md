---
name: project-planning:survey
description: Fan out over configured project roots and memory dirs, diff findings against the roadmap, and refresh it — "what should we work on next", "survey my projects", "refresh the roadmap"
---
Run the dev-cycle project-planning skill's SURVEY procedure.

Read "${CLAUDE_PLUGIN_ROOT}/skills/project-planning/SKILL.md" and follow the
Mode: survey section exactly: fan out one read-only subagent per cluster,
diff synthesis against the roadmap, batch decisions into one
AskUserQuestion, then rewrite and commit the roadmap. Arguments (if any):
$ARGUMENTS
