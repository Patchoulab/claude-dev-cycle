#!/bin/bash
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
fail=0
run() { echo "== $1"; bash "$DIR/$1" || fail=1; }
run validate_plugin.sh
run shared/test_secret_patterns.sh
run session-handoff/test_handoff_lint.sh
run session-handoff/test_precompact_hook.sh
run finish-branch/test_mechanics.sh
run review-gate/test_gate.sh
run pr-monitor/test_poller.sh
run scheduled-jobs/test_wrapper.sh
run scheduled-jobs/test_health.sh
run project-planning/test_bundle_schema.sh
run repo-whitepaper/test_sweep_patterns.sh
run demo-prep/test_i18n_parity.sh
run demo-prep/test_presentation_templates.sh
run worktree-sessions/test_session_marker.sh
run worktree-sessions/test_worktree_check.sh
run worktree-sessions/test_close_mechanics.sh
echo "== review-gate + scheduled-jobs (pytest: test_triage.py + test_verify_evidence.py + test_render_lint.py)"
python3 -m pytest "$DIR/review-gate" "$DIR/scheduled-jobs/test_render_lint.py" "$DIR/worktree-sessions" -q || fail=1
[ $fail -eq 0 ] && echo "ALL GREEN"
exit $fail
