---
name: demo-prep:bootstrap
description: Create a new GitHub repo for this project (README, CLAUDE.md, .gitignore, first push to main)
argument-hint: "[repo-name] [--public]"
---
Invoke the dev-cycle demo-prep skill, bootstrap phase, for the current
directory with arguments: $ARGUMENTS
Read ${CLAUDE_PLUGIN_ROOT}/skills/demo-prep/SKILL.md then
${CLAUDE_PLUGIN_ROOT}/skills/demo-prep/references/bootstrap.md.
