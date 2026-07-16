# finish-branch

**Purpose** — Closes out a finished branch whose PR is ready to land, running the whole end-of-branch routine in one pass: merge the PR, update the submodule pointer (the gitlink), sweep for verification drift, sync `main`, and clean up merged branches. It works both in repos that use git submodules and in plain single-repo layouts, skipping the submodule-specific work automatically when there are no submodules. Nothing it does is destructive: every phase verifies state before asserting anything, and there is no force-push or hard-reset path.

## Invocation

Run `/dev-cycle:finish-branch`. It auto-detects whether the current repo has an open PR and whether the working tree is a submodule under a canonical parent. An optional argument can name a specific PR number or a submodule path when you want to be explicit instead of relying on detection.

## Contract

The skill moves through a fixed phase flow and only asserts "clean" after each gate has actually been checked:

1. **Preflight** (read-only) — Confirms an open, mergeable PR exists, that review is approved (or no review is required), and that no review threads are unresolved. Any blocker stops here at zero cost.
2. **Merge** — Merges the PR with the configured strategy and deletes the head branch.
3. **Submodule side** *(skipped in plain-repo mode)* — In the submodule repo, confirms a clean tree, checks out the default branch, fast-forward-pulls the merge, and proves the local head matches the remote.
4. **Gitlink / submodule-pointer bump** *(skipped in plain-repo mode)* — In the parent repo, stages only the gitlink, commits a `chore(submodule)` bump referencing the PR, and pushes the parent branch.
5. **Verification sweep** — Checks for unrecorded or uninitialized submodule state, dirty worktrees, a stale progress ledger, stale README/docs pointers, and structure-contract drift. Provably-stale ledger and doc pointers are auto-fixed and reported; judgment calls are batched into a single question.
6. **Post-merge hygiene** — Checks out and fast-forwards the default branch, prunes remotes, and sweeps local branches whose upstream is gone, deleting only those proven to hold no unsaved work.
7. **Handoff offer** — Reports the landing summary and offers `/dev-cycle:handoff:save` to write the next-session handoff file. It never writes that file itself.

**Plain-repo mode** (no `submodules` entry in config) skips phases 3 and 4 and all submodule checks; the verification sweep runs only its docs/ledger and structure-checker portions.

**Worktree mode** — When the current working tree is a linked git worktree, the merge omits the branch delete (and instead deletes the remote head explicitly), and post-merge branch and worktree teardown is delegated to the caller rather than performed here.

## Config keys

Read from `.claude/dev-cycle.json` under the repo's canonical root:

| Key | Role |
|---|---|
| `canonicalRoot` | Absolute path of the parent repo that owns the layout. |
| `submodules[]` | Submodule entries (path per submodule); absence triggers plain-repo mode. |
| `defaultBranch` | Default branch per submodule to sync against. |
| `structureChecker` | Optional command run from the canonical root during the sweep; must exit 0. |
| `progressFile` | Progress ledger checked (and auto-fixed if stale) during the sweep. |
| `preauthorized[]` | Actions allowed without asking (e.g. merge-after-green-review, branch cleanup). |
| `botsToIgnore[]` | Review-thread authors dropped when counting unresolved threads. |
| `mergeStrategy` | Merge strategy passed to the PR merge (defaults to `merge`). |

## Prerequisites

- `git` on `PATH`.
- The `gh` CLI, authenticated. An expired or 401 session stops the run and hands auth back to you.

## Failure modes & remediation

| Situation | What happens |
|---|---|
| **Protected branch rejects the pointer-bump push** | The protection rule is reported and the bump is routed into its own PR; finish-branch resumes at the verification sweep once that PR merges. It never force-pushes past protection. |
| **Non-fast-forward push rejection** | One rebase-pull and one re-push are attempted. If a rebase conflict appears, the rebase is aborted, divergent commits are reported, and the run stops. No force. |
| **PR is CONFLICTING** | It offers to update the branch and re-run preflight once; if still conflicting, the conflicted files are listed and handed back. finish-branch never edits conflict markers. |
| **Dirty submodule worktree** | The run stops before touching anything, lists the dirty files, and routes them to a commit flow. It never commits your work for you. |
| **Unfetched submodule commits** (`Invalid revision range` / unknown SHA) | It fetches in the submodule, and if the commit is still missing, initializes the submodule (init only, never force) before retrying once. |

Additional detail, including the `gh auth refresh` device-flow relay for a missing `workflow` OAuth scope, lives in the skill's `references/failure-remediation.md`.

## Optional integrations

- **commit-commands** — When that plugin is installed, missing-PR creation and any needed commits (dirty submodule, the pointer bump) route through its commands; otherwise finish-branch falls back to plain `gh` and `git`. It never creates a PR on its own.
- **pr-monitor** — When preflight finds unresolved review threads, requested changes, or pending/failing checks, it stops and offers pr-monitor to handle triage rather than resolving anything inline.
