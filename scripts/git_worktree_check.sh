#!/usr/bin/env bash
# git_worktree_check.sh — exit 0 iff cwd is inside a LINKED git worktree (not
# the primary checkout). Exit 1 in the primary checkout, 2 outside a repo.
#
# A linked worktree's per-worktree git-dir differs from the shared
# git-common-dir; in the primary checkout the two resolve to the same path.
# This holds for NORMAL worktrees (common-dir <repo>/.git) AND for SUBMODULE
# worktrees (common-dir <parent>/.git/modules/<sub>, git-dir
# <parent>/.git/modules/<sub>/worktrees/<name>), and it does not false-positive
# on a primary checkout that merely lives under a path named "worktrees".
# Shared by worktree-sessions (teardown) and finish-branch (Phase 6 skip). Spec 11 §5.4.
set -uo pipefail
git rev-parse --git-dir >/dev/null 2>&1 || exit 2
gdir=$(cd "$(git rev-parse --git-dir)" 2>/dev/null && pwd -P) || exit 2
cdir=$(cd "$(git rev-parse --git-common-dir)" 2>/dev/null && pwd -P) || exit 2
[ "$gdir" = "$cdir" ] && exit 1 || exit 0
