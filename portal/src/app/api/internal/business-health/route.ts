/**
 * L18-10 — `/api/internal/business-health`
 *
 * Operational health surface for the BUSINESS LOGIC layer (as
 * opposed to `/api/liveness` and `/api/readiness`, which only
 * cover the infrastructure layer — process up, DB reachable,
 * Redis reachable).
 *
 * The signal here is "is the financial machine moving?" — not
 * "are the wires intact?". It pulls SLO-grade indicators that an
 * SRE on call would graph during an incident:
 *
 *   * `rpc_latency_ms`       — recent p50/p95/p99 for the hot
 *                              custody RPCs
 *                              (`execute_burn_atomic`,
 *                              `execute_swap_atomic`,
 *                              `custody_commit_coins`).
 *   * `webhook_success_rate` — 5-min rolling success ratio per
 *                              provider (Stripe, MercadoPago,
 *                              Asaas).
 *   * `clearing_pending`     — `clearing_settlements` rows still
 *                              `pending` plus the age of the
 *                              oldest one (escalation signal).
 *   * `withdrawal_pending`   — same shape for `custody_withdraws`.
 *   * `oldest_pending_deposit_hours` — how stale the oldest
 *                              `custody_deposits` row in `pending`
 *                              is. > 24h is a Sentry alert.
 *
 * Failure modes
 *   - Endpoint MUST be admin-only. Sub-domain auth is reused
 *     from `/api/platform/invariants` (`platform_admins.role`
 *     membership). Never expose externally — SLO data is
 *     business-sensitive.
 *   - Each indicator runs in its own try/catch. An indicator
 *     that errors returns `{ error: "<msg>" }` for that field
 *     instead of failing the whole response.
 *   - HTTP 200 on partial-failure with a flag
 *     `{ degraded: true, errors: [...] }` so external monitors
 *     (Pingdom / Better Uptime) can flip on the right signal
 *     even when only one indicator is down.
 *
 * NOTE — this endpoint is intentionally NOT the readiness probe
 * for the load balancer. A high `clearing_pending` is not a
 * reason to kill the lambda; it is a reason to page the on-call.
 */

import { type NextRequest, NextResponse } from "next/server";
import { randomUUID } from "node:crypto";
import { createClient } from "@/lib/supabase/server";
import { createServiceClient } from "@/lib/supabase/service";
import { withErrorHandler } from "@/lib/api-handler";
import { logger } from "@/lib/logger";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

interface IndicatorError {
  field: string;
  error: string;
}

const HOT_RPCS = [
  "execute_burn_atomic",
  "execute_swap_atomic",
  "custody_commit_coins",
] as const;

const HOT_WEBHOOK_PROVIDERS = ["stripe", "mercadopago", "asaas"] as const;

async function requirePlatformAdmin() {
  const supabase = createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return { error: "Not authenticated", status: 401 } as const;

  const { data: membership } = await supabase
    .from("platform_admins")
    .select("role")
    .eq("user_id", user.id)
    .single();
  if (!membership) return { error: "Forbidden", status: 403 } as const;

  return { user } as const;
}

async function fetchRpcLatency(
  db: ReturnType<typeof createServiceClient>,
): Promise<Record<string, { p50_ms: number; p95_ms: number; p99_ms: number; samples: number } | null>> {
  const out: Record<string, { p50_ms: number; p95_ms: number; p99_ms: number; samples: number } | null> = {};
  for (const fn of HOT_RPCS) {
    try {
      // The RPC `fn_rpc_latency_summary` reads from `pg_stat_statements`
      // (already enabled via L17-01 / audit:pg-stat-statements) and
      // returns p50/p95/p99 for the last 5 minutes for the named
      // function. Implementation is in the migration that lands with
      // L18-10 below; if the function does not exist yet, mark the
      // indicator as null so the response shape stays stable.
      const { data, error } = await db.rpc("fn_rpc_latency_summary", {
        p_rpc_name: fn,
        p_window_minutes: 5,
      });
      if (error) {
        out[fn] = null;
        continue;
      }
      const row = Array.isArray(data) ? data[0] : data;
      out[fn] = row
        ? {
            p50_ms: Number(row.p50_ms ?? 0),
            p95_ms: Number(row.p95_ms ?? 0),
            p99_ms: Number(row.p99_ms ?? 0),
            samples: Number(row.samples ?? 0),
          }
        : null;
    } catch {
      out[fn] = null;
    }
  }
  return out;
}

async function fetchWebhookSuccessRate(
  db: ReturnType<typeof createServiceClient>,
): Promise<Record<string, { success_rate: number; total: number } | null>> {
  const out: Record<string, { success_rate: number; total: number } | null> = {};
  for (const provider of HOT_WEBHOOK_PROVIDERS) {
    try {
      const { data, error } = await db
        .from("billing_webhook_deliveries")
        .select("status,count:status.count()")
        .eq("provider", provider)
        .gte("received_at", new Date(Date.now() - 5 * 60 * 1000).toISOString());
      if (error) {
        out[provider] = null;
        continue;
      }
      const total = (data ?? []).reduce(
        (acc: number, r: { count?: number }) => acc + (r.count ?? 0),
        0,
      );
      const ok = (data ?? [])
        .filter((r: { status?: string }) => r.status === "success")
        .reduce((acc: number, r: { count?: number }) => acc + (r.count ?? 0), 0);
      out[provider] = total === 0 ? { success_rate: 1, total: 0 } : { success_rate: ok / total, total };
    } catch {
      out[provider] = null;
    }
  }
  return out;
}

async function fetchPendingBacklog(
  db: ReturnType<typeof createServiceClient>,
): Promise<{
  clearing: { count: number; oldest_minutes: number | null } | null;
  withdrawal: { count: number; oldest_minutes: number | null } | null;
  deposit: { count: number; oldest_hours: number | null } | null;
}> {
  const result: {
    clearing: { count: number; oldest_minutes: number | null } | null;
    withdrawal: { count: number; oldest_minutes: number | null } | null;
    deposit: { count: number; oldest_hours: number | null } | null;
  } = {
    clearing: null,
    withdrawal: null,
    deposit: null,
  };

  try {
    const { data } = await db
      .from("clearing_settlements")
      .select("created_at")
      .eq("status", "pending")
      .order("created_at", { ascending: true });
    const rows = data ?? [];
    result.clearing = {
      count: rows.length,
      oldest_minutes:
        rows.length > 0
          ? Math.floor(
              (Date.now() - new Date(rows[0].created_at as string).getTime()) /
                60_000,
            )
          : null,
    };
  } catch {
    /* indicator stays null */
  }

  try {
    const { data } = await db
      .from("custody_withdraws")
      .select("created_at")
      .in("status", ["pending", "processing"])
      .order("created_at", { ascending: true });
    const rows = data ?? [];
    result.withdrawal = {
      count: rows.length,
      oldest_minutes:
        rows.length > 0
          ? Math.floor(
              (Date.now() - new Date(rows[0].created_at as string).getTime()) /
                60_000,
            )
          : null,
    };
  } catch {
    /* indicator stays null */
  }

  try {
    const { data } = await db
      .from("custody_deposits")
      .select("created_at")
      .eq("status", "pending")
      .order("created_at", { ascending: true });
    const rows = data ?? [];
    result.deposit = {
      count: rows.length,
      oldest_hours:
        rows.length > 0
          ? Number(
              (
                (Date.now() - new Date(rows[0].created_at as string).getTime()) /
                3_600_000
              ).toFixed(2),
            )
          : null,
    };
  } catch {
    /* indicator stays null */
  }

  return result;
}

export const GET = withErrorHandler(_get, "api.internal.business_health.get");

async function _get(_req: NextRequest) {
  const auth = await requirePlatformAdmin();
  if ("error" in auth) {
    return NextResponse.json({ error: auth.error }, { status: auth.status });
  }

  const requestId = randomUUID();
  const t0 = Date.now();
  const db = createServiceClient();
  const errors: IndicatorError[] = [];

  const [rpcLatency, webhookSuccess, backlog] = await Promise.all([
    fetchRpcLatency(db).catch((err: unknown) => {
      errors.push({
        field: "rpc_latency_ms",
        error: err instanceof Error ? err.message : "unknown",
      });
      return {} as Record<string, null>;
    }),
    fetchWebhookSuccessRate(db).catch((err: unknown) => {
      errors.push({
        field: "webhook_success_rate",
        error: err instanceof Error ? err.message : "unknown",
      });
      return {} as Record<string, null>;
    }),
    fetchPendingBacklog(db).catch((err: unknown) => {
      errors.push({
        field: "backlog",
        error: err instanceof Error ? err.message : "unknown",
      });
      return { clearing: null, withdrawal: null, deposit: null };
    }),
  ]);

  const degraded = errors.length > 0;

  if (degraded) {
    logger.warn("business_health.degraded", { request_id: requestId, errors });
  }

  return NextResponse.json(
    {
      status: degraded ? "degraded" : "ok",
      degraded,
      ts: Date.now(),
      latencyMs: Date.now() - t0,
      indicators: {
        rpc_latency_ms: rpcLatency,
        webhook_success_rate: webhookSuccess,
        clearing_pending: backlog.clearing,
        withdrawal_pending: backlog.withdrawal,
        oldest_pending_deposit: backlog.deposit,
      },
      errors,
    },
    { status: 200 },
  );
}
