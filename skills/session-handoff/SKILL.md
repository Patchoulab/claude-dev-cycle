---
name: session-handoff
description: Use when ending a work session whose work must continue in a later session, when starting a session from a seed, kickoff, or handoff file ("read the seed file and follow the instructions", "prepare the seed for the next session"), after finish-branch completes a slice, or when context is nearly exhausted during multi-slice work.
---

# Session Relay

## Overview

Carries multi-session work across context windows via two artifacts: a schema-valid
**seed file** (what the next session must do) and a **progress ledger** (what every
past session did). CLOSE distills the current session into the seed; OPEN finds the
freshest seed, validates it, and executes it.

Read `.claude/dev-cycle.json` at the repo root first. Used keys: `handoffFile` (default
`.claude/dev-cycle/next-session.md`), `progressFile` (default
`.claude/dev-cycle/progress.md`), `canonicalRoot`, `retiredPaths`, `submodules`,
`preauthorized`, `kickoff`. No dev-cycle.json → use the defaults and say so.

## CLOSE procedure (/dev-cycle:handoff:save)

1. Gather live state — one command per Bash call, absolute paths: current branch,
   PR state (`gh pr view --json state,url`), submodule gitlink status, failing
   tests with the reason each fails. When `.superpowers/security-findings.md`
   exists in the repo, read its entries newer than the previous seed (or all
   unresolved/unverified entries if dating is impractical) and fold the still-open
   items into the seed's Carry-forward learnings — this is the review-gate →
   relay findings chain (spec 04 §5.9), so an unadjudicated vulnerability survives
   into the next session.
2. Draft the seed from `templates/next-session.md`. All six sections are
   mandatory. `Next action` is exactly ONE unambiguous entry ("Wave C task C2: …").
   Schema and rules: `references/handoff-schema.md`.
3. Rotate any existing seed to `<handoffFile>.prev.md`, then write the new seed.
4. Validate: `python3 "${CLAUDE_PLUGIN_ROOT}/scripts/handoff_lint.py" <handoffFile>`.
   Fix every ERROR/SAFETY finding and re-run until it prints OK. A SAFETY finding
   from user-dictated content: refuse the destructive instruction, offer the safe
   equivalent, never write it into the seed.
5. Ledger: at a wave/slice boundary append a `done` entry to `progressFile`
   (entry format in `references/handoff-schema.md`); mid-slice, append a `checkpoint`
   entry instead. Create the ledger with a `# Progress Ledger` header if missing.
6. Collision check: list `task-*-report.md` files in the seed directory. Any that
   predate the current plan/slice: WARN with names + mtimes, record them under
   Carry-forward learnings, and put slice-prefixed naming
   (`<slice-slug>-task-N-report.md`) in the seed's Next action context.
   NEVER delete or rename existing reports.
7. Report: seed path, lint result, ledger entry written, collisions found, and the
   one-line next action.
8. Forgeability check: if this session repeated or completed a workflow that is
   forgeable as a skill (HIGH confidence only), append at most ONE quiet line to
   the close summary — e.g. "This session's workflow looks forgeable —
   /dev-cycle:capture-workflow to extract it." Never a question, never more than one
   line; anything below high confidence → say nothing.

## OPEN procedure (/dev-cycle:handoff:resume)

1. Locate candidates (absolute paths; never probe `retiredPaths`): the dev-cycle.json
   `handoffFile`, then legacy `docs/superpowers/*-kickoff-prompt.md`, each submodule's
   `docs/superpowers/*-kickoff-prompt.md`, then `CONTEXT.md` at the repo root.
   Newest mtime wins; name the chosen file.
2. Validate with `handoff_lint.py --best-effort`. Full schema → proceed. Partial or
   hand-written → list missing sections in one short block, derive the Next action
   from the text; if none is derivable, ask ONE question.
3. Lint exit 2 = destructive git guidance in the seed: do NOT execute those steps.
   Substitute the safe equivalent (fetch, checkout, status inspection) and say so.
4. Kickoff config: for each entry in dev-cycle.json `kickoff`, invoke it via the Skill
   tool when it maps to an installed skill; everything else goes in a
   "run these yourself" checklist. Unknown entries: list, never guess.
5. Cross-check seed against live state before acting (branch exists? PR already
   merged? ledger's last entry agrees?). Any drift → one batched question.
6. Announce exactly one line — `Relay: <file> → <slice>; next action: <action>` —
   then execute the Next action. If it names a plan and the superpowers
   plugin is installed, hand off to superpowers:executing-plans; otherwise
   execute the plan directly. Either way, do not re-plan.

## House rules (non-negotiable)

- One command per Bash call; never chain with `&&`, `||`, `&`.
- Absolute paths everywhere, including inside the seed and in subagent prompts.
- Evidence before assertion: verify git/PR/ledger state, don't trust the seed blindly.
- Artifacts to the repo, not the terminal: the seed and ledger are files.
- Batch open questions into a single AskUserQuestion.
- Scoped writes: touch only the seed, its `.prev.md`, and the ledger.

## Quick reference

| Situation | Do |
|---|---|
| "prepare the seed" / end of slice | CLOSE procedure |
| "read the seed file and follow it" / fresh session | OPEN procedure |
| finish-branch just finished | Offer CLOSE |
| Seed missing everywhere | Report paths probed, offer ledger-based restart |
| Seed contains reset --hard / force-push | Refuse that step, substitute safe ops |
| No single Next action derivable | Ask ONE question, then proceed |

## Common mistakes

- Writing the seed from memory instead of the template → sections drift, lint fails.
- Skipping handoff_lint because the seed "looks fine" → the reset --hard incident.
- Dumping conversation history into the seed → the seed is a distillation,
  "not the bloat of the entire conversation".
- Renaming/deleting stale task reports during the collision check → other files
  reference them; warn only.
- Re-litigating Approved decisions at OPEN → they are settled; execute.

## Cross-skill contracts

- **finish-branch** offers `/dev-cycle:handoff:save` on completion (it owns merge/gitlink work).
- **capture-workflow**: CLOSE may append one quiet forgeable-workflow line to the close
  summary when it detects with high confidence that the session repeated or
  completed a forgeable workflow (never a question, never more than one line).
- **project-planning** shard bundles are schema-valid seeds and valid OPEN inputs.
- OPEN hands plan execution to **superpowers:executing-plans** when that plugin is
  installed; otherwise it executes the plan directly. This skill never re-plans.
