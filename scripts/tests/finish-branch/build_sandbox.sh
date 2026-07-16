#!/bin/bash
# Usage: build_sandbox.sh <target-dir>
# Creates: <dir>/remotes/{parent,sub}.git (bare), <dir>/work/parent (clone with submodule submod)
set -eu

# Allow file:// submodule fetches. Neither `-c protocol.file.allow` nor
# GIT_CONFIG_* env vars reliably reach the submodule subprocess a recursive
# clone spawns, so point git at a controlled global config on disk (every git
# process reads it). run_all.sh usually sets this already; honor it if so.
if ! git config --global protocol.file.allow 2>/dev/null | grep -q always; then
  _DC_BS_GITCONFIG="$(mktemp)"
  git config -f "$_DC_BS_GITCONFIG" protocol.file.allow always
  git config -f "$_DC_BS_GITCONFIG" safe.directory '*'
  git config -f "$_DC_BS_GITCONFIG" user.name "dev-cycle-test"
  git config -f "$_DC_BS_GITCONFIG" user.email "test@example.com"
  git config -f "$_DC_BS_GITCONFIG" init.defaultBranch main
  export GIT_CONFIG_GLOBAL="$_DC_BS_GITCONFIG"
  export GIT_CONFIG_SYSTEM=/dev/null
  trap 'rm -f "$_DC_BS_GITCONFIG"' EXIT
fi

T="$1"
mkdir -p "$T/remotes" "$T/work"
git init -q --bare "$T/remotes/parent.git"
git init -q --bare "$T/remotes/sub.git"

SUB_SEED=$(mktemp -d)
git -C "$SUB_SEED" init -q -b main
echo "core" > "$SUB_SEED/module.txt"
git -C "$SUB_SEED" add module.txt
git -C "$SUB_SEED" -c user.email=t@t -c user.name=t commit -qm "init submodule"
git -C "$SUB_SEED" remote add origin "$T/remotes/sub.git"
git -C "$SUB_SEED" push -q origin main

PAR_SEED=$(mktemp -d)
git -C "$PAR_SEED" init -q -b main
echo "parent" > "$PAR_SEED/README.md"
git -C "$PAR_SEED" add README.md
git -C "$PAR_SEED" -c protocol.file.allow=always submodule add -q -b main "$T/remotes/sub.git" submod
git -C "$PAR_SEED" -c user.email=t@t -c user.name=t commit -qm "init parent with submodule"
git -C "$PAR_SEED" remote add origin "$T/remotes/parent.git"
git -C "$PAR_SEED" push -q origin main

git -C "$T/work" -c protocol.file.allow=always clone -q --recurse-submodules "$T/remotes/parent.git" parent
W="$T/work/parent"
printf '{"canonicalRoot": "%s", "submodules": [{"path": "submod", "remote": "origin", "defaultBranch": "main"}], "preauthorized": ["push-to-origin", "gitlink-bump", "branch-cleanup"], "mergeStrategy": "merge"}' "$W" > "$W/.claude-dev-cycle.json.tmp"
mkdir -p "$W/.claude"
mv "$W/.claude-dev-cycle.json.tmp" "$W/.claude/dev-cycle.json"

# Feature branch in the submodule, pushed, simulating a mergeable PR branch
git -C "$W/submod" checkout -qb feat/slice-a
echo "feature" >> "$W/submod/module.txt"
git -C "$W/submod" -c user.email=t@t -c user.name=t commit -qam "feat: slice A"
git -C "$W/submod" push -q origin feat/slice-a
# Return the submodule worktree to the commit recorded in the parent's
# gitlink (still "main" -- feat/slice-a has not been merged yet) so the
# sandbox starts in a clean, baseline state for test_mechanics.sh.
git -C "$W/submod" checkout -q main
echo "$W"
