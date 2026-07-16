# session-handoff

**Purpose** — Carries multi-session work across context windows so nothing is lost when a session ends or compacts. It distills the current session into a schema-valid handoff file (what the next session must do) and appends to a progress log (what every past session did), then lets a later session pick that handoff file up and execute it. Reach for it whenever work will continue in a future session, when a session finished a slice, or when context is running low.

## Invocation

| Command | What it does |
|---|---|
| `/dev-cycle:handoff:save` | End a session: gather live git/PR/test state, write the handoff file from the template, validate it, and append a progress-log entry. |
| `/dev-cycle:handoff:resume` | Start a session: find the freshest handoff file, validate it, apply kickoff config, cross-check against live state, and execute its Next action. |

A PreCompact hook writes an emergency snapshot automatically, so an approaching compaction does not lose the session's state even if you never ran `save` by hand.

## Contract

**Reads.** Live repository state (current branch, PR state via `gh`, submodule gitlink status, failing tests and why each fails), the config file `.claude/dev-cycle.json`, the template that shapes a new handoff file, and, when present, the repo's open security-review findings so unadjudicated items survive into the next session. On resume it also reads legacy kickoff prompts and a root `CONTEXT.md` as fallback inputs.

**Writes.** The handoff file at `handoffFile`, its rotated previous copy at `<handoffFile>.prev.md`, and the progress log at `progressFile`. Writes are scoped to exactly those files; existing task reports are never renamed or deleted (collisions are reported as warnings only).

**Handoff-file sections.** Every handoff file carries these six `##` sections, in order, each non-empty:

| Section | Contents |
|---|---|
| State | Branch, PR, gitlink, last progress-log entry, failing tests, task reports this slice. |
| Approved decisions | Decisions already settled this session; the next session must not re-litigate them. |
| Carry-forward learnings | Gotchas discovered this session that the next session needs to know. |
| Next action | Exactly one unambiguous entry point. |
| Verification criteria | How the next session proves it did the job. |
| Safety constraints | Allowed git operations, plus a `NEVER` line banning destructive git commands. |

**Progress log.** Each entry records the date, slice name, a `done` or `checkpoint` marker, branch/PR/gitlink status, report paths, the one-line next action, and the handoff-file path. `done` is appended at a slice boundary; `checkpoint` mid-slice.

## Config keys

Read from `.claude/dev-cycle.json` at the repo root. If the file is absent, the defaults below apply and the skill says so.

| Key | Purpose | Default |
|---|---|---|
| `handoffFile` | Path to the handoff file. | `.claude/dev-cycle/next-session.md` |
| `progressFile` | Path to the progress log. | `.claude/dev-cycle/progress.md` |
| `kickoff` | Steps to run on resume; installed skills are invoked, the rest become a manual checklist. | none |
| `canonicalRoot` | The repo root used to anchor absolute paths. | repo root |

## Prerequisites

- **git** (and `gh` for PR state) to read branch, PR, and submodule status.
- **python3** to run the handoff-file validator (`handoff_lint.py`), which every `save` must pass and every `resume` runs in best-effort mode.

## Failure modes & remediation

| Situation | What happens / what to do |
|---|---|
| Validator reports an ERROR or SAFETY finding | The handoff file is not valid yet. Fix each finding and re-run until it prints OK. |
| Handoff file (or user-dictated content) contains a destructive git command (`reset --hard`, force-push, `clean -f`, `checkout -- .`, `branch -D`) | On save, refuse the destructive instruction and write the safe equivalent instead. On resume (validator exit 2), do not execute those steps; substitute safe operations (fetch, checkout, status inspection) and say so. |
| No handoff file found anywhere on resume | Report the paths probed and offer a progress-log-based restart. |
| No single Next action can be derived | Ask exactly one clarifying question, then proceed. |
| Handoff file drifts from live state (branch gone, PR already merged, log disagrees) | Cross-check before acting; raise one batched question rather than trusting the file blindly. |

## Optional integrations

When the superpowers plugin is installed and the Next action names a plan, resume hands plan execution to `superpowers:executing-plans`. Otherwise it executes the plan directly. Either way it never re-plans. On completion, `finish-branch` offers to run `/dev-cycle:handoff:save` for you.
