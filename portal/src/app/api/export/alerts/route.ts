import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { createServiceClient } from "@/lib/supabase/service";
import { cookies } from "next/headers";

export async function GET(request: Request) {
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

  const { searchParams } = new URL(request.url);
  const from = searchParams.get("from");
  const to = searchParams.get("to");

  const now = new Date();
  const defaultFrom = new Date(now);
  defaultFrom.setDate(defaultFrom.getDate() - 30);
  const fromDate = from ? new Date(from) : defaultFrom;
  const toDate = to ? new Date(to) : now;

  let alertsQuery = db
    .from("coaching_alerts")
    .select("id, user_id, day, alert_type, title, resolved, resolved_at")
    .eq("group_id", groupId)
    .gte("day", fromDate.toISOString().slice(0, 10))
    .lte("day", toDate.toISOString().slice(0, 10))
    .order("day", { ascending: false });

  const { data: alerts } = await alertsQuery;

  if (!alerts || alerts.length === 0) {
    const BOM = "\uFEFF";
    const header = "Atleta,Tipo Alerta,Dia,Resolvido,Data Resolução";
    return new NextResponse(BOM + header + "\n", {
      headers: {
        "Content-Type": "text/csv; charset=utf-8",
        "Content-Disposition": 'attachment; filename="alerts.csv"',
      },
    });
  }

  const userIds = Array.from(
    new Set((alerts as { user_id: string }[]).map((a) => a.user_id))
  );
  const profileMap = new Map<string, string>();

  if (userIds.length > 0) {
    const { data: profiles } = await db
      .from("profiles")
      .select("id, display_name")
      .in("id", userIds);
    for (const p of profiles ?? []) {
      profileMap.set(
        (p as { id: string }).id,
        ((p as { display_name: string }).display_name || "Sem nome").replace(
          /[,;"\n]/g,
          " "
        )
      );
    }
  }

  const escape = (s: string) =>
    s.includes(",") || s.includes('"') || s.includes("\n")
      ? `"${s.replace(/"/g, '""')}"`
      : s;

  const ALERT_TYPE_LABELS: Record<string, string> = {
    athlete_high_risk: "Risco Alto",
    athlete_medium_risk: "Risco Médio",
    engagement_drop: "Queda Engajamento",
    milestone_reached: "Marco Atingido",
    inactive_7d: "Inativo 7d",
    inactive_14d: "Inativo 14d",
    inactive_30d: "Inativo 30d",
  };

  const rows = (alerts as {
    user_id: string;
    day: string;
    alert_type: string;
    resolved: boolean;
    resolved_at: string | null;
  }[]).map((a) => {
    const atleta = escape(profileMap.get(a.user_id) ?? "—");
    const tipoAlerta = escape(
      ALERT_TYPE_LABELS[a.alert_type] ?? a.alert_type
    );
    const dia = new Date(a.day).toLocaleDateString("pt-BR");
    const resolvido = a.resolved ? "Sim" : "Não";
    const dataResolucao = a.resolved_at
      ? new Date(a.resolved_at).toLocaleString("pt-BR")
      : "—";
    return `${atleta},${tipoAlerta},${dia},${resolvido},${dataResolucao}`;
  });

  const BOM = "\uFEFF";
  const header = "Atleta,Tipo Alerta,Dia,Resolvido,Data Resolução";
  const csv = BOM + header + "\n" + rows.join("\n");

  return new NextResponse(csv, {
    headers: {
      "Content-Type": "text/csv; charset=utf-8",
      "Content-Disposition": 'attachment; filename="alerts.csv"',
    },
  });
}
