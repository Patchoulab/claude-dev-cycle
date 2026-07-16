---
name: project-planning
description: Use when deciding what to work on next across many projects, refreshing a portfolio roadmap, writing an implementation plan a cheaper/less-capable model will execute, or splitting an approved plan into bundles for parallel worktree sessions. Triggers: "what should we work on", "survey my projects", "refresh the roadmap", "plan this so <model> can implement it", "split/shard this plan", "parallel sessions".
---

# Project Planning

## Overview

Frontier reasoning is the scarce resource. This skill spends it on three things only —
surveying the portfolio, deciding, and planning — and packages everything else for
cheaper executors running in parallel worktrees. Persistent state lives in the planning
repo's roadmap file, never in session memory.

Three modes. Pick by intent:

| Intent | Mode |
|---|---|
| "What's the state of everything / what next?" | survey |
| "Plan <task> for an executor model" | plan |
| "Split this plan for parallel sessions" | shard |

All modes run from the planning repo (the repo whose `.claude/dev-cycle.json` has a
`planning` block). No config block → say so and offer to bootstrap one (see Setup).

House rules apply to every mode: one command per Bash call (never `&&`/`||`/`&`);
absolute paths in every subagent prompt; artifacts are committed files, not terminal
dumps; batch ALL pending decisions into one AskUserQuestion; verify against files/git
state before asserting status.

## Mode: survey

1. Read `planning` config: `projectRoots`, `memoryDirs`, `clusters`, `roadmapFile`.
2. Fan out ONE read-only subagent per cluster, all in a single message. Each prompt is
   built from `references/survey-prompt.md` — fixed synthesis format, absolute paths,
   read-only. Cap at `maxSurveyAgents` (merge smallest clusters if over).
3. Merge synthesis entries. Diff against the roadmap:
   - roadmap item's next-step now done (cite evidence) → propose status `done`
   - project surveyed but absent from roadmap → NEW candidate
   - roadmap item with no surveyed activity and unchanged blocker → flag STALE
4. Rank candidates: leverage (impact if done) crossed with tier (what capability the
   next step needs — `frontier` beats `executor` for THIS list; executor-tier items are
   listed but marked "delegate, don't spend frontier time").
5. ONE AskUserQuestion: confirm done items, accept/reject new items, keep/drop stale.
6. Rewrite the roadmap per `references/roadmap-schema.md`. New items get a full
   `### Context` section — dump everything relevant from this session's memory; the
   roadmap is the durable store, assume this session's memory is lost tomorrow.
7. Commit the roadmap to the planning repo (message: `project-planning: survey <ISO date>`).

## Mode: plan

1. Resolve the target to a roadmap item (create one first if given free text — a plan
   without a roadmap entry is an orphan).
2. Determine repos touched. More than one → one plan document per repo, each fully
   self-contained, with any cross-repo interface (file formats, endpoints, signatures)
   specified identically in both. Never one doc spanning two repos.
3. Write the base plan with superpowers:writing-plans if that plugin is installed; otherwise write it directly, following `references/executor-checklist.md`.
4. Apply the executor gate — every item in `references/executor-checklist.md` must
   pass. The bar: the executor from config (`executor` tier alias, resolved NOW to
   the concrete current model name and recorded in the plan header) implements the
   plan with zero judgment calls. Rewrite until clean; report what the gate caught.
5. Save to `plansDir/<roadmap-id>-<repo-slug>.md`, flip roadmap status to `planned`,
   link the plan file from the roadmap item, commit.

## Mode: shard

1. Refuse to shard a plan the user hasn't approved (ask if approval isn't on record).
2. Identify independent workstreams: separate repos always split; within a repo, task
   groups with no dependency edges between them split. When in doubt, fewer bundles.
3. Write one bundle per workstream to `bundlesDir/<roadmap-id>/B<n>-<slug>.md`, using
   `references/bundle-schema.md`. Each bundle is a valid session-handoff seed: a fresh
   session must be able to boot from it with zero other context.
4. Update the roadmap item's bundle table (id, repo, status `unclaimed`), flip item
   status to `sharded`, commit.
5. Point at the consumers: the superpowers using-git-worktrees skill (or `git worktree add` directly) for isolation,
   /dev-cycle:handoff:resume to boot each bundle. Do NOT create worktrees or execute bundles.

## Claim protocol (parallel-session safety)

A session takes a bundle by editing its `Claim:` line (`claimed-by: <worktree-or-host>
<ISO date>`), mirroring it in the roadmap bundle table, committing, and pushing the
planning repo BEFORE starting work. Push rejected → someone else claimed first: pull,
pick another bundle. Claims older than `staleClaimDays` (default 7) with the bundle
still not `done` are flagged by the next survey for the user to arbitrate. Never
reassign a claim silently.

## Cadence

Recommended ritual: weekly survey → re-rank → plan the top frontier item. Offer (once,
not naggingly) to wire it via the schedule skill; a scheduled run does survey steps
1-4 + 6-7 with NO user gate — it commits the refreshed status/diff but leaves
accept/drop decisions listed in the roadmap's `## Pending decisions` section for the
next interactive session.

## Setup (first run)

No `planning` block → ask which repo is the planning repo, write the block into its
`.claude/dev-cycle.json` (template in `references/config-template.json`), create
`roadmapFile`, `plansDir`, `bundlesDir`, initial commit. If the chosen repo already
contains a roadmap file (hand-written or otherwise), ADOPT it: parse its items into
the roadmap schema preserving their statuses, show the user the old→new mapping,
then commit the normalized roadmap in its place — never bootstrap a fresh roadmap
next to an existing one. If the directory isn't a git repo, ask before `git init` —
worktree concurrency requires git.

## Red flags — stop and re-read the relevant reference

- A survey subagent prompt without absolute paths or without the fixed format
- "The executor can figure out this detail" → gate failure, decide it now
- One plan document covering two repos
- Sharding an unapproved plan
- Starting to implement a bundle yourself
- Roadmap edits kept in memory instead of committed
