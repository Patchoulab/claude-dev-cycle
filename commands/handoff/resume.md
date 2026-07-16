---
name: relay:open
description: Find the freshest session seed, validate it, apply kickoff config, and execute it
argument-hint: [seed path override]
---
Run the dev-cycle session-handoff skill in OPEN mode.

Read "${CLAUDE_PLUGIN_ROOT}/skills/session-handoff/SKILL.md" and follow the OPEN
procedure exactly. If a path is given, skip discovery and use it: $ARGUMENTS
