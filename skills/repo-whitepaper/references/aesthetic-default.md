# Aesthetic Reference — default whitepaper look

This file is the default LAW for repo-whitepaper builds: a dark, monospace,
editorial look. It is deliberately opinionated and deliberately replaceable —
point `whitepaper.aesthetic` in `.claude/dev-cycle.json` at your own reference
file to swap the entire look.

## Non-negotiables

1. **Dark only.** No light mode, no toggle, no `prefers-color-scheme: light`
   branch. Set `color-scheme: dark` on `:root` and
   `<meta name="theme-color" content="#0B0E14">`.
2. **Mono-everything.** Body, headings, UI chrome — all monospace. Pure
   terminal, editorial scale.
3. **Contrast floor.** Body text ≥ 4.5:1 against its effective background;
   headings/large text (≥ 24px or ≥ 18.5px bold) ≥ 3:1. This floor outranks
   any brand kit. A token pair that fails is adjusted (lighten foreground
   first) and the adjustment logged in the build notes.
4. **Self-hosted fonts.** No font CDNs; the site makes zero external
   requests at runtime.

## Tokens (CSS custom properties)

--bg-0:      #0B0E14;   /* page */
--bg-1:      #121826;   /* card / surface */
--bg-2:      #1A2233;   /* raised / hover surface */
--border:    #26304A;
--text-1:    #E6EDF3;   /* body — 15.2:1 on bg-0 */
--text-2:    #9AA7B4;   /* muted — 7.4:1 on bg-0; never for body-length copy on bg-2 */
--accent:    #7EE787;   /* terminal green — links, active nav, cursor motifs */
--accent-2:  #79C0FF;   /* secondary — diagram highlights, code keys */
--warn:      #FFB86B;   /* callouts */
--focus:     #7EE787;   /* 2px solid outline, 2px offset, always visible */

Forbidden pair (the black-on-charcoal defect): any text at or darker than #1A2233 on
--bg-0/--bg-1. If a computed heading color resolves near-black on a charcoal
surface, that is the black-on-charcoal defect — fix the token, not the page.

## Typography

- Stack: "JetBrains Mono", "IBM Plex Mono", ui-monospace, "SF Mono", Menlo,
  monospace. Ship JetBrains Mono woff2 (400/500/700) in `public/fonts/`.
- Scale: h1 `clamp(2.5rem, 6vw, 4.5rem)` weight 700, letter-spacing -0.02em;
  h2 `clamp(1.75rem, 3.5vw, 2.5rem)`; body 1rem/1.7; captions 0.8125rem.
- Eyebrow labels above sections: 0.75rem, uppercase, letter-spacing 0.18em,
  --text-2, prefixed with a section index like `01 /`.
- Prose measure: max 72ch.

## Interactivity bar (minimum to call it "extremely interactive")

1. **Scroll-driven reveals**: sections enter with opacity/translateY via
   IntersectionObserver. Under `prefers-reduced-motion: reduce`, reveals are
   instant — content must NEVER be trapped at opacity 0.
2. **One interactive diagram minimum** (architecture or pipeline): nodes are
   real buttons — hover AND focus show the same detail panel, Enter/Space
   activates, arrow keys move between nodes (roving tabindex).
3. **Sequential navigation**: prev/next controls, ArrowLeft/ArrowRight (and
   j/k) move between sections; a progress rail shows position; `?` opens a
   keyboard-shortcut overlay; Escape closes overlays.
4. **Live texture**: at least one ambient generative element (canvas
   particles, typing cursor, scan-line header). Deterministic PRNG
   (mulberry32-style) so vitest can assert on it; paused under reduced
   motion; never intercepts pointer events.
5. **No dead hover**: any information shown on hover is also reachable by
   focus and by touch.

## Brand-kit override procedure

If `whitepaper.brandKit` is set (an HTML/CSS design-kit file, e.g.
`design/brand-kit.html`):

1. Read the file; extract CSS custom properties, font-family declarations,
   and logo/wordmark assets.
2. Map extracted values onto the token names above; unmapped tokens keep
   the defaults.
3. Re-verify every text/background pair against the contrast floor; adjust
   failures and log each adjustment.
4. Treat the kit as inspiration for motifs, not markup to copy: extract the
   palette and voice, re-implement components natively in Astro/Preact.
