import { NextRequest, NextResponse } from "next/server";
import { cookies } from "next/headers";
import { createClient } from "@/lib/supabase/server";
import { createServiceClient } from "@/lib/supabase/service";
import { rateLimit } from "@/lib/rate-limit";
import { logger } from "@/lib/logger";

const INACTIVE_DAYS = 14;
const PENDING_CLEARING_DAYS = 3;
const LOW_CREDIT_THRESHOLD = 50;

export interface StaffAlert {
  key: string;
  label: string;
  count: number;
  severity: "warning" | "error" | "info";
}

export async function GET(req: NextRequest) {
  try {
    const ip = req.headers.get("x-forwarded-for") ?? "unknown";
    const rl = rateLimit(`staff-alerts:${ip}`, { maxRequests: 20, windowMs: 60_000 });
    if (!rl.allowed) {
      return NextResponse.json({ error: "Too many requests" }, { status: 429 });
    }

    const supabase = createClient();
    const {
      data: { user },
    } = await supabase.auth.getUser();

    if (!user) {
      return NextResponse.json({ error: "Não autorizado" }, { status: 401 });
    }

    const groupId = cookies().get("portal_group_id")?.value;
    if (!groupId) {
      return NextResponse.json({ error: "Grupo não selecionado" }, { status: 400 });
    }

    const db = createServiceClient();

    const { data: membership } = await db
      .from("coaching_members")
      .select("role")
      .eq("group_id", groupId)
      .eq("user_id", user.id)
      .maybeSingle();

    if (
      !membership ||
      !["admin_master", "coach"].includes((membership as { role: string }).role)
    ) {
      return NextResponse.json({ error: "Sem permissão" }, { status: 403 });
    }

    const alerts: StaffAlert[] = [];

    const { data: athleteMembers } = await db
      .from("coaching_members")
      .select("user_id")
      .eq("group_id", groupId)
      .in("role", ["athlete", "atleta"]);

    const athleteIds = (athleteMembers ?? []).map((m: { user_id: string }) => m.user_id);

    if (athleteIds.length > 0) {
      const cutoffMs = Date.now() - INACTIVE_DAYS * 86_400_000;

      const { data: recentActive } = await db
        .from("sessions")
        .select("user_id")
        .in("user_id", athleteIds)
        .gte("start_time_ms", cutoffMs)
        .gte("status", 3);

      const activeUserIds = new Set(
        (recentActive ?? []).map((s: { user_id: string }) => s.user_id),
      );
      const inactiveCount = athleteIds.filter((id) => !activeUserIds.has(id)).length;

      if (inactiveCount > 0) {
        alerts.push({
          key: "inactive_athletes",
          label: `${inactiveCount} atleta${inactiveCount > 1 ? "s" : ""} inativo${inactiveCount > 1 ? "s" : ""} há ${INACTIVE_DAYS}+ dias`,
          count: inactiveCount,
          severity: "warning",
        });
      }
    }

    try {
      const clearingCutoff = new Date(Date.now() - PENDING_CLEARING_DAYS * 86_400_000).toISOString();
      const { count: pendingClearings } = await db
        .from("clearing_cases")
        .select("id", { count: "exact", head: true })
        .eq("to_group_id", groupId)
        .eq("status", "OPEN")
        .lte("created_at", clearingCutoff);

      if (pendingClearings && pendingClearings > 0) {
        alerts.push({
          key: "pending_clearings",
          label: `${pendingClearings} compensaç${pendingClearings > 1 ? "ões" : "ão"} pendente${pendingClearings > 1 ? "s" : ""}`,
          count: pendingClearings,
          severity: "warning",
        });
      }
    } catch {
      // clearing_cases table may not exist yet
    }

    const { data: inventory } = await supabase
      .from("coaching_token_inventory")
      .select("available_tokens")
      .eq("group_id", groupId)
      .maybeSingle();

    const credits = (inventory as { available_tokens: number } | null)?.available_tokens ?? 0;
    if (credits < LOW_CREDIT_THRESHOLD) {
      alerts.push({
        key: "low_credits",
        label: `Créditos baixos: ${credits} restantes`,
        count: credits,
        severity: "error",
      });
    }

    return NextResponse.json({ alerts });
  } catch (error) {
    logger.error("Failed to fetch staff alerts", error);
    return NextResponse.json({ error: "Erro interno" }, { status: 500 });
  }
}
