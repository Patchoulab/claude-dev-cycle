# Sensitive-Content Sweep

Runs twice per build: (A) on the source corpus before authoring, (B) on the
built `dist/` before handoff. Output: `docs/whitepaper/sensitivity-report.md`
plus an updated allowlist file.

## Pattern classes

Run each as a separate Grep/rg pass over the corpus (pass A) or `dist/`
(pass B). One command per Bash call. Credential detection (class 5) follows
the shared dev-cycle policy: gitleaks-first, `scripts/secret_patterns.grep`
fallback — no divergent list here. Classes 1–4 and 7–11 are whitepaper-specific
NON-credential patterns (internal IPs, hostnames, etc.) and stay local to this
reference.

Patterns are listed OUTSIDE a markdown table on purpose: table cells force
pipe characters to be escaped as `\|`, which — copied verbatim into
`rg -e` — matches a literal pipe instead of acting as alternation. Every
pattern below uses unescaped pipe alternation and is safe to copy into
`rg -e` exactly as written.

1. **Private IPv4** — `\b(10\.\d{1,3}\.\d{1,3}\.\d{1,3}|192\.168\.\d{1,3}\.\d{1,3}|172\.(1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3})\b` — genericize
2. **Public IPv4** — `\b\d{1,3}(\.\d{1,3}){3}\b` minus class 1 and version-like strings — ask
3. **MAC address** — `\b([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}\b` — redact
4. **Internal hostname/FQDN** — `\b[A-Za-z0-9-]+\.(lab|local|internal|lan|home|home\.arpa)\b` — genericize
5. **Credential material** — shared source — gitleaks when installed, else `${CLAUDE_PLUGIN_ROOT}/scripts/secret_patterns.grep` (owned by review-gate, spec 04); this skill maintains NO credential patterns of its own — BLOCK
6. **Assigned env values** — `^\s*[A-Z][A-Z0-9_]+\s*=\s*\S+` in any tracked non-`*.example` env-like file — BLOCK
7. **High-entropy literal** — `['"][A-Za-z0-9+/_=-]{32,}['"]` (manual review; hashes/UUIDs usually publish) — ask
8. **Email address** — `\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b` — ask
9. **Home-dir username** — `/(Users|home)/[A-Za-z0-9._-]+` — genericize
10. **Internal URL / non-public port** — `https?://\S+` where host matches class 4, is RFC1918, or port ∉ {80,443} — genericize
11. **Wi-Fi SSID / serial / physical location** — keyword-assisted: `(SSID|serial|S/N|asset tag|address)` lines — ask

Trailing keyword on each line is the default disposition (see below).

## Dispositions

- **publish** — appears verbatim in the site.
- **genericize** — replaced with a plausible fake using a CONSISTENT mapping
  (same real value → same fake everywhere: `192.168.1.10` → `10.0.10.10`,
  `proxmox-01.lab` → `hypervisor-01.example.internal`, `/home/alice` →
  `~`). The mapping is kept only in the allowlist file, never in site source.
- **redact** — removed or replaced with `▮▮▮`; used where even a fake shape
  leaks information (MAC OUIs, serials).
- **BLOCK** — must not appear in any form. If a live credential is found in
  tracked content, additionally: report file:line (value masked to first 4
  chars), recommend rotation, and refuse Phase 5 until resolved. Never echo
  the value in chat.

## Report format (`docs/whitepaper/sensitivity-report.md`)

| ID | Class | Masked value | Where | Proposed | Decision |
|----|-------|--------------|-------|----------|----------|
| S1 | Private IPv4 | 192.168.…10 | docs/inventory.md:42 | genericize | _pending_ |

- "ask"-class rows and any row the user hasn't ruled on go into the single
  Phase 1 AskUserQuestion batch. Default-disposition rows are listed but
  pre-filled; the user can override any row.
- Approved decisions persist to `whitepaper.allowlistFile`
  (default `.claude/whitepaper-allowlist.json`):
  `{ "decisions": [{ "id": "S1", "class": "ipv4-private", "match": "<value>",
     "disposition": "genericize", "replacement": "10.0.10.10",
     "decidedAt": "<ISO>" }] }`
  Rebuild runs re-use decisions by match; only NEW findings are asked.
  NOTE: the allowlist contains real values by design — it is gitignored by
  default unless the user explicitly commits it (decided; see §9 Q1).

## Pass B (post-build gate)

Re-run classes 1–11 against `dist/`. Every hit must correspond to an
approved **publish** row. Any other hit — including a genericize replacement
that accidentally regressed to the real value — fails the run and reopens
Phase 3. Pass B clean is a precondition of Phase 5.
