#!/bin/bash
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
LINT="$DIR/../../handoff_lint.py"
fail=0
check() { # file expected_exit extra_args
  python3 "$LINT" "$DIR/fixtures/$1" ${3:-} >/dev/null 2>&1
  actual=$?
  [ "$actual" -eq "$2" ] || { echo "FAIL: $1 ${3:-}: expected exit $2 got $actual"; fail=1; }
}
check valid.md 0
check valid-project-planning-bundle.md 0
check missing-next-action.md 1
check empty-section.md 1
check no-generated-line.md 1
check leftover-placeholder.md 1
check unsafe-reset-hard.md 2
check unsafe-force-push.md 2
check force-push-in-fence.md 2
# best-effort mode: schema violations downgrade to warnings (exit 0), safety still exit 2
check missing-next-action.md 0 --best-effort
check empty-section.md 0 --best-effort
check no-generated-line.md 0 --best-effort
check leftover-placeholder.md 0 --best-effort
check unsafe-reset-hard.md 2 --best-effort
check unsafe-force-push.md 2 --best-effort
# legacy-kickoff.md: real hand-written shape (prose + imperative, no schema
# at all) -- spec 01 sec 8's "legacy-kickoff.md" acceptance case.
check legacy-kickoff.md 0 --best-effort
LEGACY_OUT="$(python3 "$LINT" "$DIR/fixtures/legacy-kickoff.md" --best-effort 2>&1)"
for section in State "Approved decisions" "Carry-forward learnings" "Next action" "Verification criteria" "Safety constraints"; do
  echo "$LEGACY_OUT" | grep -q "missing section '## $section'" \
    || { echo "FAIL: legacy-kickoff.md: WARN missing '## $section' not reported"; fail=1; }
done
[ $fail -eq 0 ] && echo "OK: handoff_lint (16 checks)"
exit $fail
