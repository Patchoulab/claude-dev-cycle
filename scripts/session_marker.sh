#!/usr/bin/env bash
# session_marker.sh — read/write/delete the worktree-sessions marker under the
# git-common-dir state path (spec 11 §5.3). Worktrees share the common dir, so
# a marker written inside a worktree is readable there and at the repo root.
#
# Usage:
#   session_marker.sh write  <slug> <json>
#   session_marker.sh read   <slug>
#   session_marker.sh delete <slug>
set -uo pipefail

cmd="${1:-}"; slug="${2:-}"
if [ -z "$cmd" ] || [ -z "$slug" ]; then
  echo "usage: $0 {write|read|delete} <slug> [json]" >&2
  exit 2
fi

common=$(git rev-parse --git-common-dir 2>/dev/null) || { echo "not a git repo" >&2; exit 2; }
case "$common" in /*) ;; *) common="$(pwd)/$common" ;; esac
path="$common/dev-cycle/session/$slug.json"

case "$cmd" in
  write)
    json="${3:-}"
    [ -n "$json" ] || { echo "write needs json" >&2; exit 2; }
    mkdir -p "$(dirname "$path")"
    printf '%s\n' "$json" > "$path.tmp" && mv "$path.tmp" "$path"
    ;;
  read)
    [ -f "$path" ] || exit 1
    cat "$path"
    ;;
  delete)
    rm -f "$path"
    ;;
  *)
    echo "unknown command: $cmd" >&2
    exit 2
    ;;
esac
