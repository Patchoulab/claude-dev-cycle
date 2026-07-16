# Validation Procedure

All four gates must pass before packaging. Record results in the
final report. When the superpowers plugin is installed, the methodology
follows superpowers:writing-skills (testing-skills-with-subagents.md);
otherwise apply the gates below directly.

## Gate 1 — Frontmatter & shape lint
- name: letters/numbers/hyphens only.
- description: third person, starts "Use when", ≤1024 chars (target
  <500), NO workflow summary (SDO rule — a description that narrates
  the process becomes a shortcut agents follow instead of the body).
- Commands: description + argument-hint present; $ARGUMENTS used.
- Body word count sane for type (skills <500 words; push detail to
  references/playbook).
- No forbidden content: secret values, reset --hard/force-push
  guidance, chained shell commands.

## Gate 2 — Trigger test
1. Write 5 phrasings the user would naturally say to start this work,
   including one voice-dictation-garbled variant (he types "suagent
   driven", "Bump the get link").
2. Write 3 near-miss phrasings that must NOT fire (adjacent workflows,
   e.g. a session-handoff ask must not trigger a build command).
3. For each phrasing, run a fresh subagent given ONLY the local skill/
   command description list (the new artifact among the real ones) and
   ask: "which, if any, would you load for this request?"
4. Pass: ≥4/5 hits, 0/3 false fires. On failure: fix the description
   keywords (per writing-skills SDO), re-run. Commands additionally
   pass if the explicit /name is unambiguous against existing commands.

## Gate 3 — Dry-run on a synthetic variant
1. Construct a variant of the ORIGINAL task with different parameters
   (other card, other host, other repo — same shape).
2. Dispatch a fresh subagent with the artifact loaded and the variant
   as the task, in a worktree or with all mutations stubbed to
   plan-only. Prompt states the canonical absolute repo root.
3. Pass criteria:
   - follows the playbook's step order;
   - does NOT re-ask questions the playbook already answers;
   - hits every gotcha's rule without rediscovering it;
   - names the verification it would run.
4. For discipline-bearing artifacts (rules an agent might rationalize
   away), also run the writing-skills RED baseline: same scenario
   WITHOUT the artifact, confirm the failure it prevents actually
   occurs, and record the rationalizations for loophole-closing.

## Gate 4 — Literal-leak scan
grep the artifact + playbook for every extraction-record literal
classified parameter or discard. Any hit fails the gate. Literals
classified invariant must each carry a justification in the record.
