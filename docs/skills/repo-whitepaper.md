# repo-whitepaper

**Purpose** — Turn a repository's scattered markdown corpus into one dark, monospace, editorial, keyboard-navigable narrative site that explains why the repo exists and how it works. The output is a static Astro + Preact build with no backend, mock data only, and zero external runtime requests. Nothing ships until a live runtime sweep confirms the built output actually behaves, not just compiles.

## Invocation

Run `/dev-cycle:repo-whitepaper`. An optional argument names the target repository; with no argument the skill operates on the current repo. The skill also activates on intent, such as asking to build a whitepaper, presentation, or interactive-docs site for a repo, or when a repo holding internal content is about to be published as a website.

## Contract

The build is gated by ordered phases. Each gate is a hard stop, not a suggestion, and two of them require the user's explicit approval.

- **Preflight.** Resolve the real, current versions of Astro, Preact, and vitest from npm dist-tags today. Briefs, plans, and memory are never trusted for versions. Read the aesthetic reference before any visual decision is made. If a user-named version conflicts with npm's latest, that conflict is surfaced for the user to settle, never silently chosen.
- **Ingest + outline.** Read the markdown corpus, extract the thesis, architecture, pipeline, key concepts, and impact, and write a narrative outline to the target repo. Every section lists its source files and its proposed interactive element. The outline must be approved before any scaffolding begins.
- **Sensitivity sweep.** Sweep the source corpus for sensitive patterns and record every finding with a proposed disposition. The user rules on every non-default row, and the run cannot proceed with any unresolved BLOCK. Outline approval, sensitivity dispositions, and stack confirmation are batched into a single question.
- **Build.** Scaffold the static site with the resolved stack. Each data or logic module ships with its vitest file in the same change, and the full suite must be green. The aesthetic reference is applied as law, including the minimum interactivity bar.
- **Runtime verification.** Serve the built `dist/` locally and run the full Playwright sweep from the controller session. Any failure means fix and re-run the entire sweep from the top, because fixes regress other checks. A 100% pass is the definition of done — "build passed, tests green" is not.
- **Handoff.** Re-sweep the built `dist/` for sensitive content, report the outline path, sensitivity summary, sweep score, and screenshot directory, then offer a deploy integration if one is installed.

## Config keys

Configuration lives in a `whitepaper` block inside the repo's dev-cycle config file. All keys are optional and fall back to sensible defaults.

| Key | Meaning |
|---|---|
| `siteDir` | Where the site is generated (default `presentation-site/`) |
| `aesthetic` | Path to the aesthetic reference that governs the look |
| `brandKit` | Optional brand-kit HTML/CSS file whose tokens override defaults |
| `allowlistFile` | Where approved sensitivity decisions persist (default `.claude/whitepaper-allowlist.json`) |
| `extraSources` | Additional markdown paths to fold into the corpus |
| `excludeSources` | Corpus paths to skip |
| `publishSkill` | The deploy integration to offer at handoff |

The default look ships bundled at `references/aesthetic-default.md`: dark only with no light mode or toggle, monospace everything, a fixed token set with enforced contrast floors, and self-hosted fonts. Point `aesthetic` at your own reference file to swap the entire look. When `brandKit` is set, its palette and voice are mapped onto the token names, but the contrast floor always outranks the brand.

## Prerequisites

- Node and npm, for the Astro / Preact / vitest toolchain.
- The Playwright MCP browser tools, used by the controller session for runtime verification against the served build.
- gitleaks is optional; when present it runs first for credential detection during the sensitivity sweep, otherwise a bundled pattern fallback is used.

## Failure modes and remediation

| Symptom | What it means | Remediation |
|---|---|---|
| Unresolved BLOCK row at handoff | A credential or forbidden value is still present in some form | Resolve every BLOCK before Phase 5; for a live credential, report the masked location, recommend rotation, and refuse handoff until cleared |
| Stack version taken from the brief | A framework version was written from a plan or memory, not npm | Re-resolve from npm dist-tags today and reconcile any conflict with the user |
| Runtime sweep failures | Hover, focus, keyboard, motion, or contrast behavior is broken in the served build | Fix the defect, then re-run the entire sweep from item one, since fixes regress other checks |
| Real finding values pasted into chat | An IP, hostname, or secret was echoed unmasked | Never echo raw finding values; credentials are masked beyond the first four characters and never repeated in chat |
| Dark palette fails contrast | Near-black text lands on a charcoal surface | The contrast floor is enforced by the sweep; adjust the token (lighten the foreground first), not the individual page |

## Optional integrations

Deployment is deliberately out of scope for this skill. When a Cloudflare publishing integration is installed, the handoff offers it — first-publish flow for a new site, existing-site flow for an update — but never performs deploy steps itself. When no deploy integration is present, the static site is left built in the site directory and the skill stops there. For aesthetic direction on an unrelated project, the frontend-design plugin is the right tool; this skill's aesthetic reference governs only the whitepaper build.
