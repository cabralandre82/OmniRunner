import { NextRequest, NextResponse } from "next/server";
import { cookies } from "next/headers";
import { createClient } from "@/lib/supabase/server";
import { createServiceClient } from "@/lib/supabase/service";
import {
  apiUnauthorized,
  apiForbidden,
  apiError,
  apiValidationFailed,
} from "@/lib/api/errors";
import { withErrorHandler } from "@/lib/api-handler";

/**
 * L05-08 — Withdrawal progress timeline.
 *
 * The portal renders a 4-step progress UI
 * (pending → processing → completed | failed) and needs:
 *   - which transitions have happened + when
 *   - expected_completion_at (SLA-derived)
 *   - sla_breached flag so the UI can switch to "estou atrasado"
 *     copy and surface the runbook link
 *   - refund_eta_days (D+2) when the final state is `failed`
 *
 * This is entirely derived from `fn_withdrawal_timeline(uuid)` so
 * the portal cannot drift from the canonical policy encoded in the
 * DB. The endpoint is admin_master-only on the owning host group.
 */

async function requireAdminMaster(withdrawalId: string) {
  const supabase = createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return { error: "unauthorized" as const };

  const groupId = cookies().get("portal_group_id")?.value;
  if (!groupId) return { error: "no_group" as const };

  const db = createServiceClient();
  const { data: membership } = await db
    .from("coaching_members")
    .select("role")
    .eq("group_id", groupId)
    .eq("user_id", user.id)
    .maybeSingle();

  if (!membership || membership.role !== "admin_master") {
    return { error: "forbidden" as const };
  }

  const { data: w } = await db
    .from("custody_withdrawals")
    .select("id, group_id")
    .eq("id", withdrawalId)
    .maybeSingle();

  if (!w || w.group_id !== groupId) {
    return { error: "not_found" as const };
  }

  return { user, groupId, db } as const;
}

export const GET = withErrorHandler(
  _get,
  "api.custody.withdraw.timeline.get",
);

async function _get(
  req: NextRequest,
  ctx: { params: { id: string } },
) {
  const id = ctx.params?.id;
  if (!id || !/^[0-9a-f-]{36}$/i.test(id)) {
    return apiValidationFailed(req, "Invalid withdrawal id");
  }

  const auth = await requireAdminMaster(id);
  if ("error" in auth) {
    if (auth.error === "unauthorized") return apiUnauthorized(req);
    if (auth.error === "no_group") {
      return apiError(req, "NO_GROUP_SESSION", "No portal group selected", 400);
    }
    if (auth.error === "forbidden") return apiForbidden(req);
    return apiError(req, "NOT_FOUND", "Withdrawal not found", 404);
  }

  const { data, error } = await auth.db.rpc("fn_withdrawal_timeline", {
    p_withdrawal_id: id,
  });

  if (error) {
    return apiError(
      req,
      "TIMELINE_UNAVAILABLE",
      "Failed to load withdrawal timeline",
      503,
    );
  }

  if (!data) {
    return apiError(req, "NOT_FOUND", "Withdrawal not found", 404);
  }

  return NextResponse.json({ timeline: data });
}
