# Crash recovery — worktree not owned by this session

`ExitWorktree(remove)` only removes a worktree that `EnterWorktree` created in
THIS session. If a session crashed and you restarted Claude and `cd`'d into the
worktree by hand, `ExitWorktree` is a no-op ("no worktree session active"). The
worktree is real but unowned. Tear it down manually — same safety gates as the
native path.

Preconditions (identical to CLOSE steps 2 & 4):
1. `git status --porcelain` in the worktree is empty (no uncommitted edits).
2. `gh pr view --json state` is `MERGED` (merged-proof).

Then, from the repo ROOT (never from inside the worktree you are removing):

1. `git -C <root> worktree remove <worktreePath>` — refuses if the worktree is
   dirty; only reached after the clean check above. Add `--force` ONLY when the
   sole reason is the (already-merged) branch being checked out, never to
   discard uncommitted work.
2. `git -C <root> branch -d <branch>` — the merged branch. If `-d` refuses
   after a squash merge, confirm the PR is MERGED and `git -C <root> cherry
   <default> <branch>` shows no `+` lines, then `-D` with a logged reason.
3. `git -C <root> worktree prune` — clear the stale administrative entry.
4. Resume CLOSE at step 6 (root sync).

Never `reset --hard` or `push --force` anywhere in this path.
