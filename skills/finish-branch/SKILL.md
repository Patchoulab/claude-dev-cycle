---
name: finish-branch
description: Use when a finished branch's PR is ready to merge and the session must end clean — user says "merge the PR", "update the submodule pointer", "finish the branch", "close out this branch", "switch to main and sync", or asks for end-of-session branch cleanup, in repos with git submodules or plain repos.
---

# Finish Branch

## Overview

Runs the full branch close-out in order: preflight → merge → submodule sync →
submodule pointer update → verification sweep → main sync → branch cleanup → offer
/dev-cycle:handoff:save. Submodule layout comes from `.claude/dev-cycle.json`; with no
`submodules` entry, phases 3–4 and the submodule checks skip silently (plain-repo
mode). Every phase verifies before asserting; nothing destructive, ever.

**Hard rules (from the user's house rules):**
- ONE git/gh command per Bash call. Never `&&`, `||`, `&`.
- Absolute paths everywhere; `git -C <abs-path>` instead of cd.
- Every `gh` call gets a Bash timeout (30000 ms default; polls in background).
- NEVER `reset --hard`, never `push --force`, never `branch -D` without the
  unsaved-work proof in Phase 6.

## Phase 0 — Load config

1. `git rev-parse --show-toplevel` from cwd.
2. Read `<canonicalRoot>/.claude/dev-cycle.json` if present. Extract: `canonicalRoot`,
   `submodules[]`, `defaultBranch` per submodule, `structureChecker`, `progressFile`,
   `preauthorized[]`, `botsToIgnore[]`, `mergeStrategy` (default `merge`).
3. Decide mode: if cwd's toplevel matches a `submodules[].path` under
   `canonicalRoot`, work = that submodule, parent = canonicalRoot. If
   `submodules` is absent/empty → plain-repo mode: run phases 1–2, 5 (docs/ledger
   + structureChecker checks only), 6, 7.

## Phase 1 — Preflight (read-only; abort here costs nothing)

1. `gh pr view --json number,state,url,mergeable,mergeStateStatus,reviewDecision,headRefName,baseRefName`
   - No PR → stop; offer commit-commands:commit-push-pr if that plugin is installed, else `gh pr create`. finish-branch never creates PRs.
   - state ≠ OPEN → report (already merged? closed?) and stop.
2. Unresolved review threads via GraphQL (`reviewThreads(first:100){nodes{isResolved
   comments(first:1){nodes{author{login}}}}}`); drop threads authored by
   `botsToIgnore`. Any unresolved → STOP and offer pr-monitor. Do not triage here.
3. Review state: `reviewDecision` must be APPROVED or empty (no required reviews).
   CHANGES_REQUESTED → stop, offer pr-monitor.
4. `mergeable`:
   - CONFLICTING → report conflicting state, offer `gh pr update-branch <n>`
     (one retry of preflight after it lands), else hand back. Never resolve here.
   - mergeStateStatus BLOCKED/UNSTABLE (checks pending/failing) → offer:
     background poll until green (10-min stall threshold) / pr-monitor / stop.

## Phase 2 — Merge

- If `preauthorized` contains `merge-pr-after-green-review` AND Phase 1 was fully
  green: merge without asking, report after. Otherwise ask once (single question,
  not a drip-feed).
- `gh pr merge <n> --<mergeStrategy> --delete-branch`
  **Worktree mode** (`"${CLAUDE_PLUGIN_ROOT}/scripts/git_worktree_check.sh"` exits 0 — cwd is a linked worktree): OMIT `--delete-branch` (git cannot drop a branch checked out in a live worktree; the caller's `ExitWorktree(remove)` removes the LOCAL branch). But `ExitWorktree` never touches the remote, so to match the non-worktree path's `--delete-branch` (which deletes local AND remote), delete the remote head branch explicitly after the merge: `gh pr merge <n> --<mergeStrategy>`, then `git push origin --delete <headRefName>`. Skip the explicit remote delete only when the repo auto-deletes merged head branches.
- Failure: re-run `gh pr view --json mergeable,mergeStateStatus`, report the exact
  blocker (protection rule, new push, check regression). One `update-branch` retry
  max, then stop with findings.

## Phase 3 — Submodule side (skip in plain-repo mode)

All commands `git -C <abs-submodule-path>`:
1. `status --porcelain` → dirty? STOP. List files; route to commit-commands:commit (or a plain `git commit` if that plugin isn't installed).
   Never commit user work here.
2. `checkout <defaultBranch>` then `pull --ff-only origin <defaultBranch>`
   (picks up the merge). ff-only fails → `fetch origin` + report divergence; never
   reset.
3. Prove pushed: `rev-parse HEAD` == `rev-parse origin/<defaultBranch>` after a
   fresh `fetch origin`. Mismatch → `push origin <defaultBranch>` (see
   references/failure-remediation.md on rejection).

## Phase 4 — Gitlink bump (skip in plain-repo mode)

All commands `git -C <canonicalRoot>`:
1. `submodule status <path>` — recorded SHA vs submodule HEAD. Equal → report
   "gitlink already current", continue to Phase 5.
2. Stage ONLY the gitlink: `add <path>` (scoped writes — nothing else rides along).
3. `commit -m "chore(submodule): bump <name> to <shortSHA> (PR #<n>: <title>)"`
4. `push origin <parentBranch>`. Non-fast-forward → `pull --rebase origin
   <parentBranch>` once, re-push once. Still failing, protected branch, or auth
   rejection → references/failure-remediation.md. NEVER force.

## Phase 5 — Verification sweep

Each check maps to a real stop-gate finding. Read/verify before asserting clean.

| Check | Command / method | Catches |
|---|---|---|
| No unrecorded submodule state | `git -C <parent> submodule status` → no `+` prefix | "parent commit relies on an unrecorded submodule state" |
| No uninitialized submodule | same → no `-` prefix | "output inside an uninitialized submodule" |
| No dirty submodule worktree | `git -C <parent> status --porcelain --ignore-submodules=none` empty | dirty-submodule drift |
| Ledger current | Read `progressFile`; confirm slice entry/pointers match landed state | "ledger points at unrecorded and stale state" |
| Docs pointers not stale | Read README (+ docs the slice touched); grep for paths/counts the slice changed | "README still points generated docs at inventory/*.md" |
| Structure contract coherent | If repo-structure.yaml exists: new/moved paths registered | unregistered domains |
| Structure checker | If `structureChecker` set: run it from `<canonicalRoot>`, expect exit 0 | machine-checkable drift |

Findings: report ALL. Stale ledger/README pointers are AUTO-FIXED — scoped per
house rule 8 (only what is provably stale; log every change and why) — then
reported; there is no report-only mode. If an Edit misses (string-not-found),
re-Read the file first — never blind-retry. Anything judgment-heavy (not
provably stale) → batch into one question.

## Phase 6 — Post-merge hygiene

**Worktree mode first:** if `"${CLAUDE_PLUGIN_ROOT}/scripts/git_worktree_check.sh"`
exits 0, cwd is a linked worktree. Do NOT run the steps below (`checkout
<defaultBranch>` is illegal while default is checked out at the primary root,
and the branch/worktree teardown belongs to the caller's `ExitWorktree`).
Report "linked worktree — branch/worktree teardown delegated to caller" and go
straight to Phase 7. The steps below apply only in a normal (non-worktree)
checkout.

Per repo (submodule first, then parent; plain repo: just it):
1. `git -C <repo> checkout <defaultBranch>` (merge with --delete-branch usually
   did this for the work repo).
2. `git -C <repo> pull --ff-only origin <defaultBranch>`
3. `git -C <repo> fetch --prune origin`
4. clean_gone sweep — for each local branch whose upstream is `[gone]`
   (`git branch -vv`):
   a. `git log <defaultBranch>..<branch> --oneline` — ANY output = unsaved work →
      keep branch, report it, do not delete.
   b. `git worktree list` — branch checked out in a worktree → skip, report.
   c. Clean → `git branch -d <branch>`. If -d refuses after a squash merge:
      confirm the PR is MERGED and `git cherry <defaultBranch> <branch>` shows no
      `+` lines, then `-D` with a logged justification.
   `branch-cleanup` in preauthorized → sweep without asking; else list candidates
   in one question.
5. Offer: "start the next feature branch?" (name it from the seed's Next action
   when a seed exists).

## Phase 7 — Chain

Report the landing summary (PR, gitlink SHA, sweep results, branches cleaned),
then offer /dev-cycle:handoff:save to write the next-session seed. Do not write the
seed yourself. (When invoked by worktree-sessions inside a worktree, that skill
declines this offer — it writes the seed at root after teardown.)

## Red flags — stop and re-read this skill

- About to chain two git commands in one Bash call
- About to `push --force` or `reset --hard` "just to sync"
- About to merge with unresolved threads "because they're minor"
- About to delete a branch without running the log/worktree proof
- About to declare clean without running the Phase 5 table

Failure remediation detail (auth refresh device flow, protected branch,
unfetched submodule): references/failure-remediation.md
