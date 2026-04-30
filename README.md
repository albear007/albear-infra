# albear-infra

Platform coordination layer for the `albeart.xyz` box. Owns Caddy (TLS
gateway), firewall management, and platform runbooks. App repos deploy their
own services; this repo manages the shared gateway in front of them.

**Architecture canonical reference** — layered ownership model, gateway
contract, endpoint security buckets, kernel sandbox status:
→ [`JBAgent/misc/skills/2026-04-12-jbagent-e2e.md`](https://github.com/albear007/jbagent) (`jbagent-architecture` skill)

The model in short: this repo is **layer 6** (platform coordination, shared
Caddy, firewall). App repos own layers 1-4. The gateway contract is defined
once and all gateway implementations (this repo, `infra/standalone/` in
JBAgent for client deploys) satisfy it.

## Contents

```
caddy/
  Caddyfile.prod          ← imports snippets/
  Caddyfile.dev           ← local dev gateway
  snippets/
    albear-t.caddy        ← routing for albeart.xyz / www
    jbagent.caddy         ← routing for agent.albeart.xyz + telegram.albeart.xyz
docker-compose.yml        ← Caddy-only; deployed from this repo
firewall/
  update-firewall.sh      ← manages JBAGENT_ACCESS iptables chain
  allowed-ips             ← IPs allowed to reach JBAgent (gitignored)
runbooks/
  vm-migration-platform.md  ← new-box provisioning, layers 5-6
  cloudflare-config.md      ← Cloudflare DNS + Zero Trust config reference
  platform-onboarding.md    ← how to add a new app to the platform
```

## Day-to-day

```bash
# Reload Caddy config on the box (after editing a snippet)
ssh ubuntu@<box> 'cd ~/infra && docker compose exec caddy caddy reload --config /etc/caddy/Caddyfile'

# Update the IP allowlist for JBAgent
# 1. Edit firewall/allowed-ips
# 2. Run update-firewall.sh on the box, or copy and run:
scp firewall/update-firewall.sh ubuntu@<box>:/tmp/
ssh ubuntu@<box> 'bash /tmp/update-firewall.sh'
```

## Secrets

`certs/` (TLS cert + key) and `allowed-ips` are gitignored. Sync them
out-of-band via `scp` and store a copy in a secure location.
