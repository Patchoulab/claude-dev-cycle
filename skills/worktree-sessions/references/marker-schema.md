# Session marker schema

Path: `<git-common-dir>/dev-cycle/session/<slug>.json` (resolved via
`git rev-parse --git-common-dir`, so it is shared across worktrees and can
never be committed). Written by OPEN, read by CLOSE, deleted by CLOSE.

```json
{
  "branch": "feat/cron-health",
  "worktreePath": "/abs/.claude/worktrees/feat/cron-health",
  "startedFrom": "seed",
  "seedPath": "/abs/.claude/dev-cycle/next-session.md",
  "sliceLabel": "Wave C — cron health",
  "openedAt": 1751600000
}
```

- `branch` — the worktree branch (= the slug from `session_slug.py`).
- `worktreePath` — absolute path `EnterWorktree` reported.
- `startedFrom` — `seed` or `live`; the single bit CLOSE reads to gate the
  seed limb.
- `seedPath` — absolute path of the seed OPEN consumed (seeded only; `null`
  for live).
- `sliceLabel` — human label from the seed header (seeded) or the one-liner.
- `openedAt` — epoch seconds (from a `date +%s` at open time).

A missing marker at CLOSE is NOT an error: CLOSE proceeds as freelance.
