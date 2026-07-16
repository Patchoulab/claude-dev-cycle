---
name: repo-whitepaper
description: Use when asked to build a white paper site, presentation site, narrative/interactive documentation site, or "explain why this repo exists" site from a repository's markdown — including rebuilding or refreshing one, or when a repo containing internal/private content is about to be published as a website.
---

# Repo Whitepaper

## Overview

Turn a repo's markdown corpus into ONE interactive narrative site: thesis-first,
dark-only, mono/editorial, keyboard-navigable, no backend. The output is a
static Astro site verified live before it is called done.

Three artifacts gate the build, in order: an approved **narrative outline**, an
approved **sensitivity decision table**, and a passing **runtime verification
sweep**. Skipping any gate is a failure, not a shortcut.

## When to use

- "Build a white paper / presentation site / interactive docs site for this repo"
- Repo markdown needs to become a public-facing narrative (why it exists, how it works)
- Refreshing a previously generated whitepaper site after the repo changed

**When NOT to use:** API reference docs (docs framework territory), the deploy
step (publishing-sites-to-cloudflare / managing-cloudflare-sites own that),
aesthetic advice for an unrelated project (frontend-design plugin).

## Quick reference

| Phase | Gate | Artifact |
|---|---|---|
| 0 Preflight | Real stack versions resolved from npm | version note in outline header |
| 1 Ingest | User approves narrative | `docs/whitepaper/outline.md` |
| 2 Safety | User approves dispositions; zero unresolved BLOCK | `docs/whitepaper/sensitivity-report.md` |
| 3 Build | All vitest green; aesthetic reference applied | site dir (default `presentation-site/`) |
| 4 Verify | Runtime sweep 100% pass on served `dist/` | `docs/whitepaper/verification/` |
| 5 Handoff | Post-build sweep of `dist/` clean | offer publishing skill |

## Phase 0 — Preflight

1. Read `.claude/dev-cycle.json` if present; use `canonicalRoot` as the one true
   absolute path and the `whitepaper` block for site dir, aesthetic file, brand
   kit, allowlist file. Defaults: site dir `presentation-site/`, aesthetic
   `references/aesthetic-default.md` (bundled), no brand kit.
2. Resolve REAL current versions — never trust a brief, plan, or memory:
   - `npm view astro dist-tags --json`
   - `npm view preact dist-tags --json`
   - `npm view vitest dist-tags --json`
   One command per Bash call. If the user named a version that conflicts with
   npm `latest`, surface the conflict in the Phase 1 question batch; do not
   silently pick either.
3. Read the aesthetic reference file NOW. Every visual decision downstream
   comes from it, not from taste.

## Phase 1 — Ingest and outline

1. Read the markdown corpus: `README.md`, `docs/**/*.md`, `specs/**/*.md`,
   `*.md` at root, plus any paths in `whitepaper.extraSources`. Skip
   `node_modules`, generated dirs, the site dir itself.
2. Extract: the thesis (why the repo exists — the one-sentence reason a
   stranger should care), the system/architecture, the pipeline/flow if one
   exists, key concepts and vocabulary, impact/outcomes.
3. Fill `templates/narrative-outline.md` and write it to
   `docs/whitepaper/outline.md` in the target repo. Every section lists its
   source files and its proposed interactive element. Artifacts go to the
   repo, never dumped in the terminal.
4. Run the Phase 2 sweep BEFORE asking for approval, then batch outline
   approval + sensitivity dispositions + stack confirmation into ONE
   AskUserQuestion call.

Do not start scaffolding before the outline is approved.

## Phase 2 — Sensitive-content sweep

**REQUIRED:** follow `references/sensitive-content-sweep.md` exactly. Summary
of the contract:

- Sweep the source corpus with the pattern classes in the reference; write
  `docs/whitepaper/sensitivity-report.md` with one row per finding:
  masked value, source `file:line`, class, proposed disposition.
- Dispositions: **publish** / **genericize** / **redact** / **BLOCK**.
  Credentials and key material are always BLOCK — and never echoed in chat,
  masked or not beyond the first 4 characters.
- The user decides every non-default row in the Phase 1 question batch.
- Approved rows persist to the allowlist file
  (default `.claude/whitepaper-allowlist.json`) so rebuilds don't re-ask.
- Re-run the sweep against `dist/` after the build. Anything found there that
  is not an approved **publish** row fails the run.

## Phase 3 — Build

Stack: Astro (the major resolved in Phase 0) + Preact islands + vitest.
Static output, mock data only, zero backend, zero external network calls at
runtime (fonts self-hosted).

- Apply the aesthetic reference as law: dark-only (no light mode, no toggle),
  mono-everything typography, token set and contrast floors as specified. If
  `whitepaper.brandKit` points to a brand-kit HTML file, extract its tokens
  per the reference's override procedure; contrast floors still win.
- Interactivity bar (minimum, from the reference): scroll-driven section
  reveals, at least one interactive architecture/pipeline diagram, sequential
  prev/next section navigation with ArrowLeft/ArrowRight, progress indicator,
  keyboard-shortcut overlay. All of it operable without a mouse and sane
  under `prefers-reduced-motion`.
- Each data/logic module ships with a vitest file in the same change.
- Run the build via superpowers (writing-plans → subagent-driven-development)
  for anything beyond trivial size. Every subagent prompt MUST contain the
  canonical absolute repo root and the line: "Do NOT start dev servers or
  browsers; the controller runs live verification separately."

## Phase 4 — Runtime verification

Diff review cannot see hover, focus, keyboard, motion, or contrast. Reviews
that say "cannot verify from diff" are the reason this phase exists.

**REQUIRED:** run the full checklist in `references/runtime-verification.md`
against the built `dist/` served locally, from the controller session, using
Playwright. Any failure → fix → re-run the ENTIRE sweep (fixes regress other
checks). Save screenshots to `docs/whitepaper/verification/`; show the user
rendered images, never raw JSON or dumps. Contrast is verified BOTH ways per
the dev-cycle-wide policy: the automated WCAG-floor check (sweep items
15–16) PLUS the section screenshots surfaced to the user for eyeball
judgment. Both, not either.

The sweep is the definition of done. "Build passed and tests are green" is
not done.

## Phase 5 — Handoff

1. Re-run the sensitivity sweep on `dist/` (Phase 2 contract).
2. Report: outline path, sensitivity summary (n published / genericized /
   redacted), sweep score, screenshot dir.
3. If a deploy integration is installed (e.g. publishing-sites-to-cloudflare
   for a first publish, managing-cloudflare-sites for an existing site), offer
   it; otherwise report that the static site is built in the site dir and stop.
   Do not perform deploy steps yourself.

## Red flags — stop and go back

- A framework version written in a plan that was not read from npm dist-tags today
- "I'll verify interactivity after merge" / "cannot verify from diff" left unresolved
- A light theme, theme toggle, or `prefers-color-scheme: light` branch
- Publishing anything while a BLOCK row is unresolved
- Declaring done without a 100% runtime sweep on served `dist/`
- Raw finding values (IPs, tokens, hostnames) pasted unmasked into chat

## Common mistakes

| Mistake | Fix |
|---|---|
| Pinning the stack from the brief | Phase 0 npm dist-tags, reconcile conflicts with the user |
| Treating the sweep as a grep-and-forget | Decision table + allowlist + post-build re-sweep of `dist/` |
| Dark palette that fails contrast (black-on-charcoal) | Contrast floor is in the sweep; tokens in the reference already pass |
| Subagents spinning up dev servers | Controller-only live verification; say so in every subagent prompt |
| Rebuilding the deploy logic | Hand off to the Cloudflare skills |
