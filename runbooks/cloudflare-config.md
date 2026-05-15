# Cloudflare Config Reference

**Date recorded:** 2026-04-30

Current Cloudflare configuration for `albeart.xyz`. This is a reference
record — update it when the dashboard config changes. Not IaC; the
dashboard is authoritative.

---

## DNS Records

| Name | Type | Value | Proxy |
|---|---|---|---|
| `@` (albeart.xyz) | A | `<box-ip>` | ✓ Proxied |
| `www` | CNAME | `albeart.xyz` | ✓ Proxied |
| `agent` | A | `<box-ip>` | ✓ Proxied |
| `telegram` | A | `<box-ip>` | ✓ Proxied |
| `chess` | A | `<box-ip>` | ✓ Proxied |

All A records point to the same OCI box IP. When the box IP changes (VM
migration), update all five records.

---

## SSL/TLS

- **Mode:** Full (Strict)
- **Origin certificate:** Cloudflare Origin CA cert, valid 15 years.
  Stored at `~/infra/certs/cert.pem` + `key.pem` on the box (gitignored).
  See `vm-migration-platform.md` Step 3 for renewal procedure.

---

## Zero Trust — Access Applications

### agent.albeart.xyz

- **Application type:** Self-hosted
- **Session duration:** 30 days
- **Policies:**
  - Name: `allow-known-emails`
  - Action: Allow
  - Rule: Emails → `[permitted email list]`
  - Fallback: One-time PIN sent to email

This is the primary gate for the JBAgent UI. Cloudflare enforces auth
before traffic reaches the box. JBAgent itself has no app-layer auth for
its internal endpoints (relies on this network gate).

### telegram.albeart.xyz

No Access policy — this subdomain is the Telegram webhook endpoint. It
must be publicly reachable (Telegram's servers need to call it). Protected
at app layer by HMAC secret-token verification in `transports/telegram.py`.

### chess.albeart.xyz

**No Access policy — intentionally public.** This subdomain serves the
phchess chess-federation portal. Read paths are public; write paths
(rating submissions, tournament management) are gated by per-TD JWT
auth implemented in `phchess/backend/app/auth/`.

Future readers: do **not** add a Cloudflare Access app here. phchess is
designed as a public site; any visitor can browse player ratings and
tournament history. The asymmetry with `agent.albeart.xyz` (gated by
Access) is deliberate — agent is an operator-only UI, chess is a
public-information portal.

---

## Page Rules / Cache Rules

None currently active.

---

## Maintenance Notes

- **Bot IP rotation:** If Telegram or other approved services start getting
  blocked, check that the ACL policy hasn't accidentally applied to
  `telegram.albeart.xyz`. That subdomain should have no Access policy.
- **Cert renewal:** The Cloudflare Origin CA cert is valid for 15 years
  from issuance. When it expires, generate a new one in the dashboard
  (SSL/TLS → Origin Server → Create Certificate), drop the new
  `cert.pem` and `key.pem` into `$CERT_LOCAL_PATH` (set in `.env`), and
  run `just refresh-certs`. (`caddy reload` silently no-ops in this
  environment; the recipe restarts Caddy. See
  `docs/2026-04-30-foundation.md` decision 7.)
