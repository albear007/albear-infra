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

### agent.albeart.xyz — two Access apps, path-scoped

The single whole-domain app was split into two on 2026-05-16 so the
`PublicLanding` + `/demo/*` showcase can be public while operator
endpoints stay gated. See `docs/2026-05-16-cloudflare-access-path-split.md`
for the reasoning.

Both apps share the same policy:

- **Application type:** Self-hosted
- **Session duration:** 30 days
- **Policy name:** `allow-known-emails`
- **Action:** Allow
- **Rule:** Emails → `[permitted email list]`
- **Fallback:** One-time PIN sent to email

**App 1 — "JBAgent"** (high-frequency operator UI, 5 hostname rows):
```
agent.albeart.xyz/sessions*
agent.albeart.xyz/files*
agent.albeart.xyz/traces*
agent.albeart.xyz/profiles*
agent.albeart.xyz/config*
```

**App 2 — "JBAgent — admin paths"** (admin / machine, 3 hostname rows;
2 free for future Bucket A additions):
```
agent.albeart.xyz/run-sync*
agent.albeart.xyz/evals*
agent.albeart.xyz/schedules*
```

Every other path on `agent.albeart.xyz` falls through to the origin:
`/`, `/me`, `/health`, `/demo/*`, `/transport/*` (self-authed), and all
static assets.

**Pass-through paths and the JWT cookie.** Cloudflare only injects the
`Cf-Access-Authenticated-User-Email` header on requests routed through
an Access app. On pass-through paths — most importantly `/me`, which
the SPA probes on initial load to decide between PublicLanding and the
operator UI — CF does **not** inject the header even for authenticated
users. The origin reads the `CF_Authorization` JWT cookie directly and
validates it against the team's JWKS endpoint instead. Operators must
set `JBAGENT_CF_ACCESS_TEAM_DOMAIN=<team>.cloudflareaccess.com` on the
box for showcase mode to work; without it, `/me` 401s even authed
operators and the SPA stays stuck on the landing. Full reasoning in
`JBAgent/docs/2026-05-18-cf-access-jwt-cookie-validation.md`.

**Allowlist update procedure:** edit Include→Emails on App 1's policy,
save, then repeat on App 2's policy. Drift between the two leaves a gap.
The server's `Cf-Access-Authenticated-User-Email` middleware (active
when `JBAGENT_SHOWCASE_ENABLED=true`) is the defense-in-depth safety
net on Bucket A paths; the JWT-cookie validation above is the
counterpart for pass-through paths.

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
