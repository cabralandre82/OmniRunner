import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { createServiceClient } from "@/lib/supabase/service";
import { cookies } from "next/headers";

export async function GET(request: Request) {
  const supabase = createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const groupId = cookies().get("portal_group_id")?.value;
  if (!groupId) {
    return NextResponse.json({ error: "No group" }, { status: 400 });
  }

  const db = createServiceClient();

  const { data: callerMembership } = await db
    .from("coaching_members")
    .select("role")
    .eq("group_id", groupId)
    .eq("user_id", user.id)
    .maybeSingle();

  if (
    !callerMembership ||
    !["admin_master", "coach", "assistant"].includes(callerMembership.role)
  ) {
    return NextResponse.json({ error: "Forbidden" }, { status: 403 });
  }

  const { searchParams } = new URL(request.url);
  const from = searchParams.get("from");
  const to = searchParams.get("to");
  const sessionId = searchParams.get("session_id");

  const now = new Date();
  const defaultFrom = new Date(now);
  defaultFrom.setDate(defaultFrom.getDate() - 30);
  const fromDate = from ? new Date(from) : defaultFrom;
  const toDate = to ? new Date(to) : now;

  let sessionsQuery = db
    .from("coaching_training_sessions")
    .select("id, title, starts_at")
    .eq("group_id", groupId)
    .gte("starts_at", fromDate.toISOString())
    .lte("starts_at", toDate.toISOString())
    .order("starts_at", { ascending: false });

  if (sessionId) {
    sessionsQuery = sessionsQuery.eq("id", sessionId);
  }

  const { data: sessions } = await sessionsQuery;

  if (!sessions || sessions.length === 0) {
    const BOM = "\uFEFF";
    const header = "Título Sessão,Data,Atleta,Check-in,Método,Status";
    return new NextResponse(BOM + header + "\n", {
      headers: {
        "Content-Type": "text/csv; charset=utf-8",
        "Content-Disposition": 'attachment; filename="attendance.csv"',
      },
    });
  }

  const sessionIds = sessions.map((s) => s.id);

  const { data: attendance } = await db
    .from("coaching_training_attendance")
    .select("session_id, athlete_user_id, checked_at, method, status")
    .in("session_id", sessionIds)
    .eq("group_id", groupId)
    .order("checked_at", { ascending: true });

  const athleteIds = Array.from(new Set((attendance ?? []).map((a) => a.athlete_user_id)));
  const profileMap = new Map<string, string>();

  if (athleteIds.length > 0) {
    const { data: profiles } = await db
      .from("profiles")
      .select("id, display_name")
      .in("id", athleteIds);

    for (const p of profiles ?? []) {
      profileMap.set(p.id, (p as { id: string; display_name: string }).display_name || "Sem nome");
    }
  }

  const sessionMap = new Map(sessions.map((s) => [s.id, s]));
  const rows: string[] = [];

  for (const a of attendance ?? []) {
    const s = sessionMap.get(a.session_id);
    const athleteName = (profileMap.get(a.athlete_user_id) ?? "—").replace(/,/g, " ");
    const sessionTitle = (s?.title ?? "").replace(/,/g, " ");
    const date = s ? new Date(s.starts_at).toLocaleDateString("pt-BR") : "";
    const checkedAt = new Date(a.checked_at).toLocaleString("pt-BR");
    const method = a.method === "qr" ? "QR" : "Manual";
    const status = a.status;
    rows.push(`${sessionTitle},${date},${athleteName},${checkedAt},${method},${status}`);
  }

  const BOM = "\uFEFF";
  const header = "Título Sessão,Data,Atleta,Check-in,Método,Status";
  const csv = BOM + header + "\n" + rows.join("\n");

  return new NextResponse(csv, {
    headers: {
      "Content-Type": "text/csv; charset=utf-8",
      "Content-Disposition": 'attachment; filename="attendance.csv"',
    },
  });
}
