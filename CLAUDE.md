# albear-infra — platform coordination

Caddy gateway, firewall (`JBAGENT_ACCESS` iptables chain), TLS certs,
platform runbooks. Layer 5-6 of the layered ownership model. Shared
across apps that live on the same box.

## Stack

- **Gateway**: Caddy 2 (Docker), TLS termination + reverse proxy
- **Firewall**: iptables, idempotent script in `firewall/`
- **Certs**: Cloudflare Origin CA (15-year lifetime, gitignored)
- **DNS / Zero Trust**: Cloudflare (dashboard-managed; runbook is the
  reference)

## Run

```bash
just validate          # lint Caddyfile locally
just deploy-gateway    # pull + up + restart caddy on the box
just update-firewall   # sync allowed-ips and rerun the iptables script
just refresh-certs     # rotate TLS certs
just ssh               # open shell on the box
```

The `provision` recipe is intentionally a pointer to
`runbooks/vm-migration-platform.md` — provisioning is too involved for a
one-liner.

## Documentation conventions

- **`docs/`** is **ADRs only**. Immutable decision history, dated
  `YYYY-MM-DD-<slug>.md`. Append-only — when a decision changes, write
  a new ADR rather than editing the old one. (Same convention as
  JBAgent and albear-t.)
- **`runbooks/`** is mutable operational playbooks — provisioning,
  onboarding a new app, Cloudflare reference. Updated in place when
  procedures evolve. This is the platform's "living truth" for ops.
- **No `misc/skills/`** here. Skills are owned by JBAgent
  (`JBAgent/misc/skills/`), and other repos point at that directory.
  Don't duplicate.
- **No `apps.yaml`** today. The multi-app registry is deferred until a
  third app lands (currently only JBAgent and albear-t consume the
  platform).

## Where to look

- `runbooks/platform-onboarding.md` — adding a new app (Caddy snippet,
  firewall, DNS, Zero Trust).
- `runbooks/vm-migration-platform.md` — provisioning a new box (paired
  with `JBAgent/docs/2026-04-29-jbagent-app-bootstrap.md`).
- `runbooks/cloudflare-config.md` — Cloudflare DNS, TLS, Zero Trust
  reference (dashboard is authoritative).
- `docs/2026-04-30-foundation.md` — why this repo is shaped the way it
  is (Caddy snippets model, firewall structure, runbooks-vs-docs
  decision, the Caddy reload gotcha).
- **`jbagent-architecture` skill** in `JBAgent/misc/skills/2026-04-12-jbagent-e2e.md`
  — canonical reference for the layered ownership model and gateway
  contract. This repo is layers 5-6; app repos own layers 1-4.
- **`cross-repo-workflow` skill** in
  `JBAgent/misc/skills/2026-04-30-cross-repo-workflow.md` — deploy
  ordering when changes span repos, where each kind of decision is
  recorded, the Caddy reload-vs-restart gotcha.

## Expected box directory layout

```
~ubuntu/
  infra/             → this repo (albear-infra)
    certs/           → TLS cert + key (gitignored)
    firewall/
      allowed-ips    → operator IP allowlist (gitignored)
  albear-t/          → portfolio app
    dist/            → Vite bundle (mounted into Caddy)
    static/          → user content (mounted into Caddy)
  jbagent/           → agent harness
    .env             → API keys / tokens (gitignored)
```

Caddy reads from `/home/ubuntu/albear-t/{static,dist}` and
`/home/ubuntu/infra/certs` at request time. The cross-repo
`docker-compose.yml` mounts assume this layout.

## Secrets handling

| What | Where | How synced |
|---|---|---|
| TLS cert + key | `infra/certs/` (gitignored, on box at `~/infra/certs/`) | `scp` during cert refresh; `just refresh-certs` wraps this |
| Operator IP allowlist | `infra/firewall/allowed-ips` (gitignored) | `scp` and `bash update-firewall.sh`; `just update-firewall` wraps this |

JBAgent runtime secrets and albear-t deploy creds live in their own
repos. See the `cross-repo-workflow` skill for the full table.

## Cosmetic naming note

The repo is `albear-infra` on the remote, but the local checkout
directory is `infra/`. That's fine — the remote name is authoritative,
and references in this repo (`cd ~/infra` on the box, sibling-checkout
mounts) use the local dir name. Other repos cross-link by repo name
(`albear-infra`).

## Auto-memory is disabled

Do not write to Claude Code's auto-memory
(`~/.claude/projects/.../memory/`) for this project. Anything worth
persisting goes in an ADR, a runbook, or a skill (in JBAgent), under
git.
