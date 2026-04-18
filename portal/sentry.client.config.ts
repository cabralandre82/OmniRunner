import * as Sentry from "@sentry/nextjs";
import { enrichWithSeverity, tracesSampler } from "@/lib/observability/sentryTuning";

Sentry.init({
  dsn: process.env.NEXT_PUBLIC_SENTRY_DSN,
  // L20-04 — adaptive sampler (custody/swap=100%, health=0%, default=10%).
  tracesSampler,
  replaysSessionSampleRate: 0.05,
  replaysOnErrorSampleRate: 1.0,
  environment: process.env.NODE_ENV,
  // L20-05 — every event tagged with derived severity (P1..P4) so Sentry
  // alert rules can route by severity (see docs/observability/ALERT_POLICY.md).
  beforeSend: enrichWithSeverity,
  beforeSendTransaction: enrichWithSeverity,
});
