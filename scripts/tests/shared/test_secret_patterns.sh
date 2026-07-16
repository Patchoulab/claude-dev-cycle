#!/bin/bash
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
PATTERNS="$DIR/../../secret_patterns.grep"
fail=0
[ -f "$PATTERNS" ] || { echo "FAIL: patterns file missing"; exit 1; }
# every positive line must match
while IFS= read -r line; do
  echo "$line" | grep -qEf "$PATTERNS" || { echo "FAIL: missed positive: $line"; fail=1; }
done < "$DIR/fixtures/secrets-positive.txt"
# no negative line may match
while IFS= read -r line; do
  echo "$line" | grep -qEf "$PATTERNS" && { echo "FAIL: false positive: $line"; fail=1; }
done < "$DIR/fixtures/secrets-negative.txt"
[ $fail -eq 0 ] && echo "OK: secret patterns"
exit $fail
