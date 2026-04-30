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
# After editing a Caddy snippet (most common):
just deploy-gateway      # ssh → git pull → docker compose up -d → restart caddy

# After editing firewall/allowed-ips:
just update-firewall     # scp the file and rerun update-firewall.sh on the box

# After rotating TLS certs (CERT_LOCAL_PATH in .env):
just refresh-certs

# Validate Caddyfile locally before pushing:
just validate
```

Caddy must be **restarted**, not reloaded — reload silently no-ops in
this environment. The recipes above do the right thing; if you're
running SSH commands manually, use `docker compose restart caddy`. See
`docs/2026-04-30-foundation.md` decision 7.

## Secrets

`certs/` (TLS cert + key) and `allowed-ips` are gitignored. Sync them
out-of-band via `scp` and store a copy in a secure location.
