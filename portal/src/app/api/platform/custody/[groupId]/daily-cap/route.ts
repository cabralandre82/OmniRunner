import { NextRequest } from "next/server";
import { z } from "zod";
import { createClient } from "@/lib/supabase/server";
import { createServiceClient } from "@/lib/supabase/service";
import { auditLog } from "@/lib/audit";
import { rateLimit } from "@/lib/rate-limit";
import { withIdempotency } from "@/lib/api/idempotency";
import {
  apiError,
  apiForbidden,
  apiNotFound,
  apiOk,
  apiRateLimited,
  apiUnauthorized,
  apiValidationFailed,
} from "@/lib/api/errors";
import { rateLimitKey } from "@/lib/api/rate-limit-key";
import { logger } from "@/lib/logger";
import { withErrorHandler } from "@/lib/api-handler";

/**
 * L05-09 — `GET|PATCH /api/platform/custody/[groupId]/daily-cap`
 *
 * Platform-admin endpoint that:
 *   • GET  → returns the current cap, the live window snapshot
 *            (current_total/available/would_exceed), and the last 20
 *            cap-change history rows.
 *   • PATCH → atomically updates `custody_accounts.daily_deposit_limit_usd`
 *            via `fn_set_daily_deposit_cap`, which also writes an audit row
 *            into `custody_daily_cap_changes`. `reason` >= 10 chars
 *            (postmortem obrigatório).
 *
 * Authorization: `profiles.platform_role = 'admin'`. Cookie-scoped
 * `portal_group_id` is NOT required — platform admins act on any group.
 *
 * Idempotency: PATCH requires `x-idempotency-key` (delegated to L18-02).
 * The downstream RPC is intrinsically idempotent on `(group_id, new_cap)`
 * but we audit each call (so retries collapse to a single audit row).
 */

const CAP_MIN = 0;
const CAP_MAX = 10_000_000;

const patchSchema = z
  .object({
    daily_deposit_limit_usd: z.number().min(CAP_MIN).max(CAP_MAX),
    reason: z.string().trim().min(10).max(500),
  })
  .strict();

const idParamSchema = z.string().uuid();

async function requirePlatformAdmin() {
  const supabase = createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return { error: "UNAUTHORIZED", status: 401 } as const;

  const { data: profile } = await supabase
    .from("profiles")
    .select("platform_role")
    .eq("id", user.id)
    .single();
  if (!profile || profile.platform_role !== "admin") {
    return { error: "FORBIDDEN", status: 403 } as const;
  }
  return { user } as const;
}

// L17-01 — endpoint financeiro crítico (configura teto de depósito que
// alimenta antifraude). Outermost wrapper garante 500 canônico + Sentry +
// x-request-id em qualquer throw inesperado.
export const GET = withErrorHandler(_get, "api.platform.custody.daily-cap.get");
export const PATCH = withErrorHandler(_patch, "api.platform.custody.daily-cap.patch");

async function _get(
  req: NextRequest,
  ctx: { params: { groupId: string } },
) {
  const auth = await requirePlatformAdmin();
  if ("error" in auth) {
    return auth.status === 401 ? apiUnauthorized(req) : apiForbidden(req);
  }

  const idParse = idParamSchema.safeParse(ctx.params.groupId);
  if (!idParse.success) {
    return apiValidationFailed(req, "Invalid groupId (must be UUID)");
  }
  const groupId = idParse.data;

  const db = createServiceClient();

  const { data: account, error: accErr } = await db
    .from("custody_accounts")
    .select(
      "group_id, daily_deposit_limit_usd, daily_limit_timezone, daily_limit_updated_at, daily_limit_updated_by",
    )
    .eq("group_id", groupId)
    .maybeSingle();

  if (accErr) {
    logger.error("daily-cap GET: load account failed", accErr, { groupId });
    return apiError(req, "INTERNAL_ERROR", "Failed to load account", 500);
  }
  if (!account) {
    return apiNotFound(req, "Custody account not found for this group");
  }

  const { data: windowData, error: winErr } = await db.rpc(
    "fn_check_daily_deposit_window",
    { p_group_id: groupId, p_amount_usd: 0 },
  );
  if (winErr) {
    logger.error("daily-cap GET: window probe failed", winErr, { groupId });
    return apiError(req, "INTERNAL_ERROR", "Failed to read window", 500);
  }
  const win = Array.isArray(windowData) ? windowData[0] : windowData;

  const { data: history } = await db
    .from("custody_daily_cap_changes")
    .select("previous_cap_usd, new_cap_usd, actor_user_id, reason, changed_at")
    .eq("group_id", groupId)
    .order("changed_at", { ascending: false })
    .limit(20);

  return apiOk({
    account: {
      group_id: account.group_id,
      daily_deposit_limit_usd: Number(account.daily_deposit_limit_usd),
      daily_limit_timezone: account.daily_limit_timezone,
      daily_limit_updated_at: account.daily_limit_updated_at,
      daily_limit_updated_by: account.daily_limit_updated_by,
    },
    window: {
      current_total_usd: Number(win?.current_total_usd ?? 0),
      daily_limit_usd: Number(win?.daily_limit_usd ?? 0),
      available_today_usd: Number(win?.available_today_usd ?? 0),
      would_exceed: Boolean(win?.would_exceed),
      window_start_utc: win?.window_start_utc ?? null,
      window_end_utc: win?.window_end_utc ?? null,
      timezone: win?.timezone ?? account.daily_limit_timezone,
    },
    history: history ?? [],
  });
}

async function _patch(
  req: NextRequest,
  ctx: { params: { groupId: string } },
) {
  const auth = await requirePlatformAdmin();
  if ("error" in auth) {
    return auth.status === 401 ? apiUnauthorized(req) : apiForbidden(req);
  }

  const idParse = idParamSchema.safeParse(ctx.params.groupId);
  if (!idParse.success) {
    return apiValidationFailed(req, "Invalid groupId (must be UUID)");
  }
  const groupId = idParse.data;

  const rl = await rateLimit(
    rateLimitKey({
      prefix: "platform:custody:daily-cap",
      userId: auth.user.id,
      request: req,
    }),
    { maxRequests: 30, windowMs: 60_000 },
  );
  if (!rl.allowed) {
    return apiRateLimited(req, Math.ceil((rl.resetAt - Date.now()) / 1000));
  }

  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return apiValidationFailed(req, "Invalid JSON body");
  }
  const parsed = patchSchema.safeParse(body);
  if (!parsed.success) {
    return apiValidationFailed(
      req,
      parsed.error.issues[0]?.message ?? "Invalid input",
      parsed.error.flatten(),
    );
  }

  const requestId = req.headers.get("x-request-id");
  const errBody = (code: string, message: string, details?: unknown) => ({
    ok: false as const,
    error: {
      code,
      message,
      request_id: requestId,
      ...(details !== undefined ? { details } : {}),
    },
  });

  return withIdempotency({
    request: req,
    namespace: "platform.custody.daily-cap.set",
    actorId: auth.user.id,
    requestBody: { groupId, ...parsed.data },
    required: true,
    handler: async () => {
      const db = createServiceClient();
      const { data, error } = await db.rpc("fn_set_daily_deposit_cap", {
        p_group_id: groupId,
        p_new_cap_usd: parsed.data.daily_deposit_limit_usd,
        p_actor_user_id: auth.user.id,
        p_reason: parsed.data.reason,
      });

      if (error) {
        const code = error.code ?? "";
        const msg = error.message ?? "";
        if (code === "P0001") {
          return { status: 400, body: errBody("VALIDATION_FAILED", msg) };
        }
        logger.error("fn_set_daily_deposit_cap failed", error, {
          group_id: groupId,
          actor: auth.user.id,
        });
        return {
          status: 500,
          body: errBody("INTERNAL_ERROR", "Failed to update daily cap"),
        };
      }

      const row = Array.isArray(data) ? data[0] : data;

      await auditLog({
        actorId: auth.user.id,
        groupId,
        action: "platform.custody.daily-cap.set",
        targetType: "custody_account",
        targetId: groupId,
        metadata: {
          previous_cap_usd: Number(row?.out_previous_cap_usd ?? 0),
          new_cap_usd: Number(row?.out_new_cap_usd ?? 0),
          reason: parsed.data.reason,
          runbook: "CUSTODY_DAILY_CAP_RUNBOOK",
        },
      });

      return {
        status: 200,
        body: {
          ok: true,
          data: {
            group_id: groupId,
            previous_cap_usd: Number(row?.out_previous_cap_usd ?? 0),
            new_cap_usd: Number(row?.out_new_cap_usd ?? 0),
            changed_at: row?.out_changed_at ?? null,
          },
        },
      };
    },
  });
}
