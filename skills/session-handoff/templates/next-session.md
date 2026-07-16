# Next Session Seed — {{slice_or_wave_name}}
Generated: {{iso8601_utc}} by session-handoff v0.1

## State
- Branch: {{branch}} ({{clean|dirty — summarize uncommitted files}})
- PR: {{url_and_state_or_none}}
- Gitlink: {{bumped|pending|n/a — per submodule}}
- Ledger: {{ledger_path}} → last entry: {{last_ledger_heading}}
- Failing tests: {{name — why it fails, or "none"}}
- Task reports this slice: {{absolute_paths_or_none}}

## Approved decisions
- {{decision already made this session — do NOT re-litigate}}

## Carry-forward learnings
- {{gotcha discovered this session that the next session must know}}

## Next action
{{Wave X task Y: one unambiguous entry point — exactly one}}

## Verification criteria
- {{how the next session proves it did the job}}

## Safety constraints
- Allowed git ops: commit, push to the feature branch, open PR{{, plus any
  dev-cycle.json preauthorized classes that apply}}
- NEVER: reset --hard, force-push, clean -f, checkout -- ., branch -D
