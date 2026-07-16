#!/bin/bash
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK="$DIR/../../../hooks/session-handoff/handoff-precompact.sh"
fail=0
[ -x "$HOOK" ] || { echo "FAIL: hook missing or not executable"; exit 1; }

# Case 1: repo WITHOUT .claude/dev-cycle.json -> hook is a no-op, exit 0
SANDBOX=$(mktemp -d)
git -C "$SANDBOX" init -q
( cd "$SANDBOX" && echo '{}' | "$HOOK" ) || { echo "FAIL: unmanaged case must exit 0"; fail=1; }
[ ! -e "$SANDBOX/.claude/dev-cycle" ] || { echo "FAIL: unmanaged case must write nothing"; fail=1; }

# Case 2: repo WITH dev-cycle.json -> writes emergency snapshot as compact-snapshot.md
# alongside the configured handoffFile (snap="$(dirname "$seed")/compact-snapshot.md")
SANDBOX2=$(mktemp -d)
git -C "$SANDBOX2" init -q
mkdir -p "$SANDBOX2/.claude"
printf '{"handoffFile": ".claude/dev-cycle/next-session.md"}' > "$SANDBOX2/.claude/dev-cycle.json"
( cd "$SANDBOX2" && echo '{}' | "$HOOK" ) || { echo "FAIL: managed case must exit 0"; fail=1; }
SNAP="$SANDBOX2/.claude/dev-cycle/compact-snapshot.md"
[ -f "$SNAP" ] || { echo "FAIL: snapshot not written to $SNAP"; fail=1; }
grep -q "Compact Snapshot" "$SNAP" || { echo "FAIL: snapshot missing marker"; fail=1; }

# Case 3: hook must NEVER block compaction — even on internal error it exits 0
SANDBOX3=$(mktemp -d)   # not a git repo at all
( cd "$SANDBOX3" && echo 'not-json' | "$HOOK" ) || { echo "FAIL: must exit 0 even on garbage input"; fail=1; }

# Case 4: pre-existing snapshot -> .prev rotation observed (spec 01 sec 8
# hook-tests bullet: "Fixture with a pre-existing snapshot -> .prev rotation
# observed"). Re-fire the hook in SANDBOX2, which already has a snapshot
# from Case 2.
FIRST_SNAP_CONTENT="$(cat "$SNAP")"
( cd "$SANDBOX2" && echo '{}' | "$HOOK" ) || { echo "FAIL: second managed-case fire must exit 0"; fail=1; }
[ -f "$SNAP.prev" ] || { echo "FAIL: .prev rotation file not written"; fail=1; }
[ -f "$SNAP" ] || { echo "FAIL: new snapshot not written after rotation"; fail=1; }
[ "$(cat "$SNAP.prev")" = "$FIRST_SNAP_CONTENT" ] || { echo "FAIL: .prev does not hold the prior snapshot's content"; fail=1; }

# Case 5: read-only snapshot directory -> exit 0, no block (spec 01 sec 8
# hook-tests bullet). A fresh sandbox whose seed dir is read-only so mkdir -p
# / the write to compact-snapshot.md both fail; the hook must still exit 0
# and never propagate the failure.
SANDBOX4=$(mktemp -d)
git -C "$SANDBOX4" init -q
mkdir -p "$SANDBOX4/.claude/dev-cycle"
printf '{"handoffFile": ".claude/dev-cycle/next-session.md"}' > "$SANDBOX4/.claude/dev-cycle.json"
chmod 555 "$SANDBOX4/.claude/dev-cycle"
# The write to compact-snapshot.md is EXPECTED to fail here; the hook still
# exits 0. Redirect this invocation's stderr so the expected "Permission
# denied" shell noise does not pollute the suite output.
( cd "$SANDBOX4" && echo '{}' | "$HOOK" 2>/dev/null ) || { echo "FAIL: read-only snapshot dir must still exit 0"; fail=1; }
chmod 755 "$SANDBOX4/.claude/dev-cycle"

# Case 6: hook fired from a SUBDIRECTORY of a dev-cycle-managed repo -> gate and
# snapshot paths anchor at the git toplevel, not the payload cwd.
SANDBOX5=$(mktemp -d)
git -C "$SANDBOX5" init -q
mkdir -p "$SANDBOX5/.claude" "$SANDBOX5/sub/dir"
printf '{"handoffFile": ".claude/dev-cycle/next-session.md"}' > "$SANDBOX5/.claude/dev-cycle.json"
( cd "$SANDBOX5/sub/dir" && printf '{"cwd": "%s"}' "$PWD" | "$HOOK" ) || { echo "FAIL: subdir managed case must exit 0"; fail=1; }
SNAP5="$SANDBOX5/.claude/dev-cycle/compact-snapshot.md"
[ -f "$SNAP5" ] || { echo "FAIL: subdir case: snapshot not written at repo toplevel ($SNAP5)"; fail=1; }
[ ! -e "$SANDBOX5/sub/dir/.claude/dev-cycle" ] || { echo "FAIL: subdir case: snapshot wrongly anchored at cwd"; fail=1; }

rm -rf "$SANDBOX" "$SANDBOX2" "$SANDBOX3" "$SANDBOX4" "$SANDBOX5"
[ $fail -eq 0 ] && echo "OK: precompact hook (6 cases)"
exit $fail
