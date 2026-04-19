/**
 * Client-side error boundary reporter (L06-07).
 *
 * Single funnel that every Next.js `error.tsx` / `global-error.tsx` boundary
 * must call inside `useEffect` so that:
 *
 *   1. Sentry receives the error with consistent `boundary` + `severity` tags
 *      (drives alert routing — see `docs/observability/ALERT_POLICY.md`).
 *   2. The Next.js `error.digest` is preserved as a Sentry tag (the digest is
 *      the only correlation key between the client error and the server-side
 *      RSC render that produced it; without it, an SRE digging a 5xx alert
 *      cannot pivot to the client report).
 *   3. The browser console still gets a `console.error` line so local dev
 *      keeps working without a Sentry DSN configured.
 *
 * Why a thin façade instead of inlining `Sentry.captureException` four times:
 *   - Without this funnel, each boundary added by future devs would forget at
 *     least one tag (history says: `app/error.tsx` and `app/(portal)/error.tsx`
 *     existed without ANY Sentry capture for months, and `global-error.tsx`
 *     was created as a Client Component but never imported `@sentry/nextjs`).
 *   - The helper is import-cheap (Sentry is already in the bundle for
 *     `instrumentation-client.ts`) and trivially mockable in tests.
 *
 * Convention: every `error.tsx` boundary file owns ONE call to this function,
 * passing a stable `boundary` literal that matches its physical location:
 *
 *   - "global"   → `app/global-error.tsx`     (root document failed to render)
 *   - "root"     → `app/error.tsx`            (root layout subtree crashed)
 *   - "portal"   → `app/(portal)/error.tsx`   (portal route group crashed)
 *   - "platform" → `app/platform/error.tsx`   (platform admin area crashed)
 *
 * Adding a new boundary? Extend `ClientErrorBoundary` and add a row to the
 * runbook table in `docs/runbooks/CSP_RUNBOOK.md` neighbour
 * `OBSERVABILITY_RUNBOOK.md` (TODO L20-* expansion).
 */

import * as Sentry from "@sentry/nextjs";

import type { SeverityTag } from "./sentryTuning";

/**
 * Stable, low-cardinality identifier of where the boundary lives in the
 * App Router tree. Used as a Sentry tag so on-call can filter/triage by
 * surface area (e.g. "all crashes in platform admin in the last hour").
 */
export type ClientErrorBoundary = "global" | "root" | "portal" | "platform";

/**
 * Severity ladder per boundary. Rationale:
 *   - global / root crashes are catastrophic — the user sees nothing and
 *     no further error boundary will catch retries. Treat as P1 (pageable).
 *   - portal / platform crashes only break a route subtree; the surrounding
 *     chrome still renders, so the user can navigate away. P2 (Slack only).
 *
 * Aligned with `docs/observability/ALERT_POLICY.md`. If you bump a boundary's
 * severity, update the alert policy doc in the same PR — Sentry routing is
 * driven by this tag.
 */
const BOUNDARY_SEVERITY: Record<ClientErrorBoundary, SeverityTag> = {
  global: "P1",
  root: "P1",
  portal: "P2",
  platform: "P2",
};

interface ReportOptions {
  /**
   * The error caught by Next.js. May be a synthetic `Error & { digest }` —
   * the `digest` is the only stable correlation id between the client report
   * and the originating server render.
   */
  error: Error & { digest?: string };
  /** Where the boundary lives. Mirrors the file location. */
  boundary: ClientErrorBoundary;
  /**
   * Optional extras for forensic value (e.g. route segment, feature flag
   * snapshot). Pure metadata — never include PII or secrets.
   */
  extras?: Record<string, string | number | boolean | null | undefined>;
}

/**
 * Forward a client-side render failure to Sentry with consistent tags + a
 * dev-friendly console echo. Safe to call:
 *   - before Sentry init finishes (Sentry's API no-ops gracefully),
 *   - in environments with no DSN (just becomes a console line),
 *   - in tests (mock `@sentry/nextjs` to assert it was called).
 *
 * Idempotency: the caller is responsible for wrapping in `useEffect` so
 * React's StrictMode double-invoke does not duplicate reports. We also tag
 * each event with the digest — Sentry's default fingerprinting will then
 * group identical errors across users into a single issue without our help.
 */
export function reportClientError({ error, boundary, extras }: ReportOptions): void {
  const severity = BOUNDARY_SEVERITY[boundary];

  // 1. Local dev visibility. Cheap; runs even if Sentry is mute.
  if (typeof console !== "undefined") {
    // eslint-disable-next-line no-console
    console.error(`[${boundary}-error-boundary]`, error);
  }

  // 2. Forward to Sentry with stable tags. The `withScope` block ensures
  //    tags do not leak into unrelated events captured later in the same
  //    session.
  try {
    Sentry.withScope((scope) => {
      scope.setTag("error_boundary", boundary);
      scope.setTag("severity", severity);
      if (error.digest) {
        // The digest is what links a client crash to the server log line
        // that produced the failed RSC payload. Without it, you have to
        // guess by timestamp.
        scope.setTag("digest", error.digest);
      }
      if (extras) {
        for (const [k, v] of Object.entries(extras)) {
          if (v === undefined || v === null) continue;
          scope.setExtra(k, v);
        }
      }
      Sentry.captureException(error);
    });
  } catch {
    // Defensive: if Sentry's API throws (e.g. extension blocked the bundle),
    // we still want the boundary to keep running — never let observability
    // failures cascade into a worse UX than the original crash.
  }
}
