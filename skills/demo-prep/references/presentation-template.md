# Presentation-mode structural template

## Narrative contract — the 5-beat spine plus bookends (8 slides default)

| # | Slide id | Kind | Content contract |
|---|---|---|---|
| 1 | `title` | content | Product name, one-line value proposition, audience/date |
| 2 | `problem` | content | The business problem, in the audience's terms |
| 3 | `status-quo` | content | Why existing approaches fail (2–4 named alternatives, each with its gap) |
| 4 | `solution` | live-demo | The proposed solution; hosts the guided-demo overlay entry ("Enter the app") |
| 5 | `benefits` | content | Concrete benefits mapped back to slide 2's problem statements |
| 6 | `roadmap` | content | Now / next / later, 3 columns max |
| 7 | `summary` | summary | Executive summary: one sentence per beat, auto-assembled from slides 2–6 titles + leads |
| 8 | `close` | content | Ask / next step / contact |

## Component contract (`templates/slides.template.ts`)

```ts
import type { ComponentType } from 'react';

export type SlideKind = 'content' | 'live-demo' | 'summary';

export interface Slide {
  id: string;                 // stable ASCII id, doubles as i18n namespace: presentation.<id>.*
  kind: SlideKind;
  titleKey: string;           // e.g. 'presentation.problem.title'
  leadKey: string;            // one-sentence lead used verbatim by the summary slide
  body: ComponentType;        // reuses APP components (cards, badges, charts) — no new design system
  demoSteps?: DemoStep[];     // only for kind: 'live-demo'
}

export interface DemoStep {
  target: string;             // CSS selector in the live app
  captionKey: string;         // i18n key for the callout text
}

export const slides: Slide[] = [
  /* one entry per row of the narrative contract table */
];
```

## Shell contract (`templates/PresentationMode.template.tsx`) — the template ships complete and compiling; behavioral contract

```tsx
// PresentationMode: full-screen layer mounted at the presentation route.
// State: currentIndex (number), overlayActive (boolean), overlayStep (number).
// Renders: slides[currentIndex].body inside the app's ThemeProvider and
//          I18nProvider — the SAME providers the app uses, never copies.
//
// Navigation (all three always available):
//   prev/next : on-screen chevrons + ArrowLeft/ArrowRight + Space (next)
//   jump      : progress dots (one per slide, click to jump) + digit keys 1–9
//   bounds    : Home → first slide, End → last, Esc → exit to app
//
// Progress indicator: dot row, current slide filled, doubles as jump menu;
//   aria-label "Slide {n} of {total}".
//
// Guided-demo overlay (kind: 'live-demo'):
//   "Enter the app" button unmounts the deck chrome and mounts the REAL app
//   with a step overlay: dimmed backdrop, spotlight cutout on
//   demoSteps[overlayStep].target, caption from captionKey, prev/next step
//   buttons, "Back to slides" returns to the same slide index.
//
// Summary slide (kind: 'summary'): assembled at render time from
//   slides.filter(content beats).map(titleKey + leadKey) — never hand-copied,
//   so it cannot drift from the deck.
//
// Every visible string goes through t(); zero literals in JSX.
```

## Integration checklist (React/Vite default)

1. Mount behind a dedicated route (`/present`, configurable via `demoPrep.presentation.route`) or `?present=1` query flag; entry affordance is a discreet footer link or keyboard shortcut, not a primary nav item.
2. `React.lazy` + dynamic import for the presentation chunk so app startup is unaffected.
3. Reuse the app's theme tokens, ThemeProvider, and I18nProvider; the theme switch must work inside the deck.
4. All slide copy keyed under `presentation.*` in the same dictionaries as the app.
5. Slide bodies import real app components (the actual card, the actual scope list) with mock props — the audience sees the product's own visual language.
6. Verify keyboard navigation and both themes with Playwright screenshots before declaring the phase done.

## Graceful degradation (non-React stacks)

- Any SPA framework (Vue/Svelte/Astro islands): same file contract (slides manifest + shell component), same keyboard/navigation contract, framework-native syntax.
- Server-rendered or static stacks: a single `/present` page of full-viewport `<section>`s with CSS `scroll-snap`, the same slide order, a small vanilla-JS controller implementing the identical keyboard contract, styled with the app's own stylesheet.
- Last resort (no framework, no build): `public/present.html` linking the app's compiled CSS. The one thing that never degrades: it ships inside the repo and reuses the app's styling. A separate deck is a phase failure.
