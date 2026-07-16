#!/usr/bin/env python3
"""Derive a git branch slug from a session-handoff seed file or a raw string.

Usage:
  session_slug.py <seedfile>
  session_slug.py --string "<text>"

Prints "<type>/<slug>" (e.g. feat/cron-health) to stdout, exit 0.
Exit 1 if the seed file is missing or has no derivable label; exit 2 on usage.
"""
import re
import sys
import unicodedata

MAX_LEN = 64  # EnterWorktree `name` limit, total including "<type>/"

FIX_RE = re.compile(r"\b(fix|bug|bugfix|hotfix)\b", re.I)
CHORE_RE = re.compile(r"\b(chore|docs?|refactor|cleanup)\b", re.I)
HEADER_RE = re.compile(r"#\s*Next Session Seed\s*[—–-]\s*(.+?)\s*$")


def classify(label):
    if FIX_RE.search(label):
        return "fix"
    if CHORE_RE.search(label):
        return "chore"
    return "feat"


def slugify(text, budget):
    text = unicodedata.normalize("NFKD", text)
    text = text.encode("ascii", "ignore").decode("ascii").lower()
    text = re.sub(r"[^a-z0-9]+", "-", text).strip("-")
    if len(text) > budget:
        text = text[:budget].rstrip("-")
    return text


def label_from_seed(path):
    try:
        with open(path, encoding="utf-8") as fh:
            for line in fh:
                m = HEADER_RE.match(line)
                if m:
                    return m.group(1)
    except OSError:
        return None
    return None


def derive(label):
    kind = classify(label)
    slug = slugify(label, MAX_LEN - len(kind) - 1)
    if not slug:
        return None
    return kind + "/" + slug


def main(argv):
    if len(argv) == 3 and argv[1] == "--string":
        label = argv[2]
    elif len(argv) == 2 and not argv[1].startswith("-"):
        label = label_from_seed(argv[1])
        if label is None:
            print("no seed label found in " + argv[1], file=sys.stderr)
            return 1
    else:
        print(__doc__, file=sys.stderr)
        return 2
    result = derive(label)
    if result is None:
        print("empty slug after sanitization", file=sys.stderr)
        return 1
    print(result)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
