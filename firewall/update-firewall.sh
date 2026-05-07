#!/usr/bin/env bash
# update-firewall.sh — Refresh the JBAGENT_ACCESS iptables chain.
#
# The JBAGENT_ACCESS chain gates access to JBAgent on port 8000.
# Run after editing allowed-ips, or after a box redeploy.
#
# Usage (from the box):
#   bash update-firewall.sh                          # apply rules
#   bash update-firewall.sh --dry-run                # print what would run
#   bash update-firewall.sh --allowed-ips path       # use a different list
#                                                    # (mostly for tests)
#
# The script is idempotent. It flushes JBAGENT_ACCESS before repopulating it,
# and saves rules via netfilter-persistent so they survive reboots.
#
# Scope. This script intentionally manages port 8000 (JBAgent) only.
# Other host ports on this box are public-by-design and rely on
# app-layer auth, NOT on iptables:
#   - Port 8001 (phchess): per-TD JWT auth in the app.
#   - Port 8080 (albear-t backend): Docker-internal; not exposed externally.
# If you add an `iptables -I INPUT 1 -p tcp --dport 8001 ...` block here,
# you will silently break the chess.albeart.xyz user-facing surface.
# See runbooks/platform-onboarding.md "Step 2 — Update the firewall"
# for the decision rule on when an app gets a chain.
#
# --dry-run is also what `tests/dry_run_firewall.sh` uses to lock down the
# rule layout against a known allowed-ips list.
set -euo pipefail

DRY_RUN=0
ALLOWED_IPS_OVERRIDE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=1; shift ;;
        --allowed-ips) ALLOWED_IPS_OVERRIDE="$2"; shift 2 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ALLOWED_IPS_FILE="${ALLOWED_IPS_OVERRIDE:-${SCRIPT_DIR}/allowed-ips}"

if [[ ! -f "$ALLOWED_IPS_FILE" ]]; then
    echo "error: $ALLOWED_IPS_FILE not found." >&2
    echo "       Create it with one IP/CIDR per line." >&2
    exit 2
fi

# Indirection so --dry-run can swap the executor without duplicating the rule
# layout below. Real run = sudo iptables; dry run = print the command.
_iptables() {
    if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "iptables $*"
    else
        sudo iptables "$@"
    fi
}

_persist() {
    if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "netfilter-persistent save"
    else
        sudo netfilter-persistent save
    fi
}

# Create chain if it doesn't exist yet (idempotent).
if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "iptables -N JBAGENT_ACCESS  # ignore-errors"
else
    sudo iptables -N JBAGENT_ACCESS 2>/dev/null || true
fi

# Ensure port 8000 is routed through JBAGENT_ACCESS.
# Remove any stale jump rules first, then re-add at position 1.
if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "iptables -D INPUT -p tcp --dport 8000 -j JBAGENT_ACCESS  # ignore-errors"
else
    sudo iptables -D INPUT -p tcp --dport 8000 -j JBAGENT_ACCESS 2>/dev/null || true
fi
_iptables -I INPUT 1 -p tcp --dport 8000 -j JBAGENT_ACCESS

# Flush existing rules in JBAGENT_ACCESS.
_iptables -F JBAGENT_ACCESS

# Allow Docker bridge networks (so Caddy container can proxy to JBAgent).
_iptables -A JBAGENT_ACCESS -s 172.16.0.0/12 -j ACCEPT

# Add each IP/CIDR from allowed-ips.
while IFS= read -r line || [[ -n "$line" ]]; do
    # Skip blank lines and comments.
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line// }" ]] && continue
    ip=$(echo "$line" | awk '{print $1}')
    _iptables -A JBAGENT_ACCESS -s "$ip" -j ACCEPT
done < "$ALLOWED_IPS_FILE"

# Default: drop everything not matched above.
_iptables -A JBAGENT_ACCESS -j DROP

# Persist rules so they survive reboots.
_persist

echo "[update-firewall] done — $(grep -cv '^[[:space:]]*\(#\|$\)' "$ALLOWED_IPS_FILE") IP entries loaded"
