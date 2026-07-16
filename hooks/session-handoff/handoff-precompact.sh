#!/bin/bash
# handoff-precompact.sh — emergency seed snapshot before compaction (dev-cycle/session-handoff).
# Registered via hooks/hooks.json (PreCompact, manual + auto).
# Contract: NEVER block compaction — every path exits 0.
set -u

payload="$(cat 2>/dev/null || true)"

json_get() {  # json_get <key> <default>
  printf '%s' "$payload" | python3 -c '
import json, sys
key, default = sys.argv[1], sys.argv[2]
try:
    print(json.load(sys.stdin).get(key, default) or default)
except Exception:
    print(default)
' "$1" "$2" 2>/dev/null
}

cwd="$(json_get cwd "$PWD")"
trigger="$(json_get trigger unknown)"

# cwd may be a subdirectory of the repo; anchor the dev-cycle gate and all
# seed/ledger paths at the git toplevel (fall back to cwd outside a repo).
root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || true)"
[ -n "$root" ] || root="$cwd"

# Gate: only act inside dev-cycle-managed repos; stay silent elsewhere.
if [ ! -f "$root/.claude/dev-cycle.json" ] && [ ! -d "$root/.superpowers/sdd" ]; then
  exit 0
fi

cfg_get() {  # cfg_get <key> <default>
  python3 -c '
import json, sys
key, default = sys.argv[2], sys.argv[3]
try:
    print(json.load(open(sys.argv[1])).get(key, default) or default)
except Exception:
    print(default)
' "$root/.claude/dev-cycle.json" "$1" "$2" 2>/dev/null
}

seed_rel="$(cfg_get handoffFile .claude/dev-cycle/next-session.md)"
ledger_rel="$(cfg_get progressFile .claude/dev-cycle/progress.md)"
seed="$root/$seed_rel"
ledger="$root/$ledger_rel"
snapdir="$(dirname "$seed")"
snap="$snapdir/compact-snapshot.md"

mkdir -p "$snapdir" 2>/dev/null || exit 0
if [ -f "$snap" ]; then mv "$snap" "$snap.prev" 2>/dev/null; fi

{
  echo "# Compact Snapshot — emergency, written by handoff-precompact hook"
  echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ) trigger=$trigger"
  echo
  echo "## Git state"
  echo "- Branch: $(git -C "$root" rev-parse --abbrev-ref HEAD 2>/dev/null || echo n/a)"
  echo "- HEAD: $(git -C "$root" log -1 --oneline 2>/dev/null || echo n/a)"
  echo '```'
  git -C "$root" status --porcelain 2>/dev/null | head -40
  echo '```'
  echo
  echo "## Ledger tail ($ledger_rel)"
  if [ -f "$ledger" ]; then tail -n 25 "$ledger"; else echo "(no ledger yet)"; fi
  echo
  echo "## Canonical seed"
  if [ -f "$seed" ]; then
    echo "- $seed_rel exists (mtime: $(stat -f %Sm "$seed" 2>/dev/null || stat -c %y "$seed" 2>/dev/null))"
  else
    echo "- MISSING: $seed_rel not written yet this session"
  fi
  echo
  echo "## Post-compact re-orientation"
  echo "1. Read the ledger tail above."
  echo "2. Read $seed_rel if present; the canonical seed outranks this snapshot."
  echo "3. Announce the next action in one line before resuming work."
} > "$snap" 2>/dev/null || exit 0

printf '{"systemMessage":"session-handoff: emergency snapshot written to %s before compaction. After compaction, re-orient from the ledger and canonical seed."}\n' "$snap"
exit 0
