---
name: worktree-sessions
description: Use when starting or ending a worktree-isolated work session — "start a worktree session", "open a session for the next slice", "start working on X in a worktree", or to close out — "close the session", "wrap up and merge", "land this and clean up", "close out and sync". open decides a branch name (from a session-handoff seed or live intent) and enters a fresh worktree; close lands the PR via finish-branch, tears the worktree down, and returns to a synced main.
---

# Session Lifecycle

Worktree-per-session bookends. `open` enters an isolated worktree so one
session's work never touches another's; `close` lands the PR and tears the
worktree down. Both reuse existing skills — this skill owns only the worktree
setup/teardown and the order things happen in.

Read `.claude/dev-cycle.json` at the repo root first (shared keys: `handoffFile`
default `.claude/dev-cycle/next-session.md`, `canonicalRoot`,
`preauthorized`, `mergeStrategy`). No dev-cycle.json → defaults, and say so.

## House rules (non-negotiable)

- One command per Bash call; never chain with `&&`, `||`, `;`, `&`.
- Absolute paths everywhere, including subagent prompts.
- Evidence before assertion: verify PR/merge/worktree state; never assume.
- NEVER `reset --hard` or `push --force`. Teardown is `ExitWorktree(remove)`,
  never a manual force-delete of unmerged work.
- Scoped writes: touch only the worktree, the marker, and (seeded) the seed.

## OPEN procedure (/dev-cycle:session:open)

1. **Preflight (read-only).** Confirm a git repo. Confirm NOT already inside a
   worktree (a session already in one can't nest a new one) — check with
   `"${CLAUDE_PLUGIN_ROOT}/scripts/git_worktree_check.sh"` (exit 0 = already in
   one) and stop if so: "Already in a worktree session; close it first." A
   dirty root working tree is fine and is left untouched — `fresh` builds a
   clean worktree off origin.
2. **Start mode.** Locate the seed at dev-cycle.json `handoffFile`. Present →
   `startedFrom: seed`. Absent → `startedFrom: live`; ask ONE line: "What's
   this session about?" An explicit name argument overrides derivation but
   still records the correct `startedFrom`.
3. **Derive the name.** Seeded or live, get the slug from
   `"${CLAUDE_PLUGIN_ROOT}/scripts/session_slug.py" <handoffFile>` (seeded) or
   `... --string "<your one-liner>"` (live). Confirm a live-derived name back
   before creating anything. Name collision with an existing branch/worktree →
   offer a suffix or ask.
4. **Enter.** `EnterWorktree(name=<slug>)`, default `baseRef: fresh` (branches
   from origin/<default-branch>; immune to a stale local main). Stacked work
   that genuinely needs `baseRef: head` is an explicit opt-in, not default.
   origin unreachable → report; offer `head` with a stale-base warning.
5. **Write the marker** with
   `"${CLAUDE_PLUGIN_ROOT}/scripts/session_marker.sh" write <slug> '<json>'`
   (schema in references/marker-schema.md). It lands under the git-common-dir,
   shared across worktrees, so `close` can read it later.
6. **Seeded → hand off.** The seed lives under `.superpowers/` (gitignored),
   so it does NOT exist in a fresh worktree. COPY it from the root path into
   the worktree's `handoffFile` path, THEN invoke `session-handoff` OPEN, which
   validates (handoff_lint), cross-checks live state, applies kickoff config, and
   executes the Next action. Live → announce the branch and begin; no copy.

## CLOSE procedure (/dev-cycle:session:close)

Runs inside the worktree, in the SAME session that opened it.

1. **Read the marker.** `git branch --show-current` → read with
   `"${CLAUDE_PLUGIN_ROOT}/scripts/session_marker.sh" read <slug>`. Missing →
   treat as freelance, say so ("no marker — closing as freelance").
2. **Guard uncommitted work.** `git status --porcelain` in the worktree. Any
   uncommitted change → STOP, list it, ask (commit into a follow-up, or
   explicit discard). The merged-proof below authorizes discarding MERGED
   COMMITS only, never live working-tree edits.
3. **Land.** Invoke `/dev-cycle:finish-branch` (Skill tool). It runs preflight →
   merge → (gitlink, or silently skipped in plain-repo mode) → verification,
   and — detecting it is inside a linked worktree — merges WITHOUT
   `--delete-branch` and SKIPS its own Phase 6 hygiene, delegating teardown to
   us. If finish-branch preflight STOPS (no PR, CHANGES_REQUESTED, conflicts, red
   checks): ABORT close, leave the worktree fully intact, relay the finding
   (usually "back to pr-monitor"). Teardown is strictly downstream of a
   completed merge.
   finish-branch ends with a Phase 7 offer to run `/dev-cycle:handoff:save` — DECLINE it
   here; the seed limb is owned by this skill and runs at ROOT in step 7. Running
   it now, inside the worktree, writes the seed into the gitignored `.superpowers/`
   that step 5 then deletes.
   **Submodule-worktree guard:** if this worktree belongs to a SUBMODULE
   (`git rev-parse --git-common-dir` contains `/.git/modules/`), finish-branch's
   Phase 0 will NOT recognize submodule mode from a worktree path — it drops to
   plain-repo mode and SKIPS the parent gitlink bump (Phases 3-4), leaving the
   parent repo pointing at the OLD submodule SHA after merge. Do NOT proceed
   silently: STOP and have the user land from the submodule's own checkout (not a
   worktree), or bump the parent gitlink manually afterward. Known limitation —
   spec 11 §9.
4. **Merged-proof.** `gh pr view --json state` MUST be `MERGED`. This proof is
   what makes the next step safe. Not MERGED → stop and report; never tear down.
5. **Re-guard, then tear down.** finish-branch's Phase 5 can AUTO-FIX stale
   ledger/README/structure pointers AFTER the merge, leaving NEW uncommitted
   changes the step-2 guard never saw. Re-run `git status --porcelain`:
   non-empty → those post-merge fixes are NOT in the merged PR and
   `discard_changes` would silently delete them, so STOP, surface them, and
   handle (commit to a follow-up / open an issue) before proceeding. Only once
   the tree is clean (or the user explicitly authorizes discarding these specific
   changes): `ExitWorktree(remove, discard_changes: true)`. The step-4 proof
   justifies `discard_changes` for the branch's MERGED commits — never for
   finish-branch's post-merge working-tree fixes. Session returns to root; worktree
   + local branch removed.
   - If `ExitWorktree` reports no active worktree session (this session did not
     create the worktree — e.g. a crash-restart that `cd`'d in by hand), FALL
     BACK per references/crash-recovery.md: from root, `git worktree remove
     <path>` then delete the branch, same merged-proof gate.
6. **Sync root.** `ExitWorktree` returns the session to root ON THE BRANCH root
   had at OPEN, which may NOT be the default (OPEN allows starting from any root
   state). Get on the default first: `git -C <root> rev-parse --abbrev-ref HEAD`;
   if it is not `<default>`, `git -C <root> checkout <default>` — and if a dirty
   tree blocks the switch, STOP and report rather than fast-forwarding the wrong
   branch. Then `git pull --ff-only origin <default>`, then `git fetch --prune
   origin`.
7. **Seed limb (only if `startedFrom: seed`).** Invoke `session-handoff` CLOSE
   HERE, at root, AFTER teardown — deliberately. Run inside the worktree it
   would write the seed into the worktree's gitignored `.superpowers/` and step
   5 would delete it. At root the next seed lands where the next session's OPEN
   will find it; the session's conversation context is intact regardless of cwd.
8. **Report.** Landed PR, sync state, worktree removed, seed written (or
   "freelance — no seed"). Delete the marker with
   `"${CLAUDE_PLUGIN_ROOT}/scripts/session_marker.sh" delete <slug>`.

## Symmetry (why the seed moves twice)

The seed is gitignored, so it lives outside git, only in whatever working copy
wrote it. OPEN copies it INTO the worktree (so relay:open can run there); CLOSE
writes the next one AT ROOT after the worktree is gone (so it survives). Same
gitignore fact, opposite directions.

## Red flags — stop and re-read

- About to `ExitWorktree(remove)` before confirming `gh state == MERGED`.
- About to `discard_changes` with uncommitted edits in the tree (step 2 guard).
- About to run relay:close INSIDE the worktree (its seed gets deleted).
- close aborted by finish-branch preflight, but you tore the worktree down anyway.
- Running full finish-branch in a worktree without the worktree-aware skip → it
  face-plants at `checkout main`.
- Tearing down a SUBMODULE worktree — finish-branch can't bump the parent gitlink
  from a worktree path (step 3 guard); land from the submodule checkout instead.
- `discard_changes` while finish-branch left post-merge ledger/README fixes
  uncommitted (step 5 re-guard) — they are not in the merged PR.
- CLOSE syncing while root is on a non-default branch (step 6) — get on
  `<default>` first, never ff the wrong branch.
