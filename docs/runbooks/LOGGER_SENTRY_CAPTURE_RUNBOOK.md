# Logger Sentry capture runbook (L17-05)

> **Scope:** Next.js portal (`portal/src/lib/logger.ts`)
> **Owner:** portal
> **Last updated:** 2026-04-21
> **Related findings:** `L17-05`, `L20-03` (trace correlation), `L17-03`
> (withErrorHandler types)

## 1. Why this exists

`logger.error(msg, error?, meta?)` is the **single** sanctioned way for
portal code to emit an error-level log line. Every other surface that
looks like an error (a thrown `Response`, a `console.error`, an awaited
`captureException` in local code) routes back through this helper by
convention and by the matching `withErrorHandler` top-level wrapper.

Historically the helper had a subtle branch that silently dropped
error-class events from Sentry whenever the caller did not pass an
`Error` instance:

```ts
if (error instanceof Error) {
  Sentry.captureException(error, ...);
} else if (error) {           // ← bug: `undefined` / `null` / `0` / "" fall through
  Sentry.captureMessage(msg, ...);
}
```

That shape meant patterns like

- `logger.error("custody.webhook.config_missing", undefined, { gateway });`
- `logger.error("checkout.proxy.gateway_non_json", undefined, { ... });`
- `logger.error("custody.webhook.dispute_feature_unavailable", undefined, { ... });`

were **console-logged only**. PagerDuty fired because the wrapping
`withErrorHandler` eventually reached a 5xx path, but Sentry had no
event and incident responders had no stacktrace, no trace link, and no
release metadata. The gap was first observed during a 2026-04-18
custody webhook outage where the operator spent 22 minutes correlating
CloudWatch console lines before the underlying gateway 403 was
identified.

This runbook documents the invariant that closes that gap.

## 2. Invariant

**`logger.error(...)` always emits one Sentry event, regardless of the
`error` argument.**

| `error` argument               | Sentry transport                 | Console log fields                   |
| ------------------------------ | -------------------------------- | ------------------------------------ |
| `Error` instance               | `Sentry.captureException(error)` | `{ error: .message, stack: .stack }` |
| `string` / `number` / `boolean`| `Sentry.captureMessage(msg, error)` | `{ error: String(error) }`       |
| plain object / array           | `Sentry.captureMessage(msg, error)` | `{ error: <shallow JSON clone> }`|
| `undefined` / `null`           | `Sentry.captureMessage(msg)`     | *no `error` field, no `stack`*       |

The `extra` payload always carries `meta` (caller context) so support
can pivot from Sentry back to the originating request/cron/job.

Trace correlation (`trace_id` / `span_id` from L20-03) is still applied
transparently via `activeTraceContext()`.

## 3. What shipped (commit landing this invariant)

| Piece                                           | File                                                |
| ----------------------------------------------- | --------------------------------------------------- |
| `normalizeErrorFields(error)` helper            | `portal/src/lib/logger.ts`                          |
| Unconditional `Sentry.captureMessage` fallback  | `portal/src/lib/logger.ts` (inside `error(...)`)    |
| Test suite `L17-05 Sentry capture invariants`   | `portal/src/lib/logger.test.ts`                     |
| CI guard `npm run audit:logger-sentry-capture`  | `tools/audit/check-logger-sentry-capture.ts`        |
| This runbook                                    | `docs/runbooks/LOGGER_SENTRY_CAPTURE_RUNBOOK.md`    |

The helper is called by 30+ API routes and 2 client screens.

## 4. How to call it

```ts
import { logger } from "@/lib/logger";

// ✅ recommended — always give Sentry an Error to anchor the stacktrace
try {
  await gateway.charge(...);
} catch (err) {
  logger.error("custody.webhook.gateway_failed", err, { gateway, invoiceId });
  throw err;
}

// ✅ acceptable — no Error yet, we only know `something is wrong`
if (!cfg) {
  logger.error("custody.webhook.config_missing", undefined, { gateway });
  return Response.json({ ok: false }, { status: 502 });
}

// ✅ acceptable — pass a string for context when the upstream gave you a body
if (!isJson(body)) {
  logger.error("checkout.proxy.gateway_non_json", body.slice(0, 256), {
    contentType,
  });
  return Response.json({ ok: false }, { status: 502 });
}
```

### Anti-patterns

```ts
// ❌ don't pass the message as the error — Sentry dedup will hash on the message
logger.error("failed", "failed");

// ❌ don't swallow — if you have the Error, pass it; the stack is the
// primary debugging asset
logger.error("checkout.proxy.gateway_non_json", undefined, { err });

// ❌ don't embed PII / tokens in meta — the logger does NOT redact
logger.error("auth.failed", err, { email, password: "…" });
```

## 5. Detection signals

| Signal                                                  | Surface                                                                                     |
| ------------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| Sentry issue count on the `config_missing` events       | Sentry → Issues → filter `msg:"custody.webhook.config_missing"` (should be ≥ 1 per incident)|
| Sentry:Log ratio on CloudWatch                          | `cloudwatch:rate(error-level logs) / sentry:rate(error-level events)` should stay near 1    |
| CI                                                      | `npm run audit:logger-sentry-capture` must stay green                                        |
| Test run                                                | `npx vitest run portal/src/lib/logger.test.ts` — 14 tests                                   |

If Sentry:Log ratio drifts below 0.95 for 10 minutes, page portal
on-call — either the logger regressed or SDK init is broken.

## 6. Operational playbooks

### 6.1 Sentry stops receiving events during an incident

1. Confirm SDK initialised: look for `Sentry` in the Next.js build
   output and `NEXT_PUBLIC_SENTRY_DSN` in the environment variables.
2. Run `npm run audit:logger-sentry-capture` against the deploying
   branch — this will catch a regressed logger in CI before rollout.
3. Temporarily bypass by raising an Error (`throw new Error("…")`) at
   the suspect call-site; the surrounding `withErrorHandler` will still
   hit `captureException`.

### 6.2 A new call-site needs logger.error

1. If you have an `Error`: `logger.error("op.short_name", err, { …meta })`.
2. If you only have a reason string: `logger.error("op.short_name", reason, { …meta })`.
3. If you have nothing at all: `logger.error("op.short_name", undefined, { …meta })`.

All three shapes now surface in Sentry.

### 6.3 Adding a redaction layer

If meta can carry sensitive fields (email, CPF, phone, token), redact
**before** calling `logger.error`. The logger is transport-only by
design — redaction lives in the caller so each domain can choose the
right policy (deterministic hash for audit trails, drop for analytics,
…).

See `portal/src/lib/audit.ts` → `redactReason(...)` (L04-07).

### 6.4 Quieting a noisy call-site

The ONLY sanctioned ways to reduce noise are:

1. **Upstream fix** — resolve the underlying error so the log line
   stops firing.
2. **Sentry Inbound Filter** — configure on the Sentry project with a
   written rationale in the Sentry Issue's timeline.

Do NOT hack `logger.error` to conditionally skip Sentry — that is
exactly what L17-05 fixed.

## 7. Rollback posture

This is a strict defence — there is no rollback lever. A regression of
the Sentry send is **observable** via Sentry:Log ratio (§5) and is
**preventable** via `audit:logger-sentry-capture` (§6.1).

## 8. Invariants (enforced by CI)

- No `} else if (error) {` branch that wraps `Sentry.captureMessage` —
  that is the shape of the 2026-04-17 bug.
- Both `Sentry.captureException(error` and `Sentry.captureMessage(msg`
  call-sites exist in `logger.ts`.
- The `normalizeErrorFields` helper is declared and handles
  `undefined` / `null` by returning `{}` (no `error` key).
- `logger.test.ts` contains the `L17-05 Sentry capture invariants`
  test suite covering the `Error`, `undefined`, `null`, `string` and
  plain-object shapes.

## 9. Cross-references

- `L17-03` — `withErrorHandler` typing: the route-level wrapper calls
  `logger.error` for every 5xx. Together with L17-05 that closes the
  portal error-observability contract end-to-end.
- `L20-03` — trace correlation: `trace_id`/`span_id` are still
  auto-injected into every log line so Sentry issues can pivot to
  full traces.
- `L04-07` — PII redaction for `coin_ledger.reason`: template for how
  callers should redact sensitive meta *before* hitting the logger.
