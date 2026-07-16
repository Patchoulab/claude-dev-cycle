"""Unit tests for hooks/review-gate/verify_evidence.py (Task 10b fixes).

Invokes verify_evidence.py the same way gate.sh does: as a subprocess with
argv <verify_raw.json> <candidates.json> <repo_root> <retired_paths_json>,
reading its single JSON object off stdout. See the module docstring in
verify_evidence.py and spec docs/specs/04-review-gate.md sec 5.9 for the
I/O contract.
"""
import json
import pathlib
import subprocess

import pytest

DIR = pathlib.Path(__file__).parent
VERIFY = DIR / "../../../hooks/review-gate/verify_evidence.py"


@pytest.fixture
def repo(tmp_path):
    """A tiny fixture repo: a known source file (vulnerable line at line 2,
    padded to 8 lines so line-offset tests have room to miss), a sibling real
    file, and the two gate-artifact directories (.git/, .superpowers/) that
    evidence.file must never be allowed to point into."""
    root = tmp_path
    (root / "src").mkdir()
    (root / "src" / "app.py").write_text(
        'def check(pw):\n'
        '    return pw == "letmein"\n'
        '    # padding line 3\n'
        '    # padding line 4\n'
        '    # padding line 5\n'
        '    # padding line 6\n'
        '    # padding line 7\n'
        '    # padding line 8\n'
    )
    (root / "other.py").write_text(
        'def other():\n'
        '    return "a totally different function body here"\n'
    )
    (root / ".git").mkdir()
    (root / ".git" / "HEAD").write_text("ref: refs/heads/main\n")
    (root / ".superpowers").mkdir()
    (root / ".superpowers" / "security-findings.md").write_text(
        "# Security findings\n\nsome prior confirmed finding text\n"
    )
    return root


def run_verify(root, candidates, raw, retired=None):
    cand_file = root / "candidates.json"
    raw_file = root / "verify_raw.json"
    cand_file.write_text(json.dumps(candidates))
    raw_file.write_text(json.dumps(raw))
    retired_json = json.dumps(retired or [])
    result = subprocess.run(
        ["python3", str(VERIFY), str(raw_file), str(cand_file), str(root), retired_json],
        capture_output=True, text=True,
    )
    assert result.returncode == 0, result.stderr
    return json.loads(result.stdout)


def confirm_verdict(evidence, filePath="src/app.py", category="auth"):
    return {"filePath": filePath, "category": category, "verdict": "confirm", "evidence": evidence}


# (a) valid quote at correct lines -> accepted
def test_valid_quote_accepted(repo):
    candidates = [{"filePath": "src/app.py", "category": "auth"}]
    verdicts = [confirm_verdict({
        "file": str(repo / "src" / "app.py"), "startLine": 2, "endLine": 2,
        "quote": 'return pw == "letmein"',
    })]
    out = run_verify(repo, candidates, {"num_turns": 3, "verdicts": verdicts})
    assert out["ok"] is True, out["reasons"]
    assert out["confirmedCount"] == 1
    assert out["dismissedCount"] == 0


# (b) fabricated quote (text not in file) -> rejected
def test_fabricated_quote_rejected(repo):
    candidates = [{"filePath": "src/app.py", "category": "auth"}]
    verdicts = [confirm_verdict({
        "file": str(repo / "src" / "app.py"), "startLine": 2, "endLine": 2,
        "quote": "this text does not appear anywhere in the file",
    })]
    out = run_verify(repo, candidates, {"num_turns": 3, "verdicts": verdicts})
    assert out["ok"] is False
    assert out["confirmedCount"] == 0
    assert any("not found" in r for r in out["reasons"]), out["reasons"]


# (c) correct quote but startLine off by >2 -> rejected (window never reaches it)
def test_line_offset_too_far_rejected(repo):
    candidates = [{"filePath": "src/app.py", "category": "auth"}]
    verdicts = [confirm_verdict({
        "file": str(repo / "src" / "app.py"), "startLine": 6, "endLine": 6,
        "quote": 'return pw == "letmein"',
    })]
    out = run_verify(repo, candidates, {"num_turns": 3, "verdicts": verdicts})
    assert out["ok"] is False
    assert not any("evidence-file-mismatch" in r for r in out["reasons"]), out["reasons"]
    assert not any("quote-too-short" in r for r in out["reasons"]), out["reasons"]


# (d) evidence.file = a gate artifact path -> rejected evidence-file-mismatch
def test_evidence_file_gate_artifact_rejected(repo):
    candidates = [{"filePath": "src/app.py", "category": "auth"}]
    verdicts = [confirm_verdict({
        "file": str(repo / ".superpowers" / "security-findings.md"),
        "startLine": 1, "endLine": 1,
        "quote": "some prior confirmed finding text",
    })]
    out = run_verify(repo, candidates, {"num_turns": 3, "verdicts": verdicts})
    assert out["ok"] is False
    assert any("evidence-file-mismatch" in r for r in out["reasons"]), out["reasons"]


# (e) evidence.file = different real file in repo -> rejected evidence-file-mismatch
def test_evidence_file_wrong_real_file_rejected(repo):
    candidates = [{"filePath": "src/app.py", "category": "auth"}]
    verdicts = [confirm_verdict({
        "file": str(repo / "other.py"), "startLine": 2, "endLine": 2,
        "quote": "a totally different function body here",
    })]
    out = run_verify(repo, candidates, {"num_turns": 3, "verdicts": verdicts})
    assert out["ok"] is False
    assert any("evidence-file-mismatch" in r for r in out["reasons"]), out["reasons"]


# (f) 1-token quote that exists in file -> rejected quote-too-short
def test_quote_too_short_rejected(repo):
    candidates = [{"filePath": "src/app.py", "category": "auth"}]
    verdicts = [confirm_verdict({
        "file": str(repo / "src" / "app.py"), "startLine": 2, "endLine": 2,
        "quote": "return",
    })]
    out = run_verify(repo, candidates, {"num_turns": 3, "verdicts": verdicts})
    assert out["ok"] is False
    assert any("quote-too-short" in r for r in out["reasons"]), out["reasons"]


# (g) num_turns=1 -> rejected wholesale
def test_num_turns_one_rejected(repo):
    candidates = [{"filePath": "src/app.py", "category": "auth"}]
    verdicts = [confirm_verdict({
        "file": str(repo / "src" / "app.py"), "startLine": 2, "endLine": 2,
        "quote": 'return pw == "letmein"',
    })]
    out = run_verify(repo, candidates, {"num_turns": 1, "verdicts": verdicts})
    assert out["ok"] is False
    assert out["confirmedCount"] == 0
    assert any("num_turns" in r for r in out["reasons"]), out["reasons"]


# (h) dismissal verdict held to the same checks -> invalid dismissal evidence rejected
def test_dismissal_verdict_same_checks(repo):
    candidates = [{"filePath": "src/app.py", "category": "auth"}]
    verdicts = [{
        "filePath": "src/app.py", "category": "auth", "verdict": "dismiss",
        "evidence": {
            "file": str(repo / "src" / "app.py"), "startLine": 2, "endLine": 2,
            "quote": "this text does not appear anywhere in the file",
        },
    }]
    out = run_verify(repo, candidates, {"num_turns": 3, "verdicts": verdicts})
    assert out["ok"] is False
    assert out["dismissedCount"] == 0
    assert any("not found" in r for r in out["reasons"]), out["reasons"]
