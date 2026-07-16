#!/bin/bash
# Fixture suite for scripts/i18n_parity.mjs (spec 09 §5.5, T5/T12).
# CLI contract: node i18n_parity.mjs <i18n-dir> — a single directory holding
# one file per locale (en.ts, fr.ts, ...); exit 0 = parity, exit 1 = drift or
# hygiene violation, with one "PARITY FAIL: ..." line per violation on stderr
# (or a distinct usage/count message for the <2-locale-files case).
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
GATE="$DIR/../../i18n_parity.mjs"
fail=0
[ -f "$GATE" ] || { echo "FAIL: i18n_parity.mjs missing"; exit 1; }
command -v node >/dev/null || { echo "FAIL: node not available"; exit 1; }

check() { # fixture-dir expected_exit label
  node "$GATE" "$DIR/fixtures/$1" >/dev/null 2>&1
  actual=$?
  [ "$actual" -eq "$2" ] || { echo "FAIL: $3 expected exit $2 got $actual"; fail=1; }
}

# Exit-code coverage across the six fixture classes named in spec 09 T12
# (clean / drift-missing / drift-extra / curly key / empty value / non-NFC)
# plus the single-file error case and a combined-violation fixture (T5).
check parity-clean 0 "parity-clean (typographic values, e.g. curly apostrophe, must stay legal)"
check missing-key 1 "missing key"
check extra-key 1 "extra key"
check curly-quote-key 1 "curly-quote key (typographic char in a KEY is the banned churn class)"
check empty-value 1 "empty value"
check non-nfc 1 "non-NFC (NFD-decomposed accent in a value)"
check single-file-error-case 1 "single-file-error-case (fewer than 2 locale files)"
check combined-violations 1 "combined-violations (curly key + missing key + untranslated value)"

# --- output-text assertions: every violation class must be nameable, not just exit-code ---
assert_output() { # fixture-dir needle label
  out="$(node "$GATE" "$DIR/fixtures/$1" 2>&1)"
  echo "$out" | grep -qF "$2" \
    || { echo "FAIL: $3 — output lacks '$2'. Got:"; echo "$out"; fail=1; }
}

# --- crash-free assertions: uncaught exceptions must not hide behind exit code 1 ---
assert_clean_fail() { # fixture-dir label
  out="$(node "$GATE" "$DIR/fixtures/$1" 2>&1)"
  if echo "$out" | grep -qE "ReferenceError|^    at "; then
    echo "FAIL: $2 — output contains uncaught exception (crash, not clean exit). Got:"; echo "$out"; fail=1;
  fi
}

assert_output missing-key "missing key" "violation output lacks detail for missing-key"
assert_clean_fail missing-key "missing-key"
assert_output extra-key "extra key" "violation output lacks detail for extra-key"
assert_clean_fail extra-key "extra-key"
assert_output curly-quote-key "non-semantic key" "violation output lacks detail for curly-quote-key"
assert_clean_fail curly-quote-key "curly-quote-key"
assert_output empty-value "empty value" "violation output lacks detail for empty-value"
assert_clean_fail empty-value "empty-value"
assert_output non-nfc "not NFC-normalized" "violation output lacks detail for non-nfc"
assert_clean_fail non-nfc "non-nfc"
assert_output single-file-error-case "need >=2 locale files" "violation output lacks detail for single-file-error-case"
assert_clean_fail single-file-error-case "single-file-error-case"

# combined-violations must name all three planted violations in one run
# (spec 09 T5: "curly key + missing fr key + untranslated value ... naming all three").
combined_out="$(node "$GATE" "$DIR/fixtures/combined-violations" 2>&1)"
for needle in "non-semantic key" "missing key" "identical to en"; do
  echo "$combined_out" | grep -qF "$needle" \
    || { echo "FAIL: combined-violations output missing '$needle'. Got:"; echo "$combined_out"; fail=1; }
done
if echo "$combined_out" | grep -qE "ReferenceError|^    at "; then
  echo "FAIL: combined-violations — output contains uncaught exception (crash, not clean exit). Got:"; echo "$combined_out"; fail=1;
fi

[ $fail -eq 0 ] && echo "OK: i18n parity gate (8 exit-code checks + 6 single-violation output checks + 6 crash-free checks + 3 combined-violation output checks + 1 combined crash-free check)"
exit $fail
