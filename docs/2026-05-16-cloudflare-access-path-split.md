---
name: cloudflare-access-path-split
description: ADR — split agent.albeart.xyz Cloudflare Access from one whole-domain app into two path-scoped apps so the showcase landing + replays can be public while operator endpoints remain gated. Records why two apps (not one), how the eight operator-path prefixes are distributed across the 5-row hostname cap, and the drift risk that comes with two policies.
---

# Path-scope `agent.albeart.xyz` Cloudflare Access into two apps

**Followed up by:** `JBAgent/docs/2026-05-18-cf-access-jwt-cookie-validation.md`
— the "App-layer expectations" section below claimed `/me` returns a
clean JSON 401 from `current_user` and identifies authed operators on
later requests. That second half was wrong: Cloudflare only injects
`Cf-Access-Authenticated-User-Email` on Access-app paths, so `/me`
returned 401 even to authed users and the SPA stayed stuck on the
public landing. The follow-up ADR records the fix (validate the
`CF_Authorization` JWT cookie at the origin against the team's JWKS).
The path-split decision below stands; only the App-layer expectation
narrative is superseded.

**Date:** 2026-05-16
**Status:** Accepted

## Context

Until today, `agent.albeart.xyz` was protected by a single Cloudflare
Access Application covering the whole domain (one `Application domain`
row: `agent.albeart.xyz`, no path). Every request — `/`, `/health`,
`/sessions`, anything — hit the email-allowlist gate. That was the right
shape for a single-operator deployment, but it makes the showcase
unreachable.

JBAgent's `JBAGENT_SHOWCASE_ENABLED=true` mode (see
`JBAgent/docs/2026-05-07-replay-mode-and-public-surface.md`) needs
specific endpoints to be reachable without auth:

- `/` — the unauthenticated `PublicLanding` page
- `/health` — gateway probe (already publicly contracted)
- `/demo/*` — Bucket E (curated trace replays, no LLM cost)
- `/transport/*` — Telegram + Discord webhooks (self-authed at the app layer)
- static assets (`/assets/*`, `/favicon.ico`, `/site.webmanifest`)

…while keeping the rest of Bucket A gated:

- `/sessions*`, `/run-sync*`, `/config*`, `/profiles*`, `/files*`,
  `/traces*`, `/evals*`, `/schedules*`

That's **eight** operator-path prefixes. Cloudflare's free plan caps
each Access Application at **five** `Application domain` rows
(hostname or hostname+path). So the natural "one app, eight rows"
solution doesn't fit.

## Decision

Split the gating across **two** Access Applications on the same
hostname, both running the same `allow-known-emails` policy:

```
agent.albeart.xyz
│
├── (no Access app — falls through to origin)
│   ├── /                                ← PublicLanding (or operator UI when logged in)
│   ├── /health                          ← gateway probe
│   ├── /demo/replays                    ← Bucket E: curated replay list
│   ├── /demo/{slug}/trace               ← Bucket E: trace JSON
│   ├── /demo/{slug}/stream              ← Bucket E: SSE replay
│   ├── /transport/telegram/webhook      ← self-authed (HMAC secret token)
│   ├── /transport/discord/interactions  ← self-authed (Ed25519 signature)
│   ├── /assets/*                        ← Vite bundle
│   ├── /favicon.ico, /apple-touch-*.png ← icons
│   └── /site.webmanifest                ← PWA manifest
│
├── App 1: "JBAgent" — high-freq operator UI       (Allow ← emails ∈ allowlist)
│   ├── /sessions*    ← list, show, run (SSE), stream (SSE)
│   ├── /files*       ← uploaded files
│   ├── /traces*      ← list, get, rename, fork, delete, star
│   ├── /profiles*    ← list profiles
│   └── /config*      ← operator config (admin-only)
│
└── App 2: "JBAgent — admin paths" — low-freq      (Allow ← emails ∈ allowlist)
    ├── /run-sync*    ← scheduler-internal POST endpoint
    ├── /evals*       ← eval-harness suites + runs
    └── /schedules*   ← scheduler introspection
```

The two apps share an identical Allow policy: emails in
`<operator allowlist>`, one-time-PIN fallback, 30-day session.

## Why two apps, not one

Three alternatives were considered.

1. **Single app + `Bypass` policy for the public paths.** Cloudflare
   Access `Bypass` actions apply to the whole app's domain — they
   don't filter by request path. So one app with a Bypass policy
   would either pass everything through (defeating the gate) or pass
   nothing through (defeating the showcase). Not viable.

2. **Upgrade Cloudflare to a paid plan** for higher per-app hostname
   limits. Buys the simpler one-app shape, costs money, doesn't change
   the security posture. Deferred until cost pressure or scale
   requires it.

3. **Drop the gateway-level gate entirely and rely on the server's
   app-layer middleware.** When `JBAGENT_SHOWCASE_ENABLED=true`,
   `server.py` already enforces the `Cf-Access-Authenticated-User-Email`
   header on Bucket A (defense in depth). The middleware would 401
   any unauthenticated Bucket A request. But losing the Cloudflare
   gate also loses the *redirect-to-login* UX and pushes all auth
   onto the app — a one-layer model, with no second-chance recovery
   if the middleware ever has a bug. Rejected.

Two apps is the minimum to fit eight prefixes under the 5-row cap.

## How the split was chosen

Eight prefixes, two buckets:

- **App 1 (5 rows)** = high-frequency operator-UI paths an operator
  hits per minute. Bundled because they share a single mental model
  ("the user is using the agent"). Tightening this app's policy
  (e.g., adding WARP) would affect daily operator UX, so keep it
  isolated.
- **App 2 (3 rows)** = admin / machine paths. `run-sync` is the
  scheduler's loopback POST endpoint, not user-driven. `evals` and
  `schedules` are touched rarely (operator-driven, but low cadence).
  Bundled so that a future security tightening (e.g., require WARP
  for admin actions) can be applied to App 2 without affecting daily
  operator UX.

A purely arbitrary 5+3 split would also work; the grouping above just
buys cleaner future surgery.

## Tradeoffs

**Drift between policies.** With two apps, adding or revoking an
allowed email must be applied to *both* policies. Forgetting one
leaves a gap — that user can still reach App 1 paths if they only
got removed from App 2 (or vice versa). Mitigations:

- Both apps use the same policy *name* (`allow-known-emails`) so the
  drift is visible at a glance in the Applications list.
- The server's `Cf-Access-Authenticated-User-Email` middleware (when
  `JBAGENT_SHOWCASE_ENABLED=true`) is the safety net — even if CF lets
  a request through that shouldn't be allowed, the app layer rejects
  it with 401. See
  `JBAgent/docs/2026-05-07-replay-mode-and-public-surface.md`.

**New Bucket A endpoint risk.** If a future PR adds an endpoint like
`/foo*` and forgets to add it to one of the two apps, the path is
silently public from Cloudflare's perspective. Same middleware safety
net applies. The lasting mitigation is the convention recorded here:
**every new Bucket A path must land in App 1 or App 2 before the
backing PR merges.** Reviewer rule, not an automated check today.

**Hostname-row inventory.** App 1 has zero headroom (5/5), App 2 has
two free rows. Future Bucket A additions live in App 2 until it
saturates, at which point a third app or the paid-plan upgrade is
forced.

## App-layer expectations

This ADR puts `/config*` and `/sessions*` behind App 1. Both paths
return a cross-origin 302 to `albear.cloudflareaccess.com` for any
request without a valid CF Access JWT cookie — a redirect the browser
CORS-blocks as `TypeError: Failed to fetch` when a SPA hits the path
from anonymous JavaScript.

The JBAgent SPA therefore uses **`/me`** (not `/config`) as its
anonymous auth probe on initial load. `/me` is outside both apps and
outside `_BUCKET_A_PREFIXES` (`JBAgent/server.py`), so it returns a
clean JSON 401 from the app's `current_user` dependency via Caddy —
which the SPA can interpret and use to render the public landing.
Only after `/me` confirms operator state does the SPA fetch
`/config` (the CF cookie auths through App 1 on the second hop).

See the JBAgent fix that wired this up:
`https://github.com/albear007/jbagent/pull/68`.

**Reviewer rule for future Bucket-A additions:** if the new endpoint
is on the SPA's anonymous-load critical path, it must either (a) stay
out of App 1 / App 2 and rely on the app-layer middleware, or (b)
land alongside an SPA change that adds an `/me`-style anonymous probe
to detect operator state before touching it. The "silently public if
forgotten" trap (recorded under § Tradeoffs) is the dual of this
trap: the "anonymous-broken if added to App 1 unannounced" trap.

## Operational notes

**Update procedure** when the operator allowlist changes:

1. Cloudflare Zero Trust dashboard → Access → Applications.
2. Open the App 1 policy, edit the `Include → Emails` list, save.
3. Open the App 2 policy, edit the *same* `Include → Emails` list, save.
4. Verify: `curl -sI https://agent.albeart.xyz/sessions` and
   `curl -sI https://agent.albeart.xyz/run-sync` both return 302 → CF
   Access login (from any non-allowed origin).

**Verification after platform changes** (box migration, gateway
deploy, etc.) — the 33-path sweep that proved this config worked is
worth re-running. Sketch:

```bash
for p in / /health /demo/replays /demo/market-brief /site.webmanifest /favicon.ico; do
  curl -sI -m 8 -w "%{http_code} %url_effective\n" -o /dev/null "https://agent.albeart.xyz$p"
done
# all → 200 (or 404 from origin if SHOWCASE off — both are public-pass-through)

for p in /sessions /files/x /traces /profiles /config /run-sync /evals /schedules; do
  curl -sI -m 8 -w "%{http_code} %url_effective\n" -o /dev/null "https://agent.albeart.xyz$p"
done
# all → 302 albear.cloudflareaccess.com/cdn-cgi/access/login/...
```

The full sweep (with near-miss singular paths like `/sess`, `/file`,
`/eval` etc. to confirm prefix matching is correct, not loose) lives
in this ADR's commit context.

## Follow-ups

- `chess.albeart.xyz` currently has its own Cloudflare Access app
  gating the whole subdomain. The architecture (`infra/runbooks/
  cloudflare-config.md`) calls for it to be public — auth is per-TD
  JWT at the app layer. Deletion deferred by the operator pending a
  separate go-live decision; that deletion does not interact with
  this ADR.
- If `chess.albeart.xyz` eventually needs a *partial* gate (e.g., an
  admin path), the pattern from this ADR is the template: path-scope
  Access apps within the 5-row cap.

## Related

- `JBAgent/docs/2026-05-07-replay-mode-and-public-surface.md` — the
  ADR that introduced `JBAGENT_SHOWCASE_ENABLED` and the
  `Cf-Access-Authenticated-User-Email` middleware.
- `infra/runbooks/cloudflare-config.md` — operational reference for
  the Cloudflare account; updated alongside this ADR.
- `JBAgent/misc/skills/2026-04-12-jbagent-e2e.md` — Endpoint Security
  Contract section: Buckets A through E.
