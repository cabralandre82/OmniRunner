/**
 * Next.js instrumentation entrypoint (L20-03 — distributed tracing).
 *
 * Next.js auto-loads this file ONCE at server cold-start (both Node.js and
 * Edge runtimes). We use it to:
 *   1. Bootstrap Sentry's OpenTelemetry-compatible tracing layer (server +
 *      edge configs are imported lazily via require so each runtime gets the
 *      right one — Next.js refuses to load Node-only code in Edge bundles).
 *   2. Set process-wide globals that every span/log can read (release SHA,
 *      deploy_env, instance_id) so traces are correlatable across pods.
 *
 * Why this file exists separately from `sentry.{server,edge,client}.config.ts`:
 *   - Sentry config files are loaded by `withSentryConfig` in next.config.mjs
 *     for ERROR reporting. They are loaded later in the request lifecycle.
 *   - `instrumentation.ts` runs BEFORE the first request — required for
 *     OTLP propagation context to be ready when the first inbound trace
 *     header arrives.
 *
 * Reference: https://nextjs.org/docs/app/api-reference/file-conventions/instrumentation
 * Audit: L20-03 (SRE — distributed tracing)
 */

export async function register() {
  // L20-03 — runtime detection. NEXT_RUNTIME is set by Next.js to
  // 'nodejs' | 'edge'. Each runtime needs its own Sentry config: the
  // edge one cannot use Node APIs (fs, async_hooks, etc).
  if (process.env.NEXT_RUNTIME === "nodejs") {
    await import("../sentry.server.config");
  }
  if (process.env.NEXT_RUNTIME === "edge") {
    await import("../sentry.edge.config");
  }
}

/**
 * Optional `onRequestError` hook — Next.js 15+ calls this on every request
 * error so we can correlate the failing trace with structured logs.
 *
 * We don't reimplement Sentry capture here (it already happens via
 * sentry.server.config.ts). We instead emit a structured log line with
 * the active trace_id so log aggregator queries (Loki/CloudWatch/etc) can
 * pivot directly from a 5xx alert to the matching Sentry trace.
 */
export async function onRequestError(
  err: unknown,
  request: { path: string; method: string; headers: Record<string, string | string[] | undefined> },
  context: { routerKind: "Pages Router" | "App Router"; routePath: string; routeType: string },
) {
  // Lazy import: keep this hook lightweight (called on every error).
  const { logger } = await import("./lib/logger");
  const { currentTraceId } = await import("./lib/observability/tracing");
  logger.error("next.request.error", err, {
    path: request.path,
    method: request.method,
    routePath: context.routePath,
    routeType: context.routeType,
    routerKind: context.routerKind,
    trace_id: currentTraceId(),
  });
}
