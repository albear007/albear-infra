#!/usr/bin/env bash
# validate_firewall_script.sh — shellcheck the firewall script.
#
# Bash bugs in update-firewall.sh can lock the operator out of production.
# Shellcheck catches the common ones (unquoted vars, $? misuse, etc.) at
# zero runtime cost.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

if ! command -v shellcheck >/dev/null 2>&1; then
    echo "[validate-firewall-script] shellcheck not on PATH; skipping" >&2
    echo "  install: brew install shellcheck (macOS) | apt install shellcheck (Ubuntu)" >&2
    # Soft-skip rather than fail — first-time runners shouldn't be blocked.
    exit 0
fi

# `--severity warning` skips style suggestions; we want correctness errors only.
echo "[validate-firewall-script] running shellcheck on firewall/update-firewall.sh"
if shellcheck --severity=warning firewall/update-firewall.sh; then
    echo "[validate-firewall-script] ok"
else
    echo "[validate-firewall-script] FAIL: shellcheck reported issues" >&2
    exit 1
fi
