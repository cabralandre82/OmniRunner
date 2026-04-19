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

/**
 * L02-06 — POST /api/platform/custody/withdrawals/[id]/complete
 *
 * Platform-admin endpoint that transitions a custody withdrawal from
 * `processing` → `completed`, replacing the manual SQL block previously
 * documented in `WITHDRAW_STUCK_RUNBOOK.md` §3.1. Calls the
 * `complete_withdrawal` RPC which is idempotent against re-clicks
 * (returns `was_terminal: true` if already completed).
 *
 * Authorization: `profiles.platform_role = 'admin'`. Cookie-scoped
 * `portal_group_id` is NOT required — platform admins act on any group.
 *
 * Idempotency: required via `x-idempotency-key` header (delegated to
 * the L18-02 wrapper). The downstream RPC is also intrinsically
 * idempotent, so this is defence-in-depth against double-click and
 * network-blip retries.
 */

const completeSchema = z
  .object({
    payout_reference: z.string().trim().min(3).max(200),
    note: z.string().trim().max(500).optional(),
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

export async function POST(
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
      prefix: "platform:withdraw:complete",
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
  const parsed = completeSchema.safeParse(body);
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
    namespace: "platform.custody.withdraw.complete",
    actorId: auth.user.id,
    requestBody: { withdrawalId, ...parsed.data },
    required: true,
    handler: async () => {
      const db = createServiceClient();
      const { data, error } = await db.rpc("complete_withdrawal", {
        p_withdrawal_id: withdrawalId,
        p_payout_reference: parsed.data.payout_reference,
        p_actor_user_id: auth.user.id,
        p_note: parsed.data.note ?? null,
      });

      if (error) {
        const code = error.code ?? "";
        const msg = error.message ?? "";
        if (code === "P0002" || msg.includes("WITHDRAWAL_NOT_FOUND")) {
          return { status: 404, body: errorBody("NOT_FOUND", "Withdrawal not found") };
        }
        if (code === "P0008" || msg.includes("INVALID_TRANSITION")) {
          return {
            status: 409,
            body: errorBody(
              "INVALID_TRANSITION",
              msg.replace(/^.*INVALID_TRANSITION:\s*/, "") || "withdrawal is not in 'processing'",
            ),
          };
        }
        if (code === "P0001") {
          return { status: 400, body: errorBody("VALIDATION_FAILED", msg) };
        }
        logger.error("complete_withdrawal failed", error, {
          withdrawal_id: withdrawalId,
          actor: auth.user.id,
        });
        return { status: 500, body: errorBody("INTERNAL_ERROR", "Failed to complete withdrawal") };
      }

      const row = Array.isArray(data) ? data[0] : data;
      const wasTerminal = Boolean(row?.was_terminal);

      if (!wasTerminal) {
        await auditLog({
          actorId: auth.user.id,
          action: "platform.custody.withdrawal.complete",
          targetType: "custody_withdrawal",
          targetId: withdrawalId,
          metadata: {
            payout_reference: parsed.data.payout_reference,
            note: parsed.data.note,
            runbook: "WITHDRAW_STUCK_RUNBOOK#3.1",
          },
        });
      }

      return {
        status: 200,
        body: {
          ok: true,
          data: {
            withdrawal_id: withdrawalId,
            status: "completed" as const,
            was_terminal: wasTerminal,
            completed_at: row?.completed_at ?? null,
          },
        },
      };
    },
  });
}
