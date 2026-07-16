You previously flagged these candidate vulnerabilities:
{{CANDIDATES_JSON}}

Repository root (absolute, canonical): {{REPO_ROOT}}
Retired paths (do not touch): {{RETIRED_PATHS_LIST}}

For EACH candidate, in order, BEFORE issuing any verdict:
1. Read the current file at its absolute path: {{REPO_ROOT}}/<filePath>.
   The code may have changed since flagging — the diff you saw is stale.
2. Locate the flagged code in what you just Read.

Verdict rules — fail closed:
- `confirm` only if the vulnerable pattern is present in the code you
  just Read.
- `dismiss` only if you can quote the current code proving the pattern is
  absent or fixed.
- EVERY verdict must carry `evidence`: `{"file": <absolute path>,
  "startLine": n, "endLine": n, "quote": "<verbatim current code>"}`.
  The harness mechanically checks that `quote` appears at those lines in
  the current file. Verdicts without valid evidence are rejected and this
  pass is re-run — an evidence-free verdict is worse than no verdict.

Same command discipline as the review pass: one command per Bash call, no
chaining, no cd, absolute paths only.

Return via StructuredOutput matching this schema (`verdicts` REQUIRED):
{{VERDICTS_SCHEMA}}
