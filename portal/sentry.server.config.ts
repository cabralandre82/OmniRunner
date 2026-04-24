import * as Sentry from "@sentry/nextjs";
import { enrichWithSeverity, tracesSampler } from "@/lib/observability/sentryTuning";
import { stripPii } from "@/lib/observability/sentryPii";

Sentry.init({
  dsn: process.env.NEXT_PUBLIC_SENTRY_DSN,
  // L20-04 — adaptive sampler shared with client + edge runtimes.
  tracesSampler,
  enabled: process.env.NODE_ENV === "production",
  // L04-13 — PII guard. Sentry SDK can attach IP, email, headers and
  // cookies by default; we explicitly disable the default PII path and
  // strip anything that may have been attached upstream (e.g. by a
  // server-action that called Sentry.setUser). See sentryPii.ts.
  sendDefaultPii: false,
  // L20-05 — severity tag enrichment for alert routing, then L04-13 PII
  // strip. Order matters: enrich first (it doesn't add PII), strip last.
  beforeSend: (event, hint) => stripPii(enrichWithSeverity(event, hint)),
  beforeSendTransaction: (event, hint) =>
    stripPii(enrichWithSeverity(event, hint)),
});
