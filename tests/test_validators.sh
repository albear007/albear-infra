#!/usr/bin/env bash
# test_validators.sh — Negative tests for the validators themselves.
#
# A validator that always passes is worse than no validator. These tests
# feed deliberately-bad inputs to each validator and assert it exits non-zero.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

errors=0

# ── validate_allowed_ips.py rejects malformed entries ────────────────────────
echo "[test-validators] validate_allowed_ips.py — bad input must fail"
if python3 tests/validate_allowed_ips.py tests/fixtures/bad-allowed-ips 2>/dev/null; then
    echo "  FAIL: validator passed on a known-bad file" >&2
    errors=$((errors + 1))
else
    echo "  ok"
fi

# ── validate_allowed_ips.py accepts valid entries ────────────────────────────
echo "[test-validators] validate_allowed_ips.py — sample fixture must pass"
if ! python3 tests/validate_allowed_ips.py tests/fixtures/sample-allowed-ips >/dev/null 2>&1; then
    echo "  FAIL: validator rejected the known-good sample" >&2
    errors=$((errors + 1))
else
    echo "  ok"
fi

if [[ "$errors" -gt 0 ]]; then
    echo "[test-validators] $errors failure(s)" >&2
    exit 1
fi
echo "[test-validators] all checks passed"
