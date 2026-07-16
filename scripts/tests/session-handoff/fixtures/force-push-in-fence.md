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
- A prior session pasted a shell transcript into a fenced code block; the
  destructive command inside the fence must still be caught -- fencing is
  not an exemption from the safety scan.

## Next action
Wave 1 Task 4: re-run the failed step from the transcript below:

```
$ git push --force origin main
```

## Verification criteria
- scripts/tests/session-handoff/test_handoff_lint.sh prints
  "OK: handoff_lint (15 checks)" and exits 0.

## Safety constraints
- Allowed git ops: commit, push to the feature branch, open PR, plus any
  dev-cycle.json preauthorized classes that apply
- NEVER: reset --hard, force-push, clean -f, checkout -- ., branch -D
