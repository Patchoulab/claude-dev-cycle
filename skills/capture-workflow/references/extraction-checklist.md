# Extraction Checklist

Fill every section. "None" is an acceptable answer; blank is not.
The output is the extraction record consumed by classify/author/validate.

## Sources to mine (in order)
1. Current conversation (best: decisions and gotchas are verbatim).
2. Artifacts the user names (specs, plans, journals, scripts).
3. Seed/ledger files from dev-cycle.json (handoffFile, progressFile).
4. `git log --stat` and diffs of the session's branch/PR.
If mining a PAST session with no context, ask the user for pointers
(branch, journal entry, artifact paths) in the stage-2 batched question.

## Record

### 1. Goal
One sentence: input → output. ("Given a service name and data endpoint,
produce a validated Homepage card.")

### 2. Happy-path steps
The steps that were ACTUALLY executed, collapsed to the path that
worked. Number them. Include the exact commands/scripts run.

### 3. Decision points
Where the run chose between options, and the criterion used.
("native widget vs customapi-only: prefer native when the vendor
exposes an aggregate.")

### 4. Failure modes encountered + fixes  ← highest-value content
Every dead end, wrong assumption, and its resolution, as a gotcha:
symptom → cause → rule. (These become the playbook's "hard-won
gotchas" section. The Uptime Kuma card produced four.)

### 5. Conventions honored
Boundaries, approval gates, source-of-truth rules, naming, paths.
("never edit the live container", "each live mutation approval-gated
with rollback ready", "journal the intervention".)

### 6. Verification
How the run proved success. Exact commands, endpoints, expected
output. If the session verified by the user eyeballing a screenshot,
record that as the verification step — don't invent a fake automated one.

### 7. Literals inventory
Table: literal | where it appeared | classification
(parameter / config / invariant / discard) | replacement.
Every proper noun, path, host, port, number, name. No exceptions.

### 8. Secrets sweep
Grep the mined material for tokens, keys, passwords, `Bearer`,
`PRIVATE`, `.env` VALUES. Anything found: record the Infisical path or
env var NAME only. A secret value in the record is a hard stop.

### 9. Reuse breadth
Who reuses this, where, how often? One honest paragraph. If the answer
is "probably never" — report that and recommend NOT forging.
