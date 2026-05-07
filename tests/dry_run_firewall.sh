#!/usr/bin/env bash
# dry_run_firewall.sh — Snapshot test of update-firewall.sh's rule layout.
#
# Runs update-firewall.sh --dry-run against tests/fixtures/sample-allowed-ips
# and asserts the printed iptables commands match
# tests/expected/firewall_dryrun.txt exactly. If the rule layout drifts
# unintentionally (a rule reordered, a default-deny removed), this fails
# loudly before the real script touches a production box.
#
# To accept a deliberate change in the rule layout, regenerate the snapshot:
#   bash firewall/update-firewall.sh --dry-run \
#       --allowed-ips tests/fixtures/sample-allowed-ips \
#     > tests/expected/firewall_dryrun.txt

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

actual="$(bash firewall/update-firewall.sh \
    --dry-run \
    --allowed-ips tests/fixtures/sample-allowed-ips 2>&1)"

expected="$(cat tests/expected/firewall_dryrun.txt)"

if [[ "$actual" != "$expected" ]]; then
    echo "[dry-run-firewall] FAIL: output drifted from snapshot" >&2
    echo "----- expected -----" >&2
    echo "$expected" >&2
    echo "----- actual -------" >&2
    echo "$actual" >&2
    echo "----- diff (- expected, + actual) -----" >&2
    diff <(echo "$expected") <(echo "$actual") >&2 || true
    echo "" >&2
    echo "If this drift is intentional, regenerate the snapshot:" >&2
    echo "  bash firewall/update-firewall.sh --dry-run \\" >&2
    echo "      --allowed-ips tests/fixtures/sample-allowed-ips \\" >&2
    echo "    > tests/expected/firewall_dryrun.txt" >&2
    exit 1
fi

echo "[dry-run-firewall] ok — rule layout matches snapshot"
