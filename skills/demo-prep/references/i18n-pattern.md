# i18n pattern & key hygiene

## Dictionary pattern (TypeScript default; JSON for non-TS stacks)

```ts
// src/i18n/en.ts — source locale
export const en = {
  'app.title': 'Knowledge Scope Manager',
  'scopes.create.title': 'Create a scope',
  'scopes.create.hint': 'Choose the sources this scope can see.',
  'presentation.problem.title': 'The problem',
  'presentation.problem.lead': 'Enterprise AI answers are only as good as their scope.',
} as const;

export type I18nKey = keyof typeof en;
```

```ts
// src/i18n/fr.ts — every key present, values fully translated
import type { I18nKey } from './en';
export const fr: Record<I18nKey, string> = {
  'app.title': 'Gestionnaire de portées de connaissances',
  'scopes.create.title': 'Créer une portée',
  'scopes.create.hint': 'Choisissez les sources visibles par cette portée.',
  'presentation.problem.title': 'Le problème',
  'presentation.problem.lead': 'Les réponses de l’IA en entreprise ne valent que par leur portée.',
};
```

```ts
// src/i18n/index.ts — single lookup entry point
import { en } from './en';
import { fr } from './fr';

const dictionaries = { en, fr } as const;
export type Locale = keyof typeof dictionaries;

export const BOOT_LOCALE: Locale =
  (import.meta.env.VITE_BOOT_LOCALE as Locale) ?? 'fr'; // set per demoPrep.locales.bootDefault

export function t(key: keyof typeof en, locale: Locale): string {
  return dictionaries[locale][key] ?? dictionaries.en[key] ?? key; // key echo = visible bug, caught by audit A15
}
```

## Key hygiene rules

**Key hygiene rules** (each one root-caused from the observed `fr.ts` curly-quote churn, where lookups failed because keys were derived from English display strings and the strings' apostrophes flipped between `'` and `’` across files):

1. **Keys are semantic identifiers, never display text.** `scopes.create.title`, not `"Create a scope"`. A key contains only `[a-z0-9._-]`. This makes the curly-vs-straight failure class structurally impossible.
2. **Typographic characters live in values only.** Curly quotes, apostrophes (`’`), guillemets (`« »`), and non-breaking spaces are correct and encouraged in French *values*; they are forbidden in keys by rule 1 and enforced by the parity script.
3. **Migrating a legacy text-keyed dictionary:** generate semantic keys, keep a one-commit codemod that rewrites call sites, delete the text keys. Never "fix" by matching quote styles across files; that is the churn, not the cure.
4. **One `t()` entry point.** No component indexes a dictionary object directly; missing keys fall back to the source locale and finally to the key itself so gaps are *visible* in the audit render check, never silent.
5. **NFC everywhere:** dictionary files are saved NFC-normalized (the parity script verifies) so composed/decomposed accent variants cannot split keys or values.
6. **Full coverage means app + presentation.** `presentation.*` keys live in the same dictionaries and are checked by the same parity gate.

## French typography QA (the translation QA pass — the user will not proofread)

- `« citation »` with narrow no-break space (U+202F) inside guillemets; NBSP before `: ; ! ?`.
- Apostrophe is `’` (U+2019) in values, never `'`.
- Sentence-case headings (French does not Title Case).
- Terminology consistency: one French term per English term across the whole dictionary (build a mini-glossary first: scope → « portée », everywhere).
- A dedicated proofread subagent reads only `fr.ts` (absolute path in the prompt) and returns spelling/agreement/anglicism findings; scoped writes — it patches only proven errors and logs each.

## Boot-locale default

Wire `BOOT_LOCALE` (env-overridable, default from `demoPrep.locales.bootDefault`), set `<html lang>` accordingly on boot (audit A14 asserts it), keep the in-app locale switcher visible so the presenter can flip to English live.

## Parity gate

Parity gate: `${CLAUDE_PLUGIN_ROOT}/scripts/i18n_parity.mjs`

The script (ships tested) validates: (1) key sets identical across locales, (2) keys are semantic ASCII, (3) no untranslated (identical-to-source) values except an allowlist, (4) files are NFC-normalized, (5) no empty values. Invoked as:

```bash
node ${CLAUDE_PLUGIN_ROOT}/scripts/i18n_parity.mjs <repo>/src/i18n
```

Exits 0 on pass, 1 on any drift or hygiene violation.
