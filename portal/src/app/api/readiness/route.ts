/**
 * L06-12 — `/api/readiness` health-check.
 *
 * Liveness vs Readiness (k8s / Vercel / load-balancer parlance):
 *
 *   * `/api/liveness` — "is this lambda alive?". Trivial 200. Used
 *     by the load balancer to decide if the instance should be
 *     killed. Cheap on purpose; failure has high blast radius
 *     (instance restart) so we don't gate it on downstream deps.
 *
 *   * `/api/readiness` — "can this lambda accept traffic right
 *     now?". Probes downstream dependencies (Postgres + Upstash
 *     Redis) without doing any business logic. Failure has low
 *     blast radius (the LB skips this instance for ~10 s) so we
 *     can be aggressive about reporting "not ready".
 *
 * Intentionally NOT checked here:
 *   * Custody invariants — those are in
 *     `/api/platform/invariants/wallets` and run on a schedule.
 *     A drift there does NOT mean we should refuse traffic.
 *   * Stripe heartbeat — Stripe's status page is the source of
 *     truth; us hitting their API on every readiness check would
 *     burn an enormous amount of API budget for no benefit.
 *
 * Output is JSON regardless of HTTP status, with per-dep latency
 * fields so the SRE dashboard can graph each downstream
 * separately.
 */

import { createServiceClient } from "@/lib/supabase/service";
import { getRedis } from "@/lib/redis";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

interface DepResult {
  ok: boolean;
  latencyMs: number;
  error?: string;
}

const DEP_TIMEOUT_MS = 1_500;

async function withTimeout<T>(p: Promise<T>, ms: number): Promise<T> {
  return await Promise.race([
    p,
    new Promise<T>((_, reject) =>
      setTimeout(() => reject(new Error(`timeout after ${ms}ms`)), ms),
    ),
  ]);
}

async function checkDb(): Promise<DepResult> {
  const t0 = Date.now();
  try {
    const db = createServiceClient();
    const { error } = await withTimeout(
      db.from("profiles").select("id").limit(1),
      DEP_TIMEOUT_MS,
    );
    if (error) {
      return { ok: false, latencyMs: Date.now() - t0, error: error.message };
    }
    return { ok: true, latencyMs: Date.now() - t0 };
  } catch (err) {
    return {
      ok: false,
      latencyMs: Date.now() - t0,
      error: err instanceof Error ? err.message : "unknown",
    };
  }
}

async function checkRedis(): Promise<DepResult> {
  const t0 = Date.now();
  const redis = getRedis();
  if (!redis) {
    // Redis is optional — degrades to in-memory rate-limit. Report
    // the absence as `ok: false, error: "not_configured"` so the
    // SRE dashboard can graph it, but DO NOT fail readiness.
    return { ok: false, latencyMs: 0, error: "not_configured" };
  }
  try {
    const reply = await withTimeout(redis.ping(), DEP_TIMEOUT_MS);
    return { ok: reply === "PONG", latencyMs: Date.now() - t0 };
  } catch (err) {
    return {
      ok: false,
      latencyMs: Date.now() - t0,
      error: err instanceof Error ? err.message : "unknown",
    };
  }
}

export async function GET() {
  const t0 = Date.now();
  const [db, redis] = await Promise.all([checkDb(), checkRedis()]);

  const ready = db.ok;

  return Response.json(
    {
      status: ready ? "ready" : "not_ready",
      ts: Date.now(),
      latencyMs: Date.now() - t0,
      deps: {
        db,
        redis,
      },
    },
    { status: ready ? 200 : 503 },
  );
}
