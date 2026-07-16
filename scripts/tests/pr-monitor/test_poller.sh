#!/bin/bash
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
POLLER="$DIR/../../pr_monitor_poll.sh"
fail=0
[ -x "$POLLER" ] || { echo "FAIL: poller missing"; exit 1; }

T=$(mktemp -d)
git -C "$T" init -q
export PATH="$DIR/stub-bin:$PATH"
export STUB_GH_RECORD="$T/rec"
: > "$STUB_GH_RECORD"

# Case 1: baseline poll writes the state file under .git/dev-cycle/pr-monitor/ and exits with a JSON event on stdout
( cd "$T" && "$POLLER" 1 --once ) > "$T/out.json" 2>"$T/err"
rc=$?
[ $rc -eq 0 ] || { echo "FAIL: poller rc=$rc"; cat "$T/err"; fail=1; }
python3 -m json.tool "$T/out.json" >/dev/null || { echo "FAIL: stdout not JSON"; fail=1; }
[ -f "$T/.git/dev-cycle/pr-monitor/1.json" ] || { echo "FAIL: state file missing"; fail=1; }
grep -q '"review_comment_ids"' "$T/.git/dev-cycle/pr-monitor/1.json" \
  || { echo "FAIL: review_comment_ids missing from state schema"; fail=1; }

# Case 2a: new top-level CONVERSATION comment between polls -> event reports it
mkdir -p "$T/replies"
printf '[{"id":201,"login":"reviewer","body":"please rename this var"}]' > "$T/replies/issue-comments.json"
export STUB_GH_DIR="$T/replies"
( cd "$T" && "$POLLER" 1 --once ) > "$T/out2a.json"
grep -q '"201"' "$T/out2a.json" || { echo "FAIL: new conversation comment not in event"; fail=1; }
grep -q '"comments":\[{"id":"201"' "$T/out2a.json" \
  || { echo "FAIL: conversation comment not filed under comments in event"; fail=1; }

# Case 2b: new INLINE REVIEW comment (served via the review-comments fixture)
# — this is the primary event source in practice: Copilot/Codex findings
# arrive as inline review comments, not top-level issue comments. Pass
# requires BOTH the event AND the state file to track it.
printf '[{"id":301,"login":"copilot-pull-request-reviewer[bot]","body":"missing null check","path":"scripts/foo.sh","line":42}]' \
  > "$T/replies/review-comments.json"
( cd "$T" && "$POLLER" 1 --once ) > "$T/out2b.json"
grep -q '"301"' "$T/out2b.json" || { echo "FAIL: new inline review comment not in event"; fail=1; }
grep -q '"review_comments":\[{"id":"301"' "$T/out2b.json" \
  || { echo "FAIL: inline review comment not filed under review_comments in event"; fail=1; }
grep -q '"301"' "$T/.git/dev-cycle/pr-monitor/1.json" \
  || { echo "FAIL: inline review comment id not tracked in state file after the round"; fail=1; }

# Case 3: every gh invocation is time-bounded (wrapper present in script text; no bare gh calls)
if grep -nE '^[^#]*\bgh (api|pr)' "$POLLER" | grep -v "gh_t" | grep -v "timeout"; then
  echo "FAIL: unbounded gh call found"; fail=1
fi

# Case 4: bot-authored comment does NOT count as new activity (bots filter,
# spec 03 §8 GREEN scenario 6's script-level half — the reply-suppression /
# report-counting half is a subagent behavior, deferred).
T4=$(mktemp -d)
git -C "$T4" init -q
mkdir -p "$T4/fx"
export STUB_GH_DIR="$T4/fx"
( cd "$T4" && "$POLLER" 4 --once ) > "$T4/seed.json" 2>"$T4/err"   # bootstrap round
printf '[{"id":401,"login":"vercel[bot]","body":"deploy preview ready"}]' > "$T4/fx/issue-comments.json"
( cd "$T4" && "$POLLER" 4 --once ) > "$T4/out4.json" 2>>"$T4/err"
grep -q '"event":"no_change"' "$T4/out4.json" \
  || { echo "FAIL: bot-only comment should not fire an event: $(cat "$T4/out4.json")"; fail=1; }
rm -rf "$T4"; unset STUB_GH_DIR

# Case 5: expired event fires immediately once the window end has passed.
T5=$(mktemp -d)
git -C "$T5" init -q
( cd "$T5" && "$POLLER" 5 --once --end "$(( $(date +%s) - 10 ))" ) > "$T5/out.json"
grep -q '"event":"expired"' "$T5/out.json" \
  || { echo "FAIL: expired event not emitted: $(cat "$T5/out.json")"; fail=1; }
rm -rf "$T5"

# Case 6: merged/closed/conflict events (state/mergeable-driven, checked
# before any prior baseline is required).
check_pv_event() {  # $1 pr-view json  $2 expected event substring
  local t; t=$(mktemp -d)
  git -C "$t" init -q
  mkdir -p "$t/fx"
  printf '%s' "$1" > "$t/fx/pr-view.json"
  ( cd "$t" && STUB_GH_DIR="$t/fx" "$POLLER" 6 --once ) > "$t/out.json"
  grep -q "\"event\":\"$2\"" "$t/out.json" \
    || { echo "FAIL: expected event $2 not emitted for $1: $(cat "$t/out.json")"; fail=1; }
  rm -rf "$t"
}
check_pv_event '{"state":"MERGED","isDraft":false,"headRefOid":"abc123","mergeable":"MERGEABLE","reviewDecision":"","url":"https://github.com/o/r/pull/1"}' pr_merged
check_pv_event '{"state":"CLOSED","isDraft":false,"headRefOid":"abc123","mergeable":"MERGEABLE","reviewDecision":"","url":"https://github.com/o/r/pull/1"}' pr_closed
check_pv_event '{"state":"OPEN","isDraft":false,"headRefOid":"abc123","mergeable":"CONFLICTING","reviewDecision":"","url":"https://github.com/o/r/pull/1"}' conflict

# Case 7: head_moved — a new push between polls is detected against the
# already-seeded baseline head, and takes priority over an activity event
# in the same cycle (both fire from the same underlying diff; only one
# event per cycle is emitted, per the poller's one-event contract).
T7=$(mktemp -d)
git -C "$T7" init -q
mkdir -p "$T7/fx"
( cd "$T7" && STUB_GH_DIR="$T7/fx" "$POLLER" 7 --once ) > "$T7/seed.json"
printf '{"state":"OPEN","isDraft":false,"headRefOid":"def456","mergeable":"MERGEABLE","reviewDecision":"","url":"https://github.com/o/r/pull/1"}' \
  > "$T7/fx/pr-view.json"
printf '[{"id":701,"login":"reviewer","body":"also new"}]' > "$T7/fx/issue-comments.json"
( cd "$T7" && STUB_GH_DIR="$T7/fx" "$POLLER" 7 --once ) > "$T7/out7.json"
grep -q '"event":"head_moved"' "$T7/out7.json" \
  || { echo "FAIL: head_moved not emitted despite headRefOid change: $(cat "$T7/out7.json")"; fail=1; }
rm -rf "$T7"

# Case 8: low-rate-limit backoff — in daemon mode (no --once), once the
# rate_limit probe reports < 100 remaining, the tick sleeps 300s instead of
# the (short) --interval. Verified by observing the actual `sleep 300` child
# process get spawned and killing it immediately, rather than waiting out
# the real 300s (impractical for a test suite; this is the deterministic,
# fast proxy for that timing branch).
T8=$(mktemp -d)
git -C "$T8" init -q
mkdir -p "$T8/fx"
( cd "$T8" && STUB_GH_DIR="$T8/fx" "$POLLER" 8 --once ) > "$T8/seed.json"   # seed baseline, no drift after
# rate_limit's --jq filter runs inside the real `gh` binary; the stub gh
# (see stub-bin/gh) ignores --jq/--paginate flags entirely and cats the
# fixture verbatim, so this fixture must already be the POST-filter shape
# (a bare number), matching every other endpoint's fixtures in this file.
printf '5' > "$T8/fx/rate-limit.json"
kill_tree() {  # recursively kill a pid and all its descendants
  local pid="$1" c
  for c in $(pgrep -P "$pid" 2>/dev/null); do kill_tree "$c"; done
  kill "$pid" 2>/dev/null
}
( cd "$T8" && STUB_GH_DIR="$T8/fx" "$POLLER" 8 --interval 1 >"$T8/daemon.out" 2>&1 ) &
DAEMON_PID=$!
# This machine's gh_t() fallback (no `timeout`/`gtimeout` binary present)
# polls in 1s ticks per gh_t call: backgrounding (`gh "$@" &`) returns to the
# parent before the stub has even started, so the very first `kill -0`
# liveness check always finds it still alive and pays a real `sleep 1` —
# gh_t costs >=1s per call even against an instant stub, not ~0s. The
# daemon's first cycle here makes ~11 gh_t calls (the seed --once call's
# bootstrap fetch, this process's own fetch_pv + fetch_events, and the
# rate_limit probe that finally trips the <100 branch), so ~6-12s of real
# wall time can elapse before `sleep 300` appears. Poll for up to ~40s
# (still nowhere near the real 300s) for documented headroom above that.
RC_SLEPT=1
for _ in $(seq 1 40); do
  sleep 1
  # Walk the descendant tree of $DAEMON_PID (bash's background-subshell exec
  # optimization means the poller script itself may land one or two levels
  # down, not necessarily as a direct child) looking for a live `sleep 300`.
  to_check="$DAEMON_PID"
  while [ -n "$to_check" ]; do
    next=""
    for p in $to_check; do
      cmd=$(ps -o command= -p "$p" 2>/dev/null)
      case "$cmd" in *"sleep 300"*) RC_SLEPT=0 ;; esac
      next="$next $(pgrep -P "$p" 2>/dev/null)"
    done
    to_check="$next"
  done
  [ "$RC_SLEPT" -eq 0 ] && break
done
kill_tree "$DAEMON_PID"
wait "$DAEMON_PID" 2>/dev/null
[ "$RC_SLEPT" -eq 0 ] \
  || { echo "FAIL: daemon mode did not invoke 'sleep 300' under a low (<100) rate-limit remaining"; fail=1; }
rm -rf "$T8"

rm -rf "$T"
[ $fail -eq 0 ] && echo "OK: pr-monitor poller (8 cases)"
exit $fail
