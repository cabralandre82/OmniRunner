# API Error Handling Runbook (L17-01)

Operational guide for the `withErrorHandler` middleware that wraps every
financial / platform-admin route under `portal/src/app/api/**`.

> Audience: backend on-call + portal devs adding new routes. Read time ~ 6 min.

## When to use this runbook

- A user / partner reports a **non-canonical 5xx body** (raw stack trace,
  `String(e)` payload, `{ error: "..." }` without the `ok: false` envelope)
  from a financial endpoint.
- Sentry shows a **route-level exception with no breadcrumb / no
  `omni.route` tag** — meaning the route bypassed `withErrorHandler`.
- A new financial route lands in PR and you need to confirm it follows
  the wrapper convention.
- The L17-01 CI guard (`tools/check_financial_routes_have_error_handler.ts`)
  fails on `master` or in a PR.
- You're triaging an incident and want a quick refresher on the
  canonical error envelope and how `x-request-id` propagates.

## Architecture — 30-second recap

```
                                ┌────────────────────────────┐
client ───► /api/<route> ────►  │  withErrorHandler wrapper  │ ─────┐
  with                          │  (portal/src/lib/api-      │      │
  x-request-id?                 │   handler.ts)              │      │
                                └────────────────────────────┘      │
                                       │      ▲                     ▼
                                       │      │ throws        ┌──────────────┐
                                       ▼      │               │   handler    │
                              ┌──────────────────────────┐    │ (_get/_post) │
                              │ Sentry breadcrumb        │    └──────────────┘
                              │   omni.route, http.method│             │
                              │ logger.error(...)        │             │
                              │ apiError(req, "INTERNAL_ │             ▼
                              │   ERROR", ...)           │       NextResponse
                              └──────────────────────────┘             │
                                       │                               │
                                       └──────────────► Response with  │
                                                       x-request-id  ◄─┘
```

- **Outermost net**: any `throw` inside the handler (or any helper it
  calls) becomes a canonical `500 INTERNAL_ERROR` envelope. Raw error
  messages, SQL strings, and stack traces NEVER reach the client.
- **Sentry**: `Sentry.getActiveSpan()` is tagged with `omni.route` +
  `http.method` so search/filter is precise. Errors are also captured
  via `logger.error` (which calls `Sentry.captureException` internally).
- **Request ID**: read from incoming `x-request-id` (or generated via
  `crypto.randomUUID()`) and echoed in BOTH the response header AND
  the body’s `error.request_id` field.
- **Domain errors**: handlers can opt into an `errorMap` to map
  domain-specific errors (e.g. `SwapError`, `FxQuoteError`) to custom
  status codes BEFORE the generic 500 fallback.

## Canonical error envelope

```jsonc
// 500 (or any non-2xx, when produced by the wrapper or by apiError())
{
  "ok": false,
  "error": {
    "code": "INTERNAL_ERROR",      // or NOT_FOUND / FORBIDDEN / VALIDATION_FAILED / ...
    "message": "Internal server error",
    "request_id": "8e2…",          // matches x-request-id header
    "details": { /* optional, schema-defined */ }
  }
}
```

The `code` enum lives in `portal/src/lib/api/errors.ts#COMMON_ERROR_CODES`
and the response builders are `apiError(...)` / `apiUnauthorized(...)` /
`apiForbidden(...)` / `apiValidationFailed(...)` / `apiInternalError(...)`.

## Diagnostics

### "Client received a raw stack trace from /api/swap"

```bash
# Confirm the response did NOT come from the wrapper
curl -is https://omnirunner.app/api/swap -H "x-request-id: probe-1" -X POST -d '{}'
#  Expected on error: HTTP 500 + body { ok: false, error: { code: "INTERNAL_ERROR", request_id: "probe-1", ... } }
#  Bad: HTTP 500 + body { error: "PrismaClientKnownRequestError: ..." } or text/plain stack trace.
```

If the body lacks `ok: false`, the route is not wrapped (or the throw
escaped above the wrapper — which should be impossible). Inspect the
route file:

```bash
rg "^export\s+(async\s+function|const)\s+(GET|POST|PUT|DELETE|PATCH)" \
   portal/src/app/api/swap/route.ts
```

The expected line is:

```ts
export const POST = withErrorHandler(_post, "api.swap.post");
```

### "Sentry has the error but no `omni.route` tag"

The error came from outside `withErrorHandler` (e.g. from middleware,
edge runtime, or a route that hasn't been wrapped). Run the guard:

```bash
npx tsx tools/check_financial_routes_have_error_handler.ts
```

Any `FAIL` line identifies a financial route still using
`export async function ...`.

### "Operator says they don't see x-request-id in our response"

Confirm both the header and the body field:

```bash
curl -is https://omnirunner.app/api/custody \
     -H "x-request-id: ops-trace-42" -X POST -d 'not-json'
# Expected: response header `x-request-id: ops-trace-42`
#           body `error.request_id == "ops-trace-42"`
```

If the header is missing, the route is bypassing the wrapper. If the
body is missing it but the header is present, the route is using a
hand-rolled `NextResponse.json({ error: ... })` instead of the
`apiError(...)` helpers — file a bug and fix the route to use the
canonical builders.

## CI guard

The guard at `tools/check_financial_routes_have_error_handler.ts` enforces
the wrapper convention. It is intentionally scoped to **financial /
platform-admin** routes (see `FINANCIAL_ROUTE_PATTERNS` in the script).

```bash
# default — pretty output, exit 1 only if a financial route is unwrapped
npx tsx tools/check_financial_routes_have_error_handler.ts

# only show failures
npx tsx tools/check_financial_routes_have_error_handler.ts --quiet

# JSON output for CI dashboards
npx tsx tools/check_financial_routes_have_error_handler.ts --json

# strict — also fail on non-financial routes (use only when extending coverage)
npx tsx tools/check_financial_routes_have_error_handler.ts --strict
```

Add the guard to CI as a step _before_ vitest so engineers see the
clear "wrap with withErrorHandler" message before chasing test errors.

## Onboarding a new financial route

1. Define your handler as a private function:
   ```ts
   async function _post(req: NextRequest) { /* ... */ }
   ```
2. Wrap and export it:
   ```ts
   export const POST = withErrorHandler(_post, "api.<group>.<verb>");
   ```
3. Use the canonical helpers for non-500 responses:
   ```ts
   import {
     apiUnauthorized, apiForbidden, apiValidationFailed, apiError,
   } from "@/lib/api/errors";
   if (!user)            return apiUnauthorized(req);
   if (!isAdmin)         return apiForbidden(req);
   if (!parsed.success)  return apiValidationFailed(req, msg, parsed.error.flatten());
   ```
4. Reserve `try/catch` for **domain errors you know how to handle**
   (e.g. mapping a `SwapError` to a 422). Never catch-and-format a
   generic `Error` — let it bubble to the wrapper.
5. Optional: pass an `errorMap` to attach domain mappings:
   ```ts
   export const POST = withErrorHandler(_post, "api.swap.post", {
     errorMap: (err, req) => {
       if (err instanceof SwapError) return apiError(req, "SWAP_REJECTED", err.message, 422);
       return null; // fall through to generic 500
     },
   });
   ```
6. Run the guard locally: `npx tsx tools/check_financial_routes_have_error_handler.ts`
7. Add a vitest case asserting the canonical envelope on an unexpected
   throw (see `portal/src/lib/api-handler.test.ts` for templates).

## Common pitfalls

| Pattern | Why it breaks | Fix |
|---|---|---|
| `export async function POST(...)` | Wrapper is not invoked. CI guard fails. Sentry loses route tag. | Rename to `_post` and wrap. |
| `try { ... } catch (e) { return NextResponse.json({ error: String(e) }, { status: 500 }) }` | Leaks raw error message; non-canonical body; no `request_id`. | Remove the catch — let it bubble; or use `apiError(req, "INTERNAL_ERROR", "...", 500)`. |
| `return NextResponse.json({ error: "Não autenticado" }, { status: 401 })` | Hardcoded pt-BR; non-canonical body. | `return apiUnauthorized(req);` |
| `withErrorHandler(handler)` (no route name) | Sentry tag missing. | Always pass `"api.<group>.<verb>"`. |
| Wrapping a Next.js route handler that itself returns `void` | Wrapper expects `NextResponse`. | Always `return` a `NextResponse`. |

## Cross-references

- `docs/audit/findings/L17-01-witherrorhandler-nao-e-usado-em-endpoints-financeiros-critic.md`
- `docs/audit/findings/L14-05-api-error-envelope-inconsistente.md` (canonical envelope)
- `docs/audit/findings/L13-06-x-request-id-nem-sempre-propagado.md` (request id)
- `portal/src/lib/api-handler.ts` (wrapper implementation)
- `portal/src/lib/api/errors.ts` (envelope builders)
- `portal/src/lib/api-handler.test.ts` (wrapper tests)
- `tools/check_financial_routes_have_error_handler.ts` (CI guard)
