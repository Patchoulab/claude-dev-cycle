---
name: review-gate
description: Use when installing, repairing, or auditing an unattended per-commit security-review gate, or when headless review sessions hit "File does not exist" path errors, "fatal - Invalid revision range" on Subproject commit diffs, "This command requires approval" walls, duplicate concurrent reviews of the same diff, StructuredOutput schema failures, or confirm/dismiss verdicts produced with zero tool calls.
---

# Review Harness

## Overview

Unattended per-commit security review gate: triage the diff locally, dedup
concurrent firings, expand submodule gitlink bumps into real content diffs,
then spawn a headless reviewer with pre-resolved absolute paths and a
read-only permission set. Core principle: **the gate does the environment
work so the reviewer only does security work.**

## When to use

- Installing the gate in a repo (new or replacing a hand-rolled hook)
- Review transcripts show path guessing, permission walls, `Invalid
  revision range`, duplicate reviews, or evidence-free verdicts
- Tuning triage (too many trivial reviews, or a skip you disagree with)
- NOT for interactive review — use /security-review or
  pr-review-toolkit:review-pr for those

## Quick reference

All operations go through the gate script (absolute path via plugin root):

| Command | Does |
|---|---|
| `gate.sh install` | Write git post-commit hook, project settings allowlist, dev-cycle.json `review` block (idempotent; conservative writes, no prompts) |
| `gate.sh run <sha>` | Gate one commit manually (same path as the hook) |
| `gate.sh status` | Show lock dir, last 20 audit lines, config in effect |
| `gate.sh replay <sha>...` | Re-run triage only (no spawn), print verdict + prompt that WOULD be sent |
| `gate.sh prune` | Remove lock dirs older than 7 days |

## Install procedure

1. Read `.claude/dev-cycle.json`. Required: `canonicalRoot`. Recommended:
   `retiredPaths`, `submodules[]`, `review{}` block (see
   `templates/review-block.jsonc`). Missing file → offer to create
   it from `git rev-parse --show-toplevel` + `.gitmodules`.
2. Run `gate.sh install`. It writes:
   - `.git/hooks/post-commit` (chains to any existing hook, never clobbers)
   - merges `templates/settings-allowlist.json` into `.claude/settings.json`,
     substituting absolute submodule paths from dev-cycle.json
   - the entry in the plugin's shared `hooks/hooks.json` ships with the plugin (PostToolUse
     on Bash git-commit commands); both triggers dedup to one review
3. Legacy-trigger sweep: `gate.sh install` also detects redundant legacy
   duplicate triggers (multiple hook firings for the same event class —
   e.g. an old hand-rolled post-commit reviewer alongside a per-push hook)
   and WARNS about them, naming the file — it never removes them itself;
   the dedup lock remains the runtime backstop either way.
4. Verify: `gate.sh replay HEAD` and confirm the printed prompt has
   absolute paths, retired-path warnings, and submodule expansion.

## Diagnose table

| Symptom in review transcript | Fix |
|---|---|
| `File does not exist` / probes of wrong volume names | dev-cycle.json `canonicalRoot` wrong or hook predates harness — reinstall |
| `fatal: Invalid revision range` | submodule missing from dev-cycle.json `submodules[]`, or fetch failing — check `gate.sh status` for `submodule_unresolved` events |
| `This command requires approval` | allowlist not merged into `.claude/settings.json`, or reviewer used a command form outside the prompt's discipline block |
| Same SHA reviewed twice | lock dir not writable, or two repos share a worktree — check `git rev-parse --git-common-dir` |
| `must have required property findings` | reviewer bypassed StructuredOutput — gate retries once automatically; recurring = check model override |
| Verdicts with no evidence | expected: gate rejects and re-runs; recurring = see `verify_rejected` audit events |

## Rules the gate enforces (do not weaken when editing templates)

- Every changed-file path handed to a reviewer is absolute and pre-verified
  to exist (deleted files are marked `D`, not listed as readable).
- A skipped review always leaves an audit line. No silent skips.
- A verification verdict without a verbatim, line-anchored quote from the
  CURRENT file is rejected. Fail closed: unverifiable candidates stay open.
- Verification evidence must come from the candidate's own file (realpath
  match; never `.git/` or `.superpowers/` artifacts) and quotes must carry
  ≥ 12 normalized characters — no one-token rubber stamps.
- Reviewer allowlists never grant exec-capable verbs: `git grep` (`-O`) and
  `rg` (`--pre`) are excluded by design; content search uses the native
  Grep tool. Do not re-add them.
- Unresolvable submodule ranges degrade to a pointer-bump-only review with
  an explicit `UNVERIFIED SUBMODULE BUMP` finding — never a flailing agent.
- Triage fails closed: unclassifiable file → full review.

Templates: `templates/review-prompt.md`, `templates/verify-prompt.md`,
`templates/settings-allowlist.json`, `templates/review-block.jsonc`.
Scripts: `hooks/review-gate/gate.sh`, `triage.py`, `verify_evidence.py`.
