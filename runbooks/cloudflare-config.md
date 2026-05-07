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

All A records point to the same OCI box IP. When the box IP changes (VM
migration), update all four records.

---

## SSL/TLS

- **Mode:** Full (Strict)
- **Origin certificate:** Cloudflare Origin CA cert, valid 15 years.
  Stored at `~/infra/certs/cert.pem` + `key.pem` on the box (gitignored).
  See `vm-migration-platform.md` Step 3 for renewal procedure.

---

## Zero Trust — Access Applications

### agent.albeart.xyz

There are **two configurations** of this Access policy depending on
whether the showcase mode is on:

#### Default (showcase off — JBAgent.JBAGENT_SHOWCASE_ENABLED=false)

The entire hostname is gated. This is the original setup and the right
state when the showcase isn't running.

- **Application type:** Self-hosted
- **Application domain:** `agent.albeart.xyz` (no path scope; all paths gated)
- **Session duration:** 30 days
- **Policies:**
  - Name: `allow-known-emails`
  - Action: Allow
  - Rule: Emails → `[permitted email list]`
  - Fallback: One-time PIN sent to email

JBAgent has no app-layer auth in this mode (relies on this network gate).

#### Showcase (JBAgent.JBAGENT_SHOWCASE_ENABLED=true)

When the showcase is live, the operator UI is no longer fully gated —
the public landing and `/demo/*` replays must reach unauthed visitors.
The Access policy is **path-scoped** so it only gates operator endpoints.

Either configure a single Access app per operator path, or use a single
app with a hostname pattern + path-include match. As of Cloudflare's
2025+ dashboard, the simplest path-include model works:

- **Application type:** Self-hosted
- **Application domain:** `agent.albeart.xyz`
- **Path-include rules** (one Access app per path prefix, OR a multi-path
  app if your dashboard version supports it):
  - `/sessions*`
  - `/run-sync`
  - `/config`
  - `/profiles`
  - `/files/*`
  - `/traces*`
  - `/evals/*`
  - `/schedules*`
- **Policies (per app):** identical to the default — `allow-known-emails`
  with the email allowlist.

**Paths intentionally NOT gated** (public, served to anyone):

- `/` and `/landing` — the public landing for unauthed visitors
- `/demo/*` — curated public replays (Bucket E in JBAgent's endpoint
  security contract; see `JBAgent/docs/2026-05-07-replay-mode-and-public-surface.md`)
- `/health` — gateway probe (Bucket D)
- `/transport/telegram/webhook`, `/transport/discord/interactions` —
  self-authenticating webhooks (Buckets B, C)
- `/assets/*`, `/favicon.*` — SPA static assets

#### Defense-in-depth: app-layer header check

When `JBAGENT_SHOWCASE_ENABLED=true`, the JBAgent server **also**
enforces the `Cf-Access-Authenticated-User-Email` header at the app
layer on every Bucket A endpoint. This is a second gate — if the
Cloudflare Access policy is ever loosened, broken, or bypassed by a
misrouted request, JBAgent still 401s. See the JBAgent ADR for the
mechanism.

The two layers fail closed independently:

- Cloudflare Access removed → app-layer 401 still fires.
- App-layer middleware disabled → Cloudflare Access still gates the path.

#### Switching between configurations

The default → showcase migration is done in the Cloudflare dashboard.
Order of operations:

1. **JBAgent first.** Deploy with `JBAGENT_SHOWCASE_ENABLED=true` so the
   app-layer middleware is active. The flag flip can ship to production
   without changing any Cloudflare state — the operator paths continue
   to be gated by both layers.
2. **Then narrow the Cloudflare Access scope.** In the dashboard, change
   the Access app from whole-hostname to path-scoped per the lists
   above, OR add bypass apps for the public paths. Test from an unauthed
   browser: `/` should now show the public landing, `/sessions` should
   still 401.
3. **Verify defense in depth.** With the new policy, `curl` an operator
   endpoint without a Cloudflare session and confirm it 401s twice in
   a row (first time from Cloudflare, second time from the app — depends
   which layer the curl hits first).

To revert: set the JBAgent flag to `false` and re-set the Access app to
whole-hostname scope. Both gates revert independently.

### telegram.albeart.xyz

No Access policy — this subdomain is the Telegram webhook endpoint. It
must be publicly reachable (Telegram's servers need to call it). Protected
at app layer by HMAC secret-token verification in `transports/telegram.py`.

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
