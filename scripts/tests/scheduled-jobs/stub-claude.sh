#!/bin/bash
# Stub `claude` binary for the scheduled-jobs wrapper end-to-end sandbox test.
#
# run.sh.tmpl (spec 06 §5.4) has no claude-binary override mechanism — it
# calls the literal command `claude`. So this script is installed as
# "$STUBDIR/claude" and $STUBDIR is PATH-prepended by the test harness (the
# review-gate stub-claude.sh pattern, adapted: that one is invoked via an
# explicit $DEV_CYCLE_CLAUDE_BIN override; this wrapper has no such hook, hence
# PATH-prepend instead).
#
# Emulates a headless `claude -p --output-format json` session honoring the
# report contract a real session's prompt.tmpl.md would produce (§5.6/§5.5
# steps 6-8): on success it writes reports/report-<date>.md,
# reports/summary-<date>.json, and advances state.json for the item(s) it
# "verified", then prints a `{"num_turns": N, "is_error": false}` result
# envelope to stdout (consumed by the wrapper as $RESULT_JSON).
#
# Consumes, via env (set by the test harness — the wrapper passes no
# job-identifying flag to claude itself, so there's nothing to parse out of
# argv/stdin for this):
#   DEV_CYCLE_STUB_JOB_DIR    - job directory (required)
#   DEV_CYCLE_STUB_RECORD     - if set, append "ARGS: ...\nSTDIN:\n<prompt>" here
#   DEV_CYCLE_STUB_NO_REPORT  - if set (any value), skip writing report/summary/
#                           state entirely — used to prove the wrapper's
#                           anti-silent-failure contract-verification step
#   DEV_CYCLE_STUB_STATUS     - summary.status field (default SUCCESS)
#   DEV_CYCLE_STUB_MATERIAL   - JSON array literal for summary.material_changes
#                           (default [])
#   DEV_CYCLE_STUB_NUM_TURNS  - result envelope num_turns (default 4)
set -u

REC="${DEV_CYCLE_STUB_RECORD:-}"
if [ -n "$REC" ]; then
  { echo "ARGS: $*"; echo "STDIN:"; cat; } >> "$REC"
else
  cat >/dev/null
fi

JOB_DIR="${DEV_CYCLE_STUB_JOB_DIR:?DEV_CYCLE_STUB_JOB_DIR not set}"
NUM_TURNS="${DEV_CYCLE_STUB_NUM_TURNS:-4}"

if [ -z "${DEV_CYCLE_STUB_NO_REPORT:-}" ]; then
  RUN_DATE="$(date +%F)"
  REPORTS="$JOB_DIR/reports"
  STATE="$JOB_DIR/state.json"
  REPORT="$REPORTS/report-$RUN_DATE.md"
  SUMMARY="$REPORTS/summary-$RUN_DATE.json"
  STATUS="${DEV_CYCLE_STUB_STATUS:-SUCCESS}"
  MATERIAL="${DEV_CYCLE_STUB_MATERIAL:-[]}"

  mkdir -p "$REPORTS"
  cat > "$REPORT" <<EOF
# stub-job — $RUN_DATE
## Summary
1/1 due items verified | 0 issues found | 0 items skipped as fresh
## Per-item findings
### widget-a
- **Current:** OUTDATED (cached)
- **Vendor/upstream says:** stub says current as of $RUN_DATE
- **Status:** OK
- **Action taken:** none
## Changes made
None
EOF

  jq -n --arg job "stub-job" --arg run_date "$RUN_DATE" --arg status "$STATUS" \
        --argjson material "$MATERIAL" \
        '{job:$job, run_date:$run_date, status:$status,
          items_checked:1, items_skipped_fresh:0, material_changes:$material}' \
        > "$SUMMARY" || exit 1

  # Emulate the state write-back a real headless session performs
  # (prompt.tmpl.md step 6): advance last_verified/status for items that
  # were NOT already OK, leaving fresh (already-OK) items untouched.
  if [ -f "$STATE" ]; then
    tmp="$(mktemp)"
    jq --arg d "$RUN_DATE" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       '.updated=$ts
        | .items |= with_entries(
            if .value.status != "OK"
            then .value.status = "OK" | .value.last_verified = $d
            else . end)' \
       "$STATE" > "$tmp" && mv "$tmp" "$STATE"
  fi
fi

printf '{"num_turns": %s, "is_error": false}\n' "$NUM_TURNS"
