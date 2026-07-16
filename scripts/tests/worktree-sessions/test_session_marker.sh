#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
MARKER="$HERE/../../session_marker.sh"
fail=0
ok() { echo "ok: $1"; }
bad() { echo "FAIL: $1"; fail=1; }

TMP=$(mktemp -d)
cd "$TMP"
git init -q
git config user.email test@example.com
git config user.name test
git commit -q --allow-empty -m init

bash "$MARKER" write feat/x '{"branch":"feat/x","startedFrom":"seed"}'
out=$(bash "$MARKER" read feat/x | tr -d '[:space:]')
[ "$out" = '{"branch":"feat/x","startedFrom":"seed"}' ] && ok roundtrip || bad "roundtrip got: $out"

[ -f "$TMP/.git/dev-cycle/session/feat/x.json" ] && ok nested-path || bad nested-path

if bash "$MARKER" read feat/absent >/dev/null 2>&1; then bad absent-should-fail; else ok absent-nonzero; fi

bash "$MARKER" delete feat/x
if bash "$MARKER" delete feat/x; then ok delete-idempotent; else bad delete-idempotent; fi

# cross-worktree: a marker written inside a linked worktree is readable at root
git worktree add -q "$TMP/wt" -b feat/cw >/dev/null 2>&1
( cd "$TMP/wt" && bash "$MARKER" write feat/cw '{"branch":"feat/cw"}' )
cw=$(cd "$TMP" && bash "$MARKER" read feat/cw | tr -d '[:space:]')
[ "$cw" = '{"branch":"feat/cw"}' ] && ok cross-worktree-read || bad "cross-worktree-read got: $cw"

rm -rf "$TMP"
exit $fail
