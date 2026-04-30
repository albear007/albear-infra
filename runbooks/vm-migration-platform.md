# VM Migration — Platform Half (layers 5-6)

**Date recorded:** 2026-04-30

This is the **platform half** of provisioning a new box. It covers layers 5
and 6 (gateway, platform coordination): Caddy bring-up, firewall setup, DNS,
Cloudflare, and albear-t deployment.

For layers 1-4 (JBAgent service code, systemd, kernel sandbox, state plane),
see `JBAgent/docs/2026-04-29-jbagent-app-bootstrap.md`.

Full process takes ~15-20 minutes on a fresh Ubuntu instance.

---

## Prerequisites

Collect before starting:

| Variable | Where | Example |
|---|---|---|
| New server IP | OCI Console → Instance details | `132.226.62.154` |
| SSH key path | `~/.ssh/` | `~/.ssh/jbagent_oci` |
| GitHub OAuth token | `gh auth token` | `gho_...` |
| Cloudflare Origin Cert | Cloudflare dashboard → SSL/TLS → Origin Server | cert.pem + key.pem |

The JBAgent app bootstrap must run before or alongside this runbook (no
strict ordering, but both must complete before the box is live).

---

## Step 1 — Provision the OCI instance

1. Create instance: **VM.Standard.A1.Flex**, Ubuntu 24.04 LTS (aarch64)
2. Allocate: 1-4 OCPU, 6+ GB RAM (within the 4 OCPU / 24 GB free tier total)
3. Upload the existing SSH public key (`~/.ssh/jbagent_oci.pub`)
4. In the VCN **Security List**, open inbound TCP on: 22, 80, 443

**Tip:** If A1 Flex shows no capacity in Ashburn, retry or switch region.

---

## Step 2 — Install Docker

```bash
ssh -i ~/.ssh/jbagent_oci ubuntu@<new-ip> bash << 'DOCKER'
curl -fsSL https://get.docker.com | sudo bash
sudo usermod -aG docker ubuntu
echo "Docker installed."
DOCKER
```

Log out and back in (or `newgrp docker`) so the group takes effect.

---

## Step 3 — Clone albear-infra and set up certs

```bash
TOKEN=$(gh auth token)

ssh -i ~/.ssh/jbagent_oci ubuntu@<new-ip> bash << INFRA
set -e
git clone https://oauth2:${TOKEN}@github.com/albear007/albear-infra.git ~/infra
git -C ~/infra remote set-url origin https://oauth2:${TOKEN}@github.com/albear007/albear-infra.git
mkdir -p ~/infra/certs
echo "albear-infra cloned."
INFRA

# Copy Cloudflare Origin Certificate (get from Cloudflare dashboard:
#   SSL/TLS → Origin Server → Create Certificate → *.albeart.xyz,albeart.xyz → 15 years)
scp -i ~/.ssh/jbagent_oci /path/to/cert.pem /path/to/key.pem ubuntu@<new-ip>:~/infra/certs/
```

---

## Step 4 — Set up albear-infra firewall

The firewall `allowed-ips` file is gitignored. Sync it from a secure location
or recreate it from scratch:

```bash
# Copy the allowed-ips file (gitignored, sync out of band)
scp -i ~/.ssh/jbagent_oci /path/to/allowed-ips ubuntu@<new-ip>:~/infra/firewall/allowed-ips

# Install iptables-persistent if not already installed
ssh -i ~/.ssh/jbagent_oci ubuntu@<new-ip> \
  'sudo apt-get install -y iptables-persistent netfilter-persistent'

# Create the JBAGENT_ACCESS chain (one-time, idempotent)
ssh -i ~/.ssh/jbagent_oci ubuntu@<new-ip> bash << 'FW'
sudo iptables -N JBAGENT_ACCESS 2>/dev/null || true
sudo iptables -I INPUT 1 -p tcp --dport 8000 -j JBAGENT_ACCESS
sudo iptables -A JBAGENT_ACCESS -j DROP
sudo netfilter-persistent save
FW

# Now run update-firewall.sh to populate the chain
ssh -i ~/.ssh/jbagent_oci ubuntu@<new-ip> 'cd ~/infra && bash firewall/update-firewall.sh'
```

---

## Step 5 — Clone and deploy albear-t

```bash
TOKEN=$(gh auth token)

ssh -i ~/.ssh/jbagent_oci ubuntu@<new-ip> bash << ALBEART
set -e
git clone https://oauth2:${TOKEN}@github.com/albear007/albear-t.git ~/albear-t
git -C ~/albear-t remote set-url origin https://oauth2:${TOKEN}@github.com/albear007/albear-t.git
mkdir -p ~/albear-t/dist ~/albear-t/static
echo "albear-t cloned."
ALBEART

# Pull and start the backend + static-init (no Caddy; that's in albear-infra)
ssh -i ~/.ssh/jbagent_oci ubuntu@<new-ip> \
  'cd ~/albear-t && docker compose -f deploy/docker-compose.prod.yml pull && docker compose -f deploy/docker-compose.prod.yml up -d'
```

---

## Step 6 — Bring up Caddy

```bash
ssh -i ~/.ssh/jbagent_oci ubuntu@<new-ip> \
  'cd ~/infra && docker compose up -d'

# Verify Caddy is running
ssh -i ~/.ssh/jbagent_oci ubuntu@<new-ip> 'docker ps | grep caddy'
```

---

## Step 7 — Cloudflare DNS

In the Cloudflare dashboard for `albeart.xyz`:

| Record | Type | Value | Proxy |
|---|---|---|---|
| `@` | A | `<new-ip>` | ✓ Proxied |
| `www` | A | `<new-ip>` | ✓ Proxied |
| `agent` | A | `<new-ip>` | ✓ Proxied |
| `telegram` | A | `<new-ip>` | ✓ Proxied |

SSL/TLS mode: **Full (Strict)**.

If replacing an old box at the same IP, no DNS changes needed. If the IP
changed, update all A records. TTL is 1 min when proxied, so traffic shifts
in under 5 minutes.

---

## Step 8 — Cloudflare Zero Trust (agent.albeart.xyz)

Zero Trust → Access → Applications:
- Application: `agent.albeart.xyz`
- Session duration: 30 days
- Policy: One-time PIN → allowed emails

This gate is enforced by Cloudflare before traffic reaches the box. JBAgent
itself does not have app-layer auth for bucket-A endpoints (it relies on this
network-level gate).

See `cloudflare-config.md` for the current policy config.

---

## Step 9 — Update GitHub Actions secrets (albear-t auto-deploy)

```bash
gh secret set ORACLE_HOST  --repo albear007/albear-t --body "<new-ip>"
gh secret set ORACLE_USER  --repo albear007/albear-t --body "ubuntu"
cat ~/.ssh/jbagent_oci | gh secret set ORACLE_SSH_KEY --repo albear007/albear-t
# GHCR_PAT should already be set; verify: gh secret list --repo albear007/albear-t
```

---

## Step 10 — Verify

```bash
# JBAgent health (via Cloudflare → Caddy → JBAgent)
curl -I https://agent.albeart.xyz/health    # expect 200 after CF Access auth

# Portfolio
curl -I https://albeart.xyz               # expect 200

# JBAgent service logs
just logs <target>                         # from JBAgent repo
```

---

## Summary checklist

- [ ] OCI instance provisioned (A1.Flex, Ubuntu 24.04, SSH key uploaded)
- [ ] OCI Security List: 22, 80, 443 open
- [ ] Docker installed (`docker --version`, ubuntu in docker group)
- [ ] `~/infra` cloned, certs at `~/infra/certs/cert.pem` + `key.pem`
- [ ] Firewall: `JBAGENT_ACCESS` chain created, `update-firewall.sh` run
- [ ] `~/albear-t` cloned, backend + static-init running (`docker ps`)
- [ ] `~/infra` Caddy running (`docker ps`)
- [ ] JBAgent systemd service running (`systemctl is-active jbagent`)
- [ ] Cloudflare DNS A records updated
- [ ] Cloudflare SSL/TLS: Full (Strict)
- [ ] Cloudflare Zero Trust: agent.albeart.xyz policy active
- [ ] GitHub Actions secrets updated (ORACLE_HOST at minimum)
- [ ] `https://albeart.xyz` → portfolio home
- [ ] `https://agent.albeart.xyz` → Cloudflare Access auth prompt → JBAgent UI
