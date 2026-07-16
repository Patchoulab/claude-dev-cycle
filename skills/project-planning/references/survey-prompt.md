# Survey fan-out prompt template

Dispatch one read-only subagent (Explore type where available) per cluster, all in a
single message. Substitute `{...}` from config; include the literal rules block.

```
You are surveying one cluster of a project portfolio. READ-ONLY: modify nothing.

Cluster: {cluster.name}
Roots (canonical absolute paths — do not probe path variants):
{one line per path}
Skip directories named: {excludeDirs}

For EVERY project directly under these roots, establish status from evidence, not
inference: `git log -1 --format=%ci` for last activity (file mtimes if not a repo);
presence/content of seed and ledger files ({handoffFile}, {progressFile} where a
.claude/dev-cycle.json exists); TODO/plan documents; README claims vs code reality.

Output EXACTLY one entry per project, no prose outside entries, verbatim headings:

### {project-name} — {absolute path}
- last-activity: <ISO date> (source: git|mtime)
- status: active | dormant | blocked | done | broken
- open-problem: <one sentence, or "none">
- next-step: <one concrete action, one sentence>
- blockers: <one sentence, or "none">
- tier: frontier | executor | either   # capability the next-step genuinely needs
- evidence: <file path or commit hash that justifies status>

Rules: one command per Bash call; never chain with && or || or &; absolute paths
only; timeouts on any remote call; unreadable directory → status: broken with the
error message as evidence — never guess.
```

Memory-dir variant (for {memoryDirs}): same entry format, one entry per project or
initiative mentioned in the memory files; `last-activity` = file mtime; `evidence` =
memory file path + line.

Synthesis (parent session, after all agents return): concatenate entries, sort by
status (active, blocked, dormant, done, broken), then run the roadmap diff. An agent
that returned malformed entries gets ONE retry with its own output quoted back and
the format restated; still malformed → mark its cluster "survey-failed" in the
roadmap update rather than fabricating entries.
