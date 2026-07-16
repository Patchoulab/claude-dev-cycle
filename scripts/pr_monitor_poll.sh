#!/usr/bin/env bash
# pr_monitor_poll.sh — fallback poller for dev-cycle:pr-monitor (spec 03 §5.2).
#
# One poll CYCLE: fetch PR state/comments/reviews/checks, diff against the
# known baseline in the state file, and emit exactly one JSON event on
# stdout. In daemon mode (default, no --once) cycles repeat on a
# cache-aware interval until an event fires or the window expires, matching
# the "one event per process exit" contract the skill's Watch mechanism
# (spec 03 §4) relies on for its relaunch loop: the agent runs this via
# Bash run_in_background=true, handles the event on exit, then relaunches.
#
# --- Reconciliation notes (Wave 2 Task 2, controller pre-authorized) ---
#
# 1. ADDED --once (single-cycle mode). Spec §5.2's script is an
#    unconditional `while :; do ... sleep; done` that only exits once an
#    event is found — fine for a live agent relaunching it, but untestable
#    stand-alone: a stub with no new activity would spin the loop with a
#    real `sleep $INTERVAL` (60s+) forever. --once runs exactly one cycle
#    body, then exits — emitting {"event":"no_change"} if nothing changed.
#    Documented per the brief's KEY RULE: an untestable daemon loop is not
#    acceptable.
#
# 2. RESTORED spec §5.2's five-gh-call cycle. An earlier revision of this
#    script collapsed everything into one `gh pr view --json
#    state,...,comments,reviews,statusCheckRollup` call. That call has no
#    field exposing inline PR *review* comments (as opposed to top-level
#    issue comments) — `gh pr view --json` simply doesn't surface them —
#    so `review_comment_ids` was silently always `[]`. That's a real
#    functional regression, not a harmless simplification: inline review
#    comments are the PRIMARY event source in practice (Copilot/Codex
#    findings land as inline review comments, proven on this repo's own
#    PR #1). Restored to the spec's five calls per cycle:
#      - `gh pr view --json state,isDraft,headRefOid,mergeable,
#         reviewDecision,url` (state/head/mergeable; `url` added so
#         owner/repo can be parsed without a 6th call when --repo is
#         omitted — gh has no "infer repo for `gh api`" shortcut the way
#         `pr view` does for the cwd's remote)
#      - `gh api repos/{repo}/issues/{pr}/comments` (top-level PR comments)
#      - `gh api repos/{repo}/pulls/{pr}/comments` (INLINE review comments
#         — this is the endpoint the consolidation dropped)
#      - `gh api repos/{repo}/pulls/{pr}/reviews` (review submissions)
#      - `gh api repos/{repo}/commits/{sha}/check-runs` (failed checks)
#    `review_comment_ids` is now genuinely populated and new inline
#    comments surface in the `activity` event's `new.review_comments`.
#
# 3. Portable gh_t() timeout wrapper (legitimate reconciliation, independent
#    of #2's regression). Spec §5.2 mandates "every gh invocation is
#    wrapped in coreutils `timeout 30`" per house rule 5. This dev machine
#    (macOS) has no `timeout` binary under either name (`timeout` or
#    `gtimeout`) — macOS doesn't ship GNU coreutils by default. Copying the
#    spec's `gh_t() { timeout 30 gh "$@"; }` verbatim would make every gh
#    call fail with "command not found" on an unmodified Mac, the plugin's
#    primary deployment target. gh_t() uses `timeout`/`gtimeout` when
#    present and falls back to a pure-bash poll loop (1s ticks, `kill -0` to
#    check liveness, TERM then KILL past 30s) otherwise, preserving the
#    house-rule-5 timeout guarantee without a coreutils dependency. (An
#    earlier fallback shape — background the real call, then background a
#    separate `( sleep 30; kill ... )` subshell as the watchdog — has a real
#    bug under bash 3.2, this machine's stock `/bin/bash`: killing the
#    watchdog subshell doesn't kill its `sleep` grandchild, which is
#    orphaned and keeps the caller's command-substitution pipe open for the
#    rest of its 30s. That turned every fallback gh_t call into a fixed
#    ~30s tax regardless of how fast `gh` actually returned. Fixed as part
#    of this task by polling instead of backgrounding a watchdog subshell.)
#
# 4. State-file bootstrap + self-persistence (legitimate reconciliation).
#    Spec's contract notes say the state file is "created by the skill at
#    arm time" and that "the agent handles [the event], rewrites
#    state.json ... and relaunches" — i.e. the poller was designed to only
#    *read* baseline state, with an external agent process owning the
#    writes. That has no meaning for a `--once` invocation run directly by
#    a test harness with no agent loop around it. The poller bootstraps
#    `.git/dev-cycle/pr-monitor/<pr>.json` itself when missing (baseline =
#    current snapshot across all five endpoints, emits `baseline_seeded`,
#    not `activity`) and persists the merged id sets back to the file
#    after any cycle that finds something new. The agent still owns the
#    `rounds` log (fixed/pushback/answered/push_sha) — the poller never
#    touches that field.
#
# 5. The rate-limit probe (`gh_t api rate_limit`) only runs in daemon mode
#    between ticks. Running it in --once would make single-cycle calls
#    cost 6 gh invocations instead of 5 for no benefit (there's no second
#    tick to back off before).
#
# 6. Every `gh` invocation — in both modes, across all five call sites — is
#    wrapped by gh_t() (see the timeout note above), per house rule 5.
#
# Usage: pr_monitor_poll.sh <pr#> [--repo <owner/repo>] [--state <path>]
#                            [--interval <sec>] [--end <epoch>] [--once]
# Defaults: --repo omitted (parsed from `pr view`'s `url` field on first
#   use), --state "<git-common-dir>/dev-cycle/pr-monitor/<pr>.json" (spec 00's
#   shared state-dir convention), --interval 60, --end now+900 (15m).
# Requires: gh (authenticated), jq, coreutils timeout (or gtimeout; falls
#   back to a pure-bash watchdog if neither is present, see gh_t() above).
set -uo pipefail

usage() {
  echo "Usage: $0 <pr#> [--repo owner/repo] [--state path] [--interval sec] [--end epoch] [--once]" >&2
  exit 2
}

[ $# -ge 1 ] || usage
PR="$1"; shift
REPO=""
STATE=""
INTERVAL=60
END=""
ONCE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --once) ONCE=1; shift ;;
    --repo) REPO="${2:-}"; shift 2 ;;
    --state) STATE="${2:-}"; shift 2 ;;
    --interval) INTERVAL="${2:-}"; shift 2 ;;
    --end) END="${2:-}"; shift 2 ;;
    *) usage ;;
  esac
done

if [ -z "$STATE" ]; then
  GIT_COMMON_DIR=$(git rev-parse --git-common-dir 2>/dev/null) || GIT_COMMON_DIR=".git"
  STATE="$GIT_COMMON_DIR/dev-cycle/pr-monitor/$PR.json"
fi
[ -n "$END" ] || END=$(( $(date +%s) + 900 ))

# gh has no --max-time (that's a curl flag) and no per-call timeout flag, so
# every gh invocation is wrapped in a 30s timeout (house rule 5: timeouts on
# every remote call). This wrapper is mandatory, not decorative.
#
# Reconciliation note (addition, controller pre-authorized): spec §5.2 says
# "coreutils timeout", but macOS ships neither `timeout` nor `gtimeout` by
# default (confirmed on the dev machine this was built on) — a plugin meant
# to run out of the box on the user's own Mac can't depend on `brew install
# coreutils`. gh_t() uses the coreutils binary when present (e.g. Linux CI)
# and falls back to a pure-bash background+kill watchdog otherwise, so the
# house-rule-5 timeout guarantee holds either way.
if command -v timeout >/dev/null 2>&1; then
  GH_T_BIN="timeout"
elif command -v gtimeout >/dev/null 2>&1; then
  GH_T_BIN="gtimeout"
else
  GH_T_BIN=""
fi

gh_t() {
  if [ -n "$GH_T_BIN" ]; then
    "$GH_T_BIN" 30 gh "$@"
    return $?
  fi
  # Polling watchdog, not a backgrounded `( sleep 30; kill ... ) &` wrapper:
  # this repo's dev machine runs bash 3.2 (macOS's stock default — no
  # `wait -n`), and under 3.2 a `( sleep 30; kill "$pid" ) &` subshell has a
  # real bug — sending it SIGTERM kills the subshell wrapper but NOT its
  # `sleep` grandchild, which is then orphaned and keeps running for the
  # rest of its 30s, holding the caller's command-substitution pipe open
  # the whole time. Every gh_t call in the fallback path was paying a fixed
  # ~30s tax regardless of how fast `gh` actually returned (reproduced: a
  # `--once` cycle that should finish in well under a second instead hung
  # for tens of seconds per call). Polling in 1s ticks and only ever
  # backgrounding the real `gh` process itself (nothing else touches the
  # pipe) avoids the orphan entirely. This does NOT make the common case
  # free: `gh "$@" &` returns to the parent immediately, before the network
  # call has even started, so the very first `kill -0` liveness check always
  # finds the process still alive — `gh` cannot realistically finish inside
  # that window. In fallback mode every call therefore pays at least one
  # real `sleep 1` of polling overhead (not zero, and not a coreutils-timeout
  # equivalent); it just bounds the tax to ~1s per call instead of the fixed
  # ~30s the orphaned-grandchild bug used to cost.
  gh "$@" &
  local pid=$! elapsed=0 rc
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$elapsed" -ge 30 ]; then
      kill -TERM "$pid" 2>/dev/null
      sleep 1
      kill -0 "$pid" 2>/dev/null && kill -KILL "$pid" 2>/dev/null
      break
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  wait "$pid" 2>/dev/null; rc=$?
  return "$rc"
}

emit() { printf '%s\n' "$1"; exit 0; }

write_json_atomic() {
  # write_json_atomic <path> <json>
  printf '%s\n' "$2" > "$1.tmp" && mv "$1.tmp" "$1"
}

bootstrap_if_missing() {
  if [ -f "$STATE" ]; then
    return 1
  fi
  mkdir -p "$(dirname "$STATE")"
  write_json_atomic "$STATE" "$(jq -n --arg repo "$REPO" --arg pr "$PR" --argjson end "$END" '
    {repo:$repo, pr:$pr, window_end_epoch:$end, head:null,
     comment_ids: [], review_comment_ids: [], review_ids: [],
     failed_checks: [], bots: ["vercel[bot]"], rounds: []}')"
  return 0
}

fetch_pv() {
  if [ -n "$REPO" ]; then
    gh_t pr view "$PR" --repo "$REPO" \
      --json state,isDraft,headRefOid,mergeable,reviewDecision,url
  else
    gh_t pr view "$PR" \
      --json state,isDraft,headRefOid,mergeable,reviewDecision,url
  fi
}

# resolve_repo <pv-json> — echoes owner/repo: --repo if given, else parsed
# from pv's `url` field (https://github.com/{owner}/{repo}/pull/{n}). `gh
# api repos/{owner}/{repo}/...` has no cwd-remote inference the way
# `gh pr view` does, so this is required for the four REST endpoints below.
resolve_repo() {
  if [ -n "$REPO" ]; then
    printf '%s' "$REPO"
    return
  fi
  jq -r '.url // empty' <<<"$1" \
    | sed -E 's#^https?://github\.com/([^/]+/[^/]+)/pull/.*#\1#'
}

# fetch_events <repo> <head-sha> — sets globals ic, rc, rv, ck (JSON arrays)
# via the spec's four REST endpoints. Spec §5.2's exact endpoint set:
#   issues/{pr}/comments   — top-level PR comments
#   pulls/{pr}/comments    — INLINE review comments (the one the earlier
#                            consolidation dropped)
#   pulls/{pr}/reviews     — review submissions
#   commits/{sha}/check-runs — failed/timed-out checks
fetch_events() {
  local repo_eff="$1" head_sha="$2"
  ic=$(gh_t api "repos/$repo_eff/issues/$PR/comments" --paginate \
        --jq '[.[]|{id,login:.user.login,body:.body}]' 2>/dev/null) || ic='[]'
  rc=$(gh_t api "repos/$repo_eff/pulls/$PR/comments" --paginate \
        --jq '[.[]|{id,login:.user.login,body:.body,path:.path,line:.line}]' 2>/dev/null) || rc='[]'
  rv=$(gh_t api "repos/$repo_eff/pulls/$PR/reviews" --paginate \
        --jq '[.[]|{id,login:.user.login,state:.state}]' 2>/dev/null) || rv='[]'
  ck=$(gh_t api "repos/$repo_eff/commits/$head_sha/check-runs" \
        --jq '[.check_runs[]|select(.conclusion=="failure" or .conclusion=="timed_out")|{id,name}]' 2>/dev/null) || ck='[]'
  [ -n "$ic" ] || ic='[]'
  [ -n "$rc" ] || rc='[]'
  [ -n "$rv" ] || rv='[]'
  [ -n "$ck" ] || ck='[]'
}

# One poll cycle. Returns 0 (via emit/exit) on any reportable event; returns
# 1 to the caller when nothing new happened yet (daemon mode keeps ticking).
cycle() {
  local now bootstrapped=0
  now=$(date +%s)
  if (( now >= END )); then emit '{"event":"expired"}'; fi

  if bootstrap_if_missing; then bootstrapped=1; fi

  local pv
  pv=$(fetch_pv 2>/dev/null) || return 1   # transient API failure: skip a tick

  local state head known_head mergeable repo_eff
  state=$(jq -r '.state // empty' <<<"$pv")
  [ "$state" = "MERGED" ] && emit '{"event":"pr_merged"}'
  [ "$state" = "CLOSED" ] && emit '{"event":"pr_closed"}'

  head=$(jq -r '.headRefOid // "null"' <<<"$pv")
  mergeable=$(jq -r '.mergeable // empty' <<<"$pv")
  [ "$mergeable" = "CONFLICTING" ] && emit '{"event":"conflict"}'

  repo_eff=$(resolve_repo "$pv")

  local ic rc rv ck
  if [ "$bootstrapped" -eq 1 ]; then
    # First run: the current snapshot IS the baseline, not "new" activity —
    # matches SKILL.md step 4 (seeding), which triages any existing backlog
    # separately at arm time rather than treating it as a poller event.
    fetch_events "$repo_eff" "$head"
    local cids rcids rids fids
    cids=$(jq -c '[.[] | (.id|tostring)]' <<<"$ic")
    rcids=$(jq -c '[.[] | (.id|tostring)]' <<<"$rc")
    rids=$(jq -c '[.[] | (.id|tostring)]' <<<"$rv")
    fids=$(jq -c '[.[] | (.id|tostring)]' <<<"$ck")
    write_json_atomic "$STATE" "$(jq -n --arg repo "$repo_eff" --arg pr "$PR" --argjson end "$END" \
      --arg head "$head" --argjson cids "$cids" --argjson rcids "$rcids" \
      --argjson rids "$rids" --argjson fids "$fids" '
      {repo:$repo, pr:$pr, window_end_epoch:$end, head:$head,
       comment_ids:$cids, review_comment_ids:$rcids, review_ids:$rids,
       failed_checks:$fids, bots: ["vercel[bot]"], rounds: []}')"
    emit "$(jq -cn --arg head "$head" '{event:"baseline_seeded", head:$head}')"
  fi

  known_head=$(jq -r '.head // "null"' "$STATE")
  if [ "$head" != "$known_head" ] && [ "$head" != "null" ]; then
    jq --arg head "$head" '.head = $head' "$STATE" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"
    emit "$(jq -cn --arg head "$head" '{event:"head_moved", head:$head}')"
  fi

  fetch_events "$repo_eff" "$head"

  local bots kc krc kr kf
  local new_comments new_review_comments new_reviews new_checks has_new
  bots=$(jq -c '.bots' "$STATE")
  kc=$(jq -c '.comment_ids' "$STATE")
  krc=$(jq -c '.review_comment_ids' "$STATE")
  kr=$(jq -c '.review_ids' "$STATE")
  kf=$(jq -c '.failed_checks' "$STATE")

  new_comments=$(jq -c --argjson bots "$bots" --argjson kc "$kc" '
    [.[] | select(((.login // "") as $l | ($bots|index($l)))|not)
         | select((((.id|tostring)) as $i | ($kc|index($i)))|not)
         | {id: (.id|tostring), login: .login, body: .body}]' <<<"$ic")

  new_review_comments=$(jq -c --argjson bots "$bots" --argjson krc "$krc" '
    [.[] | select(((.login // "") as $l | ($bots|index($l)))|not)
         | select((((.id|tostring)) as $i | ($krc|index($i)))|not)
         | {id: (.id|tostring), login: .login, body: .body, path: .path, line: .line}]' <<<"$rc")

  new_reviews=$(jq -c --argjson bots "$bots" --argjson kr "$kr" '
    [.[] | select(((.login // "") as $l | ($bots|index($l)))|not)
         | select((((.id|tostring)) as $i | ($kr|index($i)))|not)
         | {id: (.id|tostring), login: .login, state: .state}]' <<<"$rv")

  new_checks=$(jq -c --argjson kf "$kf" '
    [.[] | select((((.id|tostring)) as $i | ($kf|index($i)))|not)
         | {id: (.id|tostring), name: .name}]' <<<"$ck")

  has_new=$(jq -n --argjson c "$new_comments" --argjson rc2 "$new_review_comments" \
    --argjson r "$new_reviews" --argjson k "$new_checks" \
    '(($c|length) + ($rc2|length) + ($r|length) + ($k|length)) > 0')

  if [ "$has_new" = "true" ]; then
    local merged_c merged_rc merged_r merged_k
    merged_c=$(jq -cn --argjson kc "$kc" --argjson n "$new_comments" '($kc + [$n[].id]) | unique')
    merged_rc=$(jq -cn --argjson krc "$krc" --argjson n "$new_review_comments" '($krc + [$n[].id]) | unique')
    merged_r=$(jq -cn --argjson kr "$kr" --argjson n "$new_reviews" '($kr + [$n[].id]) | unique')
    merged_k=$(jq -cn --argjson kf "$kf" --argjson n "$new_checks" '($kf + [$n[].id]) | unique')
    jq --argjson cids "$merged_c" --argjson rcids "$merged_rc" \
       --argjson rids "$merged_r" --argjson fids "$merged_k" \
       '.comment_ids=$cids | .review_comment_ids=$rcids | .review_ids=$rids | .failed_checks=$fids' \
       "$STATE" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"
    emit "$(jq -cn --argjson c "$new_comments" --argjson rc2 "$new_review_comments" \
      --argjson r "$new_reviews" --argjson k "$new_checks" \
      '{event:"activity", new:{comments:$c, review_comments:$rc2, reviews:$r, failed_checks:$k}}')"
  fi

  return 1
}

if [ "$ONCE" -eq 1 ]; then
  cycle || emit '{"event":"no_change"}'
  exit 0
fi

# Daemon mode: spec §5.2's blocking loop, cache-aware tick pacing, with a
# rate-limit backoff check between ticks (not needed in --once: there's no
# next tick to back off before).
while :; do
  cycle || true
  remaining=$(gh_t api rate_limit --jq '.resources.core.remaining' 2>/dev/null)
  [[ "$remaining" =~ ^[0-9]+$ ]] || remaining=1000
  if (( remaining < 100 )); then sleep 300; else sleep "$INTERVAL"; fi
done
