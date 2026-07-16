# review-gate

**Purpose** — An unattended, per-commit security-review gate. After any commit made through a Bash command, it triages that commit's diff, and for surface-changing changes it spawns a headless reviewer with a read-only permission set and pre-resolved absolute paths. Every candidate vulnerability is then verified against the current file's real content before a verdict is recorded, so the gate never rubber-stamps and never blocks the commit itself.

## Invocation

The gate is hook-driven: it fires automatically from a `PostToolUse(Bash)` hook that matches git-commit commands. You do not run it by hand in normal use — committing is enough to trigger it. The reviewer runs headless in the background; a broken gate always exits cleanly so a commit is never blocked.

Install and repair happen through natural language ("install the review gate here", "the gate keeps reviewing the same commit twice", "repair the gate"). Installation is idempotent and writes conservatively:

- A git `post-commit` hook that chains to any existing hook rather than clobbering it.
- A managed allowlist block merged into `.claude/settings.json`, with absolute submodule paths substituted in. This is the read-only permission set the headless reviewer runs under.
- The `PostToolUse(Bash)` trigger ships with the plugin's shared hook config. The post-commit hook and the PostToolUse trigger both dedup down to a single review.

Install also warns (never deletes) when it detects redundant legacy triggers, such as a hand-rolled post-commit reviewer left over from a previous setup.

## Contract

The flow for each commit:

1. **Triage the diff.** Trivial change classes (docs-grade paths and similar) are skipped; surface-changing files are routed to review. Triage fails closed: an unclassifiable file gets a full review, never a silent pass.
2. **Dedup.** A lockfile under `.git/dev-cycle/review/` collapses concurrent firings (post-commit plus PostToolUse) into one review of a given commit within the dedup TTL.
3. **Expand submodules.** Gitlink pointer bumps are expanded into the real content diff so the reviewer sees actual changes, not just a `Subproject commit` line.
4. **Spawn the headless reviewer.** It receives pre-resolved absolute paths (deleted files marked as deleted, not listed as readable), retired-path warnings, and a strict command-discipline block. It returns findings via structured output.
5. **Verify the verdict (anti-rubber-stamp).** Each candidate is re-checked against the current file. A verdict is accepted only if it carries a verbatim, line-anchored quote drawn from the candidate's own file. Evidence-free or under-length quotes are rejected and the pass re-runs; unverifiable candidates stay open. Fail closed throughout.
6. **Audit.** Every action, including every skip, leaves an audit line. There are no silent skips.

## Config keys

Settings live in the `review` block of `.claude/dev-cycle.json`:

| Key | Meaning |
|---|---|
| `enabled` | Master on/off switch for the gate. |
| `model` | Reviewer model; the verification pass reuses the same model. |
| `maxTurns` | Turn cap for the headless reviewer. |
| `timeoutSeconds` | Wall-clock limit per review before the run is abandoned. |
| `dedupTtlSeconds` | Window in which repeated firings for one commit collapse to a single review. |
| `maxDiffBytes` | Above this size, the gate falls back to a per-file / stat summary instead of a full unified diff. |
| `monorepoHint` | Free-text note telling the reviewer where sources live in a monorepo. |
| `neverSkipGlobs` | Paths that always get a full review, overriding triage skips. |
| `verification.required` | When true, a verdict with no valid evidence is rejected and re-run. |

Two top-level keys in the same file support the gate:

| Key | Meaning |
|---|---|
| `canonicalRoot` | The authoritative absolute repo root handed to the reviewer, so it never guesses paths. |
| `retiredPaths` | Directories that no longer exist; the reviewer is told never to read, list, or search them. |

## Prerequisites

- `git`
- `python3` (triage and evidence verification)
- `jq` (structured-output validation)
- A headless `claude` CLI on `PATH` to run the reviewer and verification passes
- `gitleaks` optional, for secret scanning as part of triage

## Failure modes & remediation

| Symptom | Cause & remediation |
|---|---|
| No review ever fires | Gate not installed, or `enabled` is false. Reinstall via natural language and confirm the `PostToolUse(Bash)` trigger and post-commit hook are present. |
| Same commit reviewed twice | The dedup lockfile could not be written — often because two repos share one worktree. Check the shared git dir; make `.git/dev-cycle/review/` writable. |
| `fatal: Invalid revision range` on a submodule bump | The submodule is missing from config, or its objects were not fetched, so the gitlink range cannot be resolved. Register the submodule and confirm it fetches; unresolvable ranges degrade to a pointer-bump-only review with an explicit unverified-bump finding. |
| Reviewer hits an approval wall | The managed allowlist was not merged into `.claude/settings.json`, or the reviewer used a command form outside its discipline block. Reinstall to restore the allowlist. |
| Verdict rejected as evidence-free | Expected behavior: a verdict without a verbatim, line-anchored quote from the current file is rejected and the pass re-runs. Recurring rejections point to a weak or mismatched reviewer model. |

## Optional integrations

This skill is the unattended gate. For interactive, on-demand review of a working branch or pull request, reach for `/security-review` or `pr-review-toolkit:review-pr` instead — they complement the gate rather than replace it.
