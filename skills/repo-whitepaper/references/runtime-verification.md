# Runtime Verification Sweep

Run by the CONTROLLER session (never subagents) against the production
build. Precondition: `npm run build` succeeded and vitest is green.

Serve: `npm run preview` in the background (or `npx serve dist`), one
command per Bash call, with a stall threshold; confirm the port answers
before navigating.

Execute with Playwright (MCP browser tools or a scripted spec — same
checklist either way). ALL items must pass; one failure → fix → re-run the
entire sweep from item 1.

## Checklist

**Console & network**
1. Every page/section loads with zero console errors and zero failed requests.
2. Zero requests to non-localhost origins (self-hosted fonts rule).

**Dark-only**
3. `getComputedStyle(document.documentElement).colorScheme` is "dark"; no
   light-theme flash on load; `<meta name="theme-color">` present.
4. No theme toggle exists anywhere in the DOM.

**Keyboard**
5. Tab reaches every interactive element; order follows visual order.
6. Focus is always visible: for each focusable, focus it and assert a
   non-zero outline/box-shadow via getComputedStyle.
7. ArrowRight/ArrowLeft (and j/k) traverse sections sequentially; progress
   indicator updates.
8. Composite widgets (diagram nodes, tab strips) implement roving tabindex:
   exactly one member with tabindex="0", arrows move the active member,
   Enter/Space activates. (The missing WAI-ARIA tabs pattern was a real
   shipped defect — verify, don't assume.)
9. `?` opens the shortcut overlay; Escape closes it and returns focus to the
   invoker.

**ARIA**
10. Every `role` attribute value is a valid WAI-ARIA role (an invalid role
    shipped once; check the literal strings).
11. Every `aria-labelledby`/`aria-describedby`/`aria-controls` references an
    existing id.
12. Landmarks: exactly one `main`; nav landmarks labeled; headings nest
    without level skips.

**Reduced motion**
13. Reload with `prefers-reduced-motion: reduce` emulated: no running
    animations/transitions > 0.05s, ambient canvas paused.
14. Under reduced motion, scroll to the bottom: every section's content is
    fully visible — nothing trapped at opacity 0 by a disabled reveal.

**Contrast (the black-on-charcoal gate)**
15. For every visible text node: resolve computed color and effective
    background (walk ancestors to the first non-transparent
    background-color; composite alpha), compute the WCAG 2.x ratio.
    Body text ≥ 4.5:1; large text ≥ 3:1. Evaluate per section, including
    states after reveals have fired.
16. Repeat 15 on hover/focus states of nav and diagram nodes.

Contrast policy (spec 00, shared with demo-prep): the automated floor above
PLUS the item-20 screenshots surfaced to the user for eyeball judgment.
Both, not either — the automated check never replaces the human look, and
the human look never replaces the automated check.

**Interaction parity**
17. Every hover-revealed detail is also reachable via focus and via click/tap.
18. The interactive diagram: click a node → detail panel; keyboard-activate
    the same node → same panel.

**Responsive**
19. At 390px and 1440px widths: no horizontal overflow
    (documentElement.scrollWidth <= innerWidth), nav operable, diagram
    degrades to an operable (possibly stacked) form.

**Evidence**
20. Screenshot every section at both widths →
    `docs/whitepaper/verification/<section>-<width>.png`; render them for
    the user (never raw JSON/dump output).
21. Write `docs/whitepaper/verification/sweep.md`: checklist × pass/fail ×
    evidence pointer, plus the served URL and commit hash swept.

Contrast helper (browser_evaluate), abbreviated:

const ratio = (fg, bg) => { const L = c => { const s = c.map(v => v/255)
  .map(v => v <= .03928 ? v/12.92 : ((v+.055)/1.055)**2.4);
  return .2126*s[0] + .7152*s[1] + .0722*s[2]; };
  const [a, b] = [L(fg), L(bg)].sort((x, y) => y - x);
  return (a + .05) / (b + .05); };
// walk text nodes, parse rgb() of color + effective background, assert
// ratio >= (largeText ? 3 : 4.5), report offenders as selector + ratio.
