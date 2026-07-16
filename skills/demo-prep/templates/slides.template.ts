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
