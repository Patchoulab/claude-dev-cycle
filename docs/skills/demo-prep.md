# demo-prep

**Purpose** — Turns a working prototype into something you can put in front of stakeholders. It adds an in-app presentation layer (slides that live inside the app, not a separate deck), localizes the app and its slides with strict key-hygiene enforcement, and runs a pre-demo audit that proves the repo is clean, secret-free, and clone-and-runnable. A separate `new-repo` ceremony bootstraps a fresh GitHub repository and makes the first push. Core principle: the demo *is* the product, so slides reuse the app's own components and theme and drop into the live UI.

## Invocation

Run `/dev-cycle:demo-prep` with a phase:

- `present` — build the in-app presentation layer.
- `localize` — translate the app and presentation for an audience.
- `audit` — verify the repo is demo-ready.

Run `/dev-cycle:demo-prep:new-repo` for the bootstrap ceremony (create the repo, first push to `main`).

A full run is `present → localize → audit`, in that order: slides must exist before they can be translated, and the audit always goes last. Bootstrap stands alone. Skip a phase only when its output verifiably already exists.

## Contract

| Phase | Inputs | Outputs |
|---|---|---|
| present | Working app; narrative for the audience | Interoperable slide layer mounted behind a route/flag, built from the shipped templates, reusing app components, theme tokens, and providers. Includes a live-demo slide that drops into the real UI. |
| localize | Source dictionary; target locale(s); boot default | Per-locale dictionaries with identical key sets covering app *and* presentation, ASCII semantic keys, NFC-normalized files, no empty or untranslated values. Parity enforced by `i18n_parity.mjs`. |
| audit | The repo, plus a fresh clone in scratch | Committed `docs/demo-readiness.md` proving: clean working tree and history, no secrets, README present, clone installs/builds/tests, app serves, both locales render with no leaked keys, both themes render and pass the WCAG-floor contrast check, presentation route loads. |
| new-repo | Project directory; repo name; visibility | `gh repo create` plus first commit and push to `main`, seeded with README, CLAUDE.md, and a stack-appropriate `.gitignore`. Reports the URL, visibility, and default branch as evidence. |

### The presentation narrative

The default deck is eight slides: a five-beat spine (problem, status quo, solution, benefits, roadmap) between a title/close bookend, plus an auto-assembled executive summary slide that cannot drift from the deck. The solution slide is a live-demo slide that enters the real app with a spotlight-and-caption overlay. Navigation supports chevrons, arrow keys, jump dots, and digit keys. Non-React stacks degrade gracefully to the same slide order and keyboard contract; a standalone deck is treated as a phase failure.

### Key hygiene (localize)

Keys are semantic identifiers (`scopes.create.title`), never derived from display strings, and contain only `[a-z0-9._-]`. All typographic characters — curly apostrophes, guillemets, narrow no-break spaces — live in *values* only. Every lookup goes through one `t()` entry point that falls back to the source locale and finally to the key itself, so any gap shows up visibly in the audit render check instead of failing silently.

## Config keys

Read from `.claude/dev-cycle.json` under the `demoPrep` block. If it is missing, the skill asks once with a single batched question. Nothing about the audience, language, or account is ever hardcoded.

| Key | Holds |
|---|---|
| `audience` | The audience organization the demo is framed for (for example, a regional insurer). |
| `locales` | Source locale, target locale(s), and `bootDefault` — the locale the app opens in. |
| `themes` | The theme set that must render and pass contrast (light and dark by default). |
| `presentation` | Presentation `route` (default `/present`) and related layer settings. |
| `github` | `account` and `visibility` for the bootstrap ceremony. |
| `audit` | Audit configuration used by the readiness checklist. |

## Prerequisites

- **git** — required for every phase.
- **gh CLI**, authenticated — required for `new-repo`.
- **node** — required for the i18n parity check (`i18n_parity.mjs`).
- **gitleaks** — optional; the audit uses it as the primary secret scan and falls back to a shared credential-pattern list if it is absent.
- **Playwright MCP** — optional; used by the audit to drive the app and capture locale/theme/presentation screenshots.

## Failure modes & remediation

| Symptom | Cause | Remediation |
|---|---|---|
| i18n parity gate exits 1 | Mismatched key sets, non-ASCII keys, empty or untranslated values, or non-NFC files | Read the parity output; fix the offending dictionary. Keep typographic characters in values, keys semantic ASCII. Re-run the gate until it exits 0. |
| Secrets found in audit | A credential is present in the tree or history | The finding is reported as file, line, and rule name only — never the value. Remove the secret, rotate it, purge from history if needed, and re-run. FAIL here blocks the readiness verdict outright. |
| Contrast defect | A themed view falls below the WCAG floor (body 4.5:1, large text 3:1) | The audit checks *both* themes with the automated floor and surfaced screenshots. Fix the theme tokens for the failing view; dark-mode defects have shipped before when only one net was in place. |
| Dirty history | Working tree not clean, unpushed commits, or embarrassing commit messages (`wip`, `fixup`, `temp`) | Commit or stash, push, and reword as needed. History rewrites happen only on solo pre-demo repos, only with explicit approval in the session — never from a standing authorization. |
| Slides drift into a separate deck | Built outside the app | Slides must render inside the app behind a route or flag, reusing its components and theme. Rebuild against the shipped templates. |

## Optional integrations

- **frontend-design** — for visual direction when the presentation layer needs aesthetic guidance; demo-prep handles structure, not design taste.
- **Cloudflare publishing skills** — for deploying the prototype after it passes the audit; demo-prep does not deploy.
- **gitleaks** — as the primary secret scanner; without it, the audit falls back to a shared secret-pattern list.
