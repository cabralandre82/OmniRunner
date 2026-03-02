import * as Sentry from "@sentry/nextjs";

type LogMeta = Record<string, unknown>;

function format(level: string, msg: string, meta?: LogMeta): string {
  return JSON.stringify({
    level,
    msg,
    ts: new Date().toISOString(),
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
