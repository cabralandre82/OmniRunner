import { NextRequest } from "next/server";
import { z } from "zod";
import { createClient } from "@/lib/supabase/server";
import { createServiceClient } from "@/lib/supabase/service";
import { auditLog } from "@/lib/audit";
import { rateLimit } from "@/lib/rate-limit";
import { withIdempotency } from "@/lib/api/idempotency";
import {
  apiForbidden,
  apiRateLimited,
  apiUnauthorized,
  apiValidationFailed,
} from "@/lib/api/errors";
import { rateLimitKey } from "@/lib/api/rate-limit-key";
import { logger } from "@/lib/logger";
import { withErrorHandler } from "@/lib/api-handler";

/**
 * L02-06 — POST /api/platform/custody/withdrawals/[id]/fail
 *
 * Platform-admin endpoint that transitions a custody withdrawal from
 * `processing` → `failed`, replacing the manual SQL block previously
 * documented in `WITHDRAW_STUCK_RUNBOOK.md` §3.3 (provider rejected).
 * Calls `fail_withdrawal` RPC which atomically:
 *
 *   1. Refunds `total_deposited_usd` on the originating
 *      `custody_accounts` row.
 *   2. Deletes any `platform_revenue` row of `fee_type='fx_spread'`
 *      tied to this withdrawal.
 *   3. Re-validates `check_custody_invariants()` — aborts with P0008
 *      if the refund would unbalance custody (defensive; means the
 *      operator must reconcile manually before retrying).
 *   4. Marks the withdrawal `failed` and appends `| reverted: <reason>
 *      @ <ts>` to `payout_reference` for forensics.
 *
 * Idempotent against re-clicks (returns `was_terminal: true` if
 * already failed).
 */

const failSchema = z
  .object({
    reason: z.string().trim().min(3).max(500),
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

// L17-01 — endpoint financeiro crítico: reverte um withdrawal e refunda
// custody_accounts via RPC `fail_withdrawal`. Outermost wrapper garante
// 500 canônico + Sentry capture caso o supabase admin falhe ou o RPC
// retorne uma exceção fora dos códigos esperados (P0001/P0002/etc.)
export const POST = withErrorHandler(_post, "api.platform.custody.withdraw.fail");

async function _post(
  req: NextRequest,
  ctx: { params: { id: string } },
) {
  const auth = await requirePlatformAdmin();
  if ("error" in auth) {
    return auth.status === 401 ? apiUnauthorized(req) : apiForbidden(req);
  }

  const idParse = idParamSchema.safeParse(ctx.params.id);
  if (!idParse.success) {
    return apiValidationFailed(req, "Invalid withdrawal id (must be UUID)");
  }
  const withdrawalId = idParse.data;

  const rl = await rateLimit(
    rateLimitKey({
      prefix: "platform:withdraw:fail",
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
  const parsed = failSchema.safeParse(body);
  if (!parsed.success) {
    return apiValidationFailed(
      req,
      parsed.error.issues[0]?.message ?? "Invalid input",
      parsed.error.flatten(),
    );
  }

  const requestId = req.headers.get("x-request-id");
  const errorBody = (code: string, message: string, details?: unknown) => ({
    ok: false,
    error: { code, message, request_id: requestId, ...(details !== undefined ? { details } : {}) },
  });

  return withIdempotency({
    request: req,
    namespace: "platform.custody.withdraw.fail",
    actorId: auth.user.id,
    requestBody: { withdrawalId, ...parsed.data },
    required: true,
    handler: async () => {
      const db = createServiceClient();
      const { data, error } = await db.rpc("fail_withdrawal", {
        p_withdrawal_id: withdrawalId,
        p_reason: parsed.data.reason,
        p_actor_user_id: auth.user.id,
      });

      if (error) {
        const code = error.code ?? "";
        const msg = error.message ?? "";
        if (code === "P0002" || msg.includes("WITHDRAWAL_NOT_FOUND")) {
          return { status: 404, body: errorBody("NOT_FOUND", "Withdrawal not found") };
        }
        if (msg.includes("INVALID_TRANSITION")) {
          return {
            status: 409,
            body: errorBody(
              "INVALID_TRANSITION",
              msg.replace(/^.*INVALID_TRANSITION:\s*/, "") || "withdrawal is not in 'processing'",
            ),
          };
        }
        if (msg.includes("INVARIANT_VIOLATION")) {
          return {
            status: 409,
            body: errorBody(
              "INVARIANT_VIOLATION",
              "Refund would unbalance custody for this group; reconcile manually before retrying.",
              { hint: "inspect check_custody_invariants() and the WITHDRAW_STUCK_RUNBOOK §3.3 manual fallback" },
            ),
          };
        }
        if (code === "P0001") {
          return { status: 400, body: errorBody("VALIDATION_FAILED", msg) };
        }
        logger.error("fail_withdrawal failed", error, {
          withdrawal_id: withdrawalId,
          actor: auth.user.id,
        });
        return { status: 500, body: errorBody("INTERNAL_ERROR", "Failed to fail withdrawal") };
      }

      const row = Array.isArray(data) ? data[0] : data;
      const wasTerminal = Boolean(row?.was_terminal);
      const refunded = Number(row?.refunded_usd ?? 0);
      const revenueReversed = Number(row?.revenue_reversed ?? 0);

      if (!wasTerminal) {
        await auditLog({
          actorId: auth.user.id,
          action: "platform.custody.withdrawal.fail",
          targetType: "custody_withdrawal",
          targetId: withdrawalId,
          metadata: {
            reason: parsed.data.reason,
            refunded_usd: refunded,
            revenue_reversed_usd: revenueReversed,
            runbook: "WITHDRAW_STUCK_RUNBOOK#3.3",
          },
        });
      }

      return {
        status: 200,
        body: {
          ok: true,
          data: {
            withdrawal_id: withdrawalId,
            status: "failed" as const,
            was_terminal: wasTerminal,
            refunded_usd: refunded,
            revenue_reversed_usd: revenueReversed,
          },
        },
      };
    },
  });
}
