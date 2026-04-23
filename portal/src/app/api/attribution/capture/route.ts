import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { createServiceClient } from "@/lib/supabase/service";
import { readAttributionCookie } from "@/lib/attribution";
import { rateLimit } from "@/lib/rate-limit";
import {
  apiValidationFailed,
  apiRateLimited,
  apiError,
} from "@/lib/api/errors";
import { rateLimitKey } from "@/lib/api/rate-limit-key";
import { withErrorHandler } from "@/lib/api-handler";
import { z } from "zod";
import { createHash } from "node:crypto";

/**
 * L15-01 — POST /api/attribution/capture
 *
 * Called on signup and on first dashboard load to persist the
 * attribution snapshot carried in the `utm_attribution` cookie
 * into `marketing_attribution_events`. The AFTER INSERT trigger
 * in the DB back-fills `profiles.attribution` with the first-
 * touch snapshot atomically.
 *
 * The browser never writes to profiles or this table directly;
 * all mutation goes through service-role so the identity + IP
 * hashing stays canonical.
 */

const schema = z
  .object({
    event_type: z.enum(["visit", "signup", "activation", "conversion"]),
    anonymous_id: z.string().min(8).max(128).optional(),
  })
  .strict();

function truncateIp(ip: string | null): string | null {
  if (!ip) return null;
  if (ip.includes(":")) {
    const parts = ip.split(":");
    return parts.slice(0, 3).join(":") + "::/48";
  }
  const parts = ip.split(".");
  if (parts.length !== 4) return null;
  return `${parts[0]}.${parts[1]}.${parts[2]}.0/24`;
}

function hashUserAgent(ua: string | null): string | null {
  if (!ua) return null;
  return createHash("sha256").update(ua).digest("hex").slice(0, 32);
}

export const POST = withErrorHandler(_post, "api.attribution.capture.post");

async function _post(req: NextRequest) {
  const rl = await rateLimit(
    rateLimitKey({ prefix: "attribution", request: req }),
    { maxRequests: 20, windowMs: 60_000 },
  );
  if (!rl.allowed) {
    return apiRateLimited(req, Math.ceil((rl.resetAt - Date.now()) / 1000));
  }

  const body = await req.json().catch(() => null);
  const parsed = schema.safeParse(body);
  if (!parsed.success) {
    return apiValidationFailed(req, "Invalid input", parsed.error.flatten());
  }

  const snapshot = readAttributionCookie(req.headers.get("cookie"));
  if (!snapshot) {
    return NextResponse.json({ captured: false, reason: "no_cookie" });
  }

  const authed = createClient();
  const {
    data: { user },
  } = await authed.auth.getUser();

  if (!user && !parsed.data.anonymous_id) {
    return apiError(
      req,
      "NO_IDENTITY",
      "Either a logged-in user or anonymous_id is required",
      400,
    );
  }

  const db = createServiceClient();

  const forwarded = req.headers.get("x-forwarded-for")?.split(",")[0]?.trim();
  const ip =
    forwarded ??
    req.headers.get("x-real-ip") ??
    null;

  const { error } = await db
    .from("marketing_attribution_events")
    .insert({
      user_id: user?.id ?? null,
      anonymous_id: parsed.data.anonymous_id ?? null,
      event_type: parsed.data.event_type,
      source: snapshot.source ?? null,
      medium: snapshot.medium ?? null,
      campaign: snapshot.campaign ?? null,
      term: snapshot.term ?? null,
      content: snapshot.content ?? null,
      referrer_host: snapshot.referrer ?? null,
      landing_path: snapshot.landing ?? null,
      ip_prefix: truncateIp(ip),
      user_agent_sha: hashUserAgent(req.headers.get("user-agent")),
      metadata: {
        first_seen_at: snapshot.first_seen_at ?? null,
      },
    });

  if (error) {
    return apiError(
      req,
      "ATTRIBUTION_WRITE_FAILED",
      "Failed to persist attribution event",
      503,
    );
  }

  return NextResponse.json({ captured: true });
}
