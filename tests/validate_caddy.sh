#!/usr/bin/env bash
# validate_caddy.sh — Caddyfile + snippet validation.
#
# Two checks:
#   1. Each snippet in caddy/snippets/*.caddy is parseable on its own.
#   2. The full Caddyfile.prod (which imports all snippets) is parseable.
#
# Uses `caddy adapt` (not `validate`) because validate would try to load
# TLS certs that only exist on the box — adapt covers the syntax/grammar
# layer we actually want to lock down here.
#
# Exit 0 on success, 1 on any failure.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

errors=0

# ── 1. Each snippet parses on its own ────────────────────────────────────────
echo "[validate-caddy] checking snippets/*.caddy individually"
for snippet in caddy/snippets/*.caddy; do
    [ -f "$snippet" ] || continue
    if ! docker run --rm \
        -v "$PWD/caddy:/caddy" \
        caddy:alpine \
        caddy adapt --config "/caddy/snippets/$(basename "$snippet")" >/dev/null 2>&1; then
        echo "[validate-caddy] FAIL: $snippet does not parse" >&2
        # Re-run with output so the operator sees the error.
        docker run --rm \
            -v "$PWD/caddy:/caddy" \
            caddy:alpine \
            caddy adapt --config "/caddy/snippets/$(basename "$snippet")" >&2 || true
        errors=$((errors + 1))
    else
        echo "[validate-caddy]  ok  $snippet"
    fi
done

# ── 2. Full Caddyfile.prod parses (resolves all imports) ─────────────────────
echo "[validate-caddy] checking Caddyfile.prod (resolves snippet imports)"
if ! docker run --rm \
    -v "$PWD/caddy:/caddy" \
    caddy:alpine \
    caddy adapt --config /caddy/Caddyfile.prod >/dev/null 2>&1; then
    echo "[validate-caddy] FAIL: Caddyfile.prod does not parse" >&2
    docker run --rm \
        -v "$PWD/caddy:/caddy" \
        caddy:alpine \
        caddy adapt --config /caddy/Caddyfile.prod >&2 || true
    errors=$((errors + 1))
else
    echo "[validate-caddy]  ok  Caddyfile.prod"
fi

# ── 3. Cross-check: every imported file actually exists ──────────────────────
# `caddy adapt` is permissive about missing imports (treats as empty), so
# explicitly check that every import target resolves.
echo "[validate-caddy] checking import directives reference real files"
while IFS= read -r import_line; do
    [ -z "$import_line" ] && continue
    target=$(echo "$import_line" | awk '{print $2}')
    # Glob imports: caddy/snippets/*.caddy must match at least one file.
    if [[ "$target" == *"*"* ]]; then
        # shellcheck disable=SC2086
        matches=$(ls caddy/$target 2>/dev/null | wc -l | tr -d ' ')
        if [ "$matches" -eq 0 ]; then
            echo "[validate-caddy] FAIL: import $target matches no files" >&2
            errors=$((errors + 1))
        else
            echo "[validate-caddy]  ok  import $target → $matches file(s)"
        fi
    else
        if [ ! -f "caddy/$target" ]; then
            echo "[validate-caddy] FAIL: import $target — file missing" >&2
            errors=$((errors + 1))
        fi
    fi
done < <(grep -E '^\s*import\s+' caddy/Caddyfile.prod || true)

if [ "$errors" -gt 0 ]; then
    echo "[validate-caddy] $errors error(s)" >&2
    exit 1
fi
echo "[validate-caddy] all checks passed"
