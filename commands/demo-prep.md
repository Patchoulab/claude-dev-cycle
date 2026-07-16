---
name: demo-prep
description: Prepare a prototype repo for a stakeholder demo (present / localize / audit / bootstrap)
argument-hint: "[present|localize|audit|bootstrap] [--lang <code>] [--boot-default <code>]"
---
Invoke the dev-cycle demo-prep skill for the current repo with arguments: $ARGUMENTS
Read ${CLAUDE_PLUGIN_ROOT}/skills/demo-prep/SKILL.md and route to the
requested phase; with no arguments run the full sequence
(present → localize → audit).
