# Handoff file schema & progress log format (dev-cycle / session-handoff)

## Seed schema (canonical, v0.1)

Title: `# Next Session Seed — <slice/wave name>` then
`Generated: <ISO-8601 UTC> by <generator> vX.Y`, where `<generator>` is
`session-handoff` or `project-planning:shard` (validators accept both).

Required `##` sections, in order: State, Approved decisions,
Carry-forward learnings, Next action, Verification criteria, Safety constraints.
Every section non-empty. Next action contains exactly one entry point.

## Safety rules

Destructive git guidance is banned anywhere in a seed:
`reset --hard`, `push --force` / `push -f` (including --force-with-lease),
`clean -f*`, `checkout -- .`, `branch -D`.
Exemption: lines containing the uppercase word `NEVER` (prohibition lines in
Safety constraints). Enforced by scripts/handoff_lint.py (exit 2).

## Ledger entry format (appended by CLOSE)

    ## <ISO date> — <slice/wave name> — <done|checkpoint>
    - Branch: <name> | PR: <url or n/a> (<state>) | Gitlink: <bumped|pending|n/a>
    - Reports: <paths or none>
    - Next: <one line, mirrors the seed's Next action>
    - Seed: <handoffFile path> (<generated timestamp>)

If the existing ledger uses a visibly different entry style, match it and keep
the same fields; otherwise use this format verbatim.

## Legacy input mapping (OPEN, best-effort)

| Legacy content | Maps to |
|---|---|
| "context"/"background" prose | State |
| "decisions"/"agreed" bullets | Approved decisions |
| "learnings"/"gotchas"/journal refs | Carry-forward learnings |
| imperative "start/do/implement X" | Next action |
| "success looks like"/checklists | Verification criteria |
| absent | note as missing; Safety constraints default to the template's NEVER line |

project-planning shard bundles are NOT legacy input: they are schema-valid seeds and
pass strict lint as-is. Their extra header lines (Roadmap / Repo / Plan /
Executor / Claim) are ignored by validators.
