#!/bin/bash
# Records its argv and stdin, then echoes a canned Claude `--output-format json`
# response. Used as $DEV_CYCLE_CLAUDE_BIN.
#
# Two response shapes, selected by the prompt on stdin:
#   - review pass  -> STUB_FINDINGS  (findings JSON) or '{"findings": []}'
#   - verify pass  -> STUB_VERDICTS  (verdicts JSON, incl. num_turns) or a
#                     zero-tool-call default that the evidence check rejects.
# The verify pass is recognized by the verify-prompt.md sentinel line.
set -u
REC="${STUB_RECORD:-/tmp/stub-claude-record}"
# The gate passes the prompt via `-p <prompt>` (argv), with stdin at /dev/null;
# branch on argv, not stdin.
ARGS="$*"
{ echo "ARGS: $ARGS"; echo "STDIN:"; cat; } >> "$REC"

case "$ARGS" in
  *"You previously flagged these candidate vulnerabilities"*)
    if [ -n "${STUB_VERDICTS:-}" ]; then
      printf '%s\n' "$STUB_VERDICTS"
    else
      # Default: a zero-tool-call verdict (num_turns 1) -> rejected wholesale.
      echo '{"num_turns": 1, "verdicts": []}'
    fi
    ;;
  *)
    if [ -n "${STUB_FINDINGS:-}" ]; then
      printf '%s\n' "$STUB_FINDINGS"
    else
      echo '{"findings": []}'
    fi
    ;;
esac
