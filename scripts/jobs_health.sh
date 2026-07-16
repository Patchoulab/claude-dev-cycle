#!/bin/bash
# jobs_health.sh — scheduled-jobs watchdog.
#
# Contract: docs/skills/scheduled-jobs.md (health watchdog). Reads each
# registered job's runs.jsonl records and its job directory layout.
#
# Reason this exists: an unattended audit job can fire many consecutive
# scheduled runs in under a second each, with zero tool calls, and nothing
# flags it. This watchdog scans every
# registered job's run history for that signature (SILENT_FAILURE) plus the
# other silent-death modes a cron job can suffer: it never ran at all
# (NEVER_RAN), its wrapper couldn't even launch claude (LAUNCH_FAIL) or its
# rendered prompt failed lint (LINT_FAIL), it "succeeded" but didn't produce
# its promised artifacts (STALE_ARTIFACT), it simply stopped firing on
# schedule (SCHEDULE_GAP), or it's been failing repeatedly (REPEATED_FAILURE).
#
# Path mapping (locked path mapping, spec 06 §5.1/§5): this file ships in the
# plugin repo as `scripts/jobs_health.sh`. At scaffold time
# (`/dev-cycle:jobs:new`) it is copied idempotently, with a version stamp,
# to the installed runtime location `~/.claude/dev-cycle/jobs/bin/scheduled-jobs-health.sh`
# — that installed name is what `/dev-cycle:jobs:health` and any scheduled
# watchdog job actually invoke. The two names refer to the same file at two
# points in its lifecycle: repo source vs. installed copy (same convention as
# jobs_render_lint.py / bin/render_lint.py).
#
# Usage:
#   jobs_health.sh [--job NAME] [--notify] [--json]
#
#   --job NAME   Scope the scan to a single registered job (by job.json
#                "name", not directory name, though scaffolds keep them equal).
#   --notify     For every non-OK job, invoke the job's own
#                `$BIN_DIR/notify.sh <manifest> <event> <message>` (spec 06
#                §5.4 contract) so channels/subscriptions come from that job's
#                own manifest. `bin/notify.sh` is a separate deliverable
#                (spec 06 §5 preamble) not yet shipped by this wave's tasks;
#                when it is absent or not executable, --notify is a
#                documented graceful no-op — the health scan still runs,
#                still reports, still exits with the flagged-job count. This
#                mirrors the wrapper's `"$BIN_DIR/notify.sh" ... || true`
#                house rule: notification delivery must never be allowed to
#                make an unattended run (or here, an unattended health check)
#                fail louder than the thing it's reporting on.
#   --json       Emit the machine-readable results array to stdout instead of
#                the human table. The dated `health-YYYY-MM-DD.md` (table) and
#                `health-YYYY-MM-DD.json` (this same array) report files
#                under `~/.claude/dev-cycle/jobs/health/` are always written
#                regardless of this flag.
#
# Exit code: number of flagged (non-OK) jobs. 0 = every scanned job is OK.
#
# Flag evaluation order (spec 06 §5.9 table, top to bottom; first match wins
# — the table format is one flag per job, and exit code counts JOBS not
# findings, so per-job evaluation short-circuits at the first applicable
# rule): NEVER_RAN, LAUNCH_FAIL / LINT_FAIL, SILENT_FAILURE, STALE_ARTIFACT,
# SCHEDULE_GAP, REPEATED_FAILURE, OK.
#
# Reconciliation note (§5.9's closing paragraph, not a named row in the flag
# table): "NOTHING_TO_DO streaks are reported as info, not flags, unless the
# streak exceeds period_hours * 14 for a job whose TTL guarantees periodic
# due items." This has no flag name of its own in the table, so it is
# implemented as a SILENT_FAILURE variant (detail text distinguishes it) —
# a discovery job that legitimately no-ops forever is fine and untouched by
# this rule (it has no ttl_days), but a TTL-bearing job whose detection has
# silently stopped finding due items for 14x its period is exactly the same
# class of problem this watchdog exists to catch: automation that "runs"
# and produces nothing, undetected.
set -euo pipefail

JOB_FILTER=""
NOTIFY=0
JSON_OUT=0

while [ $# -gt 0 ]; do
  case "$1" in
    --job) JOB_FILTER="${2:-}"; shift 2 ;;
    --notify) NOTIFY=1; shift ;;
    --json) JSON_OUT=1; shift ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^#//; s/^ //'
      exit 0
      ;;
    *) echo "scheduled-jobs-health: unknown argument: $1" >&2; exit 64 ;;
  esac
done

SCHEDULED_JOBS_ROOT="${SCHEDULED_JOBS_ROOT:-$HOME/.claude/dev-cycle/jobs}"
JOBS_ROOT="$SCHEDULED_JOBS_ROOT/jobs"
BIN_DIR="$SCHEDULED_JOBS_ROOT/bin"
HEALTH_DIR="$SCHEDULED_JOBS_ROOT/health"
mkdir -p "$HEALTH_DIR"

TODAY="$(date +%F)"
NOW_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# ---------------------------------------------------------------------------
# All flag logic runs here, in Python: date/timezone arithmetic and file
# mtime comparisons are painful and platform-inconsistent in pure bash+jq
# (BSD vs GNU `date`/`stat` on the two platforms this plugin targets), the
# same reasoning that put jobs_render_lint.py in Python rather than
# jq. This script stays the single shipped deliverable (per the task brief)
# by embedding the logic inline rather than adding a second file.
# ---------------------------------------------------------------------------
RESULTS_JSON="$(python3 - "$JOBS_ROOT" "$JOB_FILTER" "$NOW_ISO" <<'PYEOF'
import sys, json, os, glob, pathlib
from datetime import datetime, timezone

jobs_root, job_filter, now_iso = sys.argv[1], sys.argv[2], sys.argv[3]


def parse_iso(s):
    return datetime.strptime(s, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)


def resolve_artifact(path_str, job_dir):
    if path_str.startswith("~"):
        return pathlib.Path(path_str).expanduser()
    p = pathlib.Path(path_str)
    if p.is_absolute():
        return p
    return pathlib.Path(job_dir) / p


now = parse_iso(now_iso)
results = []

job_dirs = sorted(d for d in glob.glob(os.path.join(jobs_root, "*")) if os.path.isdir(d))

for job_dir in job_dirs:
    manifest_path = os.path.join(job_dir, "job.json")
    if not os.path.isfile(manifest_path):
        continue  # not a job directory (5.1: the set of jobs/*/job.json IS the registry)

    dir_name = os.path.basename(job_dir)
    try:
        manifest = json.loads(pathlib.Path(manifest_path).read_text())
    except Exception as e:
        if job_filter and dir_name != job_filter:
            continue
        results.append({
            "job": dir_name, "flag": "LAUNCH_FAIL",
            "detail": f"job.json unreadable/invalid: {e}",
            "last_run": None,
        })
        continue

    name = manifest.get("name", dir_name)
    if job_filter and name != job_filter:
        continue

    health_cfg = manifest.get("health") or {}
    min_duration_s = health_cfg.get("min_duration_s", 5)
    min_turns = health_cfg.get("min_turns", 3)
    max_gap_factor = health_cfg.get("max_gap_factor", 2.0)
    period_hours = (manifest.get("schedule") or {}).get("period_hours", 24)
    ttl_days = manifest.get("ttl_days")
    expected_artifacts = manifest.get("expected_artifacts") or []
    notify_cfg = manifest.get("notify") or {}

    runs_path = os.path.join(job_dir, "runs.jsonl")
    runs = []
    malformed = 0
    if os.path.isfile(runs_path):
        for line in pathlib.Path(runs_path).read_text().splitlines():
            line = line.strip()
            if not line:
                continue
            try:
                runs.append(json.loads(line))
            except Exception:
                malformed += 1  # never crash the watchdog on a corrupt line

    entry = {
        "job": name, "job_dir": job_dir, "flag": None, "detail": "",
        "last_run": None, "notify": notify_cfg,
    }

    # ---- NEVER_RAN ---------------------------------------------------
    if not runs:
        entry["flag"] = "NEVER_RAN"
        entry["detail"] = "runs.jsonl missing or empty" + (
            f" ({malformed} malformed line(s) ignored)" if malformed else ""
        )
        results.append(entry)
        continue

    last = runs[-1]
    entry["last_run"] = {
        "run_id": last.get("run_id"), "started": last.get("started"),
        "status": last.get("status"), "duration_s": last.get("duration_s"),
        "num_turns": last.get("num_turns"),
    }

    # ---- LAUNCH_FAIL / LINT_FAIL (literal last run record) ------------
    if last.get("status") in ("LAUNCH_FAIL", "LINT_FAIL"):
        entry["flag"] = last["status"]
        entry["detail"] = last.get("note") or f"last run recorded {last['status']}"
        results.append(entry)
        continue

    # ---- SILENT_FAILURE: last non-NOTHING_TO_DO run ---------------------
    # This is the exact historical failure mode: a run that "completed"
    # (exit 0, no error) but in well under min_duration_s with well under
    # min_turns tool calls — the 12x sub-second, zero-tool-call audit runs.
    ref = next((r for r in reversed(runs) if r.get("status") != "NOTHING_TO_DO"), None)
    if ref is not None:
        dur = ref.get("duration_s") or 0
        turns = ref.get("num_turns") or 0
        if dur < min_duration_s or turns < min_turns:
            entry["flag"] = "SILENT_FAILURE"
            entry["detail"] = (
                f"run {ref.get('run_id')} (status={ref.get('status')}) "
                f"duration_s={dur} (<{min_duration_s}) or num_turns={turns} (<{min_turns})"
            )
            results.append(entry)
            continue

    # ---- SILENT_FAILURE (extension): dead-detection streak -------------
    # See header reconciliation note: a TTL-bearing job whose TRAILING run
    # history is NOTHING_TO_DO, spanning more than period_hours*14, has
    # detection that has silently stopped finding due items. This is a
    # trailing-streak check, not a whole-history check: it fires whether the
    # job's entire recorded history is NOTHING_TO_DO or it merely hasn't
    # found anything due in a long time after older, real runs — a job with
    # one healthy run 400 days ago followed by 200 days of NOTHING_TO_DO is
    # exactly the broken-detection case this rule exists to catch, and
    # gating on "ref is None" (whole history) would let it slip through.
    trailing_streak = []
    for r in reversed(runs):
        if r.get("status") == "NOTHING_TO_DO":
            trailing_streak.append(r)
        else:
            break
    if ttl_days and trailing_streak:
        oldest_in_streak = trailing_streak[-1]
        try:
            span_hours = (now - parse_iso(oldest_in_streak["started"])).total_seconds() / 3600.0
        except Exception:
            span_hours = 0.0
        threshold = period_hours * 14
        if span_hours > threshold:
            entry["flag"] = "SILENT_FAILURE"
            entry["detail"] = (
                f"{len(trailing_streak)} trailing consecutive NOTHING_TO_DO run(s) "
                f"spanning {span_hours:.1f}h (> period_hours*14={threshold:.1f}h) for a "
                f"TTL-bearing job (ttl_days={ttl_days}); detection is likely broken"
            )
            results.append(entry)
            continue

    # ---- STALE_ARTIFACT --------------------------------------------------
    if ref is not None:
        run_date = str(ref.get("started", ""))[:10]
        try:
            ref_started_dt = parse_iso(ref["started"])
        except Exception:
            ref_started_dt = None
        stale_detail = None
        for artifact in expected_artifacts:
            rel = artifact.replace("{RUN_DATE}", run_date)
            p = resolve_artifact(rel, job_dir)
            if not p.exists():
                stale_detail = f"expected artifact missing: {rel}"
                break
            if ref_started_dt is not None:
                mtime = datetime.fromtimestamp(p.stat().st_mtime, tz=timezone.utc)
                if mtime < ref_started_dt:
                    stale_detail = (
                        f"expected artifact stale (mtime {mtime.isoformat()} predates "
                        f"run start {ref['started']}): {rel}"
                    )
                    break
        if stale_detail:
            entry["flag"] = "STALE_ARTIFACT"
            entry["detail"] = stale_detail
            results.append(entry)
            continue

    # ---- SCHEDULE_GAP -----------------------------------------------------
    try:
        last_started_dt = parse_iso(last["started"])
        gap_hours = (now - last_started_dt).total_seconds() / 3600.0
    except Exception:
        gap_hours = 0.0
    threshold_hours = period_hours * max_gap_factor
    if gap_hours > threshold_hours:
        entry["flag"] = "SCHEDULE_GAP"
        entry["detail"] = (
            f"last run started {last.get('started')}, {gap_hours:.1f}h ago "
            f"(> period_hours*max_gap_factor={threshold_hours:.1f}h)"
        )
        results.append(entry)
        continue

    # ---- REPEATED_FAILURE ---------------------------------------------
    last3 = runs[-3:]
    if len(last3) == 3 and all(r.get("status") == "FAILED" for r in last3):
        entry["flag"] = "REPEATED_FAILURE"
        entry["detail"] = "last 3 runs all FAILED"
        results.append(entry)
        continue

    # ---- OK -------------------------------------------------------------
    entry["flag"] = "OK"
    entry["detail"] = ""
    results.append(entry)

print(json.dumps(results))
PYEOF
)"

FLAGGED_COUNT="$(echo "$RESULTS_JSON" | jq '[.[] | select(.flag != "OK")] | length')"

# ---------------------------------------------------------------------------
# Human table (always built; printed unless --json, always embedded in the
# dated .md report).
# ---------------------------------------------------------------------------
TABLE="$(echo "$RESULTS_JSON" | jq -r '
  ["JOB","LAST RUN","DURATION_S","TURNS","FLAG","DETAIL"],
  (.[] | [
    .job,
    (.last_run.started // "never"),
    ((.last_run.duration_s // "-") | tostring),
    ((.last_run.num_turns // "-") | tostring),
    .flag,
    .detail
  ])
  | @tsv' | column -t -s $'\t')"

if [ "$JSON_OUT" -eq 1 ]; then
  echo "$RESULTS_JSON"
else
  if [ "$(echo "$RESULTS_JSON" | jq 'length')" -eq 0 ]; then
    echo "No scheduled-jobs jobs registered under $JOBS_ROOT"
  else
    echo "$TABLE"
  fi
fi

# ---------------------------------------------------------------------------
# Dated report files (§5.9): health-YYYY-MM-DD.md + .json under
# ~/.claude/dev-cycle/jobs/health/. Same-day re-runs overwrite that day's pair
# (date-idempotent, same convention as job reports/ in §5.6).
# ---------------------------------------------------------------------------
echo "$RESULTS_JSON" > "$HEALTH_DIR/health-$TODAY.json"
{
  echo "# scheduled-jobs health — $TODAY"
  echo
  echo "Scanned: $(echo "$RESULTS_JSON" | jq 'length') job(s), $FLAGGED_COUNT flagged."
  echo
  if [ "$(echo "$RESULTS_JSON" | jq 'length')" -eq 0 ]; then
    echo "No scheduled-jobs jobs registered under \`$JOBS_ROOT\`."
  else
    echo '```'
    echo "$TABLE"
    echo '```'
  fi
} > "$HEALTH_DIR/health-$TODAY.md"

# ---------------------------------------------------------------------------
# --notify: fire notify.sh for every flagged job, using THAT job's own
# manifest (so channel/subscription decisions stay per-job, per the §5.4
# contract). notify.sh is a separate deliverable not yet shipped in this
# wave — its absence is a documented graceful no-op, never an error.
# ---------------------------------------------------------------------------
if [ "$NOTIFY" -eq 1 ] && [ "$FLAGGED_COUNT" -gt 0 ]; then
  NOTIFY_SH="$BIN_DIR/notify.sh"
  if [ -x "$NOTIFY_SH" ]; then
    while IFS=$'\t' read -r job job_dir flag detail; do
      manifest="$job_dir/job.json"
      "$NOTIFY_SH" "$manifest" health_flag "scheduled-jobs/health: $job [$flag] $detail" || true
    done < <(echo "$RESULTS_JSON" | jq -r '.[] | select(.flag != "OK") | [.job, .job_dir, .flag, .detail] | @tsv')
  fi
  # else: no notify infrastructure installed yet — no-op by design (see
  # header comment); the health scan itself still ran and reported.
fi

exit "$FLAGGED_COUNT"
