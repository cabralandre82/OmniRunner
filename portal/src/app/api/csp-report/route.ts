import { NextResponse, type NextRequest } from "next/server";
import * as Sentry from "@sentry/nextjs";
import { logger } from "@/lib/logger";

/**
 * POST /api/csp-report — Content-Security-Policy violation sink (L10-05).
 *
 * Browsers send CSP violation reports here in two slightly different
 * shapes depending on which directive triggered them:
 *
 *   1. Legacy `report-uri` (Firefox, Safari, older Chromium) —
 *      Content-Type: `application/csp-report`
 *      Body: `{ "csp-report": { "document-uri": "...", "violated-directive": "...", ... } }`
 *
 *   2. Modern `report-to` (Chromium 73+) —
 *      Content-Type: `application/reports+json`
 *      Body: `[{ "type": "csp-violation", "body": { "documentURL": "...", ... } }]`
 *
 * We emit BOTH `report-uri` and `report-to` from `lib/security/csp.ts`,
 * so this handler accepts either shape. The two are normalised into a
 * single internal record before logging + Sentry capture so dashboards
 * and Sentry queries don't have to special-case browsers.
 *
 * Defensive posture:
 *   • Always responds 204 (No Content) — even on parse errors. We do
 *     NOT want to leak parser/route information back to a browser
 *     that's already executing some XSS payload, and we definitely
 *     don't want to give an attacker a way to amplify their own
 *     reports into observable error responses.
 *   • Body capped at 8 KiB. Real reports are 200-800 B; anything
 *     bigger is either a misconfigured client or someone trying to
 *     fill our log pipe. We log a `csp.report.oversize` warning and
 *     drop the payload.
 *   • Coarse per-process rate limit (60 reports / 60 s window) so a
 *     misconfigured CSP on one user's tab can't pin a Sentry quota.
 *     Counter is process-local on purpose: deployed across many edge
 *     workers it gives a soft global limit of (n_workers × 60)/min,
 *     which is more than enough headroom for legitimate violations
 *     while still throttling per-pod runaway loops.
 *   • `forwardToSentry` distinguishes our own CSP from violations
 *     that look like they're coming from an injected attacker payload:
 *     anything that's NOT a `script-src` violation is logged at info
 *     level (likely policy-tightening false positives — we want them,
 *     but they're not P1); a `script-src` violation is logged at
 *     warn AND captured to Sentry as a message so the alert pipeline
 *     wakes up on real XSS attempts.
 */

const MAX_BODY_BYTES = 8 * 1024;
const RATE_LIMIT_WINDOW_MS = 60_000;
const RATE_LIMIT_MAX_REPORTS = 60;

let rateWindowStartedAt = 0;
let rateWindowCount = 0;

function admitForRateLimit(now: number): boolean {
  if (now - rateWindowStartedAt > RATE_LIMIT_WINDOW_MS) {
    rateWindowStartedAt = now;
    rateWindowCount = 0;
  }
  if (rateWindowCount >= RATE_LIMIT_MAX_REPORTS) {
    return false;
  }
  rateWindowCount += 1;
  return true;
}

interface NormalisedViolation {
  document_uri: string | null;
  blocked_uri: string | null;
  violated_directive: string | null;
  effective_directive: string | null;
  original_policy: string | null;
  source_file: string | null;
  line_number: number | null;
  column_number: number | null;
  status_code: number | null;
  disposition: string | null;
  referrer: string | null;
}

function asString(value: unknown): string | null {
  return typeof value === "string" && value.length > 0 ? value : null;
}

function asInt(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value)
    ? Math.trunc(value)
    : null;
}

function normaliseLegacyReport(raw: Record<string, unknown>): NormalisedViolation {
  return {
    document_uri: asString(raw["document-uri"]),
    blocked_uri: asString(raw["blocked-uri"]),
    violated_directive: asString(raw["violated-directive"]),
    effective_directive: asString(raw["effective-directive"]),
    original_policy: asString(raw["original-policy"]),
    source_file: asString(raw["source-file"]),
    line_number: asInt(raw["line-number"]),
    column_number: asInt(raw["column-number"]),
    status_code: asInt(raw["status-code"]),
    disposition: asString(raw["disposition"]),
    referrer: asString(raw["referrer"]),
  };
}

function normaliseModernReport(raw: Record<string, unknown>): NormalisedViolation {
  return {
    document_uri: asString(raw["documentURL"]),
    blocked_uri: asString(raw["blockedURL"]),
    violated_directive: asString(raw["effectiveDirective"]),
    effective_directive: asString(raw["effectiveDirective"]),
    original_policy: asString(raw["originalPolicy"]),
    source_file: asString(raw["sourceFile"]),
    line_number: asInt(raw["lineNumber"]),
    column_number: asInt(raw["columnNumber"]),
    status_code: asInt(raw["statusCode"]),
    disposition: asString(raw["disposition"]),
    referrer: asString(raw["referrer"]),
  };
}

/**
 * Parse either report shape into the normalised array. Exported for
 * testing — kept pure (no I/O, no logging) so unit tests can iterate
 * over fixtures cheaply.
 */
export function parseCspReportPayload(payload: unknown): NormalisedViolation[] {
  if (Array.isArray(payload)) {
    const out: NormalisedViolation[] = [];
    for (const entry of payload) {
      if (!entry || typeof entry !== "object") continue;
      const e = entry as Record<string, unknown>;
      const inner = e["body"] && typeof e["body"] === "object"
        ? (e["body"] as Record<string, unknown>)
        : e;
      out.push(normaliseModernReport(inner));
    }
    return out;
  }
  if (payload && typeof payload === "object") {
    const obj = payload as Record<string, unknown>;
    const inner = obj["csp-report"];
    if (inner && typeof inner === "object") {
      return [normaliseLegacyReport(inner as Record<string, unknown>)];
    }
  }
  return [];
}

function isHighSeverity(v: NormalisedViolation): boolean {
  const directive = (v.effective_directive ?? v.violated_directive ?? "")
    .split(" ")[0]
    ?.toLowerCase();
  return (
    directive === "script-src" ||
    directive === "script-src-elem" ||
    directive === "script-src-attr"
  );
}

export async function POST(request: NextRequest): Promise<NextResponse> {
  const now = Date.now();
  if (!admitForRateLimit(now)) {
    return new NextResponse(null, { status: 204 });
  }

  let bodyText: string;
  try {
    bodyText = await request.text();
  } catch {
    return new NextResponse(null, { status: 204 });
  }
  if (bodyText.length > MAX_BODY_BYTES) {
    logger.warn("csp.report.oversize", { bytes: bodyText.length });
    return new NextResponse(null, { status: 204 });
  }
  if (bodyText.length === 0) {
    return new NextResponse(null, { status: 204 });
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(bodyText);
  } catch {
    return new NextResponse(null, { status: 204 });
  }

  const reports = parseCspReportPayload(parsed);
  for (const r of reports) {
    const meta = {
      ...r,
      report_source: Array.isArray(parsed) ? "report-to" : "report-uri",
      user_agent: request.headers.get("user-agent"),
    };

    if (isHighSeverity(r)) {
      logger.warn("csp.violation.script_src", meta);
      Sentry.captureMessage("CSP violation: script-src", {
        level: "warning",
        tags: {
          csp_directive: r.effective_directive ?? "unknown",
          csp_blocked_uri: r.blocked_uri ?? "unknown",
        },
        extra: meta,
      });
    } else {
      logger.info("csp.violation", meta);
    }
  }

  return new NextResponse(null, { status: 204 });
}

/**
 * Test-only reset of the per-process rate-limit window. NOT exported
 * from any barrel — vitest reaches into the module directly.
 */
export function __resetRateLimitForTests(): void {
  rateWindowStartedAt = 0;
  rateWindowCount = 0;
}
