# pr-monitor

**Purpose** — Keep one pull request under a bounded watch for a fixed time window. As new comments, reviews, and check results arrive, pr-monitor triages each one, verifies claims against the actual code, batches genuine fixes into a single push per round, replies to every non-bot comment, and re-arms. When the window closes it produces a merge-readiness report. It never merges on its own.

## Invocation

```
/dev-cycle:pr-monitor [PR-ref] [window]
```

Both arguments are optional. Omit the PR reference to watch the PR for the current branch. The window defaults to `15m` and accepts `15m`, `30m`, `1h`, or a bare number read as minutes. The window is wall-clock: it starts when you invoke the skill and re-arming never extends it.

## Contract

1. **Resolve the PR.** Use the argument if given, otherwise look up the PR for the current branch.
2. **Parse the window** and record the fixed end time.
3. **Load config** from `.claude/dev-cycle.json` if present.
4. **Seed the baseline.** Record the head SHA and the IDs of all existing comments, review comments, reviews, and check runs into `.git/dev-cycle/pr-monitor/<pr>.json`. Any existing unanswered non-bot comments are backlog and get triaged before the watch arms.
5. **Run per-event rounds.** On each new event: fetch everything new since the baseline, triage each item, batch all verified fixes into one fix subagent (lettered A, B, C…), push once, reply to every triaged comment, then re-seed the baseline and re-arm. A push without a re-arm is a dropped round.
6. **Report on close.** When the window expires or the user stops the watch, run a final sweep and emit the merge-readiness report.

pr-monitor never merges directly. On a clean closer it hands the merge off to finish-branch.

**Evidence before agreement.** Every reviewer claim, human or bot, is verified against the code before any fix or reply. A claim the code contradicts earns a pushback with concrete file-and-line reasoning, not a performative "good catch." Copilot findings get the same scrutiny as human ones.

## Config keys

Read from `.claude/dev-cycle.json`:

| Key | Purpose | Default |
|---|---|---|
| `botsToIgnore` | Bot logins whose comments are skipped (still counted in the report) | `["vercel[bot]"]` |
| `preauthorized` | Actors whose input needs no extra confirmation | none |
| `canonicalRoot` | Absolute repo root passed to fix subagents | inferred |
| `prMonitor.speak` | Speak activity and expiry aloud when claude-speak is available | `false` |

## Prerequisites

- **git** — branch resolution and state directory.
- **gh CLI**, authenticated — reads PR comments, reviews, and check runs.
- **jq** — required by the fallback poller.

For the watch itself, pr-monitor prefers the harness Monitor tool, which waits on new comments, reviews, or failed checks for the remaining window. When Monitor is unavailable it falls back to background polling via `pr_monitor_poll.sh`, which fires one event per exit and is relaunched each round. A Monitor timeout is noise, not completion: always re-arm.

## Failure modes and remediation

| Situation | What happens | Remediation |
|---|---|---|
| No PR for the branch | Stops before arming | Open one first with commit-push-pr, or `gh pr create` |
| Ambiguous / multiple PRs | Cannot pick a target | You are asked which PR to watch |
| Draft PR | Warns, watches anyway, refuses to merge | Mark ready for review before requesting a merge |
| Window expires with work open | Emits a DIRTY report listing blockers | Fix the blockers, or re-invoke with a fresh window |
| Only a pending CI check at expiry | Auto-extends once by up to 10 minutes | On a second expiry still pending, it reports and stops |

## Optional integrations

- **Opening the PR** — uses commit-commands:commit-push-pr when installed, otherwise `gh pr create`.
- **Review discipline** — uses superpowers:receiving-code-review when installed; otherwise applies its core rule of verifying each claim against the code before acting.
- **Spoken updates** — with `prMonitor.speak` enabled and claude-speak available, announces activity and expiry in one short line; silent by default.
- **Merging** — on a clean closer, hands off to `/dev-cycle:finish-branch`, which owns preflight, merge strategy, and merge-failure remediation. pr-monitor never merges itself, even when the window expires clean; expiry is a report, not a go signal.
