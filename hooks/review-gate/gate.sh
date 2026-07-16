#!/bin/bash
# gate.sh -- unattended per-commit security-review gate (dev-cycle/review-gate).
#
# Contract: docs/skills/review-gate.md
#   sec 5.9 spawn & verification contract, sec 5.7 dedup lockfile protocol,
#   sec 5.8 submodule range resolution, sec 5.6 triage integration + audit,
#   sec 5.2/5.10 prompt template variables + config keys.
#
# Core principle: the gate does the environment work (path resolution,
# submodule expansion, dedup, permission preseeding) so the reviewer only
# does security work.
#
# A broken gate must NEVER block a commit: every failure path exits 0 after
# an audit line. Only `set -u` (not `-e`): we handle errors explicitly.
#
# Modes: hook (default) | hook-posttooluse | post-commit | run <sha>
#        | status | prune | replay <sha>... | install
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TRIAGE="$SCRIPT_DIR/triage.py"
VERIFY_EVIDENCE="$SCRIPT_DIR/verify_evidence.py"

# Portable timeout: prefer coreutils `timeout`/`gtimeout`; else a watchdog.
TIMEOUT_BIN="$(command -v timeout 2>/dev/null || command -v gtimeout 2>/dev/null || true)"
run_with_timeout() {  # run_with_timeout <secs> <cmd...>
  local secs="$1"; shift
  if [ -n "$TIMEOUT_BIN" ]; then
    "$TIMEOUT_BIN" "$secs" "$@"
    return $?
  fi
  "$@" &
  local cmd_pid=$!
  ( sleep "$secs"; kill -TERM "$cmd_pid" 2>/dev/null ) &
  local watch_pid=$!
  wait "$cmd_pid" 2>/dev/null
  local rc=$?
  kill "$watch_pid" 2>/dev/null
  wait "$watch_pid" 2>/dev/null
  return "$rc"
}

now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }
now_ms()  { python3 -c 'import time;print(int(time.time()*1000))' 2>/dev/null || echo 0; }

# path_mtime_epoch <path>: portable (BSD/GNU) mtime in epoch seconds, 0 on failure.
path_mtime_epoch() {
  stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0
}

# --------------------------------------------------------------------------
# JSON helpers (python3 -- no hard jq dependency, matches session-handoff style)
# --------------------------------------------------------------------------

json_stdin_get() {  # json_stdin_get <key> <default>   (reads stdin once)
  python3 -c '
import json, sys
key, default = sys.argv[1], sys.argv[2]
try:
    print(json.load(sys.stdin).get(key, default) or default)
except Exception:
    print(default)
' "$1" "$2" 2>/dev/null
}

# json_escape <string>: emit the string escaped for embedding *inside* a JSON
# string literal (no surrounding quotes) -- used for audit reason fields.
json_escape() {
  python3 -c 'import json,sys; sys.stdout.write(json.dumps(sys.argv[1])[1:-1])' "$1" 2>/dev/null
}

# extract_fenced_json <file> <n>: print the inner content of the n-th (1-based)
# ```json fenced block in <file>. Empty output if the file or block is absent
# (callers fall back to an inline default).
extract_fenced_json() {
  [ -f "$1" ] || return 0
  python3 -c '
import re, sys
try:
    text = open(sys.argv[1]).read()
except Exception:
    sys.exit(0)
try:
    n = int(sys.argv[2])
except Exception:
    sys.exit(0)
blocks = re.findall(r"```json\s*\n(.*?)```", text, re.DOTALL)
if 1 <= n <= len(blocks):
    sys.stdout.write(blocks[n-1].rstrip("\n"))
' "$1" "$2" 2>/dev/null
}

# render_retired_paths <json-array>: one "  - <path>" bullet per entry, or
# "  (none registered)" when the array is empty/absent (spec sec 5.2).
render_retired_paths() {
  python3 -c '
import json, sys
try:
    arr = json.loads(sys.argv[1])
except Exception:
    arr = []
if not isinstance(arr, list) or not arr:
    print("  (none registered)")
else:
    print("\n".join("  - " + str(x) for x in arr))
' "$1" 2>/dev/null
}

# cfg_get <dev-cycle.json> <dotted.key> <default>  -- navigates nested objects.
cfg_get() {
  python3 -c '
import json, sys
path, default = sys.argv[2], sys.argv[3]
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    print(default); sys.exit(0)
cur = d
for part in path.split("."):
    if isinstance(cur, dict) and part in cur:
        cur = cur[part]
    else:
        print(default); sys.exit(0)
if isinstance(cur, (dict, list)):
    print(json.dumps(cur))
elif isinstance(cur, bool):
    print("true" if cur else "false")
else:
    print(cur)
' "$1" "$2" "$3" 2>/dev/null
}

# --------------------------------------------------------------------------
# Audit trail (sec 5.6): one-or-more JSONL lines per invocation, in the
# git-common-dir so it is per-clone and never committed.
# --------------------------------------------------------------------------

AUDIT_LOG=""       # set once REVIEW_DIR is known
audit() {          # audit <json-object-without-braces>
  # replay is a dry run (sec 5.9 / SKILL "verify" step): it renders the prompt
  # and triage verdict but writes NO audit line, no findings, and takes no lock.
  [ "${REPLAY:-0}" = "1" ] && return 0
  local line="{\"ts\":\"$(now_iso)\",$1}"
  if [ -n "$AUDIT_LOG" ]; then
    printf '%s\n' "$line" >> "$AUDIT_LOG" 2>/dev/null || printf '%s\n' "$line" >&2
  else
    printf '%s\n' "$line" >&2
  fi
}

# --------------------------------------------------------------------------
# Glob overlay for review.neverSkipGlobs (sec 5.10 / carry-over from Task 8):
# triage takes no config, so neverSkip is a gate-side overlay -- any changed
# file matching one of the globs forces REVIEW regardless of triage's verdict.
# --------------------------------------------------------------------------

any_glob_match() {  # any_glob_match <newline-file-list> <json-array-of-globs>
  python3 -c '
import json, re, sys
files = [x for x in sys.argv[1].splitlines() if x]
try:
    globs = json.loads(sys.argv[2])
except Exception:
    globs = []
def to_re(g):
    out, i, n = [], 0, len(g)
    while i < n:
        c = g[i]
        if g[i:i+3] == "**/":
            out.append("(?:.*/)?"); i += 3; continue
        if g[i:i+2] == "**":
            out.append(".*"); i += 2; continue
        if c == "*":
            out.append("[^/]*"); i += 1; continue
        if c == "?":
            out.append("[^/]"); i += 1; continue
        out.append(re.escape(c)); i += 1
    return re.compile("^" + "".join(out) + "$")
pats = [to_re(g) for g in globs]
for f in files:
    tgt_full = f
    tgt_base = f.rsplit("/", 1)[-1]
    for g, p in zip(globs, pats):
        tgt = tgt_full if "/" in g else tgt_base
        if p.match(tgt):
            sys.exit(0)
sys.exit(1)
' "$1" "$2"
}

# --------------------------------------------------------------------------
# Submodule range resolution (sec 5.8): render resolved sections into the
# prompt, or a fail-closed UNRESOLVED section. Populates two globals.
# --------------------------------------------------------------------------

SUBMODULE_SECTIONS=""   # rendered prose for the prompt
SUBMODULE_DIFFS=""      # concatenated expanded diffs (re-triaged)
SUBMODULE_ABS_PATHS=""  # newline-separated absolute submodule paths seen this run

# Config-driven prompt injections (sec 5.2), resolved per-run in run_pipeline.
MONOREPO_HINT_LINE=""
RETIRED_PATHS_LIST="  (none registered)"
FINDINGS_SCHEMA='{"findings":[...]}'

resolve_submodules() {  # resolve_submodules <repo> <sha> <canonical_root> <cfg_json>
  local repo="$1" sha="$2" root="$3" cfg="$4"
  SUBMODULE_SECTIONS=""
  SUBMODULE_DIFFS=""
  SUBMODULE_ABS_PATHS=""
  local raw line srcsha dstsha status path
  # -m --first-parent (sec 5.8 / sec 6 "Merge commit"): a merge commit that
  # bumps a gitlink produces NO records from a plain diff-tree, so the same
  # first-parent flags the file table uses (see run_pipeline's `git show`) are
  # threaded here — otherwise a merge-borne submodule bump reaches the reviewer
  # unexpanded. Harmless no-op for ordinary single-parent commits.
  raw="$(git -C "$repo" diff-tree --no-commit-id -r -m --first-parent --root "$sha" 2>/dev/null)"
  [ -n "$raw" ] || { SUBMODULE_SECTIONS="(no submodule changes)"; return 0; }

  local found=0
  while IFS= read -r line; do
    # raw format: :<srcmode> <dstmode> <srcsha> <dstsha> <status>\t<path>
    case "$line" in
      :160000\ 160000\ *) : ;;
      *) continue ;;
    esac
    found=1
    local meta="${line%%$'\t'*}"
    path="${line#*$'\t'}"
    # meta = ":160000 160000 <A> <B> M"
    srcsha="$(printf '%s' "$meta" | awk '{print $3}')"
    dstsha="$(printf '%s' "$meta" | awk '{print $4}')"

    local sub remote
    sub="$root/$path"
    SUBMODULE_ABS_PATHS="${SUBMODULE_ABS_PATHS}${sub}
"
    remote="$(python3 -c '
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    for e in d.get("submodules", []):
        if e.get("path") == sys.argv[2]:
            print(e.get("remote", "origin")); break
    else:
        print("origin")
except Exception:
    print("origin")
' "$cfg" "$path" 2>/dev/null)"
    [ -n "$remote" ] || remote="origin"

    # dev-cycle.json absent path -> fall back to the checkout at root/<path> anyway.
    if [ ! -e "$sub" ]; then
      _submodule_unresolved "$path" "$srcsha" "$dstsha" "no checkout at $sub"
      audit "\"event\":\"submodule_unresolved\",\"sha\":\"$sha\",\"path\":\"$path\",\"reason\":\"no-checkout\""
      continue
    fi
    if ! git -C "$sub" rev-parse --git-dir >/dev/null 2>&1; then
      _submodule_unresolved "$path" "$srcsha" "$dstsha" "not a git checkout"
      audit "\"event\":\"submodule_unresolved\",\"sha\":\"$sha\",\"path\":\"$path\",\"reason\":\"not-a-checkout\""
      continue
    fi

    # Ensure both endpoints exist locally; fetch (30s) if not.
    if ! git -C "$sub" cat-file -e "${srcsha}^{commit}" 2>/dev/null || \
       ! git -C "$sub" cat-file -e "${dstsha}^{commit}" 2>/dev/null; then
      run_with_timeout 30 git -C "$sub" fetch "$remote" --quiet 2>/dev/null
      if ! git -C "$sub" cat-file -e "${dstsha}^{commit}" 2>/dev/null; then
        run_with_timeout 30 git -C "$sub" fetch "$remote" "$dstsha" --quiet 2>/dev/null
      fi
    fi
    if ! git -C "$sub" cat-file -e "${srcsha}^{commit}" 2>/dev/null || \
       ! git -C "$sub" cat-file -e "${dstsha}^{commit}" 2>/dev/null; then
      _submodule_unresolved "$path" "$srcsha" "$dstsha" "range missing after fetch"
      audit "\"event\":\"submodule_unresolved\",\"sha\":\"$sha\",\"path\":\"$path\",\"reason\":\"fetch-missing-range\""
      continue
    fi

    # Resolved: materialize log + stat + diff (diff capped by caller budget).
    local log stat sdiff commits nfiles
    log="$(git -C "$sub" log --oneline "${srcsha}..${dstsha}" 2>/dev/null | head -100)"
    stat="$(git -C "$sub" diff --stat "$srcsha" "$dstsha" 2>/dev/null)"
    sdiff="$(git -C "$sub" diff "$srcsha" "$dstsha" 2>/dev/null)"
    commits="$(printf '%s\n' "$log" | grep -c . )"
    nfiles="$(git -C "$sub" diff --name-only "$srcsha" "$dstsha" 2>/dev/null | grep -c . )"

    SUBMODULE_SECTIONS="${SUBMODULE_SECTIONS}
### Submodule ${path} — ${sub} (range ${srcsha}..${dstsha}, resolved)
Commits:
${log}

Files:
${stat}
"
    SUBMODULE_DIFFS="${SUBMODULE_DIFFS}
${sdiff}
"
    audit "\"event\":\"submodule_resolved\",\"sha\":\"$sha\",\"path\":\"$path\",\"range\":\"${srcsha}..${dstsha}\",\"commits\":${commits:-0},\"files\":${nfiles:-0}"
  done <<EOF
$raw
EOF

  [ "$found" -eq 1 ] || SUBMODULE_SECTIONS="(no submodule changes)"
  return 0
}

_submodule_unresolved() {  # <path> <A> <B> <reason>
  SUBMODULE_SECTIONS="${SUBMODULE_SECTIONS}
### Submodule ${1} — UNRESOLVED (${4})
Pointer moved ${2} -> ${3} but the content diff could not be resolved.
Do NOT attempt to fetch or resolve this range yourself. Review the
pointer bump only, and include a finding with category
\"UNVERIFIED SUBMODULE BUMP\" (severity: medium) so it stays visible.
"
}

# submodule_allowed_tools_lines <newline-separated-abs-paths>: prints one
# --allowedTools token per line for each (deduped) submodule absolute path,
# generated from the same source as the settings recipe (sec 5.5) so the
# prompt discipline block, settings.json, and CLI flags agree (sec 5.9).
submodule_allowed_tools_lines() {
  python3 -c '
import sys
seen = []
for line in sys.stdin.read().splitlines():
    p = line.strip()
    if not p or p in seen:
        continue
    seen.append(p)
for p in seen:
    for sub in ("log", "diff", "show", "ls-tree", "cat-file", "ls-files", "rev-parse"):
        print("Bash(git -C %s %s:*)" % (p, sub))
'
}

# --------------------------------------------------------------------------
# Prompt assembly (sec 5.2): render the template if it exists, else a
# minimal inline prompt (Task 10 ships templates/review-prompt.md). Both
# carry the absolute repo root and pre-resolved absolute changed-file paths.
# --------------------------------------------------------------------------

build_changed_files_table() {  # <repo> <sha> <root>
  local repo="$1" sha="$2" root="$3"
  # -M/-C: report a rename/copy as a single R/C entry (with the NEW path the
  #   reviewer must Read) instead of a spurious delete+add pair.
  # -m --first-parent: a merge commit yields its real first-parent file list
  #   instead of an empty one (plain diff-tree emits nothing for a merge).
  git -C "$repo" diff-tree --no-commit-id --name-status -M -C -m --first-parent -r --root "$sha" 2>/dev/null | \
  while IFS=$'\t' read -r status path rest; do
    [ -n "$path" ] || continue
    # Rename/copy entries are "<status>\t<old>\t<new>": keep only the current
    # (new) path so the reviewer never gets handed the retired old path.
    local oldpath=""
    case "$status" in
      R*|C*) if [ -n "$rest" ]; then oldpath="$path"; path="$rest"; fi ;;
    esac
    local abs="$root/$path"
    # Submodule gitlink bumps are directories, not files: resolve_submodules
    # ran first and recorded every gitlink absolute path in SUBMODULE_ABS_PATHS.
    # Point the reviewer at the expanded range instead of falsely reporting the
    # submodule path absent from the worktree.
    if printf '%s\n' "$SUBMODULE_ABS_PATHS" | grep -Fxq "$abs" 2>/dev/null; then
      printf -- '- %s %s (submodule bump; see the Submodule changes section for the expanded range)\n' "$status" "$abs"
      continue
    fi
    case "$status" in
      D*) printf -- '- D %s (deleted — content in diff only)\n' "$abs" ;;
      R*|C*) if [ -f "$abs" ]; then
               printf -- '- %s %s (renamed from %s)\n' "$status" "$abs" "$root/$oldpath"
             else
               printf -- '- %s %s (renamed from %s; path not present in worktree)\n' "$status" "$abs" "$root/$oldpath"
             fi ;;
      *)  if [ -f "$abs" ]; then
            printf -- '- %s %s\n' "$status" "$abs"
          else
            printf -- '- %s %s (path not present in worktree)\n' "$status" "$abs"
          fi ;;
    esac
  done
}

assemble_prompt() {  # <repo> <sha> <root> <subject> <branch> <changed_table> <diff> <out_file>
  local repo="$1" sha="$2" root="$3" subject="$4" branch="$5"
  local table="$6" diff="$7" out="$8"
  local tmpl="$PLUGIN_ROOT/skills/review-gate/templates/review-prompt.md"

  if [ -f "$tmpl" ]; then
    # Template path (Task 10). Config-driven injections (MONOREPO_HINT_LINE,
    # RETIRED_PATHS_LIST, FINDINGS_SCHEMA) are resolved by the caller into the
    # like-named globals (spec sec 5.2 variable table / sec 5.10 config keys).
    python3 - "$tmpl" "$out" \
      "$root" "$sha" "$subject" "$branch" "$table" "$SUBMODULE_SECTIONS" "$diff" \
      "$MONOREPO_HINT_LINE" "$RETIRED_PATHS_LIST" "$FINDINGS_SCHEMA" <<'PY'
import sys
tmpl, out, root, sha, subj, branch, table, subs, diff, hint, retired, schema = sys.argv[1:13]
t = open(tmpl).read()
repl = {
    "{{REPO_ROOT}}": root, "{{COMMIT_SHA}}": sha, "{{COMMIT_SUBJECT}}": subj,
    "{{BRANCH}}": branch, "{{CHANGED_FILES_TABLE}}": table,
    "{{SUBMODULE_SECTIONS}}": subs, "{{DIFF}}": diff,
    "{{MONOREPO_HINT_LINE}}": hint, "{{RETIRED_PATHS_LIST}}": retired,
    "{{ADVISORY_BLOCK}}": "", "{{FINDINGS_SCHEMA}}": schema,
}
for k, v in repl.items():
    t = t.replace(k, v)
open(out, "w").write(t)
PY
    return 0
  fi

  # Minimal inline fallback (structure mirrors the template's contract).
  {
    printf 'Review this change for security vulnerabilities.\n\n'
    printf '## Repository context (authoritative — do not guess paths)\n'
    printf -- '- Repo root (canonical, absolute): %s\n' "$root"
    printf -- '- Commit under review: %s — "%s" (branch %s)\n\n' "$sha" "$subject" "$branch"
    printf '## Changed files\n'
    printf 'Pre-resolved absolute paths. Use these EXACT strings with Read; do\n'
    printf 'not reconstruct paths yourself. You may also Read any other file\n'
    printf 'under %s.\n' "$root"
    printf '%s\n\n' "$table"
    printf '## Submodule changes (resolved for you — do not re-derive the range)\n'
    printf '%s\n\n' "$SUBMODULE_SECTIONS"
    printf '## Diff (unified; only + lines are new)\n'
    printf '%s\n\n' "$diff"
    printf '## Command discipline (violations stall this unattended run on approval prompts)\n'
    printf -- '- One command per Bash call. Never chain with `&&`, `||`, `;`, `&`, and never use `2>&1`. Never `cd`.\n'
    printf -- '- Pre-approved: read-only `git log/show/diff/blame/ls-files/ls-tree/cat-file/rev-parse/status` at the repo root and via `git -C <absolute-submodule-path>`; `ls`, `grep`, `wc`, `jq`. `git grep` and `rg` are NOT approved (arbitrary-command flags) — use the native Grep tool for content search. Prefer Read/Grep/Glob over Bash.\n'
    printf -- '- Anything else (network, writes, fetch/push, chmod) is NOT approved and will hang the session.\n\n'
    printf '## Method\n'
    printf 'Investigate per the method in your instructions, then return the findings list.\n'
    printf -- '- Every finding MUST quote `vulnerableCode` verbatim from the CURRENT file (Read it) and include line numbers.\n'
    printf -- '- No findings → return an empty `findings` array.\n\n'
    printf '## Output\n'
    printf 'Return results via StructuredOutput. The `findings` array is REQUIRED even when empty.\n'
  } > "$out"
}

# --------------------------------------------------------------------------
# Findings extraction + committed artifact (sec 5.9): confirmed findings
# append to <root>/.superpowers/security-findings.md (append-only; date +
# SHA + summary; never secret values).
# --------------------------------------------------------------------------

extract_findings_count() {  # <result_raw_file>  -> prints integer count, -1 if invalid
  # -1 = reviewer output is malformed (unparseable JSON, or no findings list
  # anywhere). A clean review MUST still carry "findings": [] -- callers treat
  # -1 as a failed review, never as zero findings (fail closed, sec 5.9).
  python3 -c '
import json, sys
try:
    raw = open(sys.argv[1]).read()
    d = json.loads(raw)
except Exception:
    print(-1); sys.exit(0)
f = d.get("findings")
if f is None and isinstance(d.get("result"), str):
    try:
        f = json.loads(d["result"]).get("findings")
    except Exception:
        f = None
print(len(f) if isinstance(f, list) else -1)
' "$1" 2>/dev/null || echo -1
}

append_findings() {  # <result_raw_file> <root> <sha> [status=confirmed]
  local raw="$1" root="$2" sha="$3" status="${4:-confirmed}"
  local dest="$root/.superpowers/security-findings.md"
  local patterns_file="$SCRIPT_DIR/../../scripts/secret_patterns.grep"
  mkdir -p "$root/.superpowers" 2>/dev/null || return 0
  python3 -c '
import json, re, sys, os, datetime
raw_file, dest, root, sha, patterns_file, status = sys.argv[1:7]
try:
    d = json.loads(open(raw_file).read())
except Exception:
    sys.exit(0)
findings = d.get("findings")
if findings is None and isinstance(d.get("result"), str):
    try:
        findings = json.loads(d["result"]).get("findings")
    except Exception:
        findings = None
if not isinstance(findings, list) or not findings:
    sys.exit(0)

# Scrub explanation against the shared secret-pattern source (same
# script-relative resolution discipline as triage.py) before it ever
# reaches the committed findings file. vulnerableCode stays excluded
# entirely (never written at all, see below).
secret_patterns = []
try:
    text = open(patterns_file).read()
    for line in text.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            secret_patterns.append(re.compile(line))
        except re.error:
            continue
except OSError:
    pass

def scrub(expl):
    if any(p.search(expl) for p in secret_patterns):
        return "[explanation withheld: matched secret pattern]"
    return expl

new = not os.path.exists(dest)
with open(dest, "a") as fh:
    if new:
        fh.write("# Security findings\n\nAppend-only. One entry per finding (non-confirmed status is marked inline). Never records secret values.\n")
    date = datetime.date.today().isoformat()
    for fnd in findings:
        # Summary only -- never echo vulnerableCode (may contain the secret).
        fp = str(fnd.get("filePath", "?"))
        cat = str(fnd.get("category", "?"))
        sev = str(fnd.get("severity", ""))
        expl = str(fnd.get("explanation", "")).splitlines()
        expl = expl[0] if expl else ""
        expl = scrub(expl)
        # A non-confirmed status (e.g. `unverified`, spec sec 5.9 step 4) is
        # marked inline so a fail-closed finding is never mistaken for a
        # confirmed one -- and never silently dropped.
        status_tag = "" if status == "confirmed" else "  **%s**" % status
        fh.write("\n- %s  %s  `%s`  [%s]%s%s\n  %s\n" % (
            date, sha[:12], fp, cat, (" " + sev) if sev else "", status_tag, expl))
' "$raw" "$dest" "$root" "$sha" "$patterns_file" "$status" 2>/dev/null
}

# extract_findings_json <result_raw_file>: print the findings array as JSON
# (or "[]"). Same top-level/`result`-string tolerance as extract_findings_count.
extract_findings_json() {
  python3 -c '
import json, sys
try:
    d = json.loads(open(sys.argv[1]).read())
except Exception:
    print("[]"); sys.exit(0)
f = d.get("findings")
if f is None and isinstance(d.get("result"), str):
    try:
        f = json.loads(d["result"]).get("findings")
    except Exception:
        f = None
print(json.dumps(f if isinstance(f, list) else []))
' "$1" 2>/dev/null || echo "[]"
}

# --------------------------------------------------------------------------
# Reviewer spawn (sec 5.9): one entry point shared by the review pass and the
# verification pass so both state one identical tool/permission/timeout
# contract. Reads its config from run_pipeline's locals via dynamic scope:
# SPAWN_REVIEWER, SPAWN_MODEL, SPAWN_TIMEOUT, and the SPAWN_ALLOWED array.
# --------------------------------------------------------------------------

spawn_claude() {  # spawn_claude <prompt_file> <out_raw> <max_turns>  -> spawn exit code
  run_with_timeout "$SPAWN_TIMEOUT" "$SPAWN_REVIEWER" -p "$(cat "$1")" \
    --model "$SPAWN_MODEL" \
    --permission-mode default \
    --allowedTools "${SPAWN_ALLOWED[@]}" \
    --disallowedTools "Edit" "Write" "NotebookEdit" \
      "Bash(git push:*)" "Bash(git fetch:*)" "Bash(git commit:*)" \
    --max-turns "$3" \
    --output-format json < /dev/null > "$2" 2>/dev/null
}

# assemble_verify_prompt <root> <candidates_file> <retired_list> <out> [note]
# Render templates/verify-prompt.md (sec 5.3); <note> is appended on a re-run
# to carry the prior rejection reasons back to the reviewer (sec 5.9 step 3).
assemble_verify_prompt() {
  local root="$1" cand_file="$2" retired_list="$3" out="$4" note="${5:-}"
  local tmpl="$PLUGIN_ROOT/skills/review-gate/templates/verify-prompt.md"
  local schema
  schema="$(extract_fenced_json "$PLUGIN_ROOT/skills/review-gate/references/schemas.md" 2)"
  [ -n "$schema" ] || schema='{"verdicts":[...]}'
  local candidates; candidates="$(cat "$cand_file" 2>/dev/null)"
  [ -n "$candidates" ] || candidates="[]"

  if [ -f "$tmpl" ]; then
    python3 - "$tmpl" "$out" "$root" "$candidates" "$retired_list" "$schema" "$note" <<'PY'
import sys
tmpl, out, root, cands, retired, schema, note = sys.argv[1:8]
t = open(tmpl).read()
for k, v in {
    "{{CANDIDATES_JSON}}": cands, "{{REPO_ROOT}}": root,
    "{{RETIRED_PATHS_LIST}}": retired, "{{VERDICTS_SCHEMA}}": schema,
}.items():
    t = t.replace(k, v)
if note:
    t = t + "\n\n" + note + "\n"
open(out, "w").write(t)
PY
    return 0
  fi

  # Minimal inline fallback (mirrors the template's contract).
  {
    printf 'You previously flagged these candidate vulnerabilities:\n%s\n\n' "$candidates"
    printf 'Repository root (absolute, canonical): %s\n' "$root"
    printf 'Retired paths (do not touch): %s\n\n' "$retired_list"
    printf 'For EACH candidate, Read the current file at %s/<filePath>, locate the\n' "$root"
    printf 'flagged code, and issue a verdict. Fail closed:\n'
    printf -- '- `confirm` only if the vulnerable pattern is present in what you just Read.\n'
    printf -- '- `dismiss` only if you can quote current code proving it is absent/fixed.\n'
    printf -- '- EVERY verdict must carry `evidence` {file,startLine,endLine,quote}; the\n'
    printf '  harness checks the quote appears at those lines. Evidence-free verdicts\n'
    printf '  are rejected and this pass is re-run.\n\n'
    printf 'Return via StructuredOutput (`verdicts` REQUIRED): %s\n' "$schema"
    [ -n "$note" ] && printf '\n%s\n' "$note"
  } > "$out"
}

# --------------------------------------------------------------------------
# Lock janitor (sec 5.7): prune lock dirs older than 7 days.
# --------------------------------------------------------------------------

prune_locks() {  # <locks_dir>
  local locks="$1"
  [ -d "$locks" ] || return 0
  find "$locks" -mindepth 1 -maxdepth 1 -type d -mtime +7 -exec rm -rf {} + 2>/dev/null
}

# --------------------------------------------------------------------------
# Core pipeline (sec 5.9): config -> lock -> diff -> submodule -> triage ->
# prompt -> spawn -> findings -> audit.
# --------------------------------------------------------------------------

run_pipeline() {  # run_pipeline <repo> <sha> <trigger>
  local repo="$1" sha="$2" trigger="$3"
  local start_ms; start_ms="$(now_ms)"

  # --- dependency check (broken gate must never block the commit) ---
  #     replay never spawns a reviewer, so it only needs git + python3.
  local reviewer="${DEV_CYCLE_CLAUDE_BIN:-claude}"
  if ! command -v git >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1; then
    [ "${REPLAY:-0}" = "1" ] && { echo "gate.sh replay: git and python3 are required" >&2; return 0; }
    audit "\"event\":\"gate_unavailable\",\"sha\":\"$sha\",\"reason\":\"missing-dependency\""
    return 0
  fi
  if [ "${REPLAY:-0}" != "1" ] && ! command -v "$reviewer" >/dev/null 2>&1; then
    audit "\"event\":\"gate_unavailable\",\"sha\":\"$sha\",\"reason\":\"missing-dependency\""
    return 0
  fi

  # --- resolve common-dir, review dir, audit log ---
  local common
  common="$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
  if [ -z "$common" ]; then
    audit "\"event\":\"gate_unavailable\",\"sha\":\"$sha\",\"reason\":\"no-git-common-dir\""
    return 0
  fi
  local review_dir="$common/dev-cycle/review"
  local locks_dir="$review_dir/locks"
  AUDIT_LOG="$review_dir/log.jsonl"
  # replay is side-effect-free: no lock dir, no janitor, no audit writes.
  if [ "${REPLAY:-0}" != "1" ]; then
    mkdir -p "$locks_dir" 2>/dev/null
    prune_locks "$locks_dir"
  fi

  # --- config load (sec 5.10) ---
  local cfg="$repo/.claude/dev-cycle.json"
  local canonical toplevel
  toplevel="$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null)"
  [ -n "$toplevel" ] || toplevel="$repo"
  if [ -f "$cfg" ]; then
    canonical="$(cfg_get "$cfg" canonicalRoot "$toplevel")"
    # A wrong canonicalRoot must not reintroduce path guessing.
    if [ "$canonical" != "$toplevel" ]; then
      audit "\"event\":\"root_mismatch\",\"sha\":\"$sha\",\"canonical\":\"$canonical\",\"toplevel\":\"$toplevel\""
      canonical="$toplevel"
    fi
  else
    canonical="$toplevel"
    audit "\"event\":\"config_fallback\",\"sha\":\"$sha\",\"reason\":\"no-dev-cycle-json\""
  fi
  local root="$canonical"

  local model max_turns timeout_s dedup_ttl max_diff never_globs verify_req
  model="$(cfg_get "$cfg" review.model sonnet)"
  max_turns="$(cfg_get "$cfg" review.maxTurns 40)"
  timeout_s="$(cfg_get "$cfg" review.timeoutSeconds 900)"
  dedup_ttl="$(cfg_get "$cfg" review.dedupTtlSeconds 3600)"
  max_diff="$(cfg_get "$cfg" review.maxDiffBytes 204800)"
  never_globs="$(cfg_get "$cfg" review.neverSkipGlobs '[]')"
  verify_req="$(cfg_get "$cfg" review.verification.required true)"

  # --- config-driven prompt injections (sec 5.2 / sec 5.10). Resolved into
  #     globals consumed by assemble_prompt / assemble_verify_prompt. ---
  local hint retired_arr
  hint="$(cfg_get "$cfg" review.monorepoHint "")"
  MONOREPO_HINT_LINE=""
  [ -n "$hint" ] && MONOREPO_HINT_LINE="- $hint"
  retired_arr="$(cfg_get "$cfg" retiredPaths '[]')"
  RETIRED_PATHS_LIST="$(render_retired_paths "$retired_arr")"
  FINDINGS_SCHEMA="$(extract_fenced_json "$PLUGIN_ROOT/skills/review-gate/references/schemas.md" 1)"
  [ -n "$FINDINGS_SCHEMA" ] || FINDINGS_SCHEMA='{"findings":[...]}'

  # --- review.enabled gate (sec 5.10 / sec 7 / sec 6 "not-configured"):
  #     the gate no-ops -- spawns nothing, acquires no lock -- unless
  #     review.enabled is true in the repo's dev-cycle.json. ---
  local review_enabled
  review_enabled="$(cfg_get "$cfg" review.enabled false)"
  if [ "$review_enabled" != "true" ]; then
    if [ "${REPLAY:-0}" = "1" ]; then
      printf 'review.enabled is not true in %s — run "gate.sh install" (or set review.enabled=true) first.\n' "$cfg"
      return 0
    fi
    audit "\"event\":\"skip\",\"sha\":\"$sha\",\"reason\":\"not-configured\""
    return 0
  fi

  # --- lock acquire (sec 5.7): atomic mkdir on the leaf, TTL steal ---
  #     replay takes no lock: it writes prompt.md into a throwaway temp dir so
  #     downstream `$lock/...` paths still resolve, then removes it on return.
  local lock="$locks_dir/$sha"
  local dedup_degraded=0
  if [ "${REPLAY:-0}" = "1" ]; then
    lock="$(mktemp -d 2>/dev/null)"
    [ -n "$lock" ] || lock="${TMPDIR:-/tmp}/dev-cycle-replay-$$-$sha"
    mkdir -p "$lock" 2>/dev/null
  elif ! mkdir "$lock" 2>/dev/null; then
    if [ ! -d "$lock" ]; then
      # mkdir failed AND the leaf does not exist: this is a lock CREATION
      # failure (review dir missing or unwritable), not lock contention.
      # Only genuine contention (an existing lock held by a live run) may skip
      # a security review -- a local permission problem must not. Proceed
      # WITHOUT dedup on a throwaway scratch dir and audit the degradation
      # (sec 5.7). The next commit still gets a fresh review attempt.
      audit "\"event\":\"gate_degraded\",\"sha\":\"$sha\",\"trigger\":\"$trigger\",\"reason\":\"lock-create-failed\""
      dedup_degraded=1
      lock="$(mktemp -d 2>/dev/null)"
      [ -n "$lock" ] || lock="${TMPDIR:-/tmp}/dev-cycle-degraded-$$-$sha"
      mkdir -p "$lock" 2>/dev/null
    else
      # The leaf exists: genuine contention with another run. Adjudicate the
      # TTL steal on the incumbent's liveness.
      local started age
      started="$(python3 -c '
import json,sys
try: print(json.load(open(sys.argv[1])).get("startedEpoch",0))
except Exception: print(0)
' "$lock/meta.json" 2>/dev/null)"
      started="${started:-0}"
      if [ "$started" = "0" ]; then
        # meta.json missing/unreadable (crash before write, or a race): fall
        # back to the lock directory's own mtime for age instead of
        # presuming the owner dead outright -- steal only if that age > TTL.
        local mtime
        mtime="$(path_mtime_epoch "$lock")"
        age=$(( $(date -u +%s) - ${mtime:-0} ))
        if [ "$age" -lt "$dedup_ttl" ]; then
          audit "\"event\":\"dedup_skip\",\"sha\":\"$sha\",\"trigger\":\"$trigger\",\"reason\":\"no-meta\",\"ageSeconds\":$age"
          return 0
        fi
      else
        age=$(( $(date -u +%s) - ${started%.*} ))
        if [ "$age" -lt "$dedup_ttl" ]; then
          audit "\"event\":\"dedup_skip\",\"sha\":\"$sha\",\"trigger\":\"$trigger\",\"ageSeconds\":$age"
          return 0
        fi
      fi
      # Presumed-dead owner: steal once.
      rm -rf "$lock" 2>/dev/null
      if ! mkdir "$lock" 2>/dev/null; then
        if [ ! -d "$lock" ]; then
          # Re-create failed with no leaf present: the review dir became
          # unwritable under us -- degrade rather than silently skip.
          audit "\"event\":\"gate_degraded\",\"sha\":\"$sha\",\"trigger\":\"$trigger\",\"reason\":\"lock-create-failed\""
          dedup_degraded=1
          lock="$(mktemp -d 2>/dev/null)"
          [ -n "$lock" ] || lock="${TMPDIR:-/tmp}/dev-cycle-degraded-$$-$sha"
          mkdir -p "$lock" 2>/dev/null
        else
          # A rival re-grabbed the leaf first: genuine contention, skip.
          audit "\"event\":\"dedup_skip\",\"sha\":\"$sha\",\"trigger\":\"$trigger\",\"reason\":\"steal-lost\""
          return 0
        fi
      fi
    fi
  fi
  if [ "${REPLAY:-0}" != "1" ] && [ "$dedup_degraded" -eq 0 ]; then
    printf '{"pid":%s,"host":"%s","started":"%s","startedEpoch":%s,"trigger":"%s"}\n' \
      "$$" "$(hostname 2>/dev/null || echo unknown)" "$(now_iso)" "$(date -u +%s)" "$trigger" \
      > "$lock/meta.json" 2>/dev/null
  fi

  # --- diff extraction ---
  local subject branch diff
  subject="$(git -C "$repo" log -1 --format=%s "$sha" 2>/dev/null)"
  branch="$(git -C "$repo" rev-parse --abbrev-ref HEAD 2>/dev/null)"
  # -m --first-parent (sec 6 "Merge commit"): merge commits get a real
  # first-parent diff instead of an empty one (an empty diff would falsely
  # triage to SKIP). Harmless no-op for non-merge commits.
  diff="$(git -C "$repo" show -m --first-parent --format= "$sha" 2>/dev/null)"

  # --- submodule expansion (sec 5.8) ---
  resolve_submodules "$repo" "$sha" "$root" "$cfg"

  # Triage runs on the parent diff plus any expanded submodule diffs so a
  # gitlink bump is judged on real content (sec 5.8: expanded verdict wins).
  local triage_input verdict_line verdict reason
  triage_input="$diff
$SUBMODULE_DIFFS"
  verdict_line="$(printf '%s' "$triage_input" | python3 "$TRIAGE" 2>/dev/null)"
  verdict="${verdict_line%% *}"
  reason="${verdict_line#* }"
  [ -n "$verdict" ] || { verdict="REVIEW"; reason="triage-unavailable"; }

  # --- neverSkipGlobs overlay (carry-over; triage takes no config) ---
  local changed_files
  changed_files="$(git -C "$repo" diff-tree --no-commit-id --name-only -r --root "$sha" 2>/dev/null)"
  if [ "$verdict" = "SKIP" ] && [ "$never_globs" != "[]" ] && [ -n "$never_globs" ]; then
    if any_glob_match "$changed_files" "$never_globs"; then
      verdict="REVIEW"; reason="never-skip-glob"
    fi
  fi

  # An unresolved submodule bump never SKIPs (sec 5.8 step 6).
  case "$SUBMODULE_SECTIONS" in
    *UNRESOLVED*) verdict="REVIEW"; [ "$reason" = "" ] && reason="submodule-unresolved" ;;
  esac

  local classes
  classes="$(python3 -c '
import json,sys
print(json.dumps([c for c in sys.argv[1].split("+") if c]))
' "$reason" 2>/dev/null)"
  [ -n "$classes" ] || classes="[\"$reason\"]"

  # --- SKIP: audit + result.json, spawn nothing (sec 5.6) ---
  if [ "$verdict" = "SKIP" ]; then
    if [ "${REPLAY:-0}" = "1" ]; then
      printf 'TRIAGE VERDICT: SKIP (%s)\n' "$reason"
      printf '(This commit would be SKIPPED — no reviewer prompt is assembled.)\n'
      rm -rf "$lock" 2>/dev/null
      return 0
    fi
    local dur=$(( $(now_ms) - start_ms ))
    audit "\"event\":\"skip\",\"sha\":\"$sha\",\"classes\":$classes,\"reason\":\"$reason\",\"durationMs\":$dur"
    printf '{"verdict":"SKIP","reason":"%s","durationMs":%s}\n' "$reason" "$dur" \
      > "$lock/result.json" 2>/dev/null
    return 0
  fi

  # --- REVIEW: assemble prompt ---
  local table prompt_file result_raw
  table="$(build_changed_files_table "$repo" "$sha" "$root")"
  prompt_file="$lock/prompt.md"
  result_raw="$lock/result_raw.json"

  # Diff budget (sec 7): truncate the body when over maxDiffBytes.
  local full_diff="$diff
$SUBMODULE_DIFFS"
  if [ "${#full_diff}" -gt "$max_diff" ] 2>/dev/null; then
    full_diff="$(printf '%s' "$full_diff" | head -c "$max_diff")
[... diff truncated at ${max_diff} bytes; see git show ${sha} for the full change ...]"
  fi

  assemble_prompt "$repo" "$sha" "$root" "$subject" "$branch" \
    "$table" "$full_diff" "$prompt_file"

  # --- replay (sec 5.9 / SKILL "verify" step): print the triage verdict and the
  #     rendered prompt that WOULD be sent, then stop. No spawn, no lock, no
  #     audit, no findings write. ---
  if [ "${REPLAY:-0}" = "1" ]; then
    printf 'TRIAGE VERDICT: %s (%s)\n\n' "$verdict" "$reason"
    printf '===== RENDERED REVIEW PROMPT for %s =====\n' "$sha"
    cat "$prompt_file"
    printf '\n===== END PROMPT (no reviewer spawned) =====\n'
    rm -rf "$lock" 2>/dev/null
    return 0
  fi

  # --- spawn reviewer (sec 5.9). Allowed/disallowed tool sets mirror the
  #     settings recipe (sec 5.5) so prompt, settings and flags agree.
  #     Per-submodule `git -C <SUB_ABS>` forms (sec 5.5/5.9) are generated
  #     from the same SUBMODULE_ABS_PATHS resolve_submodules populated. ---
  local -a sub_allowed_tools=()
  local tok
  while IFS= read -r tok; do
    [ -n "$tok" ] && sub_allowed_tools+=("$tok")
  done < <(printf '%s' "$SUBMODULE_ABS_PATHS" | submodule_allowed_tools_lines)

  # Shared spawn contract (read by spawn_claude via dynamic scope): identical
  # allowedTools / timeout for the review pass and the verification pass.
  local SPAWN_REVIEWER="$reviewer" SPAWN_MODEL="$model" SPAWN_TIMEOUT="$timeout_s"
  local -a SPAWN_ALLOWED=(
    "Read" "Grep" "Glob"
    "Bash(git log:*)" "Bash(git show:*)" "Bash(git diff:*)"
    "Bash(git blame:*)" "Bash(git ls-files:*)" "Bash(git ls-tree:*)"
    "Bash(git cat-file:*)" "Bash(git rev-parse:*)"
    "Bash(git status)" "Bash(ls:*)" "Bash(grep:*)"
    "Bash(wc:*)" "Bash(jq:*)"
    "${sub_allowed_tools[@]+"${sub_allowed_tools[@]}"}"
  )

  audit "\"event\":\"review_spawned\",\"sha\":\"$sha\",\"verdict\":\"$verdict\",\"reason\":\"$reason\",\"model\":\"$model\",\"trigger\":\"$trigger\""

  spawn_claude "$prompt_file" "$result_raw" "$max_turns"
  local spawn_rc=$?

  if [ "$spawn_rc" -ne 0 ]; then
    audit "\"event\":\"review_failed\",\"sha\":\"$sha\",\"exit\":$spawn_rc"
    printf '{"verdict":"failed","exit":%s}\n' "$spawn_rc" > "$lock/result.json" 2>/dev/null
    return 0
  fi

  # --- findings handling + verification pass (sec 5.9) ---
  local nfindings; nfindings="$(extract_findings_count "$result_raw")"
  local confirmed=0 dismissed=0 unverified=0 unadjudicated=0

  # Malformed/StructuredOutput-failed reviewer output is a FAILED review, not
  # a clean one: never record `done` with zero findings off invalid JSON.
  if [ "${nfindings:-0}" -lt 0 ]; then
    audit "\"event\":\"review_invalid_output\",\"sha\":\"$sha\""
    printf '{"verdict":"failed","reason":"invalid_reviewer_output"}\n' > "$lock/result.json" 2>/dev/null
    return 0
  fi

  if [ "${nfindings:-0}" -gt 0 ]; then
    if [ "$verify_req" = "true" ]; then
      # Evidence-integrity gate (sec 5.9). A verdict counts only with fresh
      # evidence (num_turns>=2) and a verbatim, line-anchored quote from the
      # CURRENT file. Rejected -> re-run once (maxRetries); still failing ->
      # candidates stay OPEN, marked `unverified` (fail closed: unverified is
      # never dismissed and never silently confirmed).
      local candidates_file="$lock/candidates.json"
      extract_findings_json "$result_raw" > "$candidates_file"
      local max_retries; max_retries="$(cfg_get "$cfg" review.verification.maxRetries 1)"
      case "$max_retries" in ''|*[!0-9]*) max_retries=1 ;; esac
      local verify_prompt_file="$lock/verify-prompt.md"
      local verify_raw="$lock/verify_raw.json"
      local attempt=0 accepted=0 vout="" vreasons="" vok=""
      while : ; do
        if [ "$attempt" -eq 0 ]; then
          assemble_verify_prompt "$root" "$candidates_file" "$RETIRED_PATHS_LIST" "$verify_prompt_file" ""
        else
          assemble_verify_prompt "$root" "$candidates_file" "$RETIRED_PATHS_LIST" "$verify_prompt_file" \
            "Your previous pass was rejected: ${vreasons}. Evidence is mandatory."
        fi
        spawn_claude "$verify_prompt_file" "$verify_raw" 20
        vout="$(python3 "$VERIFY_EVIDENCE" "$verify_raw" "$candidates_file" "$root" "$retired_arr" 2>/dev/null)"
        vok="$(printf '%s' "$vout" | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("ok"))
except Exception: print("None")' 2>/dev/null)"
        if [ "$vok" = "True" ]; then accepted=1; break; fi
        vreasons="$(printf '%s' "$vout" | python3 -c 'import json,sys
try: print("; ".join(json.load(sys.stdin).get("reasons",[])) or "unparseable")
except Exception: print("unparseable")' 2>/dev/null)"
        attempt=$(( attempt + 1 ))
        audit "\"event\":\"verify_rejected\",\"sha\":\"$sha\",\"reason\":\"$(json_escape "$vreasons")\",\"retry\":$attempt"
        [ "$attempt" -gt "$max_retries" ] && break
      done

      if [ "$accepted" -eq 1 ]; then
        confirmed="$(printf '%s' "$vout" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("confirmedCount",0))' 2>/dev/null)"
        dismissed="$(printf '%s' "$vout" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("dismissedCount",0))' 2>/dev/null)"
        [ -n "$confirmed" ] || confirmed=0
        [ -n "$dismissed" ] || dismissed=0
        if [ "${confirmed:-0}" -gt 0 ]; then
          local confirmed_file="$lock/confirmed.json"
          printf '%s' "$vout" | python3 -c 'import json,sys;json.dump({"findings":json.load(sys.stdin).get("confirmed",[])},open(sys.argv[1],"w"))' "$confirmed_file" 2>/dev/null
          append_findings "$confirmed_file" "$root" "$sha" confirmed
        fi
        # Dismissed findings are recorded only in the audit (sec 5.9): they do
        # NOT reach the committed findings file.
        audit "\"event\":\"verify_ok\",\"sha\":\"$sha\",\"confirmed\":${confirmed:-0},\"dismissed\":${dismissed:-0}"
      else
        # Fail closed (sec 5.9 step 4): candidates remain open, marked.
        unverified="$nfindings"
        local unverified_file="$lock/unverified.json"
        printf '{"findings":%s}' "$(cat "$candidates_file" 2>/dev/null)" > "$unverified_file"
        append_findings "$unverified_file" "$root" "$sha" unverified
        audit "\"event\":\"verification_failed\",\"sha\":\"$sha\",\"unverified\":${unverified:-0}"
      fi
    else
      # Verification disabled (sec 5.10): findings are recorded as-is so they
      # are never silently lost, but labeled `unadjudicated` rather than
      # `confirmed` -- with no verification pass run, nothing has actually
      # checked the evidence, so calling them "confirmed" would overstate
      # what the gate knows.
      append_findings "$result_raw" "$root" "$sha" unadjudicated
      unadjudicated="$nfindings"
    fi
  fi

  local dur=$(( $(now_ms) - start_ms ))
  audit "\"event\":\"done\",\"sha\":\"$sha\",\"verdict\":\"$verdict\",\"findings\":${nfindings:-0},\"confirmed\":${confirmed:-0},\"dismissed\":${dismissed:-0},\"unverified\":${unverified:-0},\"unadjudicated\":${unadjudicated:-0},\"durationMs\":$dur"
  printf '{"verdict":"%s","findings":%s,"confirmed":%s,"dismissed":%s,"unverified":%s,"unadjudicated":%s,"durationMs":%s}\n' \
    "$verdict" "${nfindings:-0}" "${confirmed:-0}" "${dismissed:-0}" "${unverified:-0}" "${unadjudicated:-0}" "$dur" > "$lock/result.json" 2>/dev/null
  return 0
}

# --------------------------------------------------------------------------
# Plugin root (for locating templates). CLAUDE_PLUGIN_ROOT when set (hook
# context), else derived from this script's location (hooks/review-gate).
# --------------------------------------------------------------------------

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

# --------------------------------------------------------------------------
# install (sec 5.9 / SKILL install procedure): idempotently wire the gate into
# a repo -- git post-commit hook, project settings allowlist, dev-cycle.json review
# block -- and warn about duplicate legacy review triggers. Never clobbers
# unrelated content; a second run is a no-op (file contents unchanged).
# --------------------------------------------------------------------------

INSTALL_MARK_START="# >>> dev-cycle review-gate (managed) >>>"
INSTALL_MARK_END="# <<< dev-cycle review-gate (managed) <<<"

do_install() {  # do_install <repo>
  local repo="$1"
  local toplevel common gate_abs cfg settings hook_file allowlist_tmpl review_tmpl
  toplevel="$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null)"
  [ -n "$toplevel" ] || { echo "gate.sh install: not in a git repo" >&2; return 1; }
  common="$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
  [ -n "$common" ] || { echo "gate.sh install: cannot resolve git-common-dir" >&2; return 1; }
  gate_abs="$SCRIPT_DIR/gate.sh"
  cfg="$toplevel/.claude/dev-cycle.json"
  settings="$toplevel/.claude/settings.json"
  hook_file="$common/hooks/post-commit"
  allowlist_tmpl="$PLUGIN_ROOT/skills/review-gate/templates/settings-allowlist.json"
  review_tmpl="$PLUGIN_ROOT/skills/review-gate/templates/review-block.jsonc"

  local -a summary=()

  # --- 1. post-commit hook (git-common-dir; append guarded block, never clobber) ---
  mkdir -p "$(dirname "$hook_file")" 2>/dev/null
  if [ -f "$hook_file" ] && grep -qF "$INSTALL_MARK_START" "$hook_file" 2>/dev/null; then
    summary+=("post-commit hook: managed block already present — skipped")
  else
    if [ ! -f "$hook_file" ]; then
      printf '#!/bin/sh\n' > "$hook_file"
      summary+=("post-commit hook: created $hook_file")
    else
      summary+=("post-commit hook: appended managed block to existing $hook_file (existing content preserved)")
    fi
    {
      printf '%s\n' "$INSTALL_MARK_START"
      printf '# dev-cycle review-gate per-commit security gate. Remove this block to uninstall.\n'
      printf '# Resolve the committed SHA synchronously BEFORE backgrounding the\n'
      printf '# review, so a rapid follow-up commit/amend cannot advance HEAD and\n'
      printf '# leave this commit reviewing the newer one (or unreviewed).\n'
      printf 'commit_sha="$(git rev-parse HEAD 2>/dev/null)"\n'
      printf 'if [ -n "$commit_sha" ]; then\n'
      printf '  "%s" run "$commit_sha" >/dev/null 2>&1 &\n' "$gate_abs"
      printf 'fi\n'
      printf '%s\n' "$INSTALL_MARK_END"
    } >> "$hook_file"
    chmod +x "$hook_file" 2>/dev/null
  fi

  # --- 2. settings allowlist merge (union into permissions.allow) ---
  local settings_out
  settings_out="$(python3 - "$allowlist_tmpl" "$settings" "$toplevel" "$cfg" <<'PY'
import json, os, sys
tmpl_path, settings_path, root, cfg_path = sys.argv[1:5]
try:
    allow_tmpl = json.load(open(tmpl_path)).get("permissions", {}).get("allow", [])
except Exception:
    allow_tmpl = []

# Absolute submodule paths from dev-cycle.json (canonicalRoot + path), for the
# `git -C <SUB_ABS> ...` template entries (spec 5.5).
subs, canonical = [], root
try:
    fd = json.load(open(cfg_path))
    canonical = fd.get("canonicalRoot", root) or root
    for e in fd.get("submodules", []):
        p = e.get("path")
        if p:
            subs.append(canonical.rstrip("/") + "/" + p)
except Exception:
    pass

expanded = []
for entry in allow_tmpl:
    if "<SUB_ABS>" in entry:
        for s in subs:
            expanded.append(entry.replace("<SUB_ABS>", s))
    else:
        expanded.append(entry)

existed = os.path.exists(settings_path)
cur = {}
if existed:
    try:
        cur = json.load(open(settings_path))
    except Exception:
        cur = {}
if not isinstance(cur, dict):
    cur = {}
perms = cur.get("permissions")
if not isinstance(perms, dict):
    perms = {}; cur["permissions"] = perms
allow = perms.get("allow")
if not isinstance(allow, list):
    allow = []; perms["allow"] = allow

seen = set(allow)
added = 0
for e in expanded:
    if e not in seen:
        allow.append(e); seen.add(e); added += 1

if added > 0 or not existed:
    os.makedirs(os.path.dirname(settings_path), exist_ok=True)
    with open(settings_path, "w") as fh:
        json.dump(cur, fh, indent=2); fh.write("\n")
    print("settings.json: %s, %d allowlist entr%s added (total %d)"
          % ("created" if not existed else "merged", added,
             "y" if added == 1 else "ies", len(allow)))
else:
    print("settings.json: all allowlist entries already present — skipped")
PY
)"
  summary+=("$settings_out")

  # --- 3. dev-cycle.json review block (seed only if absent; strip JSONC comments) ---
  local cfg_out
  cfg_out="$(python3 - "$review_tmpl" "$cfg" "$toplevel" <<'PY'
import json, os, sys
tmpl_path, cfg_path, toplevel = sys.argv[1:4]

def strip_jsonc(s):
    out, i, n, instr, esc = [], 0, len(s), False, False
    while i < n:
        c = s[i]
        if instr:
            out.append(c)
            if esc: esc = False
            elif c == "\\": esc = True
            elif c == '"': instr = False
            i += 1; continue
        if c == '"':
            instr = True; out.append(c); i += 1; continue
        if c == '/' and i + 1 < n and s[i+1] == '/':
            while i < n and s[i] != '\n': i += 1
            continue
        if c == '/' and i + 1 < n and s[i+1] == '*':
            i += 2
            while i + 1 < n and not (s[i] == '*' and s[i+1] == '/'): i += 1
            i += 2; continue
        out.append(c); i += 1
    return "".join(out)

try:
    block = json.loads(strip_jsonc(open(tmpl_path).read()))
except Exception as e:
    print("dev-cycle.json review block: template unreadable (%s) — skipped" % e); sys.exit(0)
review = block.get("review", {})

existed = os.path.exists(cfg_path)
fd = {}
if existed:
    try:
        fd = json.load(open(cfg_path))
    except Exception:
        fd = {}
if not isinstance(fd, dict):
    fd = {}

if "review" in fd:
    print("dev-cycle.json review block: already present — left untouched")
    sys.exit(0)

fd["review"] = review
if not existed and "canonicalRoot" not in fd:
    fd["canonicalRoot"] = toplevel
os.makedirs(os.path.dirname(cfg_path), exist_ok=True)
with open(cfg_path, "w") as fh:
    json.dump(fd, fh, indent=2); fh.write("\n")
print("dev-cycle.json review block: seeded%s" % (" (dev-cycle.json created)" if not existed else ""))
PY
)"
  summary+=("$cfg_out")

  # --- 4. duplicate-trigger detection (marker heuristic; warn, never remove) ---
  if [ -d "$common/hooks" ]; then
    local hf remainder
    for hf in "$common/hooks/"*; do
      [ -f "$hf" ] || continue
      case "$hf" in *.sample) continue ;; esac
      # Strip our own managed block so we never warn on the trigger we just wrote.
      remainder="$(python3 -c '
import sys
start = "# >>> dev-cycle review-gate (managed) >>>"
end   = "# <<< dev-cycle review-gate (managed) <<<"
out, skip = [], False
try:
    lines = open(sys.argv[1], errors="replace").read().splitlines(True)
except Exception:
    sys.exit(0)
for ln in lines:
    s = ln.rstrip("\n")
    if s == start: skip = True; continue
    if s == end: skip = False; continue
    if not skip: out.append(ln)
sys.stdout.write("".join(out))
' "$hf" 2>/dev/null)"
      if printf '%s' "$remainder" | grep -qE 'gate\.sh|Review this change for security vulnerabilities' 2>/dev/null; then
        summary+=("WARNING: $hf looks like a second security-review trigger — remove it to avoid duplicate reviews (NOT auto-removed; dedup lock is the runtime backstop)")
      fi
    done
  fi

  # --- 5. summary ---
  printf 'gate.sh install — summary:\n'
  local s
  for s in "${summary[@]+"${summary[@]}"}"; do
    printf '  - %s\n' "$s"
  done
  printf 'Verify with: gate.sh replay HEAD\n'
  return 0
}

# --------------------------------------------------------------------------
# Mode dispatch
# --------------------------------------------------------------------------

repo_from_cwd() {  # <cwd>  -> prints toplevel or empty
  git -C "$1" rev-parse --show-toplevel 2>/dev/null
}

mode="${1:-hook}"
case "$mode" in
  hook)
    payload="$(cat 2>/dev/null || true)"
    cwd="$(printf '%s' "$payload" | json_stdin_get cwd "$PWD")"
    repo="$(repo_from_cwd "$cwd")"
    [ -n "$repo" ] || exit 0
    sha="$(git -C "$repo" rev-parse HEAD 2>/dev/null)"
    [ -n "$sha" ] || exit 0
    run_pipeline "$repo" "$sha" "hook"
    exit 0
    ;;
  hook-posttooluse)
    payload="$(cat 2>/dev/null || true)"
    cmd="$(printf '%s' "$payload" | python3 -c '
import json,sys
try: print(((json.load(sys.stdin).get("tool_input") or {}).get("command")) or "")
except Exception: print("")
' 2>/dev/null)"
    # Only git history-writing commands; anything else is a <50ms no-op.
    case "$cmd" in
      git\ commit* | git\ merge* | git\ cherry-pick* | git\ revert* | \
      git\ -C\ *\ commit* | git\ -C\ *\ merge* | git\ -C\ *\ cherry-pick* | git\ -C\ *\ revert*) : ;;
      *) exit 0 ;;
    esac
    cwd="$(printf '%s' "$payload" | json_stdin_get cwd "$PWD")"
    # A `git -C <path> commit ...` writes history into <path>, NOT the hook cwd.
    # Resolve the repo from the -C target (absolute, or relative to cwd) so the
    # right HEAD is reviewed -- the absolute-path submodule-commit workflow this
    # plugin choreographs would otherwise review the wrong repo or no-op.
    ctarget="$(printf '%s' "$cmd" | python3 -c '
import shlex, sys
try:
    parts = shlex.split(sys.stdin.read())
except Exception:
    parts = []
tgt = ""
i = 0
while i < len(parts):
    if parts[i] == "-C" and i + 1 < len(parts):
        tgt = parts[i + 1]
        break
    i += 1
print(tgt)
' 2>/dev/null)"
    if [ -n "$ctarget" ]; then
      case "$ctarget" in
        /*) : ;;
        *)  ctarget="$cwd/$ctarget" ;;
      esac
      repo="$(repo_from_cwd "$ctarget")"
    else
      repo="$(repo_from_cwd "$cwd")"
    fi
    [ -n "$repo" ] || exit 0
    sha="$(git -C "$repo" rev-parse HEAD 2>/dev/null)"
    [ -n "$sha" ] || exit 0
    # Detach so the hook returns within its 20s budget.
    nohup "$0" run "$sha" "$repo" >/dev/null 2>&1 &
    exit 0
    ;;
  post-commit)
    repo="$(repo_from_cwd "$PWD")"
    [ -n "$repo" ] || exit 0
    # Skip mid-rebase; final commits get reviewed post-rebase.
    if [ -d "$repo/.git/rebase-merge" ] || [ -d "$repo/.git/rebase-apply" ]; then
      exit 0
    fi
    sha="$(git -C "$repo" rev-parse HEAD 2>/dev/null)"
    [ -n "$sha" ] || exit 0
    run_pipeline "$repo" "$sha" "post-commit"
    exit 0
    ;;
  run)
    sha="${2:-}"
    repo="${3:-$(repo_from_cwd "$PWD")}"
    [ -n "$sha" ] || { echo "usage: gate.sh run <sha> [repo]" >&2; exit 2; }
    [ -n "$repo" ] || { echo "gate.sh run: not in a git repo" >&2; exit 2; }
    # Resolve refs (e.g. the post-commit hook passes `run HEAD`) to a full SHA
    # so the dedup lock key is the commit, not a moving ref (sec 5.7).
    sha="$(git -C "$repo" rev-parse "$sha" 2>/dev/null || echo "$sha")"
    run_pipeline "$repo" "$sha" "manual"
    exit 0
    ;;
  prune)
    repo="$(repo_from_cwd "$PWD")"
    [ -n "$repo" ] || exit 0
    common="$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
    prune_locks "$common/dev-cycle/review/locks"
    exit 0
    ;;
  status)
    repo="$(repo_from_cwd "$PWD")"
    [ -n "$repo" ] || { echo "not in a git repo" >&2; exit 0; }
    common="$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
    rd="$common/dev-cycle/review"
    echo "review dir: $rd"
    echo "locks:"; ls -1 "$rd/locks" 2>/dev/null || echo "  (none)"
    echo "last 20 audit lines:"
    tail -n 20 "$rd/log.jsonl" 2>/dev/null || echo "  (no audit log)"
    exit 0
    ;;
  replay)
    shift
    [ "$#" -ge 1 ] || { echo "usage: gate.sh replay <sha>..." >&2; exit 2; }
    repo="$(repo_from_cwd "$PWD")"
    [ -n "$repo" ] || { echo "gate.sh replay: not in a git repo" >&2; exit 2; }
    REPLAY=1
    for arg in "$@"; do
      fsha="$(git -C "$repo" rev-parse "$arg" 2>/dev/null || echo "$arg")"
      run_pipeline "$repo" "$fsha" "replay"
    done
    exit 0
    ;;
  install)
    repo="$(repo_from_cwd "$PWD")"
    [ -n "$repo" ] || { echo "gate.sh install: not in a git repo" >&2; exit 2; }
    do_install "$repo"
    exit 0
    ;;
  *)
    echo "gate.sh: unknown mode '$mode'" >&2
    exit 2
    ;;
esac
