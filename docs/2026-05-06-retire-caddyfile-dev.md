---
name: retire-caddyfile-dev
description: ADR — retire caddy/Caddyfile.dev (unused since albear-t moved to Vite-direct dev). Closes the open question deferred by 2026-04-30-foundation.md.
---

# Retire `caddy/Caddyfile.dev`

**Date:** 2026-05-06
**Status:** Accepted
**Supersedes:** the third "Open Question" in `2026-04-30-foundation.md`
(lines 239-243).

## Context

The foundation ADR (`2026-04-30-foundation.md`) listed the fate of
`caddy/Caddyfile.dev` as an open question:

> Local-dev parity: `caddy/Caddyfile.dev` exists but no app's dev flow
> currently uses it (albear-t dev runs Vite directly post-Phase B).
> When a developer needs prod-like routing locally, decide whether to
> publish a docker-compose snippet that mounts this file, or retire
> the file. Defer until the need arises.

A week later, no app or developer has needed it. Both apps on the
platform (JBAgent and albear-t) develop without a local Caddy:

- **albear-t**: `npm run dev` (Vite) plus the FastAPI backend on a
  separate port. Production-style proxying is exercised in CI/PR
  preview deploys, not locally.
- **JBAgent**: `just dev` runs the harness on `:8000` and Vite on its
  own port; the React proxy in `vite.config.ts` handles the dev-time
  /api routing. No Caddy required.

Carrying the file forward implies a contract — "this is here for a
reason; figure out how to use it." Removing it is one less ambiguous
artifact, and `git log` preserves it if a future need re-emerges.

## Decision

Delete `caddy/Caddyfile.dev`.

## Consequences

- The "Open Question" section of `2026-04-30-foundation.md` lines
  239-243 is now resolved (this ADR is the resolution; per project
  convention the foundation ADR remains immutable).
- The file-tree snippet in `2026-04-30-foundation.md` line 181 is now
  one line stale. The discrepancy is acceptable — that ADR is a
  point-in-time snapshot of the foundation, not living truth. Future
  readers reach this ADR via the chronological dating in `docs/`.
- If a developer later wants prod-like local routing, they can either
  recover the deleted file from `git log` or write a fresh
  Caddyfile.dev based on the current snippet structure. Either path
  costs ~minutes.

## Alternatives considered

- **Keep the file with a header comment** (originally proposed in the
  cross-repo cleanup plan). Rejected: a comment claiming "kept for
  future use" without a concrete trigger has the same problem the
  foundation ADR's "defer until need arises" already had — no one
  knows when to pick it up. Deletion makes the absence explicit.
- **Publish a docker-compose snippet that mounts it** (the other
  branch of the foundation ADR's open question). Rejected: there is
  no concrete need today. If one materializes, write a fresh ADR
  scoped to that need.
