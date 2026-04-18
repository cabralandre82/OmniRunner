import * as Sentry from "@sentry/nextjs";
import { enrichWithSeverity, tracesSampler } from "@/lib/observability/sentryTuning";

Sentry.init({
  dsn: process.env.NEXT_PUBLIC_SENTRY_DSN,
  // L20-04 — adaptive sampler shared with client + edge runtimes.
  tracesSampler,
  enabled: process.env.NODE_ENV === "production",
  // L20-05 — severity tag enrichment for alert routing.
  beforeSend: enrichWithSeverity,
  beforeSendTransaction: enrichWithSeverity,
});
