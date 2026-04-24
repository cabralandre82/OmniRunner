import * as Sentry from "@sentry/nextjs";
import { enrichWithSeverity, tracesSampler } from "@/lib/observability/sentryTuning";
import { stripPii } from "@/lib/observability/sentryPii";

Sentry.init({
  dsn: process.env.NEXT_PUBLIC_SENTRY_DSN,
  // L20-04 — adaptive sampler shared with client + server runtimes.
  tracesSampler,
  enabled: process.env.NODE_ENV === "production",
  // L04-13 — explicit PII opt-out. Edge runtime would attach
  // CF-Connecting-IP if `sendDefaultPii: true`.
  sendDefaultPii: false,
  // L20-05 — severity tag enrichment for alert routing.
  // L04-13 — strip residual PII (URL query, headers, user.email/ip)
  // after enrichment.
  beforeSend: (event, hint) => stripPii(enrichWithSeverity(event, hint)),
  beforeSendTransaction: (event, hint) =>
    stripPii(enrichWithSeverity(event, hint)),
});
