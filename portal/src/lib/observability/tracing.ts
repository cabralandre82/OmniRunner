/**
 * Distributed-tracing helpers (L20-03).
 *
 * Thin façade over @sentry/nextjs that gives us:
 *   • `withSpan(name, op, fn)` — wrap an async fn in a Sentry/OTel span
 *   • `currentTraceId()` — pull trace_id from the active span (for log/audit
 *     correlation)
 *   • `traceparent()` — build outgoing W3C/Sentry trace headers for fetches
 *     to downstream services (Supabase RPC, edge functions, Asaas)
 *   • `continueTraceFromRequest(req, fn)` — resume an inbound trace from
 *     `sentry-trace` + `baggage` headers (mobile → portal handoff)
 *
 * Why a façade instead of importing Sentry everywhere:
 *   1. Single source of truth for span attribute conventions (op:, attrs:).
 *   2. Trivial to mock in tests (no Sentry init needed in vitest).
 *   3. If we ever migrate from Sentry to a vendor-neutral OTLP exporter,
 *      only this file changes.
 *
 * Span attribute conventions (OpenTelemetry semconv-aligned):
 *   • `db.system` = "postgresql" — for any Supabase RPC/SELECT/etc.
 *   • `db.operation` = "rpc:fn_name" or "select:table"
 *   • `http.method` / `http.url` — for outbound calls
 *   • `omni.actor_id` / `omni.group_id` — domain identifiers
 *   • `omni.kill_switch` — when a request was blocked by feature flag
 */

import * as Sentry from "@sentry/nextjs";

// ─────────────────────────────────────────────────────────────────────
// Types
// ─────────────────────────────────────────────────────────────────────

/**
 * Conventional span operation. Free-form string but stick to these for
 * cross-route consistency in Sentry's discover queries.
 */
export type SpanOp =
  | "db.rpc"
  | "db.select"
  | "db.insert"
  | "db.update"
  | "db.delete"
  | "http.client"
  | "audit.write"
  | "feature_flag.check"
  | "swap.execute"
  | "custody.deposit"
  | "custody.withdraw"
  | "distribute.coins"
  | "billing.webhook";

export type SpanAttributes = Record<
  string,
  string | number | boolean | undefined | null
>;

// ─────────────────────────────────────────────────────────────────────
// withSpan — wrap an async fn in a span
// ─────────────────────────────────────────────────────────────────────

/**
 * Run `fn` inside a Sentry span. Span auto-finishes when the promise
 * resolves; on throw, the span is marked `status: error` with the
 * exception attached and re-thrown.
 *
 * Behavior outside Sentry context (tests, no DSN, dev without Sentry):
 *   • `Sentry.startSpan` no-ops gracefully — it ALWAYS calls the callback
 *     and just returns its result without recording.
 *   • So this helper is safe to sprinkle anywhere, no `if (Sentry.enabled)`
 *     gates needed.
 *
 * @param name — Human-readable description (shows in Sentry trace tree).
 *               Must be high-cardinality-safe: don't include user IDs;
 *               put those in `attrs`.
 * @param op   — Operation type. See `SpanOp`.
 * @param fn   — The work. Receives the span so you can add attrs mid-flight
 *               (e.g. result counts).
 * @param attrs— Initial attributes. Use OTel-compatible keys when possible.
 */
export async function withSpan<T>(
  name: string,
  op: SpanOp,
  fn: (setAttr: (k: string, v: SpanAttributes[string]) => void) => Promise<T>,
  attrs?: SpanAttributes,
): Promise<T> {
  return Sentry.startSpan(
    {
      name,
      op,
      attributes: filterUndefined(attrs ?? {}),
    },
    async (span) => {
      const setAttr = (k: string, v: SpanAttributes[string]) => {
        if (v === undefined || v === null) return;
        span?.setAttribute(k, v);
      };
      try {
        return await fn(setAttr);
      } catch (err) {
        // Mark span as failed; Sentry derives error rate from this.
        span?.setStatus({ code: 2, message: errorMessage(err) });
        throw err;
      }
    },
  );
}

// ─────────────────────────────────────────────────────────────────────
// currentTraceId — read trace_id from the active span
// ─────────────────────────────────────────────────────────────────────

/**
 * Returns the active span's trace_id (32-hex string) or `null` if no span
 * is active. Safe to call anywhere; never throws.
 *
 * Use cases:
 *   • Embed in audit_log.metadata for post-incident pivot.
 *   • Embed in structured logs for log↔trace correlation.
 *   • Echo to clients via `X-Trace-Id` response header (debug builds only).
 */
export function currentTraceId(): string | null {
  try {
    const span = Sentry.getActiveSpan();
    if (!span) return null;
    return Sentry.spanToJSON(span).trace_id ?? null;
  } catch {
    return null;
  }
}

/**
 * Returns the active span's span_id (16-hex). Useful if you need the
 * specific operation, not just the trace it belongs to.
 */
export function currentSpanId(): string | null {
  try {
    const span = Sentry.getActiveSpan();
    if (!span) return null;
    return Sentry.spanToJSON(span).span_id ?? null;
  } catch {
    return null;
  }
}

// ─────────────────────────────────────────────────────────────────────
// traceparent — build outbound HTTP propagation headers
// ─────────────────────────────────────────────────────────────────────

/**
 * Build headers to attach to outbound `fetch()` calls so downstream
 * services (edge functions, Asaas, etc) can join the same trace.
 *
 * Returns a header dictionary; merge with your existing headers. If no
 * span is active, returns `{}` (no propagation, downstream starts fresh).
 *
 * Headers emitted:
 *   • `sentry-trace` — Sentry's compact trace_id-span_id-sampled triple
 *   • `baggage` — W3C baggage with dynamic sampling context
 *
 * Both headers are also W3C-compatible: receivers using OpenTelemetry's
 * default propagator will pick them up too.
 */
export function traceparent(): Record<string, string> {
  try {
    const span = Sentry.getActiveSpan();
    if (!span) return {};
    const headers: Record<string, string> = {};
    const sentryTrace = Sentry.spanToTraceHeader(span);
    if (sentryTrace) headers["sentry-trace"] = sentryTrace;
    const baggage = Sentry.spanToBaggageHeader(span);
    if (baggage) headers["baggage"] = baggage;
    return headers;
  } catch {
    return {};
  }
}

// ─────────────────────────────────────────────────────────────────────
// continueTraceFromRequest — resume inbound trace
// ─────────────────────────────────────────────────────────────────────

/**
 * Continue a trace from inbound HTTP headers. Use at the top of a route
 * handler when the upstream client (e.g. Flutter app) sent `sentry-trace`
 * + `baggage`. Sentry's Next.js integration auto-detects these for HTTP
 * transactions, so you only need this for non-HTTP contexts (Server
 * Actions, background jobs triggered by webhook, etc).
 */
export function continueTraceFromRequest<V>(
  headers: { get(name: string): string | null } | Record<string, string | string[] | undefined>,
  callback: () => V,
): V {
  const sentryTrace = readHeader(headers, "sentry-trace");
  const baggage = readHeader(headers, "baggage");
  return Sentry.continueTrace({ sentryTrace, baggage }, callback);
}

// ─────────────────────────────────────────────────────────────────────
// internals
// ─────────────────────────────────────────────────────────────────────

function readHeader(
  headers: { get(name: string): string | null } | Record<string, string | string[] | undefined>,
  name: string,
): string | undefined {
  if (typeof (headers as { get?: unknown }).get === "function") {
    return (headers as { get(n: string): string | null }).get(name) ?? undefined;
  }
  const v = (headers as Record<string, string | string[] | undefined>)[name];
  if (Array.isArray(v)) return v[0];
  return v ?? undefined;
}

function filterUndefined(attrs: SpanAttributes): Record<string, string | number | boolean> {
  const out: Record<string, string | number | boolean> = {};
  for (const [k, v] of Object.entries(attrs)) {
    if (v === undefined || v === null) continue;
    out[k] = v;
  }
  return out;
}

function errorMessage(err: unknown): string {
  if (err instanceof Error) return err.message;
  if (typeof err === "string") return err;
  try {
    return JSON.stringify(err);
  } catch {
    return "unknown error";
  }
}
