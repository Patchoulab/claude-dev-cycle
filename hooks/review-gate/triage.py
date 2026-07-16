#!/usr/bin/env python3
"""triage.py -- pre-spawn diff triage for the review-gate gate.

Contract (see docs/skills/review-gate.md):
  stdin  = a unified diff (git diff / git show output)
  stdout = exactly one line: "SKIP <class>" or "REVIEW <reason>"
  exit 0 always (a triage failure must never block the caller; unparseable
  input fails closed to REVIEW rather than raising)

Pure function of the diff (plus the shared secret-pattern file resolved
relative to this script's own location) -- no side effects, no network,
no repo state beyond that one file.

Classification is two-stage, per file, first match wins:
  1. path-pattern classes (C1-C8 in the spec table)
  2. hunk-content heuristics (comment-only, deletion-only, surface-scan,
     secret-literals)
then aggregated fail-closed across all files in the diff.
"""

import re
import sys
from pathlib import Path

# ---------------------------------------------------------------------------
# Path-pattern classification (spec 5.6, table C1-C8)
# ---------------------------------------------------------------------------

LOCKFILE_BASENAMES = {
    "package-lock.json", "yarn.lock", "pnpm-lock.yaml", "bun.lockb",
    "bun.lock", "Cargo.lock", "poetry.lock", "uv.lock", "Gemfile.lock",
    "composer.lock", "go.sum",
}

MANIFEST_BASENAMES = {
    "package.json", "pyproject.toml", "Cargo.toml", "go.mod", "Gemfile",
    "composer.json",
}
MANIFEST_GLOBS = ["requirements*.txt"]

SENSITIVE_GLOBS = [
    ".github/workflows/**", "**/Dockerfile*", "**/docker-compose*.y*ml",
    "**/*.tf", "**/traefik/**", "**/nginx/**", ".claude/settings*.json",
    "**/hooks/**", "**/*.pem", "**/*.key", ".env*",
]

DOCS_GLOBS = ["*.md", "*.rst", "*.txt", "docs/**", "LICENSE*", "*.svg",
              "*.png", "*.jpg", "*.webp"]

TEST_GLOBS = ["tests/**", "__tests__/**", "test_*.py", "*_test.py",
              "*_test.go", "*.test.*", "*.spec.*", "conftest.py",
              "**/fixtures/**"]

EDITOR_CONFIG_GLOBS = [".vscode/**", ".idea/**", ".editorconfig",
                        ".gitignore", ".gitattributes", ".prettierrc*",
                        ".eslintrc*", "*.code-workspace"]


def _glob_to_regex(pattern):
    """Translate a subset of gitignore-style globs to a compiled regex.

    '**/' collapses to an optional any-depth prefix; a bare trailing '**'
    (e.g. 'docs/**') matches everything under the prefix; '*' matches
    within one path segment; everything else is taken literally.
    """
    i, n = 0, len(pattern)
    out = []
    while i < n:
        c = pattern[i]
        if c == "*":
            if pattern[i:i + 3] == "**/":
                out.append("(?:.*/)?")
                i += 3
                continue
            if pattern[i:i + 2] == "**":
                out.append(".*")
                i += 2
                continue
            out.append("[^/]*")
            i += 1
            continue
        if c == "?":
            out.append("[^/]")
            i += 1
            continue
        out.append(re.escape(c))
        i += 1
    return re.compile("^" + "".join(out) + "$")


def _glob_match(path, pattern):
    """Gitignore semantics: a pattern with no '/' matches the basename at
    any depth; a pattern containing '/' is anchored to the full path."""
    target = path if "/" in pattern else path.rsplit("/", 1)[-1]
    return _glob_to_regex(pattern).match(target) is not None


def _matches_any(path, patterns):
    return any(_glob_match(path, p) for p in patterns)


def classify_path(path):
    basename = path.rsplit("/", 1)[-1]
    if basename in LOCKFILE_BASENAMES:
        return "lockfile"
    if basename in MANIFEST_BASENAMES or _matches_any(path, MANIFEST_GLOBS):
        return "manifest"
    if _matches_any(path, SENSITIVE_GLOBS):
        return "sensitive-config"
    if _matches_any(path, DOCS_GLOBS):
        return "docs"
    if _matches_any(path, TEST_GLOBS):
        return "test"
    if _matches_any(path, EDITOR_CONFIG_GLOBS):
        return "editor-config"
    return "code"  # C8: fail-closed default


# ---------------------------------------------------------------------------
# Hunk-content heuristics (spec 5.6)
# ---------------------------------------------------------------------------

# language inferred from extension -> valid single-line comment-start tokens
COMMENT_TOKENS = {
    ".py": ("#", '"""', "'''"),
    ".sh": ("#",), ".bash": ("#",), ".rb": ("#",), ".yaml": ("#",),
    ".yml": ("#",), ".toml": ("#",), ".cfg": ("#",), ".ini": ("#",),
    ".js": ("//", "/*", "*", "*/"), ".jsx": ("//", "/*", "*", "*/"),
    ".ts": ("//", "/*", "*", "*/"), ".tsx": ("//", "/*", "*", "*/"),
    ".go": ("//", "/*", "*", "*/"), ".java": ("//", "/*", "*", "*/"),
    ".c": ("//", "/*", "*", "*/"), ".cpp": ("//", "/*", "*", "*/"),
    ".h": ("//", "/*", "*", "*/"), ".hpp": ("//", "/*", "*", "*/"),
    ".rs": ("//", "/*", "*", "*/"), ".swift": ("//", "/*", "*", "*/"),
    ".kt": ("//", "/*", "*", "*/"), ".cs": ("//", "/*", "*", "*/"),
    ".css": ("/*", "*", "*/"), ".scss": ("/*", "*", "*/"),
    ".sql": ("--",), ".html": ("<!--",), ".xml": ("<!--",),
}


def comment_only(path, added, removed):
    ext = Path(path).suffix.lower()
    tokens = COMMENT_TOKENS.get(ext)
    if not tokens:
        return False  # unknown extension -> fail closed, not comment-only
    for line in added + removed:
        stripped = line.strip()
        if not stripped:
            continue
        if not stripped.startswith(tokens):
            return False
    return True


# surface-scan families, checked in this priority order for the reported reason
SURFACE_FAMILIES = [
    ("exec", re.compile(
        r"\b(eval|exec|execSync|spawn|system|popen|subprocess|"
        r"child_process|shell=True)\b", re.IGNORECASE)),
    ("network", re.compile(
        r"fetch\(|axios|requests\.|urllib|https?://|socket|listen\(|bind\(",
        re.IGNORECASE)),
    ("auth", re.compile(
        r"secret|token|passw|credential|api[-_]?key|jwt|cookie|session|"
        r"oauth|private[-_]?key|auth", re.IGNORECASE)),
    ("input", re.compile(
        r"req\.(body|params|query)|argv|stdin|input\(|deserial|pickle|"
        r"yaml\.load|fromstring", re.IGNORECASE)),
    ("sinks", re.compile(
        r"innerHTML|dangerouslySetInnerHTML|document\.write|cursor\.execute|"
        r"\bexecute\(|f[\"']\s*SELECT", re.IGNORECASE)),
    ("fs-priv", re.compile(
        r"chmod|chown|sudo|setuid|symlink|\.\./", re.IGNORECASE)),
    ("weak-crypto", re.compile(
        r"\bmd5\b|\bsha1\b|Math\.random|\bDES\b|\bECB\b", re.IGNORECASE)),
]


def surface_scan(lines):
    """Return the ordered list of family names with at least one hit across
    ALL changed lines (added and removed -- deleting an auth check is a
    security event too)."""
    hits = []
    for name, pattern in SURFACE_FAMILIES:
        if any(pattern.search(line) for line in lines):
            hits.append(name)
    return hits


def load_secret_patterns():
    """Resolve scripts/secret_patterns.grep relative to this script's own
    location (hooks/review-gate/../../scripts/secret_patterns.grep),
    never via cwd. Supports DEV_CYCLE_SECRET_PATTERNS env override (for tests).
    Returns None if the patterns file is missing/unreadable (fail-closed)."""
    import os
    patterns_file = os.environ.get("DEV_CYCLE_SECRET_PATTERNS")
    if patterns_file:
        patterns_path = Path(patterns_file)
    else:
        patterns_path = Path(__file__).resolve().parent / ".." / ".." / "scripts" / "secret_patterns.grep"
    try:
        text = patterns_path.resolve().read_text()
    except OSError:
        return None  # None signals missing/unreadable -> fail closed
    compiled = []
    for line in text.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            compiled.append(re.compile(line))
        except re.error:
            continue
    return compiled


SECRET_PATTERNS = load_secret_patterns()


def secret_hit(added_lines):
    """Secret-literal patterns are applied to ADDED lines only (spec 5.6).
    Returns False if SECRET_PATTERNS could not be loaded (None) to avoid
    masking the unavailable-patterns verdict."""
    if SECRET_PATTERNS is None:
        return False
    return any(p.search(line) for line in added_lines for p in SECRET_PATTERNS)


# ---------------------------------------------------------------------------
# Diff parsing
# ---------------------------------------------------------------------------

class FileDiff:
    def __init__(self, path):
        self.path = path
        self.added = []
        self.removed = []
        self.is_gitlink = False
        self.is_binary = False
        self.is_new_file = False
        self.is_deleted_file = False


_DIFF_HEADER_RE = re.compile(r"^diff --git a/(.+) b/(.+)$")


def parse_diff(text):
    files = []
    current = None
    for raw_line in text.splitlines():
        m = _DIFF_HEADER_RE.match(raw_line)
        if m:
            path = m.group(2) if m.group(2) != "/dev/null" else m.group(1)
            current = FileDiff(path)
            files.append(current)
            continue
        if current is None:
            continue
        # Extended-header markers (git emits these before any hunk). A binary
        # patch carries NO '+'/'-' hunk lines, so record its nature here; the
        # aggregate verdict must fail closed rather than mistake an empty
        # `added` list for a deletion-only change.
        if raw_line.startswith("new file mode"):
            current.is_new_file = True
            continue
        if raw_line.startswith("deleted file mode"):
            current.is_deleted_file = True
            continue
        if raw_line.startswith("Binary files ") or raw_line == "GIT binary patch":
            current.is_binary = True
            continue
        if raw_line.startswith("+++") or raw_line.startswith("---"):
            continue  # file-level headers, not hunk content
        if raw_line.startswith("+"):
            current.added.append(raw_line[1:])
        elif raw_line.startswith("-"):
            current.removed.append(raw_line[1:])
        # context lines (leading space) and hunk headers ("@@") ignored
    for f in files:
        for line in f.added + f.removed:
            if line.strip().startswith("Subproject commit"):
                f.is_gitlink = True
                break
    return files


# ---------------------------------------------------------------------------
# Aggregate verdict (spec 5.6, "Aggregate verdict" table)
# ---------------------------------------------------------------------------

SKIP_TRIVIAL_CLASSES = ("docs", "test", "editor-config", "lockfile")


def classify_diff(files):
    if SECRET_PATTERNS is None:
        return "REVIEW", "secret-patterns-unavailable"

    if not files:
        return "SKIP", "empty-diff"

    if any(f.is_gitlink for f in files):
        return "REVIEW", "submodule"

    for f in files:
        f.cls = classify_path(f.path)
        f.comment_only = f.cls == "code" and comment_only(f.path, f.added, f.removed)
        f.deletion_only = len(f.added) == 0
        f.surface_hits = surface_scan(f.added + f.removed)
        f.secret_hit = secret_hit(f.added)

    # Binary additions/modifications have no readable '+' lines, so every
    # content heuristic above is blind to them and deletion_only would wrongly
    # fire (len(added) == 0). A new or changed binary in a non-trivially-
    # skippable path must fail closed to REVIEW, never SKIP as "deletion-only"
    # (spec 5.6 fail-closed default). A binary *removal* stays a real deletion.
    if any(f.is_binary and not f.is_deleted_file
           and f.cls not in SKIP_TRIVIAL_CLASSES for f in files):
        return "REVIEW", "binary-addition"

    has_secret = any(f.secret_hit for f in files)
    has_sensitive = any(f.cls == "sensitive-config" for f in files)
    has_manifest = any(f.cls == "manifest" for f in files)
    surface_hits = [fam for f in files for fam in f.surface_hits]
    has_surface = bool(surface_hits)

    non_manifest = [f for f in files if f.cls != "manifest"]
    skip_possible = (not has_sensitive) and all(
        f.cls in SKIP_TRIVIAL_CLASSES
        or (f.cls == "code" and (f.comment_only or f.deletion_only))
        for f in non_manifest
    )

    if skip_possible and not has_secret and not has_surface:
        if has_manifest:
            return "REVIEW", "dependency"
        return "SKIP", _skip_reason(files)

    if has_secret and skip_possible:
        return "REVIEW", "secrets-in-skip-class"

    if has_secret:
        return "REVIEW", "secret-literals"

    if has_sensitive:
        return "REVIEW", "sensitive-config"

    if has_surface:
        return "REVIEW", "surface-scan:" + surface_hits[0]

    return "REVIEW", "code"  # fail-closed default (unclassifiable / other)


def _skip_reason(files):
    tags = []
    for f in files:
        if f.cls in SKIP_TRIVIAL_CLASSES:
            tag = f.cls
        elif f.comment_only:
            tag = "comment-only"
        elif f.deletion_only:
            tag = "deletion-only"
        else:
            tag = f.cls
        if tag not in tags:
            tags.append(tag)
    return "+".join(tags) if tags else "clean"


def main():
    diff_text = sys.stdin.read()
    files = parse_diff(diff_text)
    verdict, reason = classify_diff(files)
    print(f"{verdict} {reason}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
