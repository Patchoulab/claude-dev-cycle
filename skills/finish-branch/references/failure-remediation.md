# Push / merge failure remediation

## Remote-rejected: missing OAuth `workflow` scope
Symptom: push rejected with "refusing to allow an OAuth App to create or update
workflow `.github/workflows/...` without `workflow` scope".
1. `gh auth refresh -h github.com -s workflow` — run in background (device flow
   blocks); poll output with a 60 s stall threshold.
2. It prints a one-time code (XXXX-XXXX) and https://github.com/login/device.
   Relay BOTH to the user immediately and wait for the command to exit 0.
3. Retry the exact failed push once. Still rejected → report verbatim stderr, stop.
Never paste tokens; never suggest a PAT in chat.

## gh auth expired / 401 on any gh call
`gh auth status` → report; `gh auth login` is the user's move (device flow relay
as above if he says go). Do not retry in a loop.

## Non-fast-forward push rejection
`git -C <repo> pull --rebase origin <branch>` once → re-push once. Rebase
conflicts → `git -C <repo> rebase --abort`, report divergent commits
(`git log --oneline origin/<branch>..<branch>` and the reverse), stop. No force.

## Protected branch rejects direct push
Report the protection rule (`gh api repos/{owner}/{repo}/branches/<branch>/protection`
when readable). The submodule-pointer bump then needs its own PR → route to
commit-commands:commit-push-pr (or `gh pr create`) with the staged bump; finish-branch resumes at
Phase 5 after that PR merges.

## Unfetched submodule commits (`fatal: Invalid revision range`, unknown SHA)
The parent references submodule commits not present locally:
1. `git -C <abs-submodule> fetch origin`
2. Missing still? `git -C <parent> submodule update --init <path>` (init only;
   never `--force`), then retry the failed command once.

## Merge conflict on the PR (mergeable: CONFLICTING)
`gh pr update-branch <n>` (with user's nod unless preflight already offered it) →
re-run preflight once. Still conflicting → list conflicted files from
`gh pr view` / checks output and hand back. finish-branch never edits conflict
markers.
