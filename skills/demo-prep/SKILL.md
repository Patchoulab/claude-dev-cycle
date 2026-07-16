---
name: demo-prep
description: Use when a prototype must be shown to stakeholders - adding an in-app presentation or slide layer, translating an app and its presentation for an audience, verifying a repo is demo-ready (clean history, no secrets, clone-and-run works, both themes and locales render), or creating and pushing a brand-new GitHub repo for a finished prototype.
---

# Demo Prep

## Overview

Turns a working prototype into a stakeholder-ready demo. Four phases,
independently invokable: **present** (interactive slide layer inside the
app — never a separate deck), **localize** (key-based i18n over app +
presentation), **audit** (prove the repo is clean, secret-free, and
clone-and-runnable), **bootstrap** (create the GitHub repo and make the
first push to main).

Core principle: **the demo IS the product.** Slides live inside the app,
reuse its components and theme, and end by dropping into the live UI.

## When to use

- "I'm presenting this tomorrow" / "prepare this for a demo"
- "add a presentation mode" / anything resembling slides for a prototype
- "translate the app (and the presentation) into <lang>" for an audience
- "is the git history clean / can I clone this repo as-is tomorrow?"
- "create a new repo for this in my account and push"

NOT for: building the prototype itself; visual design direction
(frontend-design); deployment (cloudflare skills); routine commits/PRs
(commit-commands).

## Phase router

| Ask sounds like | Phase | Read first |
|---|---|---|
| slides, walkthrough, present, deck | present | references/presentation-template.md |
| translate, bilingual, boot language | localize | references/i18n-pattern.md |
| demo-ready, clean history, clonable | audit | references/audit-checklist.md |
| new repo, first push, gh repo create | bootstrap | references/bootstrap.md |

Full run = present → localize → audit, in that order (slides must exist
before they can be translated; audit always goes last). Bootstrap stands
alone. Skip a phase only when its output verifiably already exists.

## Configuration

Read `.claude/dev-cycle.json` → `demoPrep` when present (audience org, source
and target locales, boot default, GitHub account and visibility, themes,
presentation route). If the block is missing, ask once — one batched
question covering audience, target language(s), boot default, and (for
bootstrap) repo name + visibility. Never hardcode an audience, a language,
or an account.

## House rules (dev-cycle conventions — non-negotiable)

- One command per Bash call; never chain with `&&`, `||`, `&`.
- Absolute paths in every subagent prompt; state the repo root explicitly.
- Evidence before assertion: every audit line is backed by a command run
  in this session and its observed output. No line goes green from memory.
- Secrets are reported as file + line + rule name only; never echo values.
- Scoped writes: present and localize must not refactor app logic; touch
  only what the phase owns and log every change.
- Artifacts to the repo: the audit report is a committed file
  (docs/demo-readiness.md), screenshots are rendered images shown to the
  user, never raw JSON dumps.

## Common mistakes

| Mistake | Fix |
|---|---|
| Building a separate deck (PowerPoint, standalone slide site) | Slides render inside the app behind a route/flag, reusing app components and theme tokens |
| i18n keys derived from English display strings | Semantic keys only (`scopes.create.title`). Typographic characters (curly quotes, guillemets, NBSP) live in VALUES, never in keys |
| Declaring "repo is clean / clonable" without running anything | Run references/audit-checklist.md end to end; a fresh clone in the scratch dir must install, build, test, and render both locales and both themes |
| Checking only the default theme | Both themes get the automated WCAG-floor contrast check PLUS screenshots surfaced to the user (both, not either — dev-cycle contrast policy); a dark-mode contrast defect shipped before when only one net was in place |
| Translating the app but not the presentation (or vice versa) | Coverage check spans both; parity script gates the phase |
| Bootstrap pushing a public repo by default | Private unless dev-cycle.json or the user explicitly says otherwise |
| Rewriting shared history to "clean" it | History rewrites only on solo, pre-demo repos, only with explicit user approval in this session — never from a standing authorization |
