---
name: relay:close
description: Distill this session into a schema-valid next-session seed and update the progress ledger
argument-hint: [slice-or-wave label]
---
Run the dev-cycle session-handoff skill in CLOSE mode.

Read "${CLAUDE_PLUGIN_ROOT}/skills/session-handoff/SKILL.md" and follow the CLOSE
procedure exactly. Optional slice/wave label for the seed title and ledger
entry: $ARGUMENTS
