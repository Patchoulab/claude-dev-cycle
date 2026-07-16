#!/usr/bin/env python3
"""verify_evidence.py -- mechanical evidence-integrity check for the review
harness verification pass (see docs/skills/review-gate.md).

This is the anti-rubber-stamp mechanism. The original harness produced
confirm/dismiss verdicts with ZERO tool calls (sessions 4445356c / 75e9bc6f);
this check makes a verdict acceptable only when it is backed by fresh evidence
gathered from the CURRENT file.

Usage:
    verify_evidence.py <verify_raw.json> <candidates.json> <repo_root> <retired_paths_json>

  verify_raw.json     the verifier session's `claude --output-format json` result
  candidates.json     JSON array of the findings the verifier was asked to adjudicate
  repo_root           absolute canonical repo root
  retired_paths_json  JSON array of retired path prefixes (may be "[]")

Enforces, per sec 5.9 step 2 -- ALL must hold or the whole pass is rejected:
  - num_turns >= 2 (a zero-tool-call session has num_turns 1 -> wholesale reject);
  - every candidate received exactly one verdict;
  - each verdict is confirm|dismiss with well-formed evidence;
  - evidence.file exists under repo_root and is not on a retired path;
  - evidence.file realpath-resolves to exactly root/<candidate.filePath> for
    the candidate it adjudicates, and is not under .git/ or .superpowers/
    (reason: "evidence-file-mismatch" -- a verifier must ground its verdict
    in the actual file under review, not some other file or a gate artifact);
  - evidence.quote (whitespace-normalized) is >= 12 characters long (reason:
    "quote-too-short" -- a one-token "quote" is not meaningful evidence);
  - evidence.quote (whitespace-normalized) appears in the current file within
    [startLine-2, endLine+2].

Prints one JSON object to stdout:
  {"ok": bool, "reasons": [...], "confirmed": [<finding>...],
   "dismissed": [<finding>...], "confirmedCount": n, "dismissedCount": n}
On any failure ok is false and confirmed/dismissed are emptied (fail closed).
Exit is always 0: the gate reads the JSON, and a crash must never be read as a
pass -- the outer guard emits ok:false instead.
"""
import json
import os
import re
import sys


MIN_QUOTE_LEN = 12  # sec 5.9: a quote shorter than this is not meaningful evidence


def norm_ws(s):
    return re.sub(r"\s+", " ", s or "").strip()


def load_json_file(path):
    with open(path) as fh:
        return json.load(fh)


def extract_verdicts(raw):
    """Verdicts may be a top-level array or nested in a StructuredOutput
    `result` string (mirrors how findings arrive on the review pass)."""
    if isinstance(raw, dict):
        if isinstance(raw.get("verdicts"), list):
            return raw["verdicts"]
        r = raw.get("result")
        if isinstance(r, str):
            try:
                inner = json.loads(r)
                if isinstance(inner, dict) and isinstance(inner.get("verdicts"), list):
                    return inner["verdicts"]
            except Exception:
                pass
    return None


def get_num_turns(raw):
    if isinstance(raw, dict):
        nt = raw.get("num_turns")
        # bool is an int subclass; reject it explicitly.
        if isinstance(nt, bool):
            return None
        if isinstance(nt, int):
            return nt
    return None


def emit(ok, reasons, confirmed, dismissed):
    if not ok:
        confirmed, dismissed = [], []
    print(json.dumps({
        "ok": ok,
        "reasons": reasons,
        "confirmed": confirmed,
        "dismissed": dismissed,
        "confirmedCount": len(confirmed),
        "dismissedCount": len(dismissed),
    }))


def run():
    verify_raw, cand_file, root, retired_json = sys.argv[1:5]
    reasons = []

    try:
        raw = load_json_file(verify_raw)
    except Exception as e:
        emit(False, ["verifier output unparseable: %s" % e], [], [])
        return

    try:
        candidates = load_json_file(cand_file)
    except Exception:
        candidates = []
    if not isinstance(candidates, list):
        candidates = []

    try:
        retired = json.loads(retired_json)
    except Exception:
        retired = []
    if not isinstance(retired, list):
        retired = []

    root_real = os.path.realpath(root)
    retired_real = [os.path.realpath(str(p)) for p in retired]

    def under(path, base):
        return path == base or path.startswith(base + os.sep)

    # 1. num_turns >= 2: a session that returned a verdict without reading
    #    anything is rejected wholesale (the core integrity gate).
    nt = get_num_turns(raw)
    if nt is None or nt < 2:
        reasons.append("num_turns=%s (<2: zero-tool-call verdict, wholesale reject)" % nt)

    verdicts = extract_verdicts(raw)
    if verdicts is None:
        reasons.append("no verdicts array in verifier output")
        verdicts = []

    # 2. Every candidate gets exactly one verdict; pair by (filePath, category).
    remaining = list(verdicts)
    matched = []  # list of (candidate, verdict)
    for c in candidates:
        key = (str(c.get("filePath")), str(c.get("category")))
        hit = None
        for v in remaining:
            if (str(v.get("filePath")), str(v.get("category"))) == key:
                hit = v
                break
        if hit is None:
            reasons.append("candidate %s/%s received no verdict" % key)
        else:
            remaining.remove(hit)
            matched.append((c, hit))
    for v in remaining:
        reasons.append("extra verdict %s/%s with no matching candidate"
                       % (str(v.get("filePath")), str(v.get("category"))))

    confirmed, dismissed = [], []
    for c, v in matched:
        verdict = v.get("verdict")
        if verdict not in ("confirm", "dismiss"):
            reasons.append("verdict for %s is %r (not confirm/dismiss)"
                           % (c.get("filePath"), verdict))
            continue
        ev = v.get("evidence") or {}
        f, sl, el, q = ev.get("file"), ev.get("startLine"), ev.get("endLine"), ev.get("quote")
        if not (isinstance(f, str) and isinstance(sl, int) and not isinstance(sl, bool)
                and isinstance(el, int) and not isinstance(el, bool) and isinstance(q, str)):
            reasons.append("evidence for %s malformed" % c.get("filePath"))
            continue

        # Minimum quote substance (sec 5.9): a fragment shorter than this
        # cannot pin the evidence to anything specific (e.g. a single token
        # that happens to appear all over the file).
        q_norm = norm_ws(q)
        if len(q_norm) < MIN_QUOTE_LEN:
            reasons.append(
                "quote-too-short: evidence.quote %r for %s is %d chars after "
                "whitespace normalization (< %d)"
                % (q, c.get("filePath"), len(q_norm), MIN_QUOTE_LEN))
            continue

        # Evidence-file correspondence (sec 5.9): the verdict must be grounded
        # in the exact candidate file, not some other file in the repo and
        # not a gate artifact (.git/, .superpowers/) the verifier could
        # otherwise point to instead of doing real work.
        f_real = os.path.realpath(f)
        expected_real = os.path.realpath(
            os.path.join(root_real, str(c.get("filePath") or "")))
        git_dir_real = os.path.realpath(os.path.join(root_real, ".git"))
        superpowers_real = os.path.realpath(os.path.join(root_real, ".superpowers"))
        if (f_real != expected_real
                or under(f_real, git_dir_real)
                or under(f_real, superpowers_real)):
            reasons.append(
                "evidence-file-mismatch: evidence.file %s does not "
                "correspond to candidate %s" % (f, c.get("filePath")))
            continue

        if not os.path.isfile(f_real):
            reasons.append("evidence.file does not exist: %s" % f)
            continue
        if not under(f_real, root_real):
            reasons.append("evidence.file outside repo root: %s" % f)
            continue
        if any(under(f_real, rp) for rp in retired_real):
            reasons.append("evidence.file on a retired path: %s" % f)
            continue
        try:
            file_lines = open(f_real, errors="replace").read().splitlines()
        except Exception as e:
            reasons.append("cannot read evidence.file %s: %s" % (f, e))
            continue
        lo, hi = max(1, sl - 2), min(len(file_lines), el + 2)
        if lo > hi:
            reasons.append("evidence line range %s-%s outside file %s" % (sl, el, f))
            continue
        window = norm_ws("\n".join(file_lines[lo - 1:hi]))
        if q_norm not in window:
            reasons.append("evidence.quote not found at %s:%s-%s" % (f, sl, el))
            continue
        (confirmed if verdict == "confirm" else dismissed).append(c)

    emit(not reasons, reasons, confirmed, dismissed)


def main():
    try:
        run()
    except Exception as e:  # never let a crash read as a pass
        print(json.dumps({
            "ok": False, "reasons": ["verify_evidence crashed: %s" % e],
            "confirmed": [], "dismissed": [], "confirmedCount": 0, "dismissedCount": 0,
        }))


if __name__ == "__main__":
    main()
