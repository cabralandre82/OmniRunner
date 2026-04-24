# API Content Negotiation Policy

**Status:** Ratified (2026-04-21)
**Owner:** platform + product
**Related:** L14-08, OpenAPI registry (L14-01).

## TL;DR

- All API endpoints respond with `application/json` by default.
- Endpoints that have a **legitimate non-JSON shape** (CSV
  export, ICS calendar feed, PDF receipt) live at a **separate
  URL**, not behind `Accept`-header negotiation on the same
  URL.
- Server returns `406 Not Acceptable` only when the client
  explicitly sends an `Accept` header that excludes
  `application/json` AND the route has no alternate
  representation.

## Why "different URL" beats "same URL + Accept-header"

We considered the canonical REST move — single endpoint, switch
on `Accept: text/csv` — and rejected it for our scale and
audience:

1. **Cache poisoning surface.** Vercel + Cloudflare cache by
   URL by default. Adding `Vary: Accept` is fragile (proxies
   strip it; some CDN tiers don't honour it).
2. **OpenAPI tooling is happier with one shape per route.**
   `@hey-api/openapi-ts` and `openapi_generator` (Dart) both
   produce cleaner code when the response schema is mono-typed.
3. **Auditability.** "GET /api/admin/sessions/export.csv" is a
   self-evident operation in audit logs; "GET /api/admin/sessions
   with Accept: text/csv" requires correlating two fields.
4. **Auth model.** Many CSV exports require an extra
   "platform_admin" check that JSON list endpoints don't. Two
   URLs let us mount different middleware.

## Naming convention

| Format       | URL suffix        | Content-Type                     | Notes |
|--------------|-------------------|----------------------------------|-------|
| JSON         | (default)         | `application/json; charset=utf-8`| Standard response |
| CSV export   | `.../export.csv`  | `text/csv; charset=utf-8`        | Streamed, RFC-4180 quoted, UTF-8 BOM, max 10k rows. >10k → `202 Accepted` + email link. |
| Calendar feed| `.../calendar.ics`| `text/calendar; charset=utf-8`   | RFC-5545. Auth via signed URL with TTL 24h. |
| PDF receipt  | `.../receipt.pdf` | `application/pdf`                | NF-e and withdrawal receipts (L09-04). |
| OpenAPI doc  | `/api/v1/openapi.json` | `application/json`           | Per L14-01 registry. |

## Existing endpoints that already follow this

- `GET /api/v1/openapi.json` — OpenAPI doc, JSON only.
- `GET /api/admin/sessions/export.csv` — admin audit export
  (separate route; not yet built but spec'd here).
- `GET /api/billing/receipts/[id]/receipt.pdf` — receipt
  download (planned with L09-04 NF-e wave).

## Headers we DO honour on every endpoint

- `Accept-Language` — picks `pt-BR` vs `en-US` for error
  messages bodied in `error.message`. (Default `pt-BR`.)
- `Accept-Encoding` — gzip / br negotiation handled at the
  Vercel layer, not in route code.
- `Idempotency-Key` — see `IDEMPOTENCY_CONTRACT.md` (L14-07).
- `If-None-Match` / `ETag` — currently only on
  `GET /api/v1/openapi.json` and the future `GET
  /api/dashboards/*` cached responses.

## Headers we explicitly DO NOT honour

- `Accept: application/xml`, `application/x-protobuf`,
  `application/cbor`, etc. → `406 Not Acceptable`. We are
  JSON-only by design (smaller blast radius for parsing bugs).
- `Accept-Charset` → ignored. All endpoints emit UTF-8.
- `Range` → ignored on JSON endpoints. PDF / CSV downloads use
  Vercel's CDN-level `Range` support transparently.

## Migration path for the next CSV/ICS export request

When a new use-case lands ("export weekly leaderboard as
CSV"), the team:

1. Adds a new route under `/api/.../export.csv`.
2. Reuses the JSON list endpoint's data layer (don't duplicate
   the query).
3. Streams the response (`ReadableStream` in Next.js) to avoid
   loading 10k rows into memory.
4. Writes an OpenAPI entry for the new route in
   `portal/src/lib/openapi/registry.ts`.
5. Adds an audit log row (`event_domain='admin'`,
   `action='<route>.exported'`) for any CSV the operator
   downloads — chargeback / dispute hygiene.
