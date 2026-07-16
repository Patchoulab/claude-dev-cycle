# Bundle schema (session-handoff seed superset)

Path: `{bundlesDir}/R-<NNN>/B<n>-<slug>.md`. A bundle IS a schema-valid seed per the
shared seed schema (00-overview §3): the `Generated:` line reads
`Generated: <ISO date> by project-planning:shard vX.Y` (seed validators accept
`project-planning:shard` as a generator), and the extra header lines (Roadmap / Repo /
Plan / Executor / Claim) are ignored by validators (session-handoff's handoff_lint.py).
/dev-cycle:handoff:resume must accept a bundle unmodified, passing strict lint.

```markdown
# Next Session Seed — R-<NNN>.B<n>: <workstream name>
Generated: <ISO date> by project-planning:shard vX.Y
Roadmap: <planning-repo abs path>/ROADMAP.md#R-<NNN> (bundle <n> of <total>)
Repo: <canonical absolute root the session works in>
Plan: <abs path to the parent plan document>
Executor: <resolved concrete model name (from the plan header, not the raw alias)>
Claim: unclaimed
<!-- claimed form: "Claim: claimed-by <worktree-or-host> <ISO date>" -->

## State
branch to create, relevant existing branches/PRs, known failing tests (with why)
## Approved decisions
decisions already made in the plan — do NOT re-litigate
## Carry-forward learnings
gotchas from the planning session the executor must know
## Next action
ONE unambiguous entry point: the first task of this bundle, by plan task number
## Verification criteria
per-task commands + expected output, copied from the plan (bundle must not require
opening the plan to verify)
## Safety constraints
git operations allowed; NEVER include reset --hard / force-push guidance
```

Self-containment rule: the executor session boots from the bundle alone. Tasks are
copied (not referenced) into State/Next action/Verification as needed; the `Plan:`
link is provenance, not a required read.

Claim protocol: edit `Claim:` line + mirror in the roadmap bundle table + commit +
push planning repo BEFORE work starts. Push rejected → pull, pick another bundle.
Completed bundle → status `done` in both places, committed by the executor session
(/dev-cycle:handoff:save handles this when in play).
