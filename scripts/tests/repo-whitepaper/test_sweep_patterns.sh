#!/bin/bash
# Proves the sweep doc's non-credential regexes are valid ERE and its credential
# class delegates to the shared patterns file.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$DIR/../../.."
SWEEP="$ROOT/skills/repo-whitepaper/references/sensitive-content-sweep.md"
fail=0
[ -f "$SWEEP" ] || { echo "FAIL: sweep doc missing"; exit 1; }

grep -q "secret_patterns.grep" "$SWEEP" || { echo "FAIL: sweep does not reference the shared credential patterns"; fail=1; }

# Every inline-code regex in the Pattern classes section must compile as ERE.
# Extraction mechanics: adjust to the doc's actual formatting after reading §5.3;
# the pinned behavior is zero invalid ERE among the doc's own patterns.
#
# The extractor is written to a standalone temp file rather than fed via a
# heredoc nested inside process substitution: macOS ships bash 3.2 as
# /bin/bash, whose parser mishandles `<( cmd <<'EOF' ... EOF )` (a "bad
# substitution" parse error) whenever the heredoc body contains an odd count
# of literal backtick characters -- exactly what a backtick-code-span
# extractor regex contains. That failure mode is silent: the while loop
# below would simply never receive any patterns, and the test would report
# a false OK. Isolating the heredoc from the process substitution sidesteps
# the bug entirely.
PYFILE="$(mktemp -t whitepaper-sweep-extract.XXXXXX)"
trap 'rm -f "$PYFILE"' EXIT
cat >"$PYFILE" <<'EOF'
import re, sys, pathlib
text = pathlib.Path(sys.argv[1]).read_text()
m = re.search(r"## Pattern classes(.*?)(?=\n## )", text, re.S)
if not m: sys.exit(0)
bt = chr(96)
code_re = re.compile(bt + r"([^" + bt + r"\n]+)" + bt)
for code in code_re.findall(m.group(1)):
    if any(ch in code for ch in "[](|\\") and " " not in code[:3]:
        print(code)
EOF

checked=0
while IFS= read -r pattern; do
  [ -z "$pattern" ] && continue
  checked=$((checked + 1))
  echo "" | grep -qE "$pattern" 2>/dev/null
  rc=$?
  if [ $rc -eq 2 ]; then
    echo "FAIL: invalid ERE in sweep doc: $pattern"; fail=1
  fi
done < <(python3 "$PYFILE" "$SWEEP")

[ $checked -gt 0 ] || { echo "FAIL: no patterns extracted from sweep doc"; fail=1; }

[ $fail -eq 0 ] && echo "OK: whitepaper sweep patterns (2 checks)"
exit $fail
