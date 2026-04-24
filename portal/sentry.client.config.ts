import * as Sentry from "@sentry/nextjs";
import { enrichWithSeverity, tracesSampler } from "@/lib/observability/sentryTuning";
import { stripPii } from "@/lib/observability/sentryPii";

Sentry.init({
  dsn: process.env.NEXT_PUBLIC_SENTRY_DSN,
  // L20-04 — adaptive sampler (custody/swap=100%, health=0%, default=10%).
  tracesSampler,
  replaysSessionSampleRate: 0.05,
  replaysOnErrorSampleRate: 1.0,
  environment: process.env.NODE_ENV,
  // L04-13 — never let Sentry attach IP / email / cookies. Browser SDK
  // also sends URL with query string by default; stripPii canonicalises
  // it.
  sendDefaultPii: false,
  // L20-05 — every event tagged with derived severity (P1..P4) so Sentry
  // alert rules can route by severity (see docs/observability/ALERT_POLICY.md).
  // L04-13 — final PII strip happens after enrichment.
  beforeSend: (event, hint) => stripPii(enrichWithSeverity(event, hint)),
  beforeSendTransaction: (event, hint) =>
    stripPii(enrichWithSeverity(event, hint)),
});
