# Platform Onboarding — Adding a New App

**Date recorded:** 2026-04-30

How to onboard a new application to the `albeart.xyz` platform. Covers the
platform-side changes only — app-side deployment is the app repo's concern.

---

## Overview

The platform owns: Caddy gateway, firewall, DNS, Zero Trust policies. Each
app provides: a Docker image / systemd service, and a Caddy snippet for its
domain routing.

Adding a new app involves three changes:
1. Write a Caddy snippet for the new app's domain(s)
2. Update the firewall if the app needs a new port allowance
3. Add DNS records in Cloudflare

---

## Step 1 — Write the Caddy snippet

Create `caddy/snippets/<app-name>.caddy`. Template:

```caddy
<app-domain>.albeart.xyz {
    # If using Cloudflare-managed TLS (proxied A record):
    #   Cloudflare handles TLS termination; Caddy receives plain HTTP on 80.
    #   No tls directive needed.
    #
    # If using Cloudflare Origin Cert (Full Strict, bypassing CF proxy):
    tls /etc/caddy/certs/cert.pem /etc/caddy/certs/key.pem

    encode zstd gzip

    reverse_proxy host.docker.internal:<app-port> {
        # Only needed for SSE / streaming endpoints:
        # flush_interval -1
    }
}
```

For a public-facing app with no auth gate, just add it and deploy. For an
operator-only app, add a Cloudflare Zero Trust Application (see
`cloudflare-config.md`).

---

## Step 2 — Update the firewall (if needed)

If the new app listens on a new host port and needs Docker bridge access:

The `JBAGENT_ACCESS` chain manages port 8000. For new ports, add a
new rule in `update-firewall.sh`, or add a bespoke chain by analogy.
The key invariant: no port should be open to the internet that isn't
explicitly gated.

Current host ports:
- Port 8000: JBAgent (`JBAGENT_ACCESS` chain, allowlist-gated)
- Port 8080: albear-t backend (Docker internal; exposed only for infra Caddy)

---

## Step 3 — Cloudflare DNS

Add an A record in the Cloudflare dashboard:
- Name: `<subdomain>`
- Type: A
- Value: box IP
- Proxy status: Proxied (recommended — hides the real IP)

If the subdomain is operator-only, add a Zero Trust Application policy
(Settings → Access → Add Application → Self-Hosted).

---

## Step 4 — Deploy the snippet and restart Caddy

```bash
# From dev machine:
git add caddy/snippets/<app-name>.caddy
git commit -m "feat: add <app-name> Caddy snippet"
git push

# Then deploy:
just deploy-gateway
# (equivalent to: ssh ubuntu@<box> 'cd ~/infra && git pull && docker compose up -d && docker compose restart caddy')
```

**Important — restart, not reload.** `caddy reload` silently no-ops in
this environment (the new config does not take effect; the site keeps
serving the previous version with no error). Production deploys must
use `docker compose restart caddy`. See `docs/2026-04-30-foundation.md`
decision 7 and `albear-t/docs/2026-04-27-static-asset-architecture-execution-notes.md`
lines 23-31 for the original observation.

---

## Checklist

- [ ] `caddy/snippets/<app-name>.caddy` added and committed
- [ ] Caddy config validates: `just validate` (syntax-only check via `caddy adapt`; full validation runs on the box where certs are present)
- [ ] Firewall updated if app uses a new port
- [ ] DNS A record added in Cloudflare
- [ ] Zero Trust policy added if operator-only
- [ ] Caddy reloaded on the box
- [ ] End-to-end test: `curl -I https://<app-domain>.albeart.xyz`
