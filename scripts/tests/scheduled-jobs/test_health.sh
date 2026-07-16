#!/bin/bash
# scheduled-jobs watchdog test: reproduces the historical silent-failure class
# from spec 06 §1.2 — "12 consecutive scheduled audit runs completed in
# under one second... zero tool calls, zero delegations, zero errors" —
# and proves bin/scheduled-jobs-health.sh (contract: docs/specs/06-scheduled-jobs.md
# §5.9) catches it. Sandbox HOME job dirs built the way Task 8's
# test_wrapper.sh does (mktemp HOME, scaffold jobs/*/job.json + runs.jsonl +
# reports/ by hand, per §5.1's layout).
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$DIR/../../.."
HEALTH_SH="$REPO/scripts/jobs_health.sh"
fail=0

[ -f "$HEALTH_SH" ] || { echo "FAIL: jobs_health.sh missing"; exit 1; }
[ -x "$HEALTH_SH" ] || { echo "FAIL: jobs_health.sh not executable"; exit 1; }

T=$(mktemp -d)
export HOME="$T/home"
JOBS_ROOT="$HOME/.claude/dev-cycle/jobs/jobs"
mkdir -p "$JOBS_ROOT"

# ISO-8601 UTC timestamp helper, N hours offset from now (portable via
# python3 — BSD `date -v` / GNU `date -d` syntaxes differ, python3 does not).
iso_offset() {
  python3 -c "
import sys, datetime
h = float(sys.argv[1])
dt = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(hours=h)
print(dt.strftime('%Y-%m-%dT%H:%M:%SZ'))
" "$1"
}
date_offset() {
  python3 -c "
import sys, datetime
h = float(sys.argv[1])
dt = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(hours=h)
print(dt.strftime('%Y-%m-%d'))
" "$1"
}

make_job_json() {  # $1 name  $2 dir  $3 period_hours
  cat > "$2/job.json" <<EOF
{
  "version": 1,
  "name": "$1",
  "description": "test fixture job",
  "created": "2026-07-01",
  "schedule": { "backend": "launchd", "calendar": {"Hour": 9, "Minute": 0}, "period_hours": $3 },
  "ttl_days": 30,
  "max_runtime_s": 1800,
  "writes_allowed": [],
  "inputs": [],
  "expected_artifacts": ["reports/report-{RUN_DATE}.md", "reports/summary-{RUN_DATE}.json"],
  "health": { "min_duration_s": 5, "min_turns": 3, "max_gap_factor": 2.0 },
  "notify": { "on": ["failure"], "channels": ["macos"] },
  "claude": { "model": "sonnet", "extra_args": [] }
}
EOF
}

# =============================================================================
# Fixture 1: healthy-job — one normal run today, fresh artifacts. Must NOT be
# flagged.
# =============================================================================
HJ="$JOBS_ROOT/healthy-job"
mkdir -p "$HJ/reports"
make_job_json "healthy-job" "$HJ" 24
STARTED="$(iso_offset 1)"
RUN_DATE="$(date_offset 1)"
cat > "$HJ/reports/report-$RUN_DATE.md" <<EOF
# healthy-job — $RUN_DATE
## Summary
1/1 due items verified | 0 issues found | 0 items skipped as fresh
EOF
echo '{"job":"healthy-job","run_date":"'"$RUN_DATE"'","status":"SUCCESS","items_checked":1,"items_skipped_fresh":0,"material_changes":[]}' \
  > "$HJ/reports/summary-$RUN_DATE.json"
python3 -c '
import json
rec = {"run_id":"r1","started":"'"$STARTED"'","ended":"'"$STARTED"'",
       "duration_s":300,"status":"SUCCESS","exit_code":0,"num_turns":20,
       "note":"0 material change(s)"}
print(json.dumps(rec))
' > "$HJ/runs.jsonl"

# =============================================================================
# Fixture 2: silent-job — the exact historical failure. 12 consecutive runs,
# each duration_s < 1 (recorded as 0, wrapper truncates to whole seconds) and
# num_turns 0, all recent (well within schedule tolerance so SCHEDULE_GAP
# does not preempt SILENT_FAILURE). Must be flagged SILENT_FAILURE.
# =============================================================================
SJ="$JOBS_ROOT/silent-job"
mkdir -p "$SJ/reports"
make_job_json "silent-job" "$SJ" 24
: > "$SJ/runs.jsonl"
for i in $(seq 1 12); do
  HRS=$(python3 -c "print($i * 0.05)")
  ST="$(iso_offset "$HRS")"
  python3 -c '
import json
print(json.dumps({"run_id":"s'"$i"'","started":"'"$ST"'","ended":"'"$ST"'",
                   "duration_s":0,"status":"SUCCESS","exit_code":0,
                   "num_turns":0,"note":"0 material change(s)"}))
' >> "$SJ/runs.jsonl"
done
RUN_DATE_S="$(date_offset 0.05)"
cat > "$SJ/reports/report-$RUN_DATE_S.md" <<EOF
# silent-job — $RUN_DATE_S (stale placeholder from the last real run)
EOF
echo '{"job":"silent-job","run_date":"'"$RUN_DATE_S"'","status":"SUCCESS","items_checked":0,"items_skipped_fresh":0,"material_changes":[]}' \
  > "$SJ/reports/summary-$RUN_DATE_S.json"

# =============================================================================
# Fixture 3: gap-job — a real, healthy-looking run, but it happened long ago:
# no runs at all in 3x the job's 24h schedule interval (last run ~96h back,
# well past max_gap_factor=2.0 * 24h = 48h threshold). Must be flagged
# SCHEDULE_GAP, not NEVER_RAN (it HAS run history) and not SILENT_FAILURE
# (that historical run itself was perfectly healthy).
# =============================================================================
GJ="$JOBS_ROOT/gap-job"
mkdir -p "$GJ/reports"
make_job_json "gap-job" "$GJ" 24
GAP_STARTED="$(iso_offset 96)"
GAP_RUN_DATE="$(date_offset 96)"
cat > "$GJ/reports/report-$GAP_RUN_DATE.md" <<EOF
# gap-job — $GAP_RUN_DATE
## Summary
1/1 due items verified | 0 issues found | 0 items skipped as fresh
EOF
echo '{"job":"gap-job","run_date":"'"$GAP_RUN_DATE"'","status":"SUCCESS","items_checked":1,"items_skipped_fresh":0,"material_changes":[]}' \
  > "$GJ/reports/summary-$GAP_RUN_DATE.json"
python3 -c '
import json
print(json.dumps({"run_id":"g1","started":"'"$GAP_STARTED"'","ended":"'"$GAP_STARTED"'",
                   "duration_s":250,"status":"SUCCESS","exit_code":0,
                   "num_turns":15,"note":"0 material change(s)"}))
' > "$GJ/runs.jsonl"
# Backdate the artifact mtimes to just after the run's start (95h ago, still
# before "now") so STALE_ARTIFACT doesn't preempt SCHEDULE_GAP — portable via
# python3's os.utime (BSD touch -d / GNU touch -d syntaxes differ).
python3 -c '
import datetime, os, sys
ts = (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(hours=95)).timestamp()
for p in sys.argv[1:]:
    os.utime(p, (ts, ts))
' "$GJ/reports/report-$GAP_RUN_DATE.md" "$GJ/reports/summary-$GAP_RUN_DATE.json"

# =============================================================================
# Fixture 4: dead-detection-job — the trailing-streak probe case: one
# perfectly healthy run 40 days ago (duration/turns well above threshold, so
# the primary "last non-NOTHING_TO_DO run" SILENT_FAILURE check does NOT
# fire), followed by a TRAILING streak of NOTHING_TO_DO records spanning the
# last 35 days on a ttl_days-bearing, 24h-period job (threshold =
# period_hours*14 = 336h = 14 days; the streak's oldest member is 35 days
# back, well past it). This is the reviewer-probe defect: gating the
# dead-detection rule on "ref is None" (whole history NOTHING_TO_DO) misses
# exactly this shape — a job with real history that has since gone dead —
# so this fixture must be flagged SILENT_FAILURE with the dead-detection
# detail regardless of the older healthy run's presence.
# =============================================================================
DDJ="$JOBS_ROOT/dead-detection-job"
mkdir -p "$DDJ/reports"
make_job_json "dead-detection-job" "$DDJ" 24
: > "$DDJ/runs.jsonl"
HEALTHY_STARTED="$(iso_offset 960)"   # 40 days ago
python3 -c '
import json
print(json.dumps({"run_id":"dd0","started":"'"$HEALTHY_STARTED"'","ended":"'"$HEALTHY_STARTED"'",
                   "duration_s":300,"status":"SUCCESS","exit_code":0,
                   "num_turns":20,"note":"1 material change(s)"}))
' >> "$DDJ/runs.jsonl"
for HRS in 840 700 500 300 100 10; do  # trailing NOTHING_TO_DO streak, oldest 35 days back
  ST="$(iso_offset "$HRS")"
  python3 -c '
import json
print(json.dumps({"run_id":"dd-'"$HRS"'","started":"'"$ST"'","ended":"'"$ST"'",
                   "duration_s":2,"status":"NOTHING_TO_DO","exit_code":0,
                   "num_turns":1,"note":"0 due item(s)"}))
' >> "$DDJ/runs.jsonl"
done

# =============================================================================
# Fixture 5: short-streak-job — the inverse guard: one healthy run 5 days
# ago, then only a SHORT trailing NOTHING_TO_DO streak (oldest member ~2
# days back, well under the 14-day/336h threshold). Must stay OK — a short
# no-op streak on a TTL job is normal, not broken detection.
# =============================================================================
SSJ="$JOBS_ROOT/short-streak-job"
mkdir -p "$SSJ/reports"
make_job_json "short-streak-job" "$SSJ" 24
: > "$SSJ/runs.jsonl"
SS_HEALTHY_STARTED="$(iso_offset 120)"  # 5 days ago
SS_RUN_DATE="$(date_offset 120)"
cat > "$SSJ/reports/report-$SS_RUN_DATE.md" <<EOF
# short-streak-job — $SS_RUN_DATE
## Summary
1/1 due items verified | 0 issues found | 0 items skipped as fresh
EOF
echo '{"job":"short-streak-job","run_date":"'"$SS_RUN_DATE"'","status":"SUCCESS","items_checked":1,"items_skipped_fresh":0,"material_changes":[]}' \
  > "$SSJ/reports/summary-$SS_RUN_DATE.json"
python3 -c '
import json
print(json.dumps({"run_id":"ss0","started":"'"$SS_HEALTHY_STARTED"'","ended":"'"$SS_HEALTHY_STARTED"'",
                   "duration_s":300,"status":"SUCCESS","exit_code":0,
                   "num_turns":20,"note":"1 material change(s)"}))
' >> "$SSJ/runs.jsonl"
for HRS in 48 24 1; do  # short trailing NOTHING_TO_DO streak, oldest 2 days back
  ST="$(iso_offset "$HRS")"
  python3 -c '
import json
print(json.dumps({"run_id":"ss-'"$HRS"'","started":"'"$ST"'","ended":"'"$ST"'",
                   "duration_s":2,"status":"NOTHING_TO_DO","exit_code":0,
                   "num_turns":1,"note":"0 due item(s)"}))
' >> "$SSJ/runs.jsonl"
done
# Backdate the artifact mtimes to just after the healthy run's start (119h
# ago) so STALE_ARTIFACT doesn't preempt the OK verdict — same portable
# os.utime technique as gap-job above.
python3 -c '
import datetime, os, sys
ts = (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(hours=119)).timestamp()
for p in sys.argv[1:]:
    os.utime(p, (ts, ts))
' "$SSJ/reports/report-$SS_RUN_DATE.md" "$SSJ/reports/summary-$SS_RUN_DATE.json"

# =============================================================================
# Fixture 6: never-ran-job — spec 06 §8 script-level item 7's "empty
# runs.jsonl" case: a scaffolded job whose launchd/cron unit never fired even
# once. No runs.jsonl at all. Must be flagged NEVER_RAN.
# =============================================================================
NRJ="$JOBS_ROOT/never-ran-job"
mkdir -p "$NRJ/reports"
make_job_json "never-ran-job" "$NRJ" 24
# Deliberately: no runs.jsonl written.

# =============================================================================
# Fixture 7: stale-artifact-job — spec 06 §8 script-level item 7's "missing
# artifact mtime" case: a run recorded as a healthy SUCCESS (good duration,
# good turn count, recent — so it clears NEVER_RAN/LAUNCH_FAIL/SILENT_FAILURE/
# SCHEDULE_GAP) that nonetheless never wrote either of its promised
# `expected_artifacts`. Must be flagged STALE_ARTIFACT.
# =============================================================================
SAJ="$JOBS_ROOT/stale-artifact-job"
mkdir -p "$SAJ/reports"
make_job_json "stale-artifact-job" "$SAJ" 24
SA_STARTED="$(iso_offset 1)"
python3 -c '
import json
print(json.dumps({"run_id":"sa1","started":"'"$SA_STARTED"'","ended":"'"$SA_STARTED"'",
                   "duration_s":300,"status":"SUCCESS","exit_code":0,
                   "num_turns":20,"note":"1 material change(s)"}))
' > "$SAJ/runs.jsonl"
# No report-*.md / summary-*.json written for this run — the "succeeded but
# produced nothing" silent artifact gap.

# =============================================================================
# Fixture 8: repeated-failure-job — spec 06 §8 script-level item 7's "3x
# FAILED" case: the last three runs all recorded status FAILED, each with a
# healthy duration/turn count (so SILENT_FAILURE's thresholds don't preempt
# it) and fresh, present artifacts (so STALE_ARTIFACT doesn't preempt it
# either) and recent enough to clear SCHEDULE_GAP. Must be flagged
# REPEATED_FAILURE.
# =============================================================================
RFJ="$JOBS_ROOT/repeated-failure-job"
mkdir -p "$RFJ/reports"
make_job_json "repeated-failure-job" "$RFJ" 24
RF_RUN_DATE="$(date_offset 1)"
cat > "$RFJ/reports/report-$RF_RUN_DATE.md" <<EOF
# repeated-failure-job — $RF_RUN_DATE
## Summary
0/1 due items verified | 1 issues found | 0 items skipped as fresh
EOF
echo '{"job":"repeated-failure-job","run_date":"'"$RF_RUN_DATE"'","status":"FAILED","items_checked":0,"items_skipped_fresh":0,"material_changes":[]}' \
  > "$RFJ/reports/summary-$RF_RUN_DATE.json"
: > "$RFJ/runs.jsonl"
for HRS in 3 2 1; do
  ST="$(iso_offset "$HRS")"
  python3 -c '
import json
print(json.dumps({"run_id":"rf-'"$HRS"'","started":"'"$ST"'","ended":"'"$ST"'",
                   "duration_s":250,"status":"FAILED","exit_code":1,
                   "num_turns":15,"note":"claude reported failure"}))
' >> "$RFJ/runs.jsonl"
done

# =============================================================================
# Run the watchdog over all eight jobs.
# =============================================================================
OUT="$("$HEALTH_SH")"
RC=$?
echo "$OUT" > "$T/health-output.txt"

# ---- Check 1: exit code is the count of flagged jobs (silent-job + gap-job
#      + dead-detection-job + never-ran-job + stale-artifact-job +
#      repeated-failure-job = 6), and specifically nonzero (findings
#      exist). ---------------------------------------------------------------
[ "$RC" -eq 6 ] || { echo "FAIL: exit code=$RC (expected 6: silent-job + gap-job + dead-detection-job + never-ran-job + stale-artifact-job + repeated-failure-job flagged)"; fail=1; }

# ---- Check 2: silent-job flagged SILENT_FAILURE; healthy-job NOT flagged
#      (no non-OK flag token on its row). ------------------------------------
echo "$OUT" | grep -q "silent-job" || { echo "FAIL: silent-job not mentioned in output"; fail=1; }
echo "$OUT" | grep "silent-job" | grep -q "SILENT_FAILURE" \
  || { echo "FAIL: silent-job not flagged SILENT_FAILURE:"$'\n'"$OUT"; fail=1; }
echo "$OUT" | grep "healthy-job" | grep -qE "NEVER_RAN|LAUNCH_FAIL|LINT_FAIL|SILENT_FAILURE|STALE_ARTIFACT|SCHEDULE_GAP|REPEATED_FAILURE" \
  && { echo "FAIL: healthy-job was flagged (should be OK):"$'\n'"$OUT"; fail=1; }
echo "$OUT" | grep -q "healthy-job.*OK\|OK.*healthy-job" \
  || { echo "FAIL: healthy-job row does not show OK:"$'\n'"$OUT"; fail=1; }

# ---- Check 3: gap-job flagged SCHEDULE_GAP. --------------------------------
echo "$OUT" | grep "gap-job" | grep -q "SCHEDULE_GAP" \
  || { echo "FAIL: gap-job not flagged SCHEDULE_GAP:"$'\n'"$OUT"; fail=1; }

# ---- Check 4: dead-detection-job flagged SILENT_FAILURE with the
#      dead-detection detail, even though it has a real, healthy run in its
#      history (the reviewer-probe defect: gating on "ref is None" i.e. a
#      virgin/all-NOTHING_TO_DO history misses a job whose TRAILING streak
#      alone has gone dead). ---------------------------------------------
echo "$OUT" | grep -q "dead-detection-job" || { echo "FAIL: dead-detection-job not mentioned in output"; fail=1; }
echo "$OUT" | grep "dead-detection-job" | grep -q "SILENT_FAILURE" \
  || { echo "FAIL: dead-detection-job not flagged SILENT_FAILURE:"$'\n'"$OUT"; fail=1; }
echo "$OUT" | grep "dead-detection-job" | grep -qi "NOTHING_TO_DO" \
  || { echo "FAIL: dead-detection-job's detail doesn't name the dead-detection streak:"$'\n'"$OUT"; fail=1; }

# ---- Check 5 (inverse guard): short-streak-job has only a SHORT trailing
#      NOTHING_TO_DO streak (oldest member ~2 days back, well under the
#      14-day/period_hours*14 threshold) after a healthy run — must stay OK,
#      not be swept up by the dead-detection rule. ---------------------------
echo "$OUT" | grep -q "short-streak-job" || { echo "FAIL: short-streak-job not mentioned in output"; fail=1; }
echo "$OUT" | grep "short-streak-job" | grep -qE "NEVER_RAN|LAUNCH_FAIL|LINT_FAIL|SILENT_FAILURE|STALE_ARTIFACT|SCHEDULE_GAP|REPEATED_FAILURE" \
  && { echo "FAIL: short-streak-job was flagged (should be OK):"$'\n'"$OUT"; fail=1; }
echo "$OUT" | grep -q "short-streak-job.*OK\|OK.*short-streak-job" \
  || { echo "FAIL: short-streak-job row does not show OK:"$'\n'"$OUT"; fail=1; }

# ---- Check 6: never-ran-job flagged NEVER_RAN (no runs.jsonl at all). ------
echo "$OUT" | grep "never-ran-job" | grep -q "NEVER_RAN" \
  || { echo "FAIL: never-ran-job not flagged NEVER_RAN:"$'\n'"$OUT"; fail=1; }

# ---- Check 7: stale-artifact-job flagged STALE_ARTIFACT (healthy-looking
#      recent run, but neither expected artifact was ever written). ---------
echo "$OUT" | grep "stale-artifact-job" | grep -q "STALE_ARTIFACT" \
  || { echo "FAIL: stale-artifact-job not flagged STALE_ARTIFACT:"$'\n'"$OUT"; fail=1; }

# ---- Check 8: repeated-failure-job flagged REPEATED_FAILURE (last 3 runs
#      all FAILED, otherwise healthy-shaped). --------------------------------
echo "$OUT" | grep "repeated-failure-job" | grep -q "REPEATED_FAILURE" \
  || { echo "FAIL: repeated-failure-job not flagged REPEATED_FAILURE:"$'\n'"$OUT"; fail=1; }

# ---- Bonus: dated health report files were written under
#      ~/.claude/dev-cycle/jobs/health/. -----------------------------------------
HEALTH_DIR="$HOME/.claude/dev-cycle/jobs/health"
TODAY="$(date +%F)"
[ -f "$HEALTH_DIR/health-$TODAY.md" ] || { echo "FAIL: health-$TODAY.md not written"; fail=1; }
[ -f "$HEALTH_DIR/health-$TODAY.json" ] || { echo "FAIL: health-$TODAY.json not written"; fail=1; }
python3 -m json.tool "$HEALTH_DIR/health-$TODAY.json" >/dev/null 2>&1 \
  || { echo "FAIL: health-$TODAY.json is not valid JSON"; fail=1; }

# ---- Bonus: --notify no-ops gracefully when bin/notify.sh is absent (no
#      notify infra shipped yet this wave) — must not error or change exit
#      semantics. ------------------------------------------------------------
"$HEALTH_SH" --notify >/dev/null 2>"$T/notify-stderr.txt"
RC2=$?
[ "$RC2" -eq 6 ] || { echo "FAIL: --notify changed exit code to $RC2 (expected 6)"; fail=1; }
[ -s "$T/notify-stderr.txt" ] && { echo "FAIL: --notify with no notify.sh printed to stderr: $(cat "$T/notify-stderr.txt")"; fail=1; }

# ---- Bonus: --job scopes to a single job. ----------------------------------
OUT_SCOPED="$("$HEALTH_SH" --job healthy-job)"
RC3=$?
[ "$RC3" -eq 0 ] || { echo "FAIL: --job healthy-job exit=$RC3 (expected 0)"; fail=1; }
echo "$OUT_SCOPED" | grep -q "silent-job" && { echo "FAIL: --job healthy-job leaked silent-job into output"; fail=1; }

rm -rf "$T"
[ $fail -eq 0 ] && echo "OK: scheduled-jobs health (8 checks)"
exit $fail
