# Bootstrap procedure

Inputs: project directory (must be the intended repo root), repo name (default: directory name, kebab-cased), visibility (default **private**; confirm in the batched question unless `demoPrep.github.visibility` is set), account from `demoPrep.github.account`.

One command per Bash call, in order:

1. `gh auth status` — verify authenticated as the configured account; abort with a clear message otherwise.
2. `gh repo view <account>/<name>` — must FAIL (repo does not exist yet); if it exists, stop and ask.
3. `git -C <dir> rev-parse --git-dir` — detect existing repo; if absent: `git -C <dir> init -b main`.
4. `git -C <dir> remote get-url origin` — must fail (no origin yet); if origin exists, this is not a bootstrap — hand off to normal push flow and say so.
5. Write `README.md` if missing: project name, one-paragraph purpose, stack line, quickstart (`npm ci`, `npm run dev`), presentation-route note if the present phase ran. No badges, no boilerplate walls.
6. Write `CLAUDE.md` if missing: stack + entry points, dev/build/test/preview commands, i18n dictionary location and key-hygiene rule, presentation route. (Equivalent of `/init`, seeded from what demo-prep already knows about the repo.)
7. Write `.gitignore` if missing, stack-appropriate: `gh api /gitignore/templates/Node --jq .source > .gitignore` (template chosen by detected stack: Node, Python, Go, ...; offline fallback: minimal hand-rolled list — `node_modules/`, `dist/`, `.env*`, `*.local`, `.DS_Store`).
8. **Pre-push secret gate** (bootstrap is the last exit before history becomes permanent): `gitleaks detect --source <dir> --redact --no-banner` (fallback: the shared `secret_patterns.grep` per A5 in §5.4). FAIL blocks the push.
9. `git -C <dir> add -A`
10. `git -C <dir> status --porcelain` — show the user what the initial commit will contain (evidence before assertion).
11. `git -C <dir> commit -m "Initial commit: <one-line project description>"`
12. `gh repo create <account>/<name> --private --source <dir> --remote origin --push` (`--public` only on explicit request) — creates the repo, adds `origin`, pushes `main` in a single gh invocation.
13. `gh repo view <account>/<name> --json url,visibility,defaultBranchRef` — confirm and report the URL, visibility, and branch as evidence.
