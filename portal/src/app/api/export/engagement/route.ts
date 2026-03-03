import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { createServiceClient } from "@/lib/supabase/service";
import { cookies } from "next/headers";

export const dynamic = "force-dynamic";

export async function GET(req: NextRequest) {
  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();

  if (!session) {
    return NextResponse.json({ error: "Não autorizado" }, { status: 401 });
  }

  const groupId = cookies().get("portal_group_id")?.value;
  if (!groupId) {
    return NextResponse.json({ error: "Grupo não selecionado" }, { status: 400 });
  }

  const db = createServiceClient();
  const { data: callerMembership } = await db
    .from("coaching_members")
    .select("role")
    .eq("group_id", groupId)
    .eq("user_id", session.user.id)
    .maybeSingle();

  if (
    !callerMembership ||
    !["admin_master", "coach", "assistant"].includes(
      (callerMembership as { role: string }).role
    )
  ) {
    return NextResponse.json({ error: "Sem permissão" }, { status: 403 });
  }
  const url = new URL(req.url);
  const from = url.searchParams.get("from");
  const to = url.searchParams.get("to");

  let query = db
    .from("coaching_kpis_daily")
    .select("day, engagement_score, total_athletes, total_coaches, churn_risk_count")
    .eq("group_id", groupId)
    .order("day", { ascending: false });

  if (from) query = query.gte("day", from);
  if (to) query = query.lte("day", to);

  const { data, error } = await query;
  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  const rows = data ?? [];
  const header = "Dia,Score Engajamento,Total Atletas,Total Coaches,Risco Churn";
  const csv = [
    header,
    ...rows.map((r: Record<string, unknown>) =>
      [
        r.day,
        r.engagement_score ?? "",
        r.total_athletes ?? "",
        r.total_coaches ?? "",
        r.churn_risk_count ?? "",
      ].join(",")
    ),
  ].join("\n");

  return new NextResponse("\uFEFF" + csv, {
    headers: {
      "Content-Type": "text/csv; charset=utf-8",
      "Content-Disposition": 'attachment; filename="engagement.csv"',
    },
  });
}
