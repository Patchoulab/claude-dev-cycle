#!/bin/bash
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"

# Test sandboxes build submodules over file:// remotes. Modern git blocks the
# file protocol by default, and neither a one-shot `-c protocol.file.allow` nor
# GIT_CONFIG_* env vars reliably reach the submodule subprocess a recursive
# clone spawns on every git build (observed failing on GitHub CI runners). Point
# git at a controlled global/system config on disk instead: every git process,
# including submodule children, reads it. GIT_CONFIG_SYSTEM=/dev/null also drops
# any runner-injected system config. Test-only: real repos use ssh/https remotes.
DC_TEST_GITCONFIG="$(mktemp)"
git config -f "$DC_TEST_GITCONFIG" protocol.file.allow always
git config -f "$DC_TEST_GITCONFIG" safe.directory '*'
git config -f "$DC_TEST_GITCONFIG" user.name "dev-cycle-test"
git config -f "$DC_TEST_GITCONFIG" user.email "test@example.com"
git config -f "$DC_TEST_GITCONFIG" init.defaultBranch main
export GIT_CONFIG_GLOBAL="$DC_TEST_GITCONFIG"
export GIT_CONFIG_SYSTEM=/dev/null
trap 'rm -f "$DC_TEST_GITCONFIG"' EXIT

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
