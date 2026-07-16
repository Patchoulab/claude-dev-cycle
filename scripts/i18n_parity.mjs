#!/usr/bin/env node
// i18n_parity.mjs <i18n-dir> — exits 1 on any drift or hygiene violation.
// Checks: (1) key sets identical across locales, (2) keys are semantic ASCII,
// (3) no untranslated (identical-to-source) values except an allowlist,
// (4) files are NFC-normalized, (5) no empty values.
import { readFileSync, readdirSync } from 'node:fs';
import { join, basename } from 'node:path';

const dir = process.argv[2];
if (!dir) { console.error('usage: i18n_parity.mjs <i18n-dir>'); process.exit(2); }

const SAME_OK = new Set(['app.title']); // brand names may match across locales
const KEY_RE = /^[a-z0-9]+(?:[._-][a-z0-9]+)*$/;
const files = readdirSync(dir).filter(f => /^[a-z]{2}(-[A-Z]{2})?\.(ts|json)$/.test(f));
if (files.length < 2) { console.error(`need >=2 locale files in ${dir}, found ${files.length}`); process.exit(1); }

let failed = false;
function fail(msg) { console.error(`PARITY FAIL: ${msg}`); failed = true; }

const locales = {};
for (const f of files) {
  const raw = readFileSync(join(dir, f), 'utf8');
  if (raw !== raw.normalize('NFC')) fail(`${f}: file is not NFC-normalized`);
  const entries = {};
  // Matches 'key': 'value' | "key": "value" | 'key': `value` pairs in TS/JSON dictionaries.
  const re = /(['"])((?:(?!\1).)+)\1\s*:\s*(['"`])((?:\\.|(?!\3).)*)\3/g;
  let m;
  while ((m = re.exec(raw)) !== null) entries[m[2]] = m[4];
  locales[basename(f).split('.')[0]] = entries;
}

const names = Object.keys(locales);
const source = locales.en ? 'en' : names[0];
const sourceKeys = new Set(Object.keys(locales[source]));

for (const key of sourceKeys) if (!KEY_RE.test(key))
  fail(`${source}: non-semantic key ${JSON.stringify(key)} (keys must be [a-z0-9._-], no display text)`);

for (const name of names) {
  if (name === source) continue;
  const keys = new Set(Object.keys(locales[name]));
  for (const k of sourceKeys) if (!keys.has(k)) fail(`${name}: missing key '${k}'`);
  for (const k of keys) if (!sourceKeys.has(k)) fail(`${name}: extra key '${k}' not in ${source}`);
  for (const k of keys) {
    if (!locales[name][k]) fail(`${name}: empty value for '${k}'`);
    if (sourceKeys.has(k) && locales[name][k] === locales[source][k] && !SAME_OK.has(k))
      fail(`${name}: '${k}' identical to ${source} (untranslated?)`);
  }
}

if (failed) process.exit(1);
console.log(`i18n parity OK: ${names.join(', ')} — ${sourceKeys.size} keys`);
