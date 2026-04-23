import * as Sentry from "@sentry/nextjs";

type LogMeta = Record<string, unknown>;

/**
 * L20-03 — every log line auto-carries `trace_id` and `span_id` when a
 * Sentry span is active. This lets log aggregators (Loki, CloudWatch
 * Insights, Datadog) pivot from a single log line back to the full
 * Sentry trace tree.
 *
 * Lazy import of `tracing.ts` avoids a static cycle (audit.ts uses logger
 * via withSpan in tracing.ts → would force eager init of Sentry SDK).
 */
function activeTraceContext(): {
  trace_id?: string;
  span_id?: string;
} {
  try {
    const span = Sentry.getActiveSpan();
    if (!span) return {};
    const json = Sentry.spanToJSON(span);
    return {
      trace_id: json.trace_id,
      span_id: json.span_id,
    };
  } catch {
    return {};
  }
}

function format(level: string, msg: string, meta?: LogMeta): string {
  return JSON.stringify({
    level,
    msg,
    ts: new Date().toISOString(),
    ...activeTraceContext(),
    ...meta,
  });
}

/**
 * L17-05 — normalize an arbitrary `error` argument into consistent log
 * fields. The old code path did `String(error)` unconditionally, which
 * printed the literal string `"undefined"` into JSON and surfaced as a
 * useless field in log aggregators. Now:
 *
 *   - `Error`  → `{ error: message, stack }` (unchanged)
 *   - `undefined` / `null` → `{}` (field omitted entirely)
 *   - `string` / number / bool → `{ error: "<coerced>" }`
 *   - object / array → `{ error: <JSON-safe shallow clone> }`
 *
 * Centralising this keeps the console format consistent with the extras
 * Sentry receives.
 */
function normalizeErrorFields(error: unknown): {
  error?: unknown;
  stack?: string;
} {
  if (error === undefined || error === null) return {};
  if (error instanceof Error) {
    return { error: error.message, stack: error.stack };
  }
  if (typeof error === "object") {
    try {
      return { error: JSON.parse(JSON.stringify(error)) };
    } catch {
      return { error: String(error) };
    }
  }
  return { error: String(error) };
}

export const logger = {
  info(msg: string, meta?: LogMeta) {
    console.log(format("info", msg, meta));
  },

  warn(msg: string, meta?: LogMeta) {
    console.warn(format("warn", msg, meta));
  },

  /**
   * L17-05 — `logger.error` ALWAYS emits to Sentry, even when called
   * without an `error` object (`logger.error("...oh no")`) or with
   * `undefined` (`logger.error("...", undefined, meta)`). Previously the
   * `else if (error)` branch silently dropped those calls because
   * `undefined` is falsy, which meant server-side invariants such as
   * `custody.webhook.config_missing` and
   * `checkout.proxy.gateway_non_json` never surfaced in Sentry despite
   * being console-logged at ERROR level. The new contract is:
   *
   *   - `Error`            → `Sentry.captureException` (stack preserved).
   *   - anything else      → `Sentry.captureMessage(msg, "error")` with
   *                          the coerced error value (if any) attached as
   *                          an `extra`.
   */
  error(msg: string, error?: unknown, meta?: LogMeta) {
    const errorFields = normalizeErrorFields(error);
    console.error(format("error", msg, { ...meta, ...errorFields }));

    if (error instanceof Error) {
      Sentry.captureException(error, { extra: { msg, ...meta } });
      return;
    }

    Sentry.captureMessage(msg, {
      level: "error",
      extra: { ...meta, ...errorFields },
    });
  },
};
