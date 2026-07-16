# project-planning

**Purpose** — Spends scarce frontier reasoning on three things and packages the rest for cheaper executors. It surveys a portfolio of projects against a durable roadmap, writes an implementation plan targeted at a named executor model that can build it with zero judgment calls, and splits an approved plan into per-workstream bundles that boot as independent parallel worktree sessions. Persistent state lives in the planning repo's roadmap file, never in session memory.

## Invocation

| Command | What it does |
|---|---|
| `/dev-cycle:plan:survey` | Fan out over configured project roots and memory dirs, diff findings against the roadmap, and refresh it. |
| `/dev-cycle:plan:write` | Resolve a target to a roadmap item and write an executor-targeted implementation plan for it. |
| `/dev-cycle:plan:split` | Split an approved plan into per-workstream bundles for parallel sessions. |

All three run from the planning repo — the one whose `.claude/dev-cycle.json` carries a `planning` block. No block present means the skill offers to bootstrap one (write the config, create the roadmap, plans, and bundles paths, initial commit) rather than proceeding.

## Contract

**survey.** Reads `projectRoots`, `memoryDirs`, and `clusters`; dispatches one read-only subagent per cluster (capped at `maxSurveyAgents`, smallest clusters merged if over) using a fixed synthesis format and absolute paths. It establishes each project's status from git and file evidence, then diffs against the roadmap: completed next-steps become `done` proposals, unseen surveyed projects become new candidates, and untouched items with unchanged blockers get flagged stale. All accept/reject/keep decisions are batched into one question, then the roadmap is rewritten (new items get a full Context section, since the roadmap is the durable memory) and committed. A scheduled run does the refresh with no user gate and parks decisions in the roadmap's Pending decisions section for the next interactive session.

**write.** Resolves the target to a roadmap item (creating one first if given free text — a plan without a roadmap entry is an orphan). One plan document per repo touched; a multi-repo item never spans one document, and any shared interface is specified identically in each. The output must pass the executor gate: every item on the executor checklist clears so the executor named in config — resolved to the concrete current model name and recorded in the plan header — can implement it with zero open choices, exact paths, decided designs, and per-task verification commands. The plan is saved under `plansDir`, linked from the roadmap item, and the item flips to `planned`.

**split.** Refuses to run on a plan the user has not approved. It identifies independent workstreams (separate repos always split; within a repo, task groups with no dependency edges split; when in doubt, fewer bundles) and writes one bundle per workstream under `bundlesDir`. Each bundle is a valid session-handoff file — a fresh session boots from it alone, with State, Approved decisions, Carry-forward learnings, a single Next action, Verification criteria, and Safety constraints all inlined (the plan link is provenance, not a required read). The roadmap item gains a bundle table and its status advances to reflect the split. The skill points at the worktree and resume consumers but never creates worktrees or executes bundles itself.

**Claim protocol (parallel-session safety).** A session takes a bundle by editing its `Claim:` line to `claimed-by <worktree-or-host> <ISO date>`, mirroring that in the roadmap bundle table, committing, and pushing the planning repo *before* starting work. A rejected push means someone claimed first: pull and pick another bundle. Claims older than `staleClaimDays` with the bundle not yet `done` are flagged by the next survey for the user to arbitrate — claims are never reassigned silently.

## Config keys

Read from the `planning` block of `.claude/dev-cycle.json` in the planning repo.

| Key | Purpose |
|---|---|
| `roadmapFile` | The durable roadmap markdown file (e.g. `ROADMAP.md`). |
| `plansDir` | Directory where written plans are saved. |
| `bundlesDir` | Directory where split bundles are written. |
| `projectRoots` | Absolute roots the survey scans for projects (e.g. `~/projects`). |
| `memoryDirs` | Absolute memory/notes dirs the survey scans for initiatives. |
| `clusters` | Named groups of paths, one survey subagent per cluster. |
| `excludeDirs` | Directory names skipped during survey (e.g. `node_modules`, `.git`). |
| `executor` | Tier alias for the executor model plans target, resolved to a concrete name at write time. |
| `maxSurveyAgents` | Cap on concurrent survey subagents. |
| `staleClaimDays` | Age past which an unfinished claim is flagged (default 7). |

## Prerequisites

- **git** — surveys read activity from git history; worktree concurrency and the claim protocol require it.
- **python3** — bundle validation shares the session-handoff validator (`handoff_lint.py`); every split bundle must pass strict lint so `resume` accepts it unmodified.

## Failure modes & remediation

| Situation | What happens / what to do |
|---|---|
| `split` invoked on an unapproved plan | Refused. Confirm approval is on record first, then re-run. |
| No `planning` block in the config | The skill stops and offers to bootstrap one, adopting any existing hand-written roadmap rather than overwriting it. |
| A survey subagent returns malformed entries | It gets one retry with its output quoted back; still malformed, its cluster is marked survey-failed rather than fabricated. |
| Executor gate catches an open choice, vague path, or missing verification | The plan is not presentable yet. Each failure is decided now and the plan rewritten until the gate is clean; the catch is the feature. |
| A claim has gone stale past `staleClaimDays` | The next survey flags it for the user to arbitrate; the skill never reassigns silently. |

## Optional integrations

When the superpowers plugin is installed, `write` builds the base plan via `superpowers:writing-plans` before applying the executor gate; without it, the plan is written directly following the executor checklist. For isolation, `split` points at `superpowers:using-git-worktrees` when available, or plain `git worktree add` otherwise. Each bundle is booted by `/dev-cycle:handoff:resume`, which reads it as an ordinary handoff file. Optionally, the survey ritual can be wired to a scheduler for an unattended weekly refresh.
