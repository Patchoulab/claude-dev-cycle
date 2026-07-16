import subprocess, pathlib, pytest, os

DIR = pathlib.Path(__file__).parent
TRIAGE = DIR / "../../../hooks/review-gate/triage.py"

CASES = [
    ("docs-only.diff", "SKIP"),
    ("test-only.diff", "SKIP"),
    ("lockfile-only.diff", "SKIP"),
    ("comment-only.diff", "SKIP"),
    ("comment-only-js.diff", "SKIP"),
    ("deletion-only.diff", "SKIP"),
    # A binary blob added under a code-class path has no '+' hunk lines; it must
    # NOT be mistaken for a deletion-only change and skipped (security-priority
    # fail-closed regression).
    ("binary-addition.diff", "REVIEW"),
    ("editor-config-only.diff", "SKIP"),
    ("code-auth.diff", "REVIEW"),
    ("submodule-bump.diff", "REVIEW"),
    ("test-with-secret.diff", "REVIEW"),
    ("manifest-lockfile-combined.diff", "REVIEW"),
    ("workflow-sensitive.diff", "REVIEW"),
    ("deletion-auth.diff", "REVIEW"),
    ("unknown-extension.diff", "REVIEW"),
    ("surface-exec.diff", "REVIEW"),
    ("surface-network.diff", "REVIEW"),
    ("surface-input.diff", "REVIEW"),
    ("surface-sinks.diff", "REVIEW"),
    ("surface-fs-priv.diff", "REVIEW"),
    ("surface-weak-crypto.diff", "REVIEW"),
]

@pytest.mark.parametrize("fixture,expected", CASES)
def test_triage_verdict(fixture, expected):
    diff = (DIR / "fixtures/diffs" / fixture).read_text()
    r = subprocess.run(["python3", str(TRIAGE)], input=diff,
                       capture_output=True, text=True)
    assert r.returncode == 0, r.stderr
    assert r.stdout.strip().startswith(expected), f"{fixture}: {r.stdout}"


# Aggregate-verdict reasons (spec 04-review-gate.md sec 8): pin the exact
# reason string, not just SKIP/REVIEW, for the classes/heuristics that have a
# well-defined single reason so a regression in classify_diff's branch order
# is caught precisely.
REASON_CASES = [
    ("manifest-lockfile-combined.diff", "REVIEW", "dependency"),
    ("workflow-sensitive.diff", "REVIEW", "sensitive-config"),
    ("unknown-extension.diff", "REVIEW", "code"),
    ("surface-exec.diff", "REVIEW", "surface-scan:exec"),
    ("surface-network.diff", "REVIEW", "surface-scan:network"),
    ("surface-input.diff", "REVIEW", "surface-scan:input"),
    ("surface-sinks.diff", "REVIEW", "surface-scan:sinks"),
    ("surface-fs-priv.diff", "REVIEW", "surface-scan:fs-priv"),
    ("surface-weak-crypto.diff", "REVIEW", "surface-scan:weak-crypto"),
    ("deletion-auth.diff", "REVIEW", "surface-scan:auth"),
    ("binary-addition.diff", "REVIEW", "binary-addition"),
    ("editor-config-only.diff", "SKIP", "editor-config"),
    ("comment-only-js.diff", "SKIP", "comment-only"),
]

@pytest.mark.parametrize("fixture,verdict,reason", REASON_CASES)
def test_triage_reason(fixture, verdict, reason):
    diff = (DIR / "fixtures/diffs" / fixture).read_text()
    r = subprocess.run(["python3", str(TRIAGE)], input=diff,
                       capture_output=True, text=True)
    assert r.returncode == 0, r.stderr
    assert r.stdout.strip() == f"{verdict} {reason}", r.stdout

def test_secret_in_skip_class_forces_review():
    diff = (DIR / "fixtures/diffs/test-with-secret.diff").read_text()
    r = subprocess.run(["python3", str(TRIAGE)], input=diff,
                       capture_output=True, text=True)
    assert "secret" in r.stdout.lower()

def test_missing_patterns_file_fails_closed(monkeypatch):
    monkeypatch.setenv("DEV_CYCLE_SECRET_PATTERNS", "/nonexistent/patterns.grep")
    diff = (DIR / "fixtures/diffs/docs-only.diff").read_text()
    r = subprocess.run(["python3", str(TRIAGE)], input=diff,
                       capture_output=True, text=True,
                       env={**os.environ, "DEV_CYCLE_SECRET_PATTERNS": "/nonexistent/patterns.grep"})
    assert r.returncode == 0
    assert r.stdout.strip() == "REVIEW secret-patterns-unavailable"
