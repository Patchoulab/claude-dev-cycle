# Executor-plan gate

The bar: the named executor model implements the plan correctly with ZERO judgment
calls. Every item must pass before the plan is presented or committed. Report each
failure and its fix — the gate catching things is the feature.

1. **Header** names the CONCRETE executor model — the `executor` tier alias from
   config, resolved to the current concrete model name at plan-writing time — plus
   exactly one repo (canonical absolute root) and the roadmap ID:
   `Executor: <resolved model> (alias: <executor>) / Repo: <abs path> / Roadmap: ROADMAP.md#R-<NNN>`
2. **Paths:** every file created or modified is named exactly (repo-relative from the
   stated root). "Find the relevant file" or glob-and-guess = fail.
3. **No open choices.** Grep the plan for: choose, decide, either, you may, consider,
   appropriate, as needed, TBD, or similar, options, up to you. Every hit is either
   rewritten as a made decision (with the reason recorded) or is a genuine runtime
   conditional keyed to an observable predicate ("if the table already exists, ...").
4. **Designs decided:** schemas, names, signatures, error behavior, library choices,
   config keys — all stated, none delegated.
5. **Verification per task:** each task ends with exact command(s) and expected
   output. "Make sure it works" = fail.
6. **Zero-context read test:** read each task in isolation; if executing it requires
   information from conversation rather than from the plan, inline that information.
7. **Dependencies explicit:** task ordering stated; anything parallelizable marked.
8. **Cross-repo interfaces** (multi-repo items): the shared contract (format,
   endpoint, signature) appears verbatim and identically in every repo's plan.
9. **Escalation rule present:** "If reality contradicts this plan, STOP and report in
   your final message; do not improvise a workaround."
10. **Safety:** no `reset --hard`, no force-push, no destructive-git guidance
    anywhere (same rule as the seed schema, same reason: the Codex gate already
    caught one hand-written seed with unsafe sync instructions).
11. **Roadmap linkage:** plan file saved under `plansDir`, linked from the roadmap
    item, item status `planned`.
