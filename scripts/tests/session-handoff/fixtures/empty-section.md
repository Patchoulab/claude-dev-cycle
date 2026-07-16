# Next Session Seed — wave-1-session-handoff
Generated: 2026-07-03 by session-handoff v0.1

## State
- Branch: feat/wave-1 (dirty — 2 modified files: scripts/handoff_lint.py, scripts/tests/session-handoff/fixtures/)
- PR: none
- Gitlink: n/a — no submodules in this repo
- Ledger: .claude/dev-cycle/progress.md → last entry: 2026-07-02 — Task 2 — done
- Failing tests: none
- Task reports this slice: /repo/.superpowers/sdd/task-2-report.md

## Approved decisions
- Python stdlib only for scripts/handoff_lint.py; no third-party dependencies.

## Carry-forward learnings
- handoff_lint.py must exempt lines containing uppercase NEVER from the safety
  scan, otherwise the template's own mandatory prohibition line would trip
  its own linter.

## Next action
Wave 1 Task 4: implement commands/relay/close.md and commands/relay/open.md
per spec 01 §5.6-5.7 — exactly one entry point.

## Verification criteria

## Safety constraints
- Allowed git ops: commit, push to the feature branch, open PR, plus any
  dev-cycle.json preauthorized classes that apply
- NEVER: reset --hard, force-push, clean -f, checkout -- ., branch -D
