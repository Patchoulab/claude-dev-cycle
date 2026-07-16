import pathlib
import subprocess
import sys

SCRIPT = pathlib.Path(__file__).resolve().parents[2] / "session_slug.py"


def run(*args):
    return subprocess.run(
        [sys.executable, str(SCRIPT), *args], capture_output=True, text=True
    )


def test_string_basic():
    r = run("--string", "Wave C — cron health")
    assert r.returncode == 0
    assert r.stdout.strip() == "feat/wave-c-cron-health"


def test_fix_classification():
    r = run("--string", "Fix the poller race")
    assert r.returncode == 0
    assert r.stdout.strip().startswith("fix/")


def test_chore_classification():
    r = run("--string", "chore: refactor the ledger")
    assert r.returncode == 0
    assert r.stdout.strip().startswith("chore/")


def test_seed_file(tmp_path):
    seed = tmp_path / "seed.md"
    seed.write_text("# Next Session Seed — Wave C task C2\nGenerated: x\n")
    r = run(str(seed))
    assert r.returncode == 0
    assert r.stdout.strip() == "feat/wave-c-task-c2"


def test_missing_seed(tmp_path):
    r = run(str(tmp_path / "nope.md"))
    assert r.returncode == 1


def test_seed_without_header(tmp_path):
    seed = tmp_path / "seed.md"
    seed.write_text("no header here\n")
    r = run(str(seed))
    assert r.returncode == 1


def test_length_cap():
    r = run("--string", "x" * 200)
    assert r.returncode == 0
    assert len(r.stdout.strip()) <= 64


def test_emoji_sanitized():
    r = run("--string", "ship it 🚀 now")
    assert r.returncode == 0
    assert r.stdout.strip() == "feat/ship-it-now"


def test_seed_endash_header(tmp_path):
    seed = tmp_path / "seed.md"
    seed.write_text("# Next Session Seed – Wave D\nGenerated: x\n")  # en-dash U+2013
    r = run(str(seed))
    assert r.returncode == 0
    assert r.stdout.strip() == "feat/wave-d"
