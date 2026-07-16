#!/usr/bin/env bash
# Proves the git-level teardown ordering CLOSE relies on: a merged feature
# worktree can be removed, its branch drops, and main fast-forwards — the
# operations ExitWorktree(remove) + root sync perform (spec 11 §8 sc.5).
set -uo pipefail
fail=0
ok() { echo "ok: $1"; }
bad() { echo "FAIL: $1"; fail=1; }

TMP=$(mktemp -d)
git init -q --bare "$TMP/origin.git"
git clone -q "$TMP/origin.git" "$TMP/work" 2>/dev/null
cd "$TMP/work"
git config user.email t@t; git config user.name t
git commit -q --allow-empty -m init
git branch -M main
git push -q origin main

# open: a feature worktree branched from main
git worktree add -q "$TMP/work/wt" -b feat/x >/dev/null 2>&1
cd "$TMP/work/wt"
git config user.email t@t; git config user.name t
echo change > f.txt
git add f.txt
git commit -q -m "feat: change"
merged_sha=$(git rev-parse HEAD)
git push -q origin feat/x

# simulate the PR merge landing on origin/main (fast-forward)
git push -q origin feat/x:main

# teardown from ROOT (never from inside wt)
cd "$TMP/work"
git worktree remove "$TMP/work/wt"
[ ! -d "$TMP/work/wt" ] && ok worktree-removed || bad worktree-removed

git branch -D feat/x >/dev/null 2>&1
git branch --list feat/x | grep -q . && bad branch-should-be-gone || ok branch-removed

# root sync: main fast-forwards to the merged commit
git fetch -q --prune origin
git pull -q --ff-only origin main
local_main=$(git rev-parse main)
[ "$local_main" = "$merged_sha" ] && ok main-synced || bad "main-synced (main=$local_main != merged=$merged_sha)"

rm -rf "$TMP"
exit $fail
