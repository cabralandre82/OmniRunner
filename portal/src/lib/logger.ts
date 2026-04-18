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

export const logger = {
  info(msg: string, meta?: LogMeta) {
    console.log(format("info", msg, meta));
  },

  warn(msg: string, meta?: LogMeta) {
    console.warn(format("warn", msg, meta));
  },

  error(msg: string, error?: unknown, meta?: LogMeta) {
    console.error(
      format("error", msg, {
        ...meta,
        error: error instanceof Error ? error.message : String(error),
        stack: error instanceof Error ? error.stack : undefined,
      }),
    );
    if (error instanceof Error) {
      Sentry.captureException(error, { extra: { msg, ...meta } });
    } else if (error) {
      Sentry.captureMessage(msg, { level: "error", extra: { error, ...meta } });
    }
  },
};
