# worktree-sessions

**Purpose** — Worktree-per-session bookends for the dev-cycle plugin. `open` enters a fresh git worktree on a branch named from a handoff file or from your live intent, so one session's work never touches another's. `close` finishes the branch through finish-branch, tears the worktree down, and returns you to a synced main.

## Invocation

- `/dev-cycle:session:open` — start an isolated session.
- `/dev-cycle:session:close` — land the work and clean up, from the same session that opened it.

## Contract

**open** decides a branch name, then builds around it:

1. Preflight (read-only): confirm a git repo, and confirm you are not already inside a worktree (sessions do not nest). A dirty root working tree is fine and is left untouched, because the new worktree branches clean off origin.
2. Pick the start mode. If a handoff file exists at the configured path, the session is handoff-seeded; otherwise it is live and you answer one line about what the session is for. An explicit name argument overrides the derived slug but still records how the session started.
3. Derive the branch name (the slug) from the handoff file or from your one-liner. Live-derived names are confirmed back before anything is created; a collision offers a suffix.
4. Enter the worktree, by default branching from the origin default branch so a stale local main can't taint it. Stacked work off the current head is an explicit opt-in.
5. Write the session marker under `.git/dev-cycle/session/` (see below).
6. If seeded, copy the handoff file into the worktree and run session-handoff at open, which validates it, cross-checks live state, applies kickoff config, and executes the next action. If live, announce the branch and begin.

**close** runs inside the worktree:

1. Read the marker to recover the slug and start mode. A missing marker is not an error — close proceeds as freelance.
2. Guard uncommitted work: any pending edit stops close so you decide to commit or explicitly discard.
3. Run finish-branch (via the Skill tool). Detecting it is inside a linked worktree, finish-branch merges without deleting the branch and skips its own teardown, delegating that to close. If finish-branch's preflight stops (no PR, changes requested, conflicts, red checks), close aborts and leaves the worktree fully intact.
4. Require merged-proof: the PR state must read `MERGED` before anything is removed.
5. Re-guard the tree (finish-branch may auto-fix pointers after the merge, creating new uncommitted changes), then tear the worktree and its local branch down.
6. Sync the root: get onto the default branch, fast-forward pull, then prune remotes.
7. If the session was handoff-seeded, run session-handoff at close **at the root** (after teardown) so the next handoff file lands where the next open will find it, not inside the deleted worktree.
8. Report and delete the marker.

**Crash recovery.** The marker lives under the shared git-common-dir, so it survives a crash and restart. If you restart and step into the worktree by hand, the harness teardown is a no-op because it did not create that worktree; tear it down manually from the root with `git worktree remove` and a branch delete, under the same clean-tree and merged-proof gates.

## The session marker

Written by open, read and deleted by close. It is resolved via the git-common-dir, so it is shared across worktrees and can never be committed.

| Field | Meaning |
| --- | --- |
| `branch` | The worktree branch (equals the derived slug). |
| `worktreePath` | Absolute path the worktree was created at. |
| `startedFrom` | `seed` or `live` — the one bit close reads to gate the handoff limb. |
| `seedPath` | Absolute path of the handoff file consumed (seeded only; `null` for live). |
| `sliceLabel` | Human label from the handoff header or the live one-liner. |
| `openedAt` | Epoch seconds at open time. |

## Config keys

Read from `.claude/dev-cycle.json` at the repo root; missing file means defaults (and the skill says so).

| Key | Role |
| --- | --- |
| `canonicalRoot` | Absolute path of the repo root to operate from. |
| `submodules[]` | Submodules that need special handling at land time. |
| `handoffFile` | Path to the handoff file that seeds open and receives the next seed at close. |
| `kickoff` | Config applied by session-handoff when opening from a handoff file. |
| `preauthorized[]` | Commands allowed to run without an extra prompt. |

## Prerequisites

- Git with worktree support.
- The `gh` CLI, used indirectly through finish-branch to merge and verify the PR.
- The harness `EnterWorktree` / `ExitWorktree` tools when available; the manual `git worktree` path is the fallback.

## Failure modes and remediation

- **Stale or orphaned marker after a crash.** A restarted session that steps into the worktree by hand does not own it, so harness teardown no-ops. Remove the worktree and branch manually from the root under the clean-tree and merged-proof gates, then finish the root sync.
- **Submodule worktree at close.** finish-branch cannot recognize submodule mode from a worktree path, so it drops to plain-repo mode and skips the parent gitlink bump, leaving the parent pointing at the old submodule SHA. Do not proceed silently: land from the submodule's own checkout, or bump the parent gitlink manually afterward.
- **Dirty worktree at close.** Uncommitted edits stop close before any teardown. Commit them into a follow-up or explicitly discard; the merged-proof authorizes discarding merged commits only, never live working-tree edits.
- **Post-merge fixes left uncommitted.** finish-branch may rewrite ledger or README pointers after the merge. Those are not in the merged PR, so close re-guards and stops rather than discarding them; commit or open an issue before teardown.
- **finish-branch preflight aborts.** No PR, changes requested, conflicts, or red checks abort close and leave the worktree intact. Address the finding (usually back to PR monitoring), then re-run close.

## Optional integrations

- **finish-branch** owns the merge, submodule pointer update, and verification; worktree-sessions only sequences it and handles teardown.
- **session-handoff** provides the handoff file at open and writes the next one at close.
- **superpowers:using-git-worktrees** or plain `git worktree` back the worktree setup and teardown when the harness tools are unavailable.
