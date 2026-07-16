#!/bin/bash
# Structural gates for the demo-prep presentation-mode templates
# (spec 09 §5.1 file layout, §5.3 normative contracts).
#
# templates/slides.template.ts must be byte-identical to the fenced TS block
# in docs/specs/09-demo-prep.md §5.3 (component contract). This script
# re-extracts that exact line range and diffs it against the shipped file,
# so an edit to either side that drifts from the other fails loudly.
#
# templates/PresentationMode.template.tsx also ships as a full, literal
# fenced block in spec 09's "#### Shipped shell" section (full source, kept
# in sync with the shipped file "by diff" per the spec's own text) — so it
# gets the SAME byte-identity re-extraction/diff treatment as slides.template.ts
# above, not just structural checks. On top of that identity guard it is
# checked structurally: exports the component, imports slide types from
# './slides.template', references the state/contract vocabulary
# (slides/currentIndex/overlay), has no {{...}} placeholders and no
# TODO/FIXME, and has balanced braces/parens/brackets (a TSX-aware compiler
# check is out of reach for `node --input-type=module`, so this is a
# Python-based structural parse rather than a real TS parse).
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/../../.." && pwd)"
SPEC="$ROOT/docs/specs/09-demo-prep.md"
TPL_DIR="$ROOT/skills/demo-prep/templates"
SLIDES="$TPL_DIR/slides.template.ts"
SHELL_TSX="$TPL_DIR/PresentationMode.template.tsx"
fail=0
err() { echo "FAIL: $1"; fail=1; }

# --- existence -----------------------------------------------------------
[ -f "$SLIDES" ] || err "missing $SLIDES"
[ -f "$SHELL_TSX" ] || err "missing $SHELL_TSX"

# --- slides.template.ts byte-identical to spec §5.3 fenced block ---------
if [ -f "$SLIDES" ] && [ -f "$SPEC" ]; then
  SPEC_BLOCK="$(sed -n '241,261p' "$SPEC")"
  if ! diff -q <(printf '%s\n' "$SPEC_BLOCK") "$SLIDES" >/dev/null 2>&1; then
    err "slides.template.ts is not byte-identical to spec 09 §5.3's fenced TS block (lines 241-261)"
    diff <(printf '%s\n' "$SPEC_BLOCK") "$SLIDES" || true
  fi
fi

# --- PresentationMode.template.tsx byte-identical to spec §5.3's shipped
# shell fenced block ("#### Shipped shell") -------------------------------
# Same drift guard as slides.template.ts above: re-extract the exact line
# range of the spec's fenced ```tsx block and diff it against the shipped
# file, so an edit to either side alone fails loudly instead of silently
# diverging (this file is a full implementation, not a summarized contract,
# so the spec keeps the authoritative copy in sync "by diff" per its own
# text — this is that diff, made executable).
if [ -f "$SHELL_TSX" ] && [ -f "$SPEC" ]; then
  SHELL_BLOCK="$(sed -n '301,568p' "$SPEC")"
  if ! diff -q <(printf '%s\n' "$SHELL_BLOCK") "$SHELL_TSX" >/dev/null 2>&1; then
    err "PresentationMode.template.tsx is not byte-identical to spec 09's '#### Shipped shell' fenced block (lines 301-568)"
    diff <(printf '%s\n' "$SHELL_BLOCK") "$SHELL_TSX" || true
  fi
fi

# --- PresentationMode.template.tsx structural gates -----------------------
if [ -f "$SHELL_TSX" ]; then
  grep -qE "export (function|const) PresentationMode" "$SHELL_TSX" \
    || err "PresentationMode.template.tsx does not export a PresentationMode component"
  grep -q "from './slides.template'" "$SHELL_TSX" \
    || err "PresentationMode.template.tsx does not import from './slides.template'"
  grep -q "slides" "$SHELL_TSX" || err "PresentationMode.template.tsx does not reference 'slides'"
  grep -q "currentIndex" "$SHELL_TSX" || err "PresentationMode.template.tsx does not reference 'currentIndex'"
  grep -qi "overlay" "$SHELL_TSX" || err "PresentationMode.template.tsx does not reference 'overlay'"

  if grep -q '{{' "$SHELL_TSX"; then
    err "PresentationMode.template.tsx contains {{...}} placeholder syntax"
  fi
  if grep -Eq "TODO|FIXME" "$SHELL_TSX"; then
    err "PresentationMode.template.tsx contains a TODO/FIXME"
  fi

  # Balanced braces/parens/brackets — a structural parse, not a real TS
  # parse (node --input-type=module cannot compile TSX).
  python3 - "$SHELL_TSX" <<'PYEOF' || err "PresentationMode.template.tsx has unbalanced braces/parens/brackets"
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as fh:
    src = fh.read()

pairs = {')': '(', ']': '[', '}': '{'}
openers = set(pairs.values())
stack = []
in_line_comment = False
in_block_comment = False
in_string = None  # one of "'", '"', '`'
i = 0
n = len(src)
while i < n:
    c = src[i]
    nxt = src[i + 1] if i + 1 < n else ''
    if in_line_comment:
        if c == '\n':
            in_line_comment = False
        i += 1
        continue
    if in_block_comment:
        if c == '*' and nxt == '/':
            in_block_comment = False
            i += 2
            continue
        i += 1
        continue
    if in_string:
        if c == '\\':
            i += 2
            continue
        if c == in_string:
            in_string = None
        i += 1
        continue
    if c == '/' and nxt == '/':
        in_line_comment = True
        i += 2
        continue
    if c == '/' and nxt == '*':
        in_block_comment = True
        i += 2
        continue
    if c in ('"', "'", '`'):
        in_string = c
        i += 1
        continue
    if c in openers:
        stack.append(c)
        i += 1
        continue
    if c in pairs:
        if not stack or stack[-1] != pairs[c]:
            print(f"mismatch at offset {i}: found '{c}'")
            sys.exit(1)
        stack.pop()
        i += 1
        continue
    i += 1

if stack:
    print(f"unclosed: {stack}")
    sys.exit(1)
sys.exit(0)
PYEOF
fi

# --- bonus: real tsc compile, if available --------------------------------
TSC_BIN=""
if command -v tsc >/dev/null 2>&1; then
  TSC_BIN="tsc"
elif command -v npx >/dev/null 2>&1 && npx --no-install tsc --version >/dev/null 2>&1; then
  TSC_BIN="npx --no-install tsc"
fi

if [ -n "$TSC_BIN" ]; then
  SCRATCH="$(mktemp -d)"
  mkdir -p "$SCRATCH/src/presentation" "$SCRATCH/src/i18n" "$SCRATCH/src/theme"
  cp "$SLIDES" "$SCRATCH/src/presentation/slides.template.ts"
  cp "$SHELL_TSX" "$SCRATCH/src/presentation/PresentationMode.template.tsx"

  cat > "$SCRATCH/src/i18n/index.ts" <<'EOF'
export function useI18n(): { t: (key: string) => string; locale: string } {
  return { t: (key: string) => key, locale: 'en' };
}
EOF
  cat > "$SCRATCH/src/theme/index.ts" <<'EOF'
export function useTheme(): { theme: 'light' | 'dark' } {
  return { theme: 'light' };
}
EOF
  cat > "$SCRATCH/react-stub.d.ts" <<'EOF'
declare module 'react' {
  export type ReactNode = any;
  export type ComponentType<P = any> = (props: P) => any;
  export function useState<T>(initial: T): [T, (value: T | ((prev: T) => T)) => void];
  export function useCallback<T extends (...args: any[]) => any>(fn: T, deps: any[]): T;
  export function useEffect(fn: () => void | (() => void), deps: any[]): void;
  export function useMemo<T>(fn: () => T, deps: any[]): T;
}

declare module 'react/jsx-runtime' {
  export function jsx(type: any, props: any, key?: any): any;
  export function jsxs(type: any, props: any, key?: any): any;
  export const Fragment: any;
}

declare namespace JSX {
  interface IntrinsicElements {
    [elemName: string]: any;
  }
  interface Element {}
}
EOF

  if (cd "$SCRATCH" && $TSC_BIN --noEmit --jsx react-jsx --skipLibCheck \
        --moduleResolution bundler --module esnext --target es2020 --lib es2020,dom \
        src/presentation/slides.template.ts src/presentation/PresentationMode.template.tsx react-stub.d.ts \
        > "$SCRATCH/tsc.out" 2>&1); then
    echo "BONUS: tsc --noEmit compiled both templates clean (stub react + i18n/theme modules)"
  else
    err "BONUS tsc compile failed (see below) — hard structural gates above still apply"
    cat "$SCRATCH/tsc.out"
  fi
  rm -rf "$SCRATCH"
else
  echo "BONUS: tsc not found on PATH (and npx has no cached tsc) — skipped; structural gates above are the hard requirement"
fi

[ $fail -eq 0 ] && echo "OK: presentation-mode templates (existence, byte-identity, structural gates)"
exit $fail
