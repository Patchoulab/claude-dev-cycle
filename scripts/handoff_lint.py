#!/usr/bin/env python3
"""handoff_lint.py — validate a session-handoff file (dev-cycle plugin).

Usage: handoff_lint.py <seed-file> [--best-effort]

Exit codes: 0 = OK, 1 = schema errors (strict mode only), 2 = safety violations
(any mode; safety outranks schema). --best-effort downgrades schema errors to
warnings for legacy/hand-written seeds.
"""
import argparse
import re
import sys
from pathlib import Path

REQUIRED_SECTIONS = [
    "State",
    "Approved decisions",
    "Carry-forward learnings",
    "Next action",
    "Verification criteria",
    "Safety constraints",
]

# Destructive git guidance is never allowed in a seed, even inside code fences.
FORBIDDEN = [
    (re.compile(r"\breset\s+--hard\b"), "git reset --hard"),
    (re.compile(r"\bpush\b[^\n]*\s(--force|-f)\b"), "force push"),
    (re.compile(r"\bclean\s+(?:-[A-Za-z-]+\s+)*-[A-Za-z-]*f"), "git clean -f"),
    (re.compile(r"\bcheckout\s+--\s+\."), "git checkout -- ."),
    (re.compile(r"\bbranch\s+-D\b"), "git branch -D"),
]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("seed", type=Path)
    ap.add_argument("--best-effort", action="store_true",
                    help="downgrade schema errors to warnings (legacy seeds)")
    args = ap.parse_args()

    if not args.seed.is_file():
        print(f"ERROR seed file not found: {args.seed}")
        return 1
    text = args.seed.read_text(encoding="utf-8", errors="replace")
    lines = text.splitlines()

    schema: list[str] = []
    safety: list[str] = []

    first = next((ln for ln in lines if ln.strip()), "")
    if not re.match(r"#\s+Next Session Seed\s*[—–-]", first):
        schema.append("missing title line '# Next Session Seed — <name>'")
    if not re.search(r"^Generated:\s+.+\bby\s+(?:session-handoff|project-planning:shard)\s+v",
                     text, re.M):
        schema.append("missing 'Generated: <date> by <generator> vX.Y' line "
                      "(generator: session-handoff or project-planning:shard)")

    sections: dict[str, list[str]] = {}
    current = None
    for ln in lines:
        m = re.match(r"##\s+(.+?)\s*$", ln)
        if m:
            current = m.group(1)
            sections[current] = []
        elif current is not None:
            sections[current].append(ln)

    for name in REQUIRED_SECTIONS:
        if name not in sections:
            schema.append(f"missing section '## {name}'")
        elif not any(ln.strip() for ln in sections[name]):
            schema.append(f"section '## {name}' is empty")

    if "{{" in text:
        schema.append("unfilled template placeholder '{{...}}' present")

    for n, ln in enumerate(lines, 1):
        if "NEVER" in ln:
            continue  # prohibition lines may name forbidden operations
        for rx, label in FORBIDDEN:
            if rx.search(ln):
                safety.append(f"line {n}: destructive git guidance ({label})")

    for msg in safety:
        print(f"SAFETY {msg}")
    level = "WARN" if args.best_effort else "ERROR"
    for msg in schema:
        print(f"{level} {msg}")

    if safety:
        return 2
    if schema and not args.best_effort:
        return 1
    print(f"OK {args.seed}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
