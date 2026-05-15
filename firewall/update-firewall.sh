#!/usr/bin/env bash
# update-firewall.sh — Refresh the JBAGENT_ACCESS iptables chain.
#
# The JBAGENT_ACCESS chain gates access to JBAgent on port 8000.
# Run after editing allowed-ips, or after a box redeploy.
#
# Usage (from the box):
#   bash update-firewall.sh
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
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ALLOWED_IPS_FILE="${SCRIPT_DIR}/allowed-ips"

if [[ ! -f "$ALLOWED_IPS_FILE" ]]; then
    echo "error: $ALLOWED_IPS_FILE not found." >&2
    echo "       Create it with one IP/CIDR per line." >&2
    exit 2
fi

# Create chain if it doesn't exist yet (idempotent).
sudo iptables -N JBAGENT_ACCESS 2>/dev/null || true

# Ensure port 8000 is routed through JBAGENT_ACCESS.
# Remove any stale jump rules first, then re-add at position 1.
sudo iptables -D INPUT -p tcp --dport 8000 -j JBAGENT_ACCESS 2>/dev/null || true
sudo iptables -I INPUT 1 -p tcp --dport 8000 -j JBAGENT_ACCESS

# Flush existing rules in JBAGENT_ACCESS.
sudo iptables -F JBAGENT_ACCESS

# Allow Docker bridge networks (so Caddy container can proxy to JBAgent).
sudo iptables -A JBAGENT_ACCESS -s 172.16.0.0/12 -j ACCEPT

# Add each IP/CIDR from allowed-ips.
while IFS= read -r line || [[ -n "$line" ]]; do
    # Skip blank lines and comments.
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line// }" ]] && continue
    ip=$(echo "$line" | awk '{print $1}')
    sudo iptables -A JBAGENT_ACCESS -s "$ip" -j ACCEPT
done < "$ALLOWED_IPS_FILE"

# Default: drop everything not matched above.
sudo iptables -A JBAGENT_ACCESS -j DROP

# Persist rules so they survive reboots.
sudo netfilter-persistent save

echo "[update-firewall] done — $(wc -l < "$ALLOWED_IPS_FILE") IP entries loaded"
