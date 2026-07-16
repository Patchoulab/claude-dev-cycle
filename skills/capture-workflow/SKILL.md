---
name: capture-workflow
description: Use when finished work should become reusable — the user says "turn this into a skill/command/playbook", "I don't want to re-explain this next time", "make this repeatable", asks how to start a similar task next time without redoing the setup, or is repeating a workflow that was already run once before.
---

# Capture Workflow

## Overview

Turn a completed session or workflow into the right reusable artifact:
a project slash command, a skill, a playbook doc, or a scheduled-jobs job.

**Cardinal rule: extract the LOGIC, never the literals.** The user's own
teaching: "not just copy the exact coordinate … those python files are
there to auto generate those graphics out of whatever gets detected in
the future." Every literal in the extraction gets classified before
authoring (see The Literals Rule).

**Authoring discipline:** if the superpowers plugin is installed,
superpowers:writing-skills owns the authoring discipline (description
triggers, conciseness, frontmatter, loophole closing, TDD-for-docs) —
invoke it. Otherwise author by hand: a tight when-to-use description,
minimal frontmatter, no redundant prose. Capture-workflow's job is what
comes before and after: extraction, classification, playbook, validation,
packaging.

## When NOT to use

- Session handoff / "prepare the seed for the next session" → session-handoff.
- The work is a one-off that won't recur → say so and stop. No artifact.
- Standard practice already covered by an existing skill → point at it.

## Pipeline

Work through the stages in order; each stage's output is the next
stage's input. Present all user decisions as ONE batched AskUserQuestion
after stage 2 (artifact type, name, location).

1. **Extract** — mine the completed work using
   references/extraction-checklist.md. Sources, in preference order:
   current conversation; artifacts the user names; the repo's seed and
   ledger files (dev-cycle.json handoffFile/progressFile); git log/diff of the
   session's branch. Output: a filled extraction record.
2. **Classify** — pick the artifact type with the decision table below.
   Recommend; don't silently decide.
3. **Author** — if the superpowers plugin is installed, invoke
   superpowers:writing-skills and follow it; otherwise author the artifact
   directly (tight when-to-use description, minimal frontmatter). Produce
   the artifact plus a playbook reference doc from
   templates/playbook-template.md (commands use
   templates/command-template.md and point at the playbook).
4. **Validate** — run references/validation.md: frontmatter lint,
   trigger-phrase test, dry-run on a synthetic variant of the original
   task, literal-leak scan. Do not package an artifact that failed any.
5. **Package** — place and register per references/packaging.md. Commit
   on a branch if "commit-approved-artifacts" is preauthorized;
   otherwise ask. NEVER push — shipping is the user's call.

## Artifact decision table

| Artifact | Choose when | Trigger style | Lives at |
|---|---|---|---|
| Project slash command | Repo-specific workflow the user starts on demand with a per-request argument ("add a card for X") | Explicit `/name args` | `<repo>/.claude/commands/<name>.md` + playbook doc in the owning domain |
| Project skill | Repo-specific procedure Claude should auto-apply whenever matching work happens in that repo (conventions, pipelines, guardrails) | Contextual (description match) | `<repo>/.claude/skills/<name>/SKILL.md` |
| User skill | Procedure spans the user's repos but embeds personal facts (machines, accounts, habits) that can't be externalized | Contextual, any repo | `~/.claude/skills/<name>/SKILL.md` |
| plugin skill | Generic engine; every user-specific literal externalized to dev-cycle.json/args; worth sharing | Contextual, distributable | `<your-plugin>/skills/<name>/` + plugin.json bump |
| scheduled-jobs job | Recurring chore on a clock, no human trigger | Schedule | hand a pre-filled answer record to /dev-cycle:jobs:new; stop |

Tie-breakers: (a) trigger first — clock beats everything → scheduled-jobs;
explicit-argument start → command; otherwise skill. (b) then scope —
narrowest scope that covers the expected reuse. (c) personal literals
that can't become parameters or config cap the scope at user level.

## The Literals Rule

Classify EVERY proper noun, path, host, port, coordinate, name, and
number in the extraction as exactly one of:

- **parameter** — the caller supplies it ($ARGUMENTS, quick-fill form)
- **config** — read from dev-cycle.json / repo files
- **invariant** — genuinely fixed for the artifact's scope (a repo's
  own script paths in a project command are invariants; an IP in a
  plugin skill never is)
- **discard** — incidental to the original run

A literal's legal classifications shrink as scope widens: what is an
invariant in a project command is config or parameter in a plugin
skill. The validation stage greps the artifact for every literal
classified parameter/discard; any hit is a failure.

## House rules (non-negotiable in produced artifacts)

- One command per Bash call; never chain with &&, ||, &.
- Absolute paths in any subagent prompt the artifact dispatches.
- No secret values — .env names or Infisical paths only.
- No destructive-git guidance (reset --hard, force-push) in any
  produced command, skill, or playbook.
- Verification steps included: an artifact that can't prove it worked
  is incomplete.

## Red flags — stop and fix

- You copied a coordinate, IP, or name without classifying it.
- The artifact's description summarizes its workflow (SDO violation —
  see writing-skills).
- You are about to `git push` or bump a marketplace listing.
- You skipped the dry-run because the artifact "is obviously clear."
- The "reusable" workflow ran exactly once and has no second use case.
