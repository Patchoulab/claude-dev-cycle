#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
CHECK="$HERE/../../git_worktree_check.sh"
fail=0

TMP=$(mktemp -d)
cd "$TMP"
git init -q
git config user.email test@example.com
git config user.name test
git commit -q --allow-empty -m init

rc=0; ( cd "$TMP" && bash "$CHECK" ) || rc=$?
[ "$rc" -eq 1 ] && echo "ok: primary=1" || { echo "FAIL: primary rc=$rc"; fail=1; }

git worktree add -q "$TMP/wt" -b feat/x >/dev/null 2>&1
rc=0; ( cd "$TMP/wt" && bash "$CHECK" ) || rc=$?
[ "$rc" -eq 0 ] && echo "ok: linked=0" || { echo "FAIL: linked rc=$rc"; fail=1; }

NR=$(mktemp -d)
rc=0; ( cd "$NR" && GIT_CEILING_DIRECTORIES="$(dirname "$NR")" bash "$CHECK" ) || rc=$?
[ "$rc" -eq 2 ] && echo "ok: nonrepo=2" || { echo "FAIL: nonrepo rc=$rc"; fail=1; }

# regression: a primary checkout under a path containing 'worktrees' must be 1, not 0.
# No commit needed — the check only reads git-dir/common-dir, which `git init` provides.
WTP="$(mktemp -d)/worktrees/proj"
mkdir -p "$WTP"
( cd "$WTP" && git init -q ) >/dev/null 2>&1
rc=0; ( cd "$WTP" && bash "$CHECK" ) || rc=$?
[ "$rc" -eq 1 ] && echo "ok: worktrees-named-primary=1" || { echo "FAIL: worktrees-named-primary rc=$rc"; fail=1; }

# regression (submodule worktree): a linked worktree of a submodule must be 0, not 1.
# Its git-dir is <parent>/.git/modules/<sub>/worktrees/<name> — no ".git/worktrees/"
# segment — so a glob-anchored check misreported it as primary; the git-dir vs
# git-common-dir comparison gets it right.
SUP=$(mktemp -d)
git init -q "$SUP/sub"
( cd "$SUP/sub" && git config user.email test@example.com && git config user.name test && git commit -q --allow-empty -m init )
git init -q "$SUP/super"
( cd "$SUP/super" && git config user.email test@example.com && git config user.name test && git -c protocol.file.allow=always submodule add -q "$SUP/sub" sub && git commit -q -m addsub )
git -C "$SUP/super/sub" worktree add -q "$SUP/super/subwt" -b feat/s >/dev/null 2>&1
rc=0; ( cd "$SUP/super/subwt" && bash "$CHECK" ) || rc=$?
[ "$rc" -eq 0 ] && echo "ok: submodule-worktree=0" || { echo "FAIL: submodule-worktree rc=$rc"; fail=1; }

rm -rf "$TMP" "$NR" "$SUP" "$(dirname "$(dirname "$WTP")")"
exit $fail
