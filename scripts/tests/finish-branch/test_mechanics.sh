#!/bin/bash
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
fail=0
T=$(mktemp -d)
W=$("$DIR/build_sandbox.sh" "$T" | tail -1)

# Baseline: clean state -> no unrecorded submodule change
git -C "$W" diff --quiet -- submod || { echo "FAIL: baseline should be clean"; fail=1; }

# Simulate merged submodule work: advance submodule main, leaving parent gitlink stale
git -C "$W/submod" checkout -q main
git -C "$W/submod" merge -q --no-ff feat/slice-a -m "merge slice A"
git -C "$W/submod" push -q origin main

# Detection 1 (unrecorded gitlink): parent must now see the submodule pointer change
git -C "$W" diff --quiet -- submod && { echo "FAIL: stale gitlink not detected"; fail=1; }

# The bump itself (Phase 4's mechanical core)
git -C "$W" add submod
git -C "$W" -c user.email=t@t -c user.name=t commit -qm "chore: bump submod gitlink"
git -C "$W" push -q origin main
git -C "$W" diff --quiet -- submod || { echo "FAIL: gitlink still dirty after bump"; fail=1; }

# Detection 2 (dirty submodule worktree)
echo "wip" >> "$W/submod/module.txt"
git -C "$W" submodule status | grep -q '^+\|^-' ; SUBSTAT=$?
git -C "$W/submod" diff --quiet ; DIRTY=$?
[ $DIRTY -ne 0 ] || { echo "FAIL: dirty submodule not detected"; fail=1; }

rm -rf "$T"
[ $fail -eq 0 ] && echo "OK: finish-branch mechanics (4 checks)"
exit $fail
