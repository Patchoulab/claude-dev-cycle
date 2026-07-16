"""Tests for scripts/jobs_render_lint.py against docs/specs/06-scheduled-jobs.md §5.8.

Reconciliation vs the task-7 brief's pytest skeleton: the brief sketched a
`--template/--job/--out` CLI operating on a single job.json. The actual §5.8
contract is:

    render_lint.py --template T --manifest M --state S --due D \
                    --run-date DATE --report R --summary Y --out OUT

so this file uses the real flags and fixtures (job-valid.json is the §5.2
manifest; state-valid.json / due-valid.json are its companions) rather than
the brief's single-file shape. The three pinned behaviors from the brief are
kept as named tests below (clean render, unfilled-placeholder refusal,
dangling-separator refusal) — only their setup was adapted to the real
contract. See task-7-report.md for the full reconciliation list.
"""
import datetime
import json
import pathlib
import subprocess

import pytest

DIR = pathlib.Path(__file__).parent
LINT = DIR / "../../jobs_render_lint.py"
TMPL = DIR / "../../../skills/scheduled-jobs/templates/prompt.tmpl.md"
FIXTURES = DIR / "fixtures"

TODAY = datetime.date.today().isoformat()
YESTERDAY = (datetime.date.today() - datetime.timedelta(days=1)).isoformat()


def run_lint(template, manifest, state, due, out, report=None, summary=None,
             run_date=None):
    report = report or (out.parent / "report.md")
    summary = summary or (out.parent / "summary.json")
    run_date = run_date or TODAY
    return subprocess.run(
        ["python3", str(LINT),
         "--template", str(template),
         "--manifest", str(manifest),
         "--state", str(state),
         "--due", str(due),
         "--run-date", str(run_date),
         "--report", str(report),
         "--summary", str(summary),
         "--out", str(out)],
        capture_output=True, text=True)


def setup_job(tmp_path, job_overrides=None, state_overrides=None,
              due_override=None, make_input_file=True):
    """Materialize a job.json/state.json/due.json triplet under tmp_path,
    derived from the fixtures, with a real input file so L3 existence checks
    pass by default."""
    job = json.loads((FIXTURES / "job-valid.json").read_text())
    if make_input_file:
        input_file = tmp_path / "input.txt"
        input_file.write_text("example input\n")
        job["inputs"] = [str(input_file)]
    if job_overrides:
        job.update(job_overrides)
    job_path = tmp_path / "job.json"
    job_path.write_text(json.dumps(job))

    state = json.loads((FIXTURES / "state-valid.json").read_text())
    if state_overrides:
        state.update(state_overrides)
    state_path = tmp_path / "state.json"
    state_path.write_text(json.dumps(state))

    due = (json.loads((FIXTURES / "due-valid.json").read_text())
           if due_override is None else due_override)
    due_path = tmp_path / "due.json"
    due_path.write_text(json.dumps(due))

    return job_path, state_path, due_path


def lint_findings(tmp_path, out_name="prompt.md"):
    return (tmp_path / f"{out_name}.lint").read_text()


# ---------------------------------------------------------------------------
# Pinned behaviors (from the task-7 brief) — the point of this task.
# ---------------------------------------------------------------------------

def test_valid_job_renders_clean(tmp_path):
    job, state, due = setup_job(tmp_path)
    out = tmp_path / "prompt.md"
    r = run_lint(TMPL, job, state, due, out)
    assert r.returncode == 0, r.stderr
    text = out.read_text()
    assert "{{" not in text            # L1
    assert not text.rstrip().endswith(",")


def test_unfilled_placeholder_fails(tmp_path):
    # A stray/typoed token in the template survives rendering (L1's actual
    # purpose per the spec's rule table: "template drift, typoed placeholder").
    job, state, due = setup_job(tmp_path)
    out = tmp_path / "prompt.md"
    mangled = tmp_path / "mangled.tmpl.md"
    mangled.write_text(TMPL.read_text() + "\nStray token: {{NOT_A_REAL_FIELD}}\n")
    r = run_lint(mangled, job, state, due, out)
    assert r.returncode == 2
    assert "L1" in lint_findings(tmp_path)
    assert not out.exists()


def test_dangling_separator_fails(tmp_path):
    # The historical 'vercel,bun,' bug class: an empty due-item name renders
    # a dangling/empty entry in a line-per-item list block.
    job, state, due = setup_job(tmp_path, due_override=[
        {"name": "widget-a", "state": {"status": "OUTDATED"}},
        {"name": "", "state": {"status": "OK"}},
    ])
    out = tmp_path / "prompt.md"
    r = run_lint(TMPL, job, state, due, out)
    assert r.returncode == 2
    assert "L2" in lint_findings(tmp_path)


# ---------------------------------------------------------------------------
# One test per §5.8 rule (L1-L6), each proven to fail on a crafted violation.
# ---------------------------------------------------------------------------

def test_L1_unrendered_placeholder_fails(tmp_path):
    job, state, due = setup_job(tmp_path)
    out = tmp_path / "prompt.md"
    mangled = tmp_path / "mangled.tmpl.md"
    mangled.write_text(TMPL.read_text().replace("{{ROLE_FRAMING}}", "{{TYPO_FIELD}}"))
    r = run_lint(mangled, job, state, due, out)
    assert r.returncode == 2
    assert "L1" in lint_findings(tmp_path)


@pytest.mark.parametrize("due_payload", [
    [{"name": "widget-a", "state": {}}, {"name": "", "state": {}}],   # empty entry
    [{"name": "widget-a,", "state": {}}],                              # trailing comma
    [{"name": "widget-a,,extra", "state": {}}],                        # doubled comma
], ids=["empty-entry", "trailing-comma", "doubled-comma"])
def test_L2_dangling_separator_variants_fail(tmp_path, due_payload):
    job, state, due = setup_job(tmp_path, due_override=due_payload)
    out = tmp_path / "prompt.md"
    r = run_lint(TMPL, job, state, due, out)
    assert r.returncode == 2
    assert "L2" in lint_findings(tmp_path)


def test_L3_missing_input_path_fails(tmp_path):
    job, state, due = setup_job(
        tmp_path,
        job_overrides={"inputs": ["/nonexistent/path/should/not/exist.txt"]},
        make_input_file=False,
    )
    out = tmp_path / "prompt.md"
    r = run_lint(TMPL, job, state, due, out)
    assert r.returncode == 2
    assert "L3" in lint_findings(tmp_path)


def test_L4_stale_date_fails(tmp_path):
    job, state, due = setup_job(tmp_path)
    out = tmp_path / "prompt.md"
    r = run_lint(TMPL, job, state, due, out, run_date=YESTERDAY)
    assert r.returncode == 2
    assert "L4" in lint_findings(tmp_path)


@pytest.mark.parametrize("clause_text", [
    "Be conservative",
    "Log every change",
    "one command per Bash call",
], ids=["conservative-fallback", "change-log", "bash-discipline"])
def test_L5_missing_mandatory_clause_fails(tmp_path, clause_text):
    job, state, due = setup_job(tmp_path)
    out = tmp_path / "prompt.md"
    mangled = tmp_path / "mangled.tmpl.md"
    text = TMPL.read_text()
    assert clause_text in text, f"fixture assumption broken: {clause_text!r} not in shipped template"
    mangled.write_text(text.replace(clause_text, "REDACTED"))
    r = run_lint(mangled, job, state, due, out)
    assert r.returncode == 2
    assert "L5" in lint_findings(tmp_path)


@pytest.mark.parametrize("due_payload", [[], {}], ids=["empty-array", "not-an-array"])
def test_L6_invalid_due_fails(tmp_path, due_payload):
    job, state, due = setup_job(tmp_path, due_override=due_payload)
    out = tmp_path / "prompt.md"
    r = run_lint(TMPL, job, state, due, out)
    assert r.returncode == 2
    assert "L6" in lint_findings(tmp_path)
