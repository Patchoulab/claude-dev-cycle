#!/bin/bash
# Proves the shipped bundle-schema template produces handoff_lint-clean bundles.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$DIR/../../.."
SCHEMA="$ROOT/skills/project-planning/references/bundle-schema.md"
fail=0
[ -f "$SCHEMA" ] || { echo "FAIL: bundle-schema.md missing"; exit 1; }

# Extract the template's fenced example bundle (first fenced block containing 'by project-planning:shard')
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
python3 - "$SCHEMA" "$T/bundle.md" <<'EOF'
import re, sys, pathlib
text = pathlib.Path(sys.argv[1]).read_text()
blocks = re.findall(r"```(?:markdown)?\n(.*?)```", text, re.S)
for b in blocks:
    if "by project-planning:shard" in b:
        pathlib.Path(sys.argv[2]).write_text(b)
        sys.exit(0)
sys.exit(3)
EOF
rc=$?
[ $rc -eq 0 ] || { echo "FAIL: no shard-generated bundle block found in schema doc (rc=$rc)"; exit 1; }

# Fill any {{placeholders}} with plausible values so lint sees a REAL bundle
python3 - "$T/bundle.md" <<'EOF'
import re, sys, pathlib
p = pathlib.Path(sys.argv[1])
t = p.read_text()
t = re.sub(r"\{\{[^}]+\}\}", "example-value", t)
t = t.replace("vX.Y", "v0.1")
p.write_text(t)
EOF

python3 "$ROOT/scripts/handoff_lint.py" "$T/bundle.md"
rc=$?
[ $rc -eq 0 ] || { echo "FAIL: bundle template does not pass strict handoff_lint (exit $rc)"; fail=1; }

# Config template ships placeholders, not user home/volume absolute paths
if grep -nE "/(Users|home|Volumes)/[A-Za-z]" "$ROOT/skills/project-planning/references/config-template.json"; then
  echo "FAIL: user literal in config-template.json"; fail=1
fi

rm -rf "$T"
[ $fail -eq 0 ] && echo "OK: project-planning bundle schema (2 checks)"
exit $fail
