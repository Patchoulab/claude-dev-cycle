#!/bin/bash
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
GATE="$DIR/../../../hooks/review-gate/gate.sh"
fail=0
[ -x "$GATE" ] || { echo "FAIL: gate.sh missing"; exit 1; }

T=$(mktemp -d)
W=$("$DIR/../finish-branch/build_sandbox.sh" "$T" | tail -1)
export DEV_CYCLE_CLAUDE_BIN="$DIR/stub-claude.sh"
export STUB_RECORD="$T/record"

# Fix 3 (review.enabled gate, spec 04-review-gate sec 5.10/sec7): the gate
# now no-ops unless review.enabled is true in the repo's dev-cycle.json. Opt in
# so cases 1-4 keep exercising the full pipeline. Two repos need it: the
# parent ($W, used by case 4 whose hook fires with cwd=$W) and the submodule
# ($W/submod, used by cases 1-3 whose hook fires with cwd=$W/submod --
# per spec sec 6 "submodule checkout", a submodule is its own repo and needs
# its own dev-cycle.json, so it gets a fresh minimal one).
python3 -c '
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d.setdefault("review", {})["enabled"] = True
json.dump(d, open(p, "w"))
' "$W/.claude/dev-cycle.json"
mkdir -p "$W/submod/.claude"
# monorepoHint + top-level retiredPaths feed the config-driven prompt
# injections asserted in Case 1 (spec 04-review-gate sec 5.2/sec 5.10).
printf '{"retiredPaths": ["/retired/old-path-xyz"], "review": {"enabled": true, "monorepoHint": "All modules live under submod/"}}' > "$W/submod/.claude/dev-cycle.json"

# Make a code change with security surface and commit it
printf 'def auth(token):\n    return token == "x"\n' > "$W/submod/auth.py"
git -C "$W/submod" add auth.py
git -C "$W/submod" -c user.email=t@t -c user.name=t commit -qm "feat: auth"
SHA=$(git -C "$W/submod" rev-parse HEAD)

hook_input() { printf '{"cwd": "%s"}' "$W/submod"; }

# Case 1: REVIEW-classed diff spawns exactly one reviewer with absolute paths in the prompt
( cd "$W/submod" && hook_input | "$GATE" ) || { echo "FAIL: gate errored"; fail=1; }
grep -q "ARGS:" "$STUB_RECORD" || { echo "FAIL: reviewer not spawned"; fail=1; }
grep -q "$W/submod" "$STUB_RECORD" || { echo "FAIL: prompt lacks absolute repo root"; fail=1; }
# Config-driven prompt injections (Part B): monorepoHint + retiredPaths from
# dev-cycle.json, and the findings schema extracted from references/schemas.md.
grep -q "All modules live under submod/" "$STUB_RECORD" || { echo "FAIL: monorepoHint not injected into prompt"; fail=1; }
grep -q "/retired/old-path-xyz" "$STUB_RECORD" || { echo "FAIL: retiredPaths not injected into prompt"; fail=1; }
grep -q "additionalProperties" "$STUB_RECORD" || { echo "FAIL: findings schema not injected from schemas.md"; fail=1; }

# Case 2: dedup — same SHA immediately again spawns nothing new
BEFORE=$(grep -c "ARGS:" "$STUB_RECORD")
( cd "$W/submod" && hook_input | "$GATE" )
AFTER=$(grep -c "ARGS:" "$STUB_RECORD")
[ "$BEFORE" -eq "$AFTER" ] || { echo "FAIL: duplicate review not deduped"; fail=1; }
[ -d "$W/submod/.git/dev-cycle/review" ] || echo "note: lock dir may live in common gitdir (submodule)"

# Case 3: SKIP-classed diff (docs only) spawns nothing and logs the skip
echo "notes" > "$W/submod/NOTES.md"
git -C "$W/submod" add NOTES.md
git -C "$W/submod" -c user.email=t@t -c user.name=t commit -qm "docs: notes"
BEFORE=$(grep -c "ARGS:" "$STUB_RECORD")
( cd "$W/submod" && hook_input | "$GATE" )
AFTER=$(grep -c "ARGS:" "$STUB_RECORD")
[ "$BEFORE" -eq "$AFTER" ] || { echo "FAIL: docs-only diff was not skipped"; fail=1; }

# Case 4: submodule bump in the PARENT resolves the real range (no Invalid revision range)
git -C "$W" add submod
git -C "$W" -c user.email=t@t -c user.name=t commit -qm "chore: bump gitlink"
( cd "$W" && printf '{"cwd": "%s"}' "$W" | "$GATE" ) || { echo "FAIL: gate errored on gitlink bump"; fail=1; }
grep -q "auth.py" "$STUB_RECORD" || { echo "FAIL: submodule bump not resolved to real changed files"; fail=1; }
# Finding: the changed-files table must not tell the reviewer the submodule
# path is absent from the worktree; it must point at the expanded range.
grep -q "submod (submodule bump; see the Submodule changes section" "$STUB_RECORD" || { echo "FAIL: submodule path in changed-files table not annotated as a bump"; fail=1; }
grep -q "submod (path not present in worktree)" "$STUB_RECORD" && { echo "FAIL: submodule bump falsely reported path-not-present in changed-files table"; fail=1; }

# Case 5: review.enabled=false (block disabled) -> gate no-ops entirely on a
# NEW commit: nothing spawned, and a "not-configured" audit record is
# written (spec sec 5.10/sec7, sec 6 "not-configured").
python3 -c '
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["review"] = {"enabled": False}
json.dump(d, open(p, "w"))
' "$W/.claude/dev-cycle.json"
echo "print(1)" > "$W/toplevel_change.py"
git -C "$W" add toplevel_change.py
git -C "$W" -c user.email=t@t -c user.name=t commit -qm "feat: toplevel change while review disabled"
BEFORE=$(grep -c "ARGS:" "$STUB_RECORD")
( cd "$W" && printf '{"cwd": "%s"}' "$W" | "$GATE" ) || { echo "FAIL: gate errored with review disabled"; fail=1; }
AFTER=$(grep -c "ARGS:" "$STUB_RECORD")
[ "$BEFORE" -eq "$AFTER" ] || { echo "FAIL: gate spawned a reviewer despite review.enabled=false"; fail=1; }
COMMON=$(git -C "$W" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
grep -q '"reason":"not-configured"' "$COMMON/dev-cycle/review/log.jsonl" 2>/dev/null || { echo "FAIL: no not-configured audit record"; fail=1; }

# Case 6: findings-write regression: stub returns two findings (one clean,
# one with a secret in its explanation), scrubber withholds the secret
# finding's explanation, both findings append to .superpowers/security-findings.md.
# Verification is turned OFF here so this stays a pure scrub/write regression
# (the verification pass is exercised by Cases 7-8).
printf '{"review": {"enabled": true, "verification": {"required": false}}}' > "$W/submod/.claude/dev-cycle.json"
echo "def bypass_check(secret):" > "$W/submod/secret-code.py"
echo "    pass" >> "$W/submod/secret-code.py"
git -C "$W/submod" add secret-code.py
git -C "$W/submod" -c user.email=t@t -c user.name=t commit -qm "feat: secret bypass"
STUB_FINDINGS='{"findings":[{"filePath":"secret-code.py","category":"secret","severity":"critical","explanation":"Weak bypass check detected"},{"filePath":"secret-code.py","category":"secret","severity":"critical","explanation":"Token ghp_A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6Q7r8 found in secret"}]}'
export STUB_FINDINGS
( cd "$W/submod" && hook_input | "$GATE" ) || { echo "FAIL: gate errored on secret case"; fail=1; }
FINDINGS_PATH="$W/submod/.superpowers/security-findings.md"
[ -f "$FINDINGS_PATH" ] || { echo "FAIL: security-findings.md not created"; fail=1; }
grep -q "Weak bypass check detected" "$FINDINGS_PATH" || { echo "FAIL: clean finding explanation not in findings file"; fail=1; }
grep -q "\[explanation withheld: matched secret pattern\]" "$FINDINGS_PATH" || { echo "FAIL: scrubbed explanation marker not found"; fail=1; }
grep -q "ghp_A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6Q7r8" "$FINDINGS_PATH" && { echo "FAIL: secret token leaked into findings file"; fail=1; }

# submod audit log (submodule is its own repo -> its own git-common-dir).
COMMON_SUB=$(git -C "$W/submod" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)

# Case 7: verification pass WITH valid evidence (num_turns>=2, verbatim
# line-anchored quote from the current file) -> finding CONFIRMED, appended to
# security-findings.md, audit `done` carries confirmed/dismissed counts
# (spec 04-review-gate sec 5.9 steps 2-5, sec 5.6 audit shape).
printf '{"review": {"enabled": true, "verification": {"required": true, "maxRetries": 1}}}' > "$W/submod/.claude/dev-cycle.json"
printf 'def login(pw):\n    return pw == "admin"\n' > "$W/submod/vuln.py"
git -C "$W/submod" add vuln.py
git -C "$W/submod" -c user.email=t@t -c user.name=t commit -qm "feat: vuln login"
STUB_FINDINGS='{"findings":[{"filePath":"vuln.py","category":"auth","vulnerableCode":"return pw == \"admin\"","explanation":"hardcoded admin password"}]}'
export STUB_FINDINGS
STUB_VERDICTS='{"num_turns":3,"verdicts":[{"filePath":"vuln.py","category":"auth","verdict":"confirm","evidence":{"file":"'"$W"'/submod/vuln.py","startLine":2,"endLine":2,"quote":"return pw == \"admin\""}}]}'
export STUB_VERDICTS
BEFORE_V=$(grep -c "You previously flagged" "$STUB_RECORD")
( cd "$W/submod" && hook_input | "$GATE" ) || { echo "FAIL: gate errored on verification-pass case"; fail=1; }
AFTER_V=$(grep -c "You previously flagged" "$STUB_RECORD")
[ "$AFTER_V" -gt "$BEFORE_V" ] || { echo "FAIL: verification pass not spawned"; fail=1; }
grep -q "hardcoded admin password" "$FINDINGS_PATH" || { echo "FAIL: confirmed finding not appended to findings file"; fail=1; }
grep -q '"event":"verify_ok"' "$COMMON_SUB/dev-cycle/review/log.jsonl" || { echo "FAIL: no verify_ok audit line"; fail=1; }
grep -Eq '"event":"done"[^}]*"confirmed":1' "$COMMON_SUB/dev-cycle/review/log.jsonl" || { echo "FAIL: done event missing confirmed:1"; fail=1; }
grep -Eq '"event":"done"[^}]*"dismissed":0' "$COMMON_SUB/dev-cycle/review/log.jsonl" || { echo "FAIL: done event missing dismissed count"; fail=1; }

# Case 8: verification response WITHOUT valid evidence (num_turns=1, the
# observed zero-tool-call rubber-stamp signature) -> rejected wholesale,
# re-run once (2 verify spawns total), then the finding is left OPEN and
# marked `unverified` in both the findings file and the audit log
# (spec sec 5.9 steps 3-4: unverified != dismissed, never silently confirmed).
printf 'def admin(pw):\n    return pw == "root"\n' > "$W/submod/vuln8.py"
git -C "$W/submod" add vuln8.py
git -C "$W/submod" -c user.email=t@t -c user.name=t commit -qm "feat: vuln8"
STUB_FINDINGS='{"findings":[{"filePath":"vuln8.py","category":"auth","vulnerableCode":"return pw == \"root\"","explanation":"hardcoded root password"}]}'
export STUB_FINDINGS
STUB_VERDICTS='{"num_turns":1,"verdicts":[{"filePath":"vuln8.py","category":"auth","verdict":"confirm","evidence":{"file":"'"$W"'/submod/vuln8.py","startLine":2,"endLine":2,"quote":"return pw == \"root\""}}]}'
export STUB_VERDICTS
BEFORE8=$(grep -c "You previously flagged" "$STUB_RECORD")
( cd "$W/submod" && hook_input | "$GATE" ) || { echo "FAIL: gate errored on verification-fail case"; fail=1; }
AFTER8=$(grep -c "You previously flagged" "$STUB_RECORD")
DELTA8=$(( AFTER8 - BEFORE8 ))
[ "$DELTA8" -eq 2 ] || { echo "FAIL: expected 2 verify spawns (initial + 1 retry), got $DELTA8"; fail=1; }
grep -q '"event":"verify_rejected"' "$COMMON_SUB/dev-cycle/review/log.jsonl" || { echo "FAIL: no verify_rejected audit line"; fail=1; }
grep -q '"event":"verification_failed"' "$COMMON_SUB/dev-cycle/review/log.jsonl" || { echo "FAIL: no verification_failed audit line"; fail=1; }
grep -q "hardcoded root password" "$FINDINGS_PATH" || { echo "FAIL: unverified finding silently dropped from findings file"; fail=1; }
grep -q "unverified" "$FINDINGS_PATH" || { echo "FAIL: finding not marked unverified in findings file"; fail=1; }
grep -Eq '"event":"done"[^}]*"unverified":1' "$COMMON_SUB/dev-cycle/review/log.jsonl" || { echo "FAIL: done event missing unverified:1"; fail=1; }


# Case 9: verification response WITH num_turns>=2 (a real tool-call session)
# but a FABRICATED quote -- text that does not appear anywhere in the current
# file -- must still be rejected on the quote-anchoring check (spec sec 5.9
# step 2), re-run once, and (the stub being deterministic) fail identically
# on retry -> `verification_failed`, finding left OPEN and marked
# `**unverified**` in the findings file (fail closed, same as case 8 but
# isolating the quote check rather than the num_turns check).
printf 'def check(pw):\n    return pw == "letmein"\n' > "$W/submod/vuln9.py"
git -C "$W/submod" add vuln9.py
git -C "$W/submod" -c user.email=t@t -c user.name=t commit -qm "feat: vuln9"
STUB_FINDINGS='{"findings":[{"filePath":"vuln9.py","category":"auth","vulnerableCode":"return pw == \"letmein\"","explanation":"hardcoded password nine"}]}'
export STUB_FINDINGS
STUB_VERDICTS='{"num_turns":3,"verdicts":[{"filePath":"vuln9.py","category":"auth","verdict":"confirm","evidence":{"file":"'"$W"'/submod/vuln9.py","startLine":2,"endLine":2,"quote":"this text does not appear anywhere in the file"}}]}'
export STUB_VERDICTS
BEFORE9=$(grep -c "You previously flagged" "$STUB_RECORD")
( cd "$W/submod" && hook_input | "$GATE" ) || { echo "FAIL: gate errored on fabricated-quote case"; fail=1; }
AFTER9=$(grep -c "You previously flagged" "$STUB_RECORD")
DELTA9=$(( AFTER9 - BEFORE9 ))
[ "$DELTA9" -eq 2 ] || { echo "FAIL: expected 2 verify spawns for fabricated quote (initial + 1 retry), got $DELTA9"; fail=1; }
grep -q '"event":"verify_rejected"' "$COMMON_SUB/dev-cycle/review/log.jsonl" || { echo "FAIL: no verify_rejected audit line for fabricated quote"; fail=1; }
grep -q '"event":"verification_failed"' "$COMMON_SUB/dev-cycle/review/log.jsonl" || { echo "FAIL: no verification_failed audit line for fabricated quote"; fail=1; }
grep -q "hardcoded password nine" "$FINDINGS_PATH" || { echo "FAIL: fabricated-quote finding silently dropped from findings file"; fail=1; }
grep -qF '**unverified**' "$FINDINGS_PATH" || { echo "FAIL: fabricated-quote finding not marked **unverified** in findings file"; fail=1; }

# Case 10: install (spec 04-review-gate sec 5.9 / SKILL install procedure).
# Run `gate.sh install` in the sandbox parent: it writes the post-commit hook,
# merges the settings allowlist, and seeds the dev-cycle.json review block. Assert
# each landed, then assert a second run is a byte-for-byte no-op (idempotency).
# Reset the parent dev-cycle.json to a no-review state first so seeding is actually
# exercised (earlier cases mutated it).
printf '{"canonicalRoot": "%s", "submodules": [{"path": "submod", "remote": "origin"}]}' "$W" > "$W/.claude/dev-cycle.json"
( cd "$W" && "$GATE" install >/dev/null 2>&1 ) || { echo "FAIL: gate install errored"; fail=1; }
PC="$W/.git/hooks/post-commit"
[ -f "$PC" ] || { echo "FAIL: post-commit hook not written"; fail=1; }
grep -qF "dev-cycle review-gate (managed)" "$PC" || { echo "FAIL: post-commit hook lacks managed marker"; fail=1; }
# The hook must resolve HEAD synchronously and pass the pinned SHA to the
# backgrounded review (never background an unpinned `run HEAD`, which races a
# follow-up commit/amend) — Codex finding "Pin native hook invocations".
grep -qF 'commit_sha="$(git rev-parse HEAD 2>/dev/null)"' "$PC" || { echo "FAIL: post-commit hook does not resolve the SHA synchronously"; fail=1; }
grep -qF 'run "$commit_sha"' "$PC" || { echo "FAIL: post-commit hook does not pass the pinned SHA to gate.sh run"; fail=1; }
grep -q 'run HEAD' "$PC" && { echo "FAIL: post-commit hook still backgrounds an unpinned run HEAD"; fail=1; }
[ -f "$W/.claude/settings.json" ] || { echo "FAIL: settings.json not written by install"; fail=1; }
grep -qF '"Bash(git log:*)"' "$W/.claude/settings.json" || { echo "FAIL: settings.json missing known allowlist entry"; fail=1; }
grep -qF "Bash(git -C $W/submod log:*)" "$W/.claude/settings.json" || { echo "FAIL: settings.json missing expanded submodule allowlist entry"; fail=1; }
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if isinstance(d.get("review"),dict) and d["review"].get("enabled") is True else 1)' "$W/.claude/dev-cycle.json" || { echo "FAIL: dev-cycle.json review block not seeded"; fail=1; }
# Idempotency: snapshot the three files, run install again, assert unchanged.
cp "$PC" "$T/pc.snap"; cp "$W/.claude/settings.json" "$T/set.snap"; cp "$W/.claude/dev-cycle.json" "$T/cfg.snap"
( cd "$W" && "$GATE" install >/dev/null 2>&1 ) || { echo "FAIL: second gate install errored"; fail=1; }
cmp -s "$PC" "$T/pc.snap" || { echo "FAIL: second install changed post-commit hook (not idempotent)"; fail=1; }
cmp -s "$W/.claude/settings.json" "$T/set.snap" || { echo "FAIL: second install changed settings.json (not idempotent)"; fail=1; }
cmp -s "$W/.claude/dev-cycle.json" "$T/cfg.snap" || { echo "FAIL: second install changed dev-cycle.json (not idempotent)"; fail=1; }

# Case 11: replay (spec 04-review-gate sec 5.9 / SKILL "verify" step).
# Run against an existing commit in the submodule repo: replay renders the
# prompt it WOULD send and prints the triage verdict, but spawns no reviewer,
# takes no lock, and writes no audit line. Enable review in submod first.
printf '{"review": {"enabled": true}}' > "$W/submod/.claude/dev-cycle.json"
RSHA=$(git -C "$W/submod" rev-parse HEAD)
BEFORE_SPAWN=$(grep -c "ARGS:" "$STUB_RECORD")
AUDIT_LOG_SUB="$COMMON_SUB/dev-cycle/review/log.jsonl"
BEFORE_AUDIT=$( [ -f "$AUDIT_LOG_SUB" ] && wc -l < "$AUDIT_LOG_SUB" || echo 0 )
REPLAY_OUT="$T/replay.out"
( cd "$W/submod" && "$GATE" replay "$RSHA" > "$REPLAY_OUT" 2>&1 ) || { echo "FAIL: gate replay errored"; fail=1; }
grep -q "$W/submod" "$REPLAY_OUT" || { echo "FAIL: replay prompt lacks absolute repo root"; fail=1; }
grep -q "vuln9.py" "$REPLAY_OUT" || { echo "FAIL: replay prompt lacks a changed file path"; fail=1; }
grep -q "TRIAGE VERDICT" "$REPLAY_OUT" || { echo "FAIL: replay did not print the triage verdict"; fail=1; }
AFTER_SPAWN=$(grep -c "ARGS:" "$STUB_RECORD")
[ "$AFTER_SPAWN" -eq "$BEFORE_SPAWN" ] || { echo "FAIL: replay spawned a reviewer (stub record delta != 0)"; fail=1; }
AFTER_AUDIT=$( [ -f "$AUDIT_LOG_SUB" ] && wc -l < "$AUDIT_LOG_SUB" || echo 0 )
[ "$AFTER_AUDIT" -eq "$BEFORE_AUDIT" ] || { echo "FAIL: replay wrote an audit line (before=$BEFORE_AUDIT after=$AFTER_AUDIT)"; fail=1; }

# Case 12: rename commit -> the changed-files table lists the NEW path for the
# reviewer to Read, annotated as a rename, NOT the retired old path marked
# "not present in worktree" (Codex finding "Use the new path for renamed
# files"). The rename also adds a surface hit so the commit is REVIEW-classed
# and actually spawns a reviewer (a pure rename would triage to SKIP).
printf '{"review": {"enabled": true, "verification": {"required": false}}}' > "$W/submod/.claude/dev-cycle.json"
printf 'def helper(a):\n    x = a + 1\n    y = x * 2\n    z = y - 3\n    return z\n' > "$W/submod/oldname.py"
git -C "$W/submod" add oldname.py
git -C "$W/submod" -c user.email=t@t -c user.name=t commit -qm "feat: add oldname"
git -C "$W/submod" mv oldname.py newname.py
printf 'def run(cmd):\n    return eval(cmd)\n' >> "$W/submod/newname.py"
git -C "$W/submod" add newname.py
git -C "$W/submod" -c user.email=t@t -c user.name=t commit -qm "refactor: rename oldname to newname"
export STUB_FINDINGS='{"findings":[]}'
( cd "$W/submod" && hook_input | "$GATE" ) || { echo "FAIL: gate errored on rename commit"; fail=1; }
grep -q "submod/newname.py (renamed from" "$STUB_RECORD" || { echo "FAIL: rename not annotated with the new path in changed-files table"; fail=1; }
grep -q "submod/oldname.py (path not present in worktree)" "$STUB_RECORD" && { echo "FAIL: rename handed the reviewer the stale old path"; fail=1; }

# Case 13: a MERGE commit that bumps a submodule -> resolve_submodules threads
# -m --first-parent, so the gitlink change is seen (a plain diff-tree emits
# nothing for a merge) and the expanded submodule diff reaches the reviewer
# (Codex finding "Expand submodule diffs for merge commits"). A distinctive
# marker line proves the EXPANDED range (not just the pointer bump) was
# rendered into the prompt.
printf '{"canonicalRoot": "%s", "submodules": [{"path": "submod", "remote": "origin"}], "review": {"enabled": true, "verification": {"required": false}}}' "$W" > "$W/.claude/dev-cycle.json"
git -C "$W/submod" checkout -q main
printf 'MERGE_SUBMODULE_MARKER\n' >> "$W/submod/module.txt"
git -C "$W/submod" -c user.email=t@t -c user.name=t commit -qam "feat: submodule change for merge"
BASE_BR=$(git -C "$W" rev-parse --abbrev-ref HEAD)
git -C "$W" checkout -qb feat/merge-bump
git -C "$W" add submod
git -C "$W" -c user.email=t@t -c user.name=t commit -qm "chore: bump submodule on branch"
git -C "$W" checkout -q "$BASE_BR"
printf 'base\n' > "$W/base-change.txt"
git -C "$W" add base-change.txt
git -C "$W" -c user.email=t@t -c user.name=t commit -qm "chore: divergent base change"
git -C "$W" -c user.email=t@t -c user.name=t merge --no-ff -q -m "merge feat/merge-bump" feat/merge-bump
export STUB_FINDINGS='{"findings":[]}'
( cd "$W" && printf '{"cwd": "%s"}' "$W" | "$GATE" ) || { echo "FAIL: gate errored on merge-commit submodule bump"; fail=1; }
grep -q "MERGE_SUBMODULE_MARKER" "$STUB_RECORD" || { echo "FAIL: merge-commit submodule bump not expanded (plain diff-tree emits nothing for merges)"; fail=1; }

# Case 14: hook-posttooluse with `git -C <abs-submodule> commit ...` while the
# hook cwd is the PARENT -> the gate must resolve the repo from the -C target
# and review the SUBMODULE's HEAD, not the parent's (Codex finding "Resolve
# `git -C` hooks against the command target"). The mode detaches the review, so
# poll (bounded) the submodule audit log for the submodule's own SHA.
printf '{"review": {"enabled": true, "verification": {"required": false}}}' > "$W/submod/.claude/dev-cycle.json"
printf 'def q(cmd):\n    return eval(cmd)\n' > "$W/submod/ptt.py"
git -C "$W/submod" add ptt.py
git -C "$W/submod" -c user.email=t@t -c user.name=t commit -qm "feat: ptt eval"
PTT_SHA=$(git -C "$W/submod" rev-parse HEAD)
export STUB_FINDINGS='{"findings":[]}'
printf '{"cwd": "%s", "tool_input": {"command": "git -C %s commit -m x"}}' "$W" "$W/submod" | ( cd "$W" && "$GATE" hook-posttooluse )
ptt_ok=0
for _ in $(seq 1 60); do
  if grep -q "$PTT_SHA" "$COMMON_SUB/dev-cycle/review/log.jsonl" 2>/dev/null; then ptt_ok=1; break; fi
  sleep 0.1
done
[ "$ptt_ok" -eq 1 ] || { echo "FAIL: hook-posttooluse resolved the wrong repo (did not review the -C target submodule commit)"; fail=1; }

# Case 15: lock CREATION failure (unwritable review dir) must NOT be mistaken
# for lock contention -> the gate proceeds WITHOUT dedup and audits
# gate_degraded rather than silently skipping the review (Codex finding "Review
# without dedup when lock creation fails"). Make the locks dir read-only so the
# per-SHA leaf mkdir fails with EACCES (a permission error, not contention).
printf '{"review": {"enabled": true, "verification": {"required": false}}}' > "$W/submod/.claude/dev-cycle.json"
printf 'def danger(cmd):\n    return eval(cmd)\n' > "$W/submod/degraded.py"
git -C "$W/submod" add degraded.py
git -C "$W/submod" -c user.email=t@t -c user.name=t commit -qm "feat: degraded eval"
export STUB_FINDINGS='{"findings":[]}'
LOCKS_DIR="$COMMON_SUB/dev-cycle/review/locks"
mkdir -p "$LOCKS_DIR"
chmod 500 "$LOCKS_DIR"
BEFORE_D=$(grep -c "ARGS:" "$STUB_RECORD")
( cd "$W/submod" && hook_input | "$GATE" ) || { echo "FAIL: gate errored on lock-creation failure"; fail=1; }
AFTER_D=$(grep -c "ARGS:" "$STUB_RECORD")
chmod 700 "$LOCKS_DIR"
[ "$AFTER_D" -gt "$BEFORE_D" ] || { echo "FAIL: gate skipped the review on a lock-creation failure (treated a permission error as contention)"; fail=1; }
grep -q '"event":"gate_degraded"' "$COMMON_SUB/dev-cycle/review/log.jsonl" || { echo "FAIL: no gate_degraded audit line on lock-creation failure"; fail=1; }

rm -rf "$T"
[ $fail -eq 0 ] && echo "OK: gate (15 cases)"
exit $fail
