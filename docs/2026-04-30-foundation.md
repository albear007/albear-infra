---
name: albear-infra-foundation
description: Foundational ADR for albear-infra — why the repo exists, the Caddy snippets model, the firewall structure, the runbooks-vs-docs distinction, the deferred apps.yaml registry, the thin justfile that wraps SSH ops, and the documented Caddy reload-vs-restart gotcha. First ADR in this repo's docs/.
---

# albear-infra Foundation

**Date:** 2026-04-30
**Cross-references:**
- `albear-t/docs/2026-04-27-infrastructure-separation.md` — the original
  decision to extract this repo
- `JBAgent/docs/2026-04-29-deployment-and-security-audit.md` — the
  audit that executed the extraction (Phase B)
- `albear-t/docs/2026-04-27-static-asset-architecture-execution-notes.md`
  — origin of the Caddy reload gotcha

## Why This Came Up

`albear-infra` was created in late April 2026 by extracting Caddy +
firewall + platform runbooks out of `albear-t` (where Caddy was
proxying for both the portfolio and the agent) and `JBAgent` (where
the firewall script and VM migration SOPs lived). Both placements were
accidents of authorship — whichever repo needed the file first ended
up owning it — not architectural design.

The infrastructure-separation ADR proposed the split. The
deployment-and-security audit ADR executed it (Phases A and B). What
neither captured: the *internal* shape of `albear-infra` itself —
why the directory layout looks like it does, why `runbooks/` instead
of `docs/SOPs/`, why no `misc/skills/`, why a `justfile` was added
even though the runbooks already document the procedures.

This ADR is the first one in `albear-infra/docs/`. It records the
foundational decisions so a future operator (or a future agent) can
understand the shape of this repo without archaeologizing the chain
of cross-repo ADRs.

## What We Considered

### Decision 1 — Caddy snippets model

Caddy's main `Caddyfile.prod` is a single line: `import snippets/*.caddy`.
Each app gets one snippet under `caddy/snippets/<app>.caddy` describing
its own domain routing.

Alternatives:

- **One monolithic Caddyfile** with all apps' rules inline. Simpler
  initially; brittle as more apps land. A small change for one app
  forces the entire team to coordinate around a single file.
- **One Caddyfile per app, no `import` glob.** More explicit but
  requires hand-listing every snippet at the top, which is just a
  worse `import`.

Chose snippets + glob because:
- Per-app isolation: editing the JBAgent snippet doesn't risk
  destabilizing albear-t's routing.
- Easy onboarding: adding an app means dropping one new file in
  `caddy/snippets/`. No surgery on existing configs.
- Mirrors the per-app firewall structure (one chain per app).

### Decision 2 — Firewall structure

A custom iptables chain `JBAGENT_ACCESS` hangs off `INPUT` at position
1 and gates port 8000 (JBAgent). The `firewall/update-firewall.sh`
script flushes and rebuilds the chain idempotently from
`firewall/allowed-ips` (gitignored).

Alternatives:

- **No custom chain; raw rules in `INPUT`** — works for two rules,
  scales poorly with allowlist size and per-app gating.
- **`ufw` instead of raw iptables** — friendlier syntax, but the
  Cloudflare-IPs + Docker-bridge interaction is messier through ufw's
  abstraction; raw iptables is one less layer of indirection.
- **Cloudflare-only access control** (no host firewall) — relies on
  the upstream to never leak. Defense-in-depth wins.

Chose raw iptables + custom chain + idempotent script because:
- Per-app chains scale: the next app gets `<APP>_ACCESS`, same pattern.
- The script is the source of truth — running it on a fresh box
  reproduces the rules exactly.
- `netfilter-persistent save` makes rules survive reboots.
- Allowlist file is gitignored so personal/client IPs stay out of git.

### Decision 3 — `runbooks/` distinct from `docs/`

Operational playbooks (provisioning a box, onboarding a new app,
Cloudflare reference) live in `runbooks/`, not `docs/`. `docs/` is
reserved for ADRs (immutable decision history, the same convention as
JBAgent and albear-t).

Alternatives:

- **`docs/SOPs/`** — the convention albear-t's documentation-strategy
  ADR initially proposed. Dropped after JBAgent's Phase A audit
  established that ops procedures evolve too continuously to live as
  ADRs (which are append-only history) but also don't fit JBAgent's
  per-profile `sops/` model (which is per-agent-persona, not
  platform-wide).
- **Both `docs/SOPs/` and `docs/`** — split between mutable and
  immutable docs in the same directory. Confusing; the directory's
  name no longer signals immutability.
- **All in `docs/`** — would force the runbooks to be ADRs, which
  fights their purpose (they need to be edited as procedures change).

Chose `runbooks/` because the distinction is real and worth surfacing
in the directory name: runbooks change; ADRs don't.

### Decision 4 — No `misc/skills/` here

Skills are lazy-loaded reference material for agents (JBAgent at
runtime, Claude Code at dev time). JBAgent loads them from disk; other
repos don't have a runtime that needs them. Per the documentation-strategy
ADR in albear-t, skills are canonical in JBAgent and other repos point
at that directory.

Duplicating skills here would create drift. Linking from here would
create a cross-repo dependency for what is otherwise a self-contained
ops repo. Easier: don't have skills here, reference JBAgent's where
needed.

### Decision 5 — Defer `apps.yaml` (multi-app registry)

The `jbagent-architecture` skill names `albear-infra/apps.yaml` as a
planned layer-6 file: a registry of which apps live on the box, their
domains, ports, security buckets, and owner. The ADR for the multi-app
registry shape doesn't exist yet — it's deferred.

Alternatives:

- **Implement now** — would shape decisions before there's enough data
  to know what the registry should contain. Currently only two apps
  consume the platform; both are implicitly tracked by their snippets.
- **Defer until needed** — the per-snippet pattern is sufficient for
  N=2; revisit when N≥3.

Chose defer. The trigger: a third app ships, and we need to decide
what the per-app metadata is. At that point, write a new ADR shaped
by what the third app needs.

### Decision 6 — Thin `justfile` wrapping SSH ops

JBAgent's `jbagent-deployment` skill describes platform operations as
`just deploy-gateway`, `just update-firewall`, `just refresh-certs`. The
SSH commands behind those recipes are documented in this repo's
runbooks. Two paths:

- **No `justfile`** — operators copy-paste from the runbook each time.
  Simple but fragile; muscle memory drifts from the runbook.
- **`justfile` wrapping the SSH ops** — recipes match the JBAgent skill's
  references; the runbooks describe the *what* and the recipes are the
  *how*.

Chose to add the `justfile` because it makes JBAgent's deployment
skill text accurate (the recipes exist) and gives operators a stable
interface that's harder to drift from. The recipes are
intentionally thin — each is a one-line SSH wrapper around what the
runbooks already describe.

`provision` is the exception: provisioning is too involved (200+ line
runbook with manual Cloudflare and OCI steps) to wrap. The recipe
exists but only prints a pointer to the runbook.

### Decision 7 — Document the Caddy reload gotcha here

`caddy reload` silently no-ops in this environment;
`docker compose restart caddy` is required. The original observation
landed in `albear-t/docs/2026-04-27-static-asset-architecture-execution-notes.md`
when the Caddyfile lived in albear-t. Now that Caddy lives here, the
gotcha is a platform-side commitment and should have a record here.

## What We Decided

All seven decisions above. The repo's directory layout is the result:

```
albear-infra/
  caddy/
    Caddyfile.prod        ← imports snippets/
    Caddyfile.dev         ← optional local-dev gateway (currently unused; albear-t dev runs Vite directly)
    snippets/
      albear-t.caddy
      jbagent.caddy
  firewall/
    update-firewall.sh
    allowed-ips           ← gitignored
  runbooks/
    platform-onboarding.md
    vm-migration-platform.md
    cloudflare-config.md
  docs/
    2026-04-30-foundation.md  ← this file
  justfile
  docker-compose.yml      ← Caddy-only
  README.md
  CLAUDE.md
  .env.example
  .env                    ← gitignored
  certs/                  ← gitignored, on the box only
```

Caddy must be **restarted**, not reloaded, after any Caddyfile or
snippet change in production. `just deploy-gateway` does this.
`runbooks/platform-onboarding.md:88` and `README.md:39` use the right
verb (post-2026-04-30 cleanup).

## Tradeoffs Accepted

- **`runbooks/` vs `docs/` distinction is convention-only.** A future
  operator might write a new operational doc and put it in `docs/` by
  reflex. Mitigation: this ADR; CLAUDE.md states the rule explicitly.
- **`apps.yaml` deferral means the platform's app list is implicit**
  in the snippet directory and the firewall script. For N=2, the
  inference is trivial; for N≥3 with varied security buckets, the
  implicit list will start to hurt. Acceptable until then.
- **`justfile` adds a small layer between operators and the actual
  commands.** The recipes are thin enough that anyone can `cat
  justfile` and read what each does, but if the recipe drifts from
  what the runbook describes, two things to keep in sync.
- **The Caddy reload-vs-restart gotcha is documented in three
  places** (this ADR, the platform-onboarding runbook, the
  static-asset execution-notes ADR in albear-t). Triplicate
  documentation has duplication cost; the alternative — only one
  source — would mean an operator following one document might not
  see the rule. Worth the duplication; the rule is sneaky and silent
  failures are expensive.

## Open Questions

- When a third app lands, write the `apps.yaml` ADR and decide the
  registry shape based on what that third app actually needs.
- A graceful Caddy reload would be preferable to a restart for
  higher-traffic origins. Today's traffic profile makes the dropped-
  connections cost negligible, but if traffic grows or another
  high-throughput app lands, revisit. The fix would be a Caddy
  upgrade with `caddy reload --force` or moving to a config-watcher
  pattern; both are ADR-worthy when the time comes.
- Local-dev parity: `caddy/Caddyfile.dev` exists but no app's dev
  flow currently uses it (albear-t dev runs Vite directly post-Phase B).
  When a developer needs prod-like routing locally, decide whether to
  publish a docker-compose snippet that mounts this file, or retire
  the file. Defer until the need arises.
