# <Workflow> Playbook

How to <goal> **without re-deriving the context every time.** Read this
first; it encodes the lessons from <originating work, dated>.

## 0. Boundaries & source of truth
<From extraction §5: what owns what, what is never edited directly,
where secrets live (names/paths only), what is approval-gated.>

## 1. The pipeline
<From extraction §2: the exact commands/scripts in order, with one-line
purpose each. One command per line — the consumer runs them as separate
Bash calls.>

## 2. Check before you design
<From extraction §3/§4: the recon/verification that must happen BEFORE
building — the assumptions that died expensively in the original run,
and the cheap command that tests each one.>

## 3. The reusable pattern
<From extraction §2/§3: the parameterized core artifact/config/code
shape, with <angle-bracket> parameters — never the original literals.>

## 4. Gotchas (hard-won)
<From extraction §4: every symptom → cause → rule. Keep the original
run's specifics as EXAMPLES, clearly marked, not as the rule.>

## 5. The process
<Numbered end-to-end steps including brainstorm/spec gates if the
original used them, and the journaling/registration duties.>

## 6. Worked example
<Links to the originating spec, plan, journal, and commit/PR — the
reference implementation.>

## 7. Quick-fill
<From extraction §7: one blank line per parameter, exactly the inputs a
new run needs. e.g.
- Target + name: __________
- Data source / endpoint: __________ — verified reachable? __________>
