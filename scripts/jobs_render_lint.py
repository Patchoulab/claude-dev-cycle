#!/usr/bin/env python3
"""jobs_render_lint.py — render + lint a scheduled-jobs job prompt.

Contract: docs/skills/scheduled-jobs.md (render + lint; job.json
manifest schema it consumes).

Path mapping (per the plan's locked path mapping, §5.1): this file ships in
the plugin repo as `scripts/jobs_render_lint.py`. At scaffold time
(`/dev-cycle:jobs:new`) it is copied idempotently, with a version stamp, to
the installed runtime location `~/.claude/dev-cycle/jobs/bin/render_lint.py` —
that installed name is what job wrappers (`run.sh`, generated from
`templates/run.sh.tmpl`) actually invoke. The two names refer to the same
file at two points in its lifecycle: repo source vs. installed copy.

Usage:
    jobs_render_lint.py --template T --manifest M --state S --due D \\
        --run-date DATE --report R --summary Y --out OUT

Renders `--template` (a scheduled-jobs prompt.tmpl.md) against the manifest,
state, due-items and run-scoped paths, then lints the RENDERED text.

Exit 0: the render is clean; the rendered prompt is written to OUT.
Exit 2: lint failure. Findings are written to OUT.<lint-suffix> (OUT with
        ".lint" appended), one "RULE: message" line per finding; OUT itself
        is NOT written.
Exit 1: usage / IO error before rendering could be attempted (bad JSON,
        missing template, etc.) — not a lint failure, no OUT.lint written.

Rules L1-L6 (see §5.8's table for the authoritative description):
    L1  No {{...}} survives rendering (template drift, typoed placeholder).
    L2  No dangling separators in rendered list blocks: no trailing comma at
        end of a list line, no doubled comma, no empty list entries — the
        historical 'vercel,bun,' bug class.
    L3  Every input path (state file, manifest inputs) exists; output paths'
        (report, summary) parent directories exist and are writable.
    L4  --run-date is a valid ISO date and equals today (local, ±0 days).
    L5  All mandatory clauses from the template's header checklist are
        present in the rendered text, matched by anchor phrase.
    L6  --due is a non-empty JSON array and every due item's name appears in
        the rendered due-items block.

Reconciliation note (job.json §5.2 does not define ROLE_FRAMING,
PER_ITEM_PROCEDURE, REMEDIATION_STEP or JOB_TITLE): per §5.5, those four
template placeholders are meant to already be fixed text in a job's own
prompt.tmpl.md copy, baked in once at scaffold time — by the time a real
job's wrapper calls this script, those tokens no longer exist as {{...}}.
This script still renders them (with generic derived fallbacks, or optional
non-schema `role_framing` / `per_item_procedure` / `remediation_step` /
`job_title` manifest keys if present) so it also works standalone against
the master template shipped in `skills/scheduled-jobs/templates/prompt.tmpl.md`
— which is how this script's own test suite and `/dev-cycle:jobs:lint`
exercise it. See task-7-report.md for the full list of contract
reconciliations made while implementing this script.
"""
import argparse
import datetime
import json
import os
import pathlib
import re
import sys

PLACEHOLDER_RE = re.compile(r"\{\{([A-Z0-9_]+)\}\}")

# Rendered list blocks that must never contain dangling separators (L2).
# DUE_STATE_JSON is deliberately excluded: it is pretty-printed JSON, whose
# commas are syntactically correct and would false-positive this check.
LIST_BLOCK_NAMES = ("INPUT_PATHS_BLOCK", "DUE_ITEMS_BLOCK", "WRITES_ALLOWED_BLOCK")

WRITES_ALLOWED_NONE_LINE = (
    "NONE — this job is report-only; write nothing except the state file, "
    "report, and summary"
)


def abspath(p):
    return str(pathlib.Path(str(p)).expanduser().resolve(strict=False))


def load_json(path, label):
    try:
        return json.loads(pathlib.Path(path).read_text())
    except FileNotFoundError:
        raise SystemExit(f"error: {label} not found: {path}")
    except json.JSONDecodeError as e:
        raise SystemExit(f"error: {label} is not valid JSON ({path}): {e}")


def build_context(manifest, state, due_raw, args):
    """Build the placeholder -> rendered-text substitution map."""
    due_items = due_raw if isinstance(due_raw, list) else []

    due_names = []
    due_state = {}
    for item in due_items:
        if not isinstance(item, dict):
            continue
        name = item.get("name", "")
        due_names.append(name)
        due_state[name] = item.get("state", {})

    total_items = len(state.get("items", {})) if isinstance(state, dict) else 0
    fresh_count = max(total_items - len({n for n in due_names if n}), 0)

    inputs = [abspath(p) for p in manifest.get("inputs", [])]
    writes_allowed = [abspath(p) for p in manifest.get("writes_allowed", [])]

    input_paths_block = "\n".join(f"- {p}" for p in inputs)
    due_items_block = "\n".join(f"- {n}" for n in due_names)
    writes_allowed_block = (
        "\n".join(f"- {p}" for p in writes_allowed)
        if writes_allowed else WRITES_ALLOWED_NONE_LINE
    )
    due_state_json = json.dumps(due_state, indent=2, sort_keys=True)

    job_name = manifest.get("name", "")
    job_title = manifest.get("job_title") or manifest.get("description") or job_name
    role_framing = manifest.get("role_framing") or (
        f"auditing the tracked items for the '{job_name}' job"
    )
    per_item_procedure = manifest.get("per_item_procedure") or (
        "verify its current state against its authoritative upstream source"
    )
    remediation_step = manifest.get("remediation_step") or (
        "If a due item's current state is provably wrong, patch it."
    )

    ctx = {
        "ROLE_FRAMING": role_framing,
        "RUN_DATE": args.run_date,
        "STATE_PATH": abspath(args.state),
        "REPORT_PATH": abspath(args.report),
        "SUMMARY_PATH": abspath(args.summary),
        "INPUT_PATHS_BLOCK": input_paths_block,
        "DUE_ITEMS_BLOCK": due_items_block,
        "DUE_STATE_JSON": due_state_json,
        "PER_ITEM_PROCEDURE": per_item_procedure,
        "REMEDIATION_STEP": remediation_step,
        "WRITES_ALLOWED_BLOCK": writes_allowed_block,
        "JOB_TITLE": job_title,
        "JOB_NAME": job_name,
        "FRESH_COUNT": str(fresh_count),
    }
    return ctx, due_names


def render(template_text, ctx):
    def repl(m):
        key = m.group(1)
        return ctx[key] if key in ctx else m.group(0)  # leave unknown for L1
    return PLACEHOLDER_RE.sub(repl, template_text)


# ---------------------------------------------------------------------------
# Lint rules
# ---------------------------------------------------------------------------

def check_L1(rendered):
    findings = []
    for m in PLACEHOLDER_RE.finditer(rendered):
        line_no = rendered.count("\n", 0, m.start()) + 1
        findings.append(f"L1: unrendered placeholder {m.group(0)} survived rendering (line {line_no})")
    return findings


def check_L2(ctx):
    findings = []
    for block_name in LIST_BLOCK_NAMES:
        block = ctx.get(block_name, "")
        if not block:
            continue
        for line in block.split("\n"):
            if re.search(r",\s*$", line):
                findings.append(f"L2: dangling separator (trailing comma) in {block_name}: {line!r}")
            if ",," in line:
                findings.append(f"L2: doubled separator ',,' in {block_name}: {line!r}")
            if re.match(r"^-\s*$", line):
                findings.append(f"L2: empty list entry in {block_name}")
    return findings


def check_L3(manifest, args):
    findings = []

    def check_exists(label, path):
        p = pathlib.Path(str(path)).expanduser()
        if not p.exists():
            findings.append(f"L3: {label} does not exist: {p}")

    check_exists("state file", args.state)
    for i, inp in enumerate(manifest.get("inputs", [])):
        check_exists(f"manifest input[{i}]", inp)

    def check_writable_parent(label, path):
        parent = pathlib.Path(str(path)).expanduser().parent
        if not parent.exists():
            findings.append(f"L3: parent directory for {label} output does not exist: {parent}")
        elif not os.access(parent, os.W_OK):
            findings.append(f"L3: parent directory for {label} output is not writable: {parent}")

    check_writable_parent("report", args.report)
    check_writable_parent("summary", args.summary)
    return findings


def check_L4(run_date_str):
    findings = []
    try:
        run_date = datetime.date.fromisoformat(run_date_str)
    except ValueError:
        findings.append(f"L4: --run-date '{run_date_str}' is not a valid ISO date (YYYY-MM-DD)")
        return findings
    today = datetime.date.today()
    if run_date != today:
        findings.append(
            f"L4: --run-date {run_date_str} does not equal today's date {today.isoformat()}"
        )
    return findings


# (clause label, anchor pattern) — anchor phrases per §5.8's L5 row, mapped
# onto the template header's twelve mandatory-clause tags where the rule
# text names a concrete phrase; "bash-discipline" is the rule table's
# thirteenth explicit anchor ("one command per Bash call"), checked
# alongside the twelve for the same reason: it guards against hand-edits
# that strip guardrails.
MANDATORY_CLAUSES = [
    ("role-framing", re.compile(r"You are")),
    ("absolute-paths", re.compile(r"\(absolute paths\)")),
    ("numbered-steps", re.compile(r"(?m)^1\.\s")),
    ("due-items-only", re.compile(r"ONLY these")),
    ("status-enums", re.compile(r"OK \| OUTDATED \| CHANGED \| UNKNOWN")),
    ("conservative-fallback", re.compile(r"Be conservative")),
    ("scoped-writes", re.compile(r"Only patch what is provably\s+wrong")),
    ("change-log", re.compile(r"Log every change")),
    ("state-write-back", re.compile(r"last_verified")),
    ("evidence-urls", re.compile(r"Do NOT guess")),
    ("bash-discipline", re.compile(r"one command per Bash call")),
]


def check_L5(rendered, ctx):
    findings = []
    for label, pattern in MANDATORY_CLAUSES:
        if not pattern.search(rendered):
            findings.append(f"L5: missing mandatory clause '{label}' (anchor {pattern.pattern!r} not found)")
    # report-contract / summary-contract: both output paths must appear
    # verbatim in the rendered prompt (the two "output paths" anchors).
    for label, key in (("report-contract", "REPORT_PATH"), ("summary-contract", "SUMMARY_PATH")):
        if ctx[key] not in rendered:
            findings.append(f"L5: missing mandatory clause '{label}' ({key} does not appear in rendered text)")
    return findings


def check_L6(due_raw, due_names, ctx):
    findings = []
    if not isinstance(due_raw, list):
        findings.append("L6: --due file does not contain a JSON array")
        return findings
    if len(due_raw) == 0:
        findings.append("L6: --due is empty; no due items to render")
        return findings
    block = ctx.get("DUE_ITEMS_BLOCK", "")
    for name in due_names:
        if f"- {name}" not in block.split("\n"):
            findings.append(f"L6: due item {name!r} does not appear in the rendered due-items block")
    return findings


def run_lint_rules(rendered, ctx, manifest, args, due_raw, due_names):
    findings = []
    findings += check_L1(rendered)
    findings += check_L2(ctx)
    findings += check_L3(manifest, args)
    findings += check_L4(args.run_date)
    findings += check_L5(rendered, ctx)
    findings += check_L6(due_raw, due_names, ctx)
    return findings


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                  formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--template", required=True)
    ap.add_argument("--manifest", required=True)
    ap.add_argument("--state", required=True)
    ap.add_argument("--due", required=True)
    ap.add_argument("--run-date", required=True)
    ap.add_argument("--report", required=True)
    ap.add_argument("--summary", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    template_path = pathlib.Path(args.template)
    if not template_path.is_file():
        raise SystemExit(f"error: template not found: {args.template}")
    template_text = template_path.read_text()

    manifest = load_json(args.manifest, "manifest")
    state = load_json(args.state, "state file")
    due_raw = load_json(args.due, "due file")

    ctx, due_names = build_context(manifest, state, due_raw, args)
    rendered = render(template_text, ctx)

    findings = run_lint_rules(rendered, ctx, manifest, args, due_raw, due_names)

    out_path = pathlib.Path(args.out)
    lint_path = pathlib.Path(str(args.out) + ".lint")

    if findings:
        lint_path.parent.mkdir(parents=True, exist_ok=True)
        lint_path.write_text("\n".join(findings) + "\n")
        if out_path.exists():
            out_path.unlink()
        return 2

    if lint_path.exists():
        lint_path.unlink()
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(rendered)
    return 0


if __name__ == "__main__":
    sys.exit(main())
