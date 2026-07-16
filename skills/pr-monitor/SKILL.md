---
name: pr-monitor
description: Use when the user asks to monitor, watch, or babysit a PR for a time window, to answer/address/fix all PR comments or review issues, after pushing a PR when reviews (human, Copilot, CI) are expected, or when they say "stop monitoring" / "stop monitoring and merge". Also triggers on typo'd variants ("fixe all issues", "15 mibutes").
---

# PR Babysit

Bounded watch on one PR: triage every new comment, review, and failed check;
fix what is verified real; push back with evidence on what is not; reply to
EVERY non-bot comment; re-arm after every push; report merge-readiness when
the window closes.

**Core rule: evidence before agreement.** Verify each reviewer claim against
the code before acting. Reviewer wrong → push back with technical reasoning.
Never post performative agreement.

## Setup

1. **Resolve the PR.** Argument if given; else `gh pr view --json number,state,headRefName,url` on the current branch. No PR → stop: "No PR for this branch — create one first: /commit-commands:commit-push-pr, or `gh pr create` if that plugin isn't installed." Multiple/ambiguous → ask. Draft → warn, watch anyway, refuse merge while draft.
2. **Parse the window.** Default 15m. Accept 15m/30m/1h and bare numbers (minutes). Record `end = now + window` in wall time — re-arms never extend it.
3. **Load config.** `.claude/dev-cycle.json` if present: `botsToIgnore` (default `["vercel[bot]"]`), `preauthorized`, `canonicalRoot`, `prMonitor.speak` (default `false`).
4. **Seed the baseline.** Record head SHA and the IDs of all existing issue comments, review comments, reviews, and check runs into `.git/dev-cycle/pr-monitor/<pr>.json`. Existing *unanswered* non-bot comments are backlog: triage them NOW, before arming.
5. **Arm the watch** (see Watch mechanism), then tell the user: PR, window, baseline counts, filtered bots.

## Watch mechanism

Preferred: the **Monitor tool** — condition "PR #N: new comments, reviews, or
failed checks (baseline seeded, bots filtered)", timeout = remaining window.
- Monitor emits `[Monitor timed out — re-arm if needed.]` → **always re-arm**
  with the remaining window. Timeout is noise, not completion.

Fallback (Monitor unavailable): run `"${CLAUDE_PLUGIN_ROOT}/scripts/pr_monitor_poll.sh"` via Bash with
`run_in_background: true`. It exits when there is an event; handle it, then
relaunch. Intervals: 60s (window ≤15m), 90s (≤30m), 120s (>30m) — GitHub list
reads are cache-backed (~60s), polling faster burns quota for stale data.

House rules: one command per Bash call; every `gh`/`curl` gets a timeout;
quote bot logins (`'vercel[bot]'` — unquoted brackets are zsh globs).

## Per-event round

1. Fetch everything new since baseline (comments, review comments, reviews, check runs). Drop authors in `botsToIgnore` (count them for the report).
2. Triage each item with the decision table below. **Recommended background:** if the superpowers plugin is installed, superpowers:receiving-code-review; otherwise apply its core rule — verify each review claim against the actual code before acting, and push back on ones that are wrong.
3. Batch all verified-legit fixes into ONE fix subagent per round (lettered A, B, C…), prompt containing the absolute repo root and per-fix file:line + verification step.
4. Push once per round. Run repo checks first if fast (<2m).
5. Reply to EVERY triaged comment (templates below). Resolve a thread only when its fix is pushed or it was a question you answered; NEVER resolve a pushback thread.
6. Re-seed the baseline (new head SHA, current ID sets) and **re-arm**. New commits invite new reviews — a push without a re-armed watch is a dropped round.
7. If dev-cycle.json `prMonitor.speak` is `true` and claude-speak is available, announce activity and expiry in one short line. Default is silent (`speak: false` or absent).

## Triage decision table

| New item | Verify by | Action | Reply |
|---|---|---|---|
| Claimed bug — verified TRUE | read the code/tests it names | fix, push | agree+fixed |
| Claimed bug — verified FALSE | code contradicts the claim | no change | pushback + evidence |
| Style/nit matching repo conventions | conventions/CLAUDE.md | apply | agree+fixed |
| Style/nit contradicting conventions | cite the convention | no change | pushback citing convention |
| Question | answer from code, file:line | none | direct answer |
| Out-of-scope suggestion | confirm unrelated to diff | none | acknowledge, offer follow-up issue |
| Failed check | read the log | PR-caused → fix; flaky/infra → re-run once, then report | n/a (report) |
| Requested-changes review | triage each inline item | per rows above | per-comment |
| Bot in botsToIgnore | — | skip | none |

Copilot comments get the SAME verification as human ones — Copilot is
frequently wrong and the user's rule applies to it doubly.

## Reply templates

- **Agree+fixed:** `Fixed in <short-sha> — <one line: what changed>.`
- **Pushback:** `Checked <file>:<line> — <what the code actually does, concretely>. <Why the suggestion doesn't apply>. Keeping as-is; happy to revisit if I'm missing something.`
- **Question:** `<direct answer>. See <file>:<line>.`
- **Out-of-scope:** `Valid, but out of scope for this PR (<reason>). Can open a follow-up issue if you want it tracked.`

Forbidden: "Good catch!" / "You're right" without a verified fix behind it;
resolving a thread you pushed back on; leaving any non-bot comment unanswered.

## Copilot re-request

After a fix push, Copilot does not re-review automatically. Try ONCE:
`gh api repos/{owner}/{repo}/pulls/{n}/requested_reviewers -f 'reviewers[]=copilot-pull-request-reviewer[bot]'`
On 422 / "Reviews may only be requested from collaborators" (the normal case —
gh cannot request bot reviewers): do NOT retry. Tell the user exactly:
> "gh can't re-request Copilot. On the PR page, right sidebar → **Reviewers**
> → click the ↻ re-request icon next to **Copilot** (or the gear → select
> Copilot if it's not listed). I'll keep watching for the result."
Then keep the watch armed — the review lands as a normal event.

## Closers and expiry

- **Explicit closer** ("stop monitoring and merge", "you can stop monitoring,and merge the PR"): kill the watch, run one final sweep, then — if CLEAN — invoke `/dev-cycle:finish-branch` to perform the merge. finish-branch owns preflight, `mergeStrategy`, and merge-failure remediation; on a clean PR its green path is instant. If DIRTY, list the blockers and ask before invoking it. pr-monitor NEVER merges directly.
- **"stop monitoring"** alone: kill the watch, final sweep, report, no merge.
- **Window expiry:** final sweep (full paginated fetch, ignore cache), then the merge-readiness report:

```
PR #<n> — window closed (<window>, <rounds> rounds, <pushes> pushes)
Comments: <handled> handled (<fixed> fixed, <pushback> pushback, <answered> answered), <ignored> bot-ignored
Checks: <green>/<total> green (<pending> pending)  ·  Review decision: <state>
Threads: <resolved> resolved, <open> open (<list>)  ·  Conflicts: <none|CONFLICTING>
Verdict: CLEAN — ready to merge | DIRTY — <itemized blockers>
```

CLEAN = checks green, no CHANGES_REQUESTED review, no conflicts, not draft,
every non-bot comment answered, no open threads except your own pushbacks.
Then offer: merge now (invokes `/dev-cycle:finish-branch`) or extend the window. Never auto-merge
on expiry, even when preauthorized — expiry is a report, not a go signal.

Pending-check exception: when the ONLY open item at expiry is a pending CI
check, auto-extend the window once by up to 10 minutes — no question. A second
expiry with the check still pending → report and stop; no further extensions.

## Red flags — stop and re-check

- About to reply "you're right" without having read the code → verify first.
- Pushed a commit and moved on without re-arming → dropped round; re-arm.
- Monitor timed out and you treated it as "window over" → it isn't; re-arm.
- About to resolve a thread you disagreed in → leave it open.
- Retrying the Copilot gh request a second time → it will fail again; UI fallback.
