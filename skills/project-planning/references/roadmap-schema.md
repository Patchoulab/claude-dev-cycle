# Roadmap file schema

One markdown file (default `ROADMAP.md`) at the planning repo root. project-planning owns
its structure; humans and other sessions may read it freely.

```markdown
# Roadmap — <portfolio name>
Updated: <ISO date> by project-planning v<X.Y>

## Pending decisions
<!-- written by scheduled surveys; cleared by the next interactive session -->
- <question needing the user's call, one per line; "none" if empty>

## R-<NNN>: <title>
- status: todo | planned | sharded | in-progress | done | dropped
- leverage: high | medium | low — <one-line why>
- tier: frontier | executor | either
- repos: <absolute path>[, <absolute path>...]
- source: survey <ISO date> | user <ISO date>
- plan: <plansDir/file.md per repo, or "—">
- next-step: <one sentence>
- blockers: <one sentence or "none">

### Context
<Everything a future session needs if all other memory is lost: background, prior
decisions and their reasons, links to evidence files/commits/PRs. No length limit;
this section IS the durable memory.>

### Bundles
| bundle | repo | status | claimed-by | date |
|---|---|---|---|---|
| B1-<slug> | <abs path> | unclaimed / claimed / done | — / <worktree-or-host> | <ISO> |
```

Rules:
- IDs are `R-` + zero-padded counter, never reused, never renumbered.
- Items are never deleted; `dropped` items keep their Context (they get re-proposed
  otherwise).
- Item status lifecycle: todo → planned → sharded → in-progress → done. `in-progress`
  = at least one bundle claimed; `done` = all bundles done AND verification evidence
  cited in Context.
- Every field above is mandatory per item; `### Bundles` appears only once sharded.
