# Public Status Page — Runbook (L20-06)

**Audit finding:** [`L20-06 — Status page pública inexistente`](../audit/findings/L20-06-status-page-publica-inexistente.md) (Lente 20 — SRE, High).
**CI guard:** `npm run audit:public-status` (see `tools/audit/check-public-status.ts`).
**Endpoint:** `GET /api/public/status` (unauthenticated, CORS-open).

## Problem

Before this fix, the only public signal users had for "Is Omni Runner
operational?" was the opaque `GET /api/health` endpoint (boolean
`ok | degraded | down`). During any outage, support was flooded with
individual tickets ("is it down for you too?") because there was no
canonical page to point at. The audit finding explicitly asks for
something like `status.omnirunner.com`, consumable by:

- athletes and coaches checking the app;
- uptime probes (UptimeRobot, Better Stack, Atlassian Statuspage);
- external status aggregators that want a machine-readable feed.

## What shipped

1. **`portal/src/lib/status/types.ts`** — canonical value objects:
   - `StatusComponent` (`web | api | database | auth | payments |
     strava`) with pinned order in `STATUS_COMPONENTS`;
   - `StatusLevel` (`operational | degraded | partial_outage |
     major_outage | unknown`) and `compareStatusLevels()` with
     pinned worst-wins ordering;
   - `StatusFeed`, `ComponentStatus`, `AggregateStatus` interfaces;
   - `STATUS_CACHE_MIN_TTL_MS = 30_000` floor (CI-pinned — vendor
     rate-limit protection).
2. **`portal/src/lib/status/aggregate.ts`** — pure aggregator:
   - `aggregateStatus()` fills any missing component with
     `unknown + 'no feed registered'`, so a forgotten feed can never
     silently hide a component.
   - `collectFromFeeds()` coerces every throw/rejection to
     `unknown + 'feed fetch failed'`, so a single vendor outage can
     never 5xx the whole status endpoint.
   - `createCachedAggregator()` TTL-caches the aggregate (default
     60 s, floor 30 s).
3. **`portal/src/lib/status/feeds.ts`** — `staticFeed`,
   `internalProbeFeed` (delegates to an injected `() => 'ok' |
   'degraded' | 'down'` probe), and `withTimeout` wrapper.
4. **`portal/src/app/api/public/status/route.ts`** — public endpoint
   with `GET` + `OPTIONS` (CORS preflight), CORS-permissive headers,
   never-5xx fallback.
5. **Unit tests** (`portal/src/lib/status/__tests__/aggregate.test.ts`)
   — 27 tests covering canonical ordering, worst-wins level ranking,
   duplicate-component handling, timeout behaviour, TTL floor,
   invalidate(), and feed-level graceful degradation.
6. **CI guard** (`tools/audit/check-public-status.ts`) — 40+ checks
   pinning every invariant above.

## What did **not** ship (follow-ups)

The domain + endpoint is deliberately scoped. These are tracked
separately so we don't ship unvalidated vendor wiring:

- `L20-06-external-feeds` — real Vercel / Supabase / Stripe / Strava
  feed adapters that parse the vendors' public status APIs. Gated
  behind an env flag so local dev never hits vendor endpoints.
- `L20-06-incident-timeline` — a read model for ongoing incidents
  (title, status, latest update, affected components) that the
  status page renders below the components grid.
- `L20-06-site` — the actual `status.omnirunner.com` static site
  (probably Next.js static export or Cachet/Statuspage self-host).
- `L20-06-i18n` — localize `STATUS_COMPONENT_LABELS` once we settle
  on the i18n story for the portal.
- `L20-06-rate-limit` — currently relies on the platform edge rate
  limiter for DoS protection; a dedicated per-IP limiter on the
  aggregate endpoint is on the security wishlist.

## Response contract

```json
{
  "overall": "degraded",
  "components": [
    { "component": "web",      "level": "operational",
      "observedAt": "2026-04-21T12:00:00.000Z" },
    { "component": "api",      "level": "degraded",
      "observedAt": "2026-04-21T12:00:00.000Z",
      "note": "p95 > 1s" },
    { "component": "database", "level": "operational",
      "observedAt": "2026-04-21T12:00:00.000Z" },
    { "component": "auth",     "level": "operational",
      "observedAt": "2026-04-21T12:00:00.000Z" },
    { "component": "payments", "level": "unknown",
      "observedAt": "2026-04-21T12:00:00.000Z",
      "note": "feed fetch failed" },
    { "component": "strava",   "level": "operational",
      "observedAt": "2026-04-21T12:00:00.000Z" }
  ],
  "generatedAt": "2026-04-21T12:00:00.000Z"
}
```

Component order is **always** `[web, api, database, auth, payments,
strava]`. The renderer does not need to sort.

## How to add a component

1. Extend `StatusComponent` union + `STATUS_COMPONENTS` array +
   `STATUS_COMPONENT_LABELS` map in `types.ts`.
2. Register a feed for the new component in the route handler
   (`portal/src/app/api/public/status/route.ts`), wrapped in
   `withTimeout(..., 2_000)`.
3. Add a test in `aggregate.test.ts` for the new label & ordering.
4. Re-run `npm run audit:public-status` until all checks pass.
5. Update this runbook's "Response contract" example.

## How to tune cache TTL

The default is 60 s. Floor is 30 s, pinned by CI. You can pass a
custom TTL to `createCachedAggregator({ ttlMs: ... })`. Going below
30 s requires moving the floor in `STATUS_CACHE_MIN_TTL_MS` — which
the CI guard flags — and writing a follow-up ADR explaining why the
rate-limit risk against vendor APIs is acceptable.

## Operational playbooks

### "User reports the status page says 'unknown' but the app works"

Expected when an individual feed provider is down or slow. Steps:

1. Hit `/api/public/status` and confirm which components report
   `unknown`.
2. Check the logs for `status.aggregate_failed` or
   `status.api_probe_failed` warnings.
3. If a specific vendor feed is down, open a follow-up incident on
   `L20-06-external-feeds` (or the appropriate vendor integration).
4. The renderer MUST visually distinguish `unknown` from
   `operational` — if it doesn't, that's a separate bug in the
   renderer.

### "We have an outage — how do I force a status update?"

The aggregate is cached server-side (up to 60 s). To force a
refresh on the next request you have three options:

1. **Redeploy** — the module-level cache resets with the lambda.
2. **Restart the container** — if you control the runtime.
3. **Invalidate via admin endpoint** — not yet shipped; follow-up
   `L20-06-admin-invalidate`.

Until (3) ships, SRE communicates outages through the separate
incident timeline (currently manual).

### "A vendor status API started 5xx'ing"

Expected behaviour: the affected component drops to `unknown`, the
overall status becomes `unknown` (or worse if others are also
down), and the endpoint keeps returning 200. If instead you see the
whole `/api/public/status` returning 5xx, that's a bug in
`collectFromFeeds` coercion — open a critical incident and pin
`audit:public-status` to confirm the CI guard still catches the
regression.

## Detection signals

- `status.aggregate_failed` — internal logger warning when the
  aggregator fell back to the empty-feed payload. Should be ~0.
- `status.api_probe_failed` — internal probe rejected (DB
  unreachable from the portal process). Alarm at >1/min.
- External synthetic check on `GET /api/public/status` returning
  something other than HTTP 200 — should never happen by design.

## Rollback

If the public status endpoint misbehaves in a way we cannot hot-fix
(e.g. leaks internal detail), the rollback is:

1. Ship a patch that replaces the route body with the "empty feed"
   fallback (always returns `unknown` for every component, HTTP 200).
2. Point `status.omnirunner.com` at a static "investigating" page.
3. Keep `GET /api/health` (L06-02) untouched — that one is behind a
   different set of invariants and is the authoritative uptime
   probe.

## References

- Finding: [`L20-06`](../audit/findings/L20-06-status-page-publica-inexistente.md)
- Related:
  - [`L06-02`](../audit/findings/L06-02-health-check-exibe-contagem-exata-de-violacoes-info.md) — opaque `/api/health`.
  - [`L01-07`](../audit/findings/L01-07-get-api-health-information-disclosure.md) — info-leak hardening on `/api/health`.
