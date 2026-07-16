Review this change for security vulnerabilities.

## Repository context (authoritative — do not guess paths)
- Repo root (canonical, absolute): {{REPO_ROOT}}
- Commit under review: {{COMMIT_SHA}} — "{{COMMIT_SUBJECT}}" (branch {{BRANCH}})
{{MONOREPO_HINT_LINE}}
- RETIRED paths. These directories DO NOT EXIST. Never Read, ls, glob, or
  git against them; any path containing these prefixes is wrong:
{{RETIRED_PATHS_LIST}}

## Changed files
Pre-resolved absolute paths. Use these EXACT strings with Read; do not
reconstruct paths yourself. You may also Read any other file under
{{REPO_ROOT}}.
{{CHANGED_FILES_TABLE}}

## Submodule changes (resolved for you — do not re-derive the range)
{{SUBMODULE_SECTIONS}}

## Diff (unified; only + lines are new)
{{DIFF}}

## Command discipline (violations stall this unattended run on approval prompts)
- One command per Bash call. Never chain with `&&`, `||`, `;`, `&`, and
  never use redirects like `2>&1`. Never `cd`.
- Pre-approved commands: `git log/show/diff/blame/ls-files/ls-tree/
  cat-file/rev-parse/status` at the repo root; `git log/show/diff/
  ls-tree/ls-files/cat-file/rev-parse` (no blame/status) via
  `git -C <submodule-abs-path>` using exactly the absolute submodule
  paths listed above; `ls`, `grep`, `wc`, `jq`. `git grep` and `rg` are
  NOT approved — both admit arbitrary-command flags (`-O`/
  `--open-files-in-pager`, `--pre`) — use the native Grep tool for
  content search instead. Prefer Read/Grep/Glob tools over Bash for
  file content.
- Anything else (network calls, writes, fetch/push, chmod) is NOT
  approved and will hang the session. Do not attempt it.
{{ADVISORY_BLOCK}}

## Method
Investigate per the method in your instructions, then return the findings
list.
- Every finding MUST quote `vulnerableCode` verbatim from the CURRENT file
  (Read it — do not quote from the diff alone) and include line numbers.
- No findings → return an empty `findings` array. Do not pad, do not
  restate the diff.

## Output
Return results via StructuredOutput matching this schema. The `findings`
property is REQUIRED even when empty:
{{FINDINGS_SCHEMA}}
