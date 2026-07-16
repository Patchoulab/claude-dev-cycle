#!/bin/bash
# Structural validation for the dev-cycle plugin. Exit 0 = valid.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0
err() { echo "FAIL: $1"; fail=1; }

[ -f "$ROOT/.claude-plugin/plugin.json" ] || err "missing plugin.json"
python3 -c "import json,sys; d=json.load(open('$ROOT/.claude-plugin/plugin.json')); sys.exit(0 if d.get('name')=='dev-cycle' and 'version' in d else 1)" || err "plugin.json invalid or name != dev-cycle"

[ -f "$ROOT/.claude-plugin/marketplace.json" ] || err "missing marketplace.json"
python3 -c "
import json, sys
d = json.load(open('$ROOT/.claude-plugin/marketplace.json'))
names = [p.get('name') for p in d.get('plugins', [])]
sys.exit(0 if d.get('name') and isinstance(d.get('plugins'), list) and 'dev-cycle' in names else 1)
" || err "marketplace.json invalid, missing 'name', or 'dev-cycle' not listed in plugins[]"
[ -f "$ROOT/hooks/hooks.json" ] && python3 -m json.tool "$ROOT/hooks/hooks.json" >/dev/null 2>&1 || err "hooks/hooks.json missing or invalid JSON"
[ -f "$ROOT/LICENSE" ] || err "missing LICENSE"
[ -f "$ROOT/README.md" ] || err "missing README.md"

# Every SKILL.md and command file must have frontmatter with name + description
while IFS= read -r f; do
  head -1 "$f" | grep -q '^---$' || err "$f: no frontmatter"
  grep -q '^name:' "$f" || err "$f: no name"
  grep -q '^description:' "$f" || err "$f: no description"
done < <(find "$ROOT/skills" "$ROOT/commands" -name "*.md" -not -path "*/references/*" -not -path "*/templates/*" 2>/dev/null)

# SKILL.md frontmatter budget + description convention, applied to every
# shipped skill. Machine-checks two clauses: frontmatter <=1024 chars and
# description starts with "Use when". A third convention ("contains no
# workflow summary") is a judgment call left to code review; NOT enforced here.
while IFS= read -r f; do
  fm_len=$(awk '/^---$/{c++; next} c==1' "$f" | wc -c | tr -d ' ')
  [ "$fm_len" -le 1024 ] || err "$f: frontmatter is $fm_len chars (must be <=1024)"
  desc=$(grep '^description:' "$f" | head -1 | sed 's/^description: *//')
  case "$desc" in
    "Use when"*) : ;;
    *) err "$f: description does not start with 'Use when'" ;;
  esac
done < <(find "$ROOT/skills" -name "SKILL.md" 2>/dev/null)

# Executables must be executable
while IFS= read -r f; do
  [ -x "$f" ] || err "$f: not executable"
done < <(find "$ROOT/hooks" "$ROOT/scripts" -name "*.sh" -o -name "*.py" 2>/dev/null | grep -v "/tests/")

# Scrub scope: the shippable tree + docs + README + manifests. This script and
# the test tree are excluded — they legitimately contain scrub patterns and
# fixture data. `Patchoulab` (the publishing org) is allowlisted on the
# deliberate identity surfaces; any other personal literal is a failure.
SCRUB_SCOPE=("$ROOT/skills" "$ROOT/commands" "$ROOT/hooks" "$ROOT/docs" \
             "$ROOT/README.md" "$ROOT/LICENSE" "$ROOT/.claude-plugin")
# shipped scripts too, but not the test tree
SHIPPED_SCRIPTS="$(find "$ROOT/scripts" -maxdepth 1 -type f 2>/dev/null)"

PERSONAL='pchouinard|hopchouinard|chouinpa|patchou|CDPQ|Home\.servers|agent-ops|Cognitive-Backlog|RecapFlow|/Volumes/|NVMe|10\.1\.|Patchou-Skill-forge'
OLDVOCAB='\bforge\b|land-slice|gitlink dance|skill-smith|cron-forge|plan-forge|session-relay|pr-babysit|session-lifecycle|review-harness|homelab|forge\.json|\.git/forge'

# Personal-literal sweep (allowlist Patchoulab)
if grep -rniE "$PERSONAL" "${SCRUB_SCOPE[@]}" $SHIPPED_SCRIPTS 2>/dev/null | grep -viE 'Patchoulab'; then
  err "personal literal in shipped/doc file"
fi
# Old-vocabulary sweep
if grep -rniE "$OLDVOCAB" "${SCRUB_SCOPE[@]}" $SHIPPED_SCRIPTS 2>/dev/null; then
  err "old-vocabulary token in shipped/doc file"
fi

[ $fail -eq 0 ] && echo "OK: plugin structure valid"
exit $fail
