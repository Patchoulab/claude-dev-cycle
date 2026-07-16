#!/bin/bash
# scheduled-jobs wrapper end-to-end test: scaffolds a job directory in a sandbox
# HOME per spec 06 §5.1, renders templates/run.sh.tmpl (Task 6) verbatim,
# wires the real bin/render_lint.py (Task 7), and drives the wrapper against
# a stub `claude` binary (PATH-prepended — run.sh.tmpl has no override
# mechanism for the claude binary; see stub-claude.sh's header). Exercises
# the brief's 5 assertions end to end.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$DIR/../../.."
TMPL="$REPO/skills/scheduled-jobs/templates/run.sh.tmpl"
PROMPT_TMPL="$REPO/skills/scheduled-jobs/templates/prompt.tmpl.md"
RENDER_LINT_SRC="$REPO/scripts/jobs_render_lint.py"
fail=0

[ -f "$TMPL" ] || { echo "FAIL: run.sh.tmpl missing"; exit 1; }
[ -f "$PROMPT_TMPL" ] || { echo "FAIL: prompt.tmpl.md missing"; exit 1; }
[ -f "$RENDER_LINT_SRC" ] || { echo "FAIL: render_lint.py missing"; exit 1; }

T=$(mktemp -d)
export HOME="$T/home"
JOB_DIR="$HOME/.claude/dev-cycle/jobs/jobs/test-job"
BIN_DIR="$HOME/.claude/dev-cycle/jobs/bin"
REPORTS="$JOB_DIR/reports"
RUNS="$JOB_DIR/runs.jsonl"
TODAY="$(date +%F)"

mkdir -p "$JOB_DIR" "$BIN_DIR" "$HOME/example-job"

# ---- Scaffold the job directory (spec 06 §5.1) ----------------------------

# job.json: Task 7's valid fixture, renamed to this job and pointed at an
# input file that actually exists under the sandbox HOME (render_lint's L3
# checks manifest inputs for real existence).
python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
d["name"] = "test-job"
d["inputs"] = ["~/example-job/input.txt"]
d["writes_allowed"] = ["~/example-job/output.txt"]
json.dump(d, open(sys.argv[2], "w"), indent=2)
' "$DIR/fixtures/job-valid.json" "$JOB_DIR/job.json"
echo "stub input" > "$HOME/example-job/input.txt"

# prompt template: master template, verbatim (per §5.5, ROLE_FRAMING et al.
# are normally pre-baked at scaffold time; render_lint.py's documented
# fallbacks make the master template itself a conforming standalone target,
# same as Task 7's own test suite exercises).
cp "$PROMPT_TMPL" "$JOB_DIR/prompt.tmpl.md"

# settings.json: content is opaque to the wrapper (only the path is passed
# to `claude --settings`); a minimal file is enough.
echo '{}' > "$JOB_DIR/settings.json"

# bin/render_lint.py: the real Task 7 script, copied in as scaffolding would
# (spec 06 §5 preamble: installed idempotently to ~/.claude/dev-cycle/jobs/bin/).
cp "$RENDER_LINT_SRC" "$BIN_DIR/render_lint.py"

# bin/notify.sh: not yet implemented by any task in this wave (spec 06 §5.4's
# `bin/notify.sh` contract is out of scope here) — a spy stand-in so the
# wrapper's `"$BIN_DIR/notify.sh" ... || true` calls resolve to a real,
# harmless executable (instead of a bare "command not found") AND so
# Assertion 6 below can prove notify.sh was actually invoked on LAUNCH_FAIL.
# Pure test harness wiring, not a template/contract concern.
cat > "$BIN_DIR/notify.sh" <<'EOF'
#!/bin/bash
echo "$*" >> "${DEV_CYCLE_NOTIFY_RECORD:-/dev/null}"
exit 0
EOF
chmod +x "$BIN_DIR/notify.sh"
NOTIFY_RECORD="$T/notify-record"
export DEV_CYCLE_NOTIFY_RECORD="$NOTIFY_RECORD"

# run.sh: templates/run.sh.tmpl (spec 06 §5.4, verbatim) with the three
# scaffold tokens substituted, exactly as `/dev-cycle:jobs:new` would.
sed -e 's/@JOB_NAME@/test-job/g' \
    -e 's/@TTL_DAYS@/30/g' \
    -e 's/@MAX_RUNTIME_S@/5/g' \
    "$TMPL" > "$JOB_DIR/run.sh"
chmod +x "$JOB_DIR/run.sh"

# state.json: one OUTDATED (due) item, one OK/fresh item — matches Task 7's
# due-valid.json fixture (only widget-a is due).
seed_state() {
  cat > "$JOB_DIR/state.json" <<EOF
{
  "version": 1,
  "job": "test-job",
  "updated": "2026-07-01T09:00:00Z",
  "items": {
    "widget-a": {
      "kind": "example",
      "status": "OUTDATED",
      "last_verified": "2026-05-01",
      "source_url": "https://example.com/widget-a",
      "method": "download latest release",
      "consecutive_failures": 0,
      "notes": ""
    },
    "widget-b": {
      "kind": "example",
      "status": "OK",
      "last_verified": "2026-07-01",
      "source_url": "https://example.com/widget-b",
      "method": "n/a",
      "consecutive_failures": 0,
      "notes": ""
    }
  },
  "ignored": {},
  "seen": {}
}
EOF
}
seed_state

# ---- claude binary: PATH-prepend the stub (no override mechanism exists in
#      run.sh.tmpl — command -v claude / claude are both literal) ----------
STUBDIR="$T/stubbin"
mkdir -p "$STUBDIR"
cp "$DIR/stub-claude.sh" "$STUBDIR/claude"
chmod +x "$STUBDIR/claude"
export PATH="$STUBDIR:$PATH"
export DEV_CYCLE_STUB_JOB_DIR="$JOB_DIR"
export DEV_CYCLE_STUB_RECORD="$T/stub-record"

run_wrapper() { bash "$JOB_DIR/run.sh"; }

# =============================================================================
# Assertion 1: wrapper run -> exit 0; runs.jsonl gains exactly one §5.7-shaped
# record.
# =============================================================================
run_wrapper
rc=$?
[ "$rc" -eq 0 ] || { echo "FAIL: wrapper exit=$rc (expected 0) on first run"; fail=1; }
[ -f "$RUNS" ] || { echo "FAIL: runs.jsonl not created"; fail=1; }
LINES=$(wc -l < "$RUNS" | tr -d ' ')
[ "$LINES" -eq 1 ] || { echo "FAIL: runs.jsonl has $LINES lines after first run (expected 1)"; fail=1; }
REC1="$(tail -1 "$RUNS")"
python3 -c '
import json, sys
d = json.loads(sys.argv[1])
required = ["run_id", "started", "ended", "duration_s", "status", "exit_code", "num_turns", "note"]
missing = [k for k in required if k not in d]
sys.exit(1 if missing else 0)
' "$REC1" || { echo "FAIL: runs.jsonl record missing §5.7 fields: $REC1"; fail=1; }
echo "$REC1" | jq -e '.status == "SUCCESS" and .exit_code == 0' >/dev/null \
  || { echo "FAIL: first-run record not SUCCESS/exit_code 0: $REC1"; fail=1; }

# =============================================================================
# Assertion 2: state file updated for due items (last-verified date advanced).
# =============================================================================
jq -e --arg d "$TODAY" '.items["widget-a"].status == "OK" and .items["widget-a"].last_verified == $d' \
  "$JOB_DIR/state.json" >/dev/null \
  || { echo "FAIL: widget-a (due) not advanced to OK/$TODAY in state.json"; fail=1; }
jq -e '.items["widget-b"].status == "OK" and .items["widget-b"].last_verified == "2026-07-01"' \
  "$JOB_DIR/state.json" >/dev/null \
  || { echo "FAIL: widget-b (fresh, not due) was mutated by a run that shouldn't have touched it"; fail=1; }

# =============================================================================
# Assertion 3: report artifact written per §5.6's path contract; previous
# report preserved (dated history, not overwrite). Run twice: both a
# pre-existing older-dated report and the new run's dated report survive.
# =============================================================================
[ -f "$REPORTS/report-$TODAY.md" ] || { echo "FAIL: today's report not written"; fail=1; }
[ -f "$REPORTS/summary-$TODAY.json" ] || { echo "FAIL: today's summary not written"; fail=1; }
[ -L "$REPORTS/latest.md" ] || { echo "FAIL: reports/latest.md symlink not created"; fail=1; }
readlink "$REPORTS/latest.md" | grep -q "report-$TODAY.md" \
  || { echo "FAIL: latest.md does not point at today's report"; fail=1; }

# Simulate history from an earlier day, then re-run today.
OLD_REPORT="$REPORTS/report-2026-06-01.md"
echo "# stub-job — 2026-06-01 (pre-existing dated history)" > "$OLD_REPORT"
OLD_REPORT_SNAPSHOT="$(cat "$OLD_REPORT")"

seed_state   # make widget-a due again so the second run is a real run, not NOTHING_TO_DO
run_wrapper
rc=$?
[ "$rc" -eq 0 ] || { echo "FAIL: wrapper exit=$rc (expected 0) on second run"; fail=1; }
LINES=$(wc -l < "$RUNS" | tr -d ' ')
[ "$LINES" -eq 2 ] || { echo "FAIL: runs.jsonl has $LINES lines after second run (expected 2)"; fail=1; }

[ -f "$OLD_REPORT" ] || { echo "FAIL: pre-existing dated report (2026-06-01) was deleted by a same-day re-run"; fail=1; }
[ "$(cat "$OLD_REPORT")" = "$OLD_REPORT_SNAPSHOT" ] || { echo "FAIL: pre-existing dated report content was altered"; fail=1; }
[ -f "$REPORTS/report-$TODAY.md" ] || { echo "FAIL: today's report missing after second run"; fail=1; }
[ -f "$REPORTS/diff-$TODAY.txt" ] || { echo "FAIL: diff vs previous dated report not produced"; fail=1; }

# =============================================================================
# Assertion 4: contract-verification. Stub produces NO report -> wrapper
# marks the run FAILED in runs.jsonl (anti-silent-failure invariant).
# =============================================================================
seed_state
rm -f "$REPORTS/report-$TODAY.md" "$REPORTS/summary-$TODAY.json"
DEV_CYCLE_STUB_NO_REPORT=1 run_wrapper
rc=$?
[ "$rc" -ne 0 ] || { echo "FAIL: wrapper exited 0 despite the stub producing no report (silent failure)"; fail=1; }
LINES=$(wc -l < "$RUNS" | tr -d ' ')
[ "$LINES" -eq 3 ] || { echo "FAIL: runs.jsonl has $LINES lines after the no-report run (expected 3)"; fail=1; }
REC4="$(tail -1 "$RUNS")"
echo "$REC4" | jq -e '.status == "FAILED"' >/dev/null \
  || { echo "FAIL: no-report run not recorded as FAILED: $REC4"; fail=1; }
echo "$REC4" | grep -q "summary" || { echo "FAIL: FAILED record note doesn't mention the missing summary: $REC4"; fail=1; }
[ -f "$REPORTS/report-$TODAY.md" ] && { echo "FAIL: a report materialized despite the stub being told not to write one"; fail=1; }

# =============================================================================
# Assertion 5: lint gate. Corrupt job.json (dangling separator in a rendered
# list block) -> wrapper refuses to launch (render_lint exit 2 path).
# =============================================================================
seed_state
cp "$JOB_DIR/job.json" "$T/job.json.bak"
python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
# Dangling separator: an inputs entry with a trailing comma baked into the
# path itself -- the historical "vercel,bun," bug class (spec 06 §5.8 L2).
d["inputs"].append("~/example-job/extra,")
json.dump(d, open(sys.argv[1], "w"), indent=2)
' "$JOB_DIR/job.json"

BEFORE_LINES=$(wc -l < "$RUNS" | tr -d ' ')
run_wrapper
rc=$?
[ "$rc" -ne 0 ] || { echo "FAIL: wrapper exited 0 against a corrupted (dangling-separator) job.json"; fail=1; }
AFTER_LINES=$(wc -l < "$RUNS" | tr -d ' ')
[ "$AFTER_LINES" -eq $((BEFORE_LINES + 1)) ] || { echo "FAIL: expected exactly one new runs.jsonl record for the lint-fail run"; fail=1; }
REC5="$(tail -1 "$RUNS")"
echo "$REC5" | jq -e '.status == "LINT_FAIL"' >/dev/null \
  || { echo "FAIL: corrupted-manifest run not recorded as LINT_FAIL: $REC5"; fail=1; }
LINT_FILE="$(ls -t "$JOB_DIR"/logs/*.lint 2>/dev/null | head -1)"
[ -n "$LINT_FILE" ] || { echo "FAIL: no .lint findings file written for the lint-fail run"; fail=1; }
grep -q "^L2:" "$LINT_FILE" || { echo "FAIL: lint findings don't include the expected L2 (dangling separator) finding: $(cat "$LINT_FILE" 2>/dev/null)"; fail=1; }
RENDERED_FILE="${LINT_FILE%.lint}"
[ -f "$RENDERED_FILE" ] && { echo "FAIL: a rendered prompt was written despite the lint failure (never launch an unlinted prompt)"; fail=1; }

cp "$T/job.json.bak" "$JOB_DIR/job.json"

# =============================================================================
# Assertion 6 (spec 06 §8 script-level item 3): claude binary unavailable ->
# exactly one LAUNCH_FAIL record and a notify.sh invocation (spy), wrapper
# exits nonzero. PATH is filtered (not just the sandbox stub renamed away) so
# a real `claude` CLI elsewhere on the dev machine's PATH can't mask the
# preflight check and accidentally get invoked with fake sandbox args.
# =============================================================================
seed_state
: > "$NOTIFY_RECORD"
BEFORE_LINES=$(wc -l < "$RUNS" | tr -d ' ')
mv "$STUBDIR/claude" "$STUBDIR/claude.hidden"
NOCLAUDE_PATH=""
OLD_IFS="$IFS"; IFS=':'
for d in $PATH; do
  [ -n "$d" ] || continue
  [ -x "$d/claude" ] && continue   # drop any PATH component with its own claude
  NOCLAUDE_PATH="$NOCLAUDE_PATH:$d"
done
IFS="$OLD_IFS"
NOCLAUDE_PATH="${NOCLAUDE_PATH#:}"
PATH="$NOCLAUDE_PATH" run_wrapper
rc=$?
mv "$STUBDIR/claude.hidden" "$STUBDIR/claude"
[ "$rc" -ne 0 ] || { echo "FAIL: wrapper exited 0 despite claude missing from PATH"; fail=1; }
AFTER_LINES=$(wc -l < "$RUNS" | tr -d ' ')
[ "$AFTER_LINES" -eq $((BEFORE_LINES + 1)) ] || { echo "FAIL: expected exactly one new runs.jsonl record for the LAUNCH_FAIL run (before=$BEFORE_LINES after=$AFTER_LINES)"; fail=1; }
REC6="$(tail -1 "$RUNS")"
echo "$REC6" | jq -e '.status == "LAUNCH_FAIL"' >/dev/null \
  || { echo "FAIL: claude-missing run not recorded as LAUNCH_FAIL: $REC6"; fail=1; }
[ -s "$NOTIFY_RECORD" ] || { echo "FAIL: notify.sh not invoked on LAUNCH_FAIL"; fail=1; }

# =============================================================================
# Assertion 7 (spec 06 §8 script-level item 4): zero due items -> a single
# NOTHING_TO_DO record and the stub claude is never invoked at all (spy via
# DEV_CYCLE_STUB_RECORD — zero new lines, not just "no report written").
# =============================================================================
cat > "$JOB_DIR/state.json" <<EOF
{
  "version": 1,
  "job": "test-job",
  "updated": "2026-07-01T09:00:00Z",
  "items": {
    "widget-a": {
      "kind": "example",
      "status": "OK",
      "last_verified": "$TODAY",
      "source_url": "https://example.com/widget-a",
      "method": "download latest release",
      "consecutive_failures": 0,
      "notes": ""
    }
  },
  "ignored": {},
  "seen": {}
}
EOF
BEFORE_LINES=$(wc -l < "$RUNS" | tr -d ' ')
: > "$DEV_CYCLE_STUB_RECORD"
run_wrapper
rc=$?
[ "$rc" -eq 0 ] || { echo "FAIL: wrapper exit=$rc (expected 0) on a zero-due-items run"; fail=1; }
AFTER_LINES=$(wc -l < "$RUNS" | tr -d ' ')
[ "$AFTER_LINES" -eq $((BEFORE_LINES + 1)) ] || { echo "FAIL: expected exactly one new runs.jsonl record for the no-due-items run"; fail=1; }
REC7="$(tail -1 "$RUNS")"
echo "$REC7" | jq -e '.status == "NOTHING_TO_DO"' >/dev/null \
  || { echo "FAIL: zero-due-items run not recorded as NOTHING_TO_DO: $REC7"; fail=1; }
[ -s "$DEV_CYCLE_STUB_RECORD" ] && { echo "FAIL: stub claude was invoked despite zero due items: $(cat "$DEV_CYCLE_STUB_RECORD")"; fail=1; }

# =============================================================================
# Assertion 8 (spec 06 §8 script-level item 8): staleness selection. A state
# with an item at TTL-1 days (fresh, NOT due), one at TTL+1 days (stale, due),
# one with status:FAILED (due regardless of date), and one entry under the
# top-level `ignored` dict (never selected — `ignored` lives outside `items`
# entirely, per spec 06 §5.3's selection rule) must produce a due list
# containing exactly the stale and FAILED items. Runs the REAL detect_items()
# extracted out of the already-rendered run.sh (TTL_DAYS=30 in this sandbox),
# not a hand-copied mirror of its jq filter, so a future template edit can't
# silently drift out of sync with this test.
# =============================================================================
DETECT_SRC="$(sed -n '/^detect_items() {/,/^}/p' "$JOB_DIR/run.sh")"
[ -n "$DETECT_SRC" ] || { echo "FAIL: could not extract detect_items() from rendered run.sh"; fail=1; }

STALE_DIR=$(mktemp -d)
STALE_STATE="$STALE_DIR/state.json"
STALE_DUE="$STALE_DIR/due.json"
# UTC, not local date: detect_items()'s jq compares against `now` (UTC epoch)
# at T00:00:00Z, so anchoring the fixture dates to the local calendar date
# can land on the wrong side of the 30-day boundary whenever local time and
# UTC disagree on "today" (i.e. within a few hours of UTC midnight).
TTL_MINUS_1_DATE="$(python3 -c "import datetime; print((datetime.datetime.now(datetime.timezone.utc).date()-datetime.timedelta(days=29)).isoformat())")"
TTL_PLUS_1_DATE="$(python3 -c "import datetime; print((datetime.datetime.now(datetime.timezone.utc).date()-datetime.timedelta(days=31)).isoformat())")"
cat > "$STALE_STATE" <<EOF
{
  "version": 1,
  "job": "test-job",
  "updated": "${TODAY}T00:00:00Z",
  "items": {
    "fresh-item":  {"kind":"x","status":"OK","last_verified":"$TTL_MINUS_1_DATE","source_url":"","method":"","consecutive_failures":0,"notes":""},
    "stale-item":  {"kind":"x","status":"OK","last_verified":"$TTL_PLUS_1_DATE","source_url":"","method":"","consecutive_failures":0,"notes":""},
    "failed-item": {"kind":"x","status":"FAILED","last_verified":"$TODAY","source_url":"","method":"","consecutive_failures":1,"notes":""}
  },
  "ignored": { "ignored-item": {"reason":"test","added":"$TODAY"} },
  "seen": {}
}
EOF
(
  STATE="$STALE_STATE"; DUE_FILE="$STALE_DUE"
  eval "$DETECT_SRC"
  detect_items
)
DUE_NAMES="$(jq -r '[.[].name] | sort | join(",")' "$STALE_DUE" 2>/dev/null)"
[ "$DUE_NAMES" = "failed-item,stale-item" ] \
  || { echo "FAIL: staleness selection due list = [$DUE_NAMES], expected exactly [failed-item,stale-item]"; fail=1; }
rm -rf "$STALE_DIR"

rm -rf "$T"
[ $fail -eq 0 ] && echo "OK: scheduled-jobs wrapper (8 checks)"
exit $fail
