import { NextResponse } from "next/server";

import { createServiceClient } from "@/lib/supabase/service";
import { logger } from "@/lib/logger";
import {
  createCachedAggregator,
  collectFromFeeds,
  aggregateStatus,
} from "@/lib/status/aggregate";
import {
  internalProbeFeed,
  staticFeed,
  withTimeout,
} from "@/lib/status/feeds";
import type { StatusFeed } from "@/lib/status/types";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

/**
 * GET /api/public/status — L20-06.
 *
 * Feeds the future `status.omnirunner.com` page and any third-party
 * status platform (Atlassian Statuspage, Better Stack, Cachet) that
 * polls us.
 *
 * Contract: see `AggregateStatus` in `src/lib/status/types.ts`.
 *
 * Policy:
 *  - **Public**: no auth, no CSRF. Uptime probes and the status page
 *    itself need to reach this from an unauthenticated context.
 *  - **CORS-permissive**: `Access-Control-Allow-Origin: *`. The only
 *    data in the response is already public-by-design.
 *  - **Cached**: a module-level `createCachedAggregator` dedups
 *    within the warm container lifetime (default 60s, floor 30s).
 *  - **Never 5xx on partial outages**: the whole point is to be the
 *    signal that tells users *we have an outage*. A broken feed is
 *    coerced to `unknown`, not a 500.
 *
 * The external-vendor feeds (Vercel, Supabase, Stripe, Strava) are a
 * follow-up (`L20-06-external-feeds`) — they need their own URL
 * parsers and live behind an env flag so local dev never hits the
 * vendor APIs.
 */

function internalApiProbe(): () => Promise<"ok" | "degraded" | "down"> {
  return async () => {
    try {
      const db = createServiceClient();
      const { error } = await db.from("profiles").select("id").limit(1);
      return error ? "degraded" : "ok";
    } catch (e) {
      logger.warn("status.api_probe_failed", { error: String(e) });
      return "down";
    }
  };
}

function buildFeeds(): StatusFeed[] {
  return [
    withTimeout(staticFeed("web", "operational"), 2_000),
    withTimeout(internalProbeFeed("api", internalApiProbe()), 2_000),
    withTimeout(internalProbeFeed("database", internalApiProbe()), 2_000),
    withTimeout(staticFeed("auth", "operational"), 2_000),
    withTimeout(staticFeed("payments", "operational"), 2_000),
    withTimeout(staticFeed("strava", "operational"), 2_000),
  ];
}

const aggregator = createCachedAggregator({ feeds: buildFeeds() });

export async function GET() {
  try {
    const payload = await aggregator.get();
    return new NextResponse(JSON.stringify(payload), {
      status: 200,
      headers: {
        "content-type": "application/json",
        "access-control-allow-origin": "*",
        "cache-control": `public, max-age=${Math.floor(
          aggregator.ttlMs / 1000,
        )}`,
      },
    });
  } catch (e) {
    logger.warn("status.aggregate_failed", { error: String(e) });
    const fallback = aggregateStatus(
      await collectFromFeeds([], new Date()),
      new Date(),
    );
    return new NextResponse(JSON.stringify(fallback), {
      status: 200,
      headers: {
        "content-type": "application/json",
        "access-control-allow-origin": "*",
        "cache-control": "no-store",
      },
    });
  }
}

export function OPTIONS() {
  return new NextResponse(null, {
    status: 204,
    headers: {
      "access-control-allow-origin": "*",
      "access-control-allow-methods": "GET, OPTIONS",
      "access-control-max-age": "86400",
    },
  });
}
