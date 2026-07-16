# Pre-demo audit checklist

Every row = one Bash call (house rule 1), run in order, output captured into `docs/demo-readiness.md` with PASS/FAIL per row. `<repo>` is the canonical absolute root (dev-cycle.json `canonicalRoot` when present); `<scratch>` is the session scratchpad directory.

| # | Check | Exact command(s) — one per Bash call | Pass condition |
|---|---|---|---|
| A1 | Working tree clean | `git -C <repo> status --porcelain` | Empty output |
| A2 | Nothing unpushed | `git -C <repo> log --oneline @{u}..` | Empty output (skip with note if no upstream — pre-bootstrap repo) |
| A3 | No embarrassing commit messages | `git -C <repo> log --format='%h %s' \| grep -iE '\b(wip\|fixup\|squash\|oops\|temp\|tmp\|asdf\|xxx\|revert revert\|do not commit)\b'` | No matches (each match listed verbatim in the report if any) |
| A4 | No secrets in tree or history (primary) | `gitleaks detect --source <repo> --redact --no-banner` | Exit 0, "no leaks found" |
| A5 | Secrets fallback (only if gitleaks absent) | `git -C <repo> log -p --all \| grep -cEf ${CLAUDE_PLUGIN_ROOT}/scripts/secret_patterns.grep` — the shared credential pattern source (owned by review-gate, spec 04; gitleaks-first policy, no private pattern list in this skill) | Count 0. Report matches as commit+file+rule only, never the value |
| A6 | No tracked env files | `git -C <repo> ls-files \| grep -E '(^\|/)\.env(\..+)?$' \| grep -v '\.example$'` | No matches |
| A7 | README present and non-trivial | `wc -l <repo>/README.md` | File exists, ≥ 15 lines |
| A8 | Fresh clone (the "clone as-is tomorrow" proof) | `git clone <origin-url> <scratch>/demo-clone` (no remote yet: `git clone <repo> <scratch>/demo-clone`) | Exit 0 |
| A9 | Clone matches local HEAD | `git -C <scratch>/demo-clone rev-parse HEAD` then compare with `git -C <repo> rev-parse HEAD` (two calls) | Identical hashes |
| A10 | Dependencies install from lockfile | `npm ci` (cwd: clone) — or `pnpm install --frozen-lockfile` / `yarn install --immutable` / `bun install --frozen-lockfile` per detected lockfile | Exit 0 |
| A11 | Build green | `npm run build` (cwd: clone) | Exit 0 |
| A12 | Tests green | `npm test -- --run` (vitest) or the repo's test script (cwd: clone) | Exit 0 (absent test script → reported as WARN, never silently skipped) |
| A13 | App serves | `npm run preview -- --port 4173 --strictPort` (cwd: clone, `run_in_background: true`) then `curl --connect-timeout 5 --max-time 10 -s http://localhost:4173/` | HTTP 200, HTML body |
| A14 | Boot locale correct | Playwright: navigate `http://localhost:4173/`, assert `document.documentElement.lang` equals `demoPrep.locales.bootDefault`, screenshot | Assertion true |
| A15 | All target locales render | Playwright: switch locale via the app's own switcher, screenshot each; assert zero raw i18n keys visible (`grep`-style scan of page text for `presentation.` / dictionary key patterns) | Each locale renders, no key leaks |
| A16 | Both themes render | Playwright: toggle theme via the app's own switch, screenshot light + dark on the app home AND slide 1 and the live-demo slide; run the automated WCAG-floor contrast check on each themed view (adopt repo-whitepaper's contrast helper — spec 08, `references/runtime-verification.md`: body ≥ 4.5:1, large text ≥ 3:1) | Automated contrast floor passes AND screenshots are captured and surfaced to the user for eyeball judgment (spec 00 contrast policy: both, not either — the black-on-charcoal defect class needs both nets) |
| A17 | Presentation route loads | Playwright: navigate the presentation route, ArrowRight through all slides, screenshot first/middle/last | All slides reachable, no console errors |
| A18 | i18n parity | `node ${CLAUDE_PLUGIN_ROOT}/scripts/i18n_parity.mjs <repo>/src/i18n` | Exit 0 |
| A19 | Kill preview server | stop the background task from A13 | Server stopped |

Report: `docs/demo-readiness.md` (committed) — table of rows A1–A19 with PASS/FAIL/WARN, observed output snippets, screenshot references, and a one-line verdict: "Clonable and demo-ready" or the ordered fix list. FAIL on A3–A6 blocks the verdict regardless of everything else.
