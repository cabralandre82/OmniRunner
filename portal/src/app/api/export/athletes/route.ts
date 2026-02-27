import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { createServiceClient } from "@/lib/supabase/service";
import { cookies } from "next/headers";
import { auditLog } from "@/lib/audit";
import { rateLimit } from "@/lib/rate-limit";

export async function GET() {
  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();

  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const rl = rateLimit(`export:${session.user.id}`, { maxRequests: 3, windowMs: 60_000 });
  if (!rl.allowed) {
    return NextResponse.json({ error: "Too many requests" }, { status: 429 });
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
    .eq("user_id", session.user.id)
    .maybeSingle();

  if (
    !callerMembership ||
    !["admin_master", "professor"].includes(callerMembership.role)
  ) {
    return NextResponse.json({ error: "Forbidden" }, { status: 403 });
  }

  const { data: members } = await db
    .from("coaching_members")
    .select("user_id, display_name, joined_at_ms")
    .eq("group_id", groupId)
    .eq("role", "atleta")
    .order("display_name");

  const allMembers = members ?? [];
  const userIds = allMembers.map((m: { user_id: string }) => m.user_id);

  const verMap = new Map<string, { status: string; trust: number }>();
  const sessionMap = new Map<string, { total: number; distance: number }>();

  if (userIds.length > 0) {
    const [verRes, sessRes] = await Promise.all([
      db
        .from("athlete_verification")
        .select("user_id, verification_status, trust_score")
        .in("user_id", userIds),
      db
        .from("sessions")
        .select("user_id, total_distance_m")
        .in("user_id", userIds)
        .gte("status", 3),
    ]);

    for (const v of verRes.data ?? []) {
      const r = v as { user_id: string; verification_status: string; trust_score: number };
      verMap.set(r.user_id, { status: r.verification_status, trust: r.trust_score });
    }

    for (const s of sessRes.data ?? []) {
      const r = s as { user_id: string; total_distance_m: number };
      const ex = sessionMap.get(r.user_id);
      if (ex) {
        ex.total++;
        ex.distance += r.total_distance_m ?? 0;
      } else {
        sessionMap.set(r.user_id, { total: 1, distance: r.total_distance_m ?? 0 });
      }
    }
  }

  const BOM = "\uFEFF";
  const header = "Nome,Status Verificação,Trust Score,Corridas,Distância (km),Membro Desde";
  const rows = allMembers.map((m: { user_id: string; display_name: string; joined_at_ms: number }) => {
    const v = verMap.get(m.user_id);
    const s = sessionMap.get(m.user_id);
    const km = ((s?.distance ?? 0) / 1000).toFixed(1);
    const joined = new Date(m.joined_at_ms).toLocaleDateString("pt-BR");
    const name = (m.display_name || "Sem nome").replace(/,/g, " ");
    return `${name},${v?.status ?? "UNVERIFIED"},${v?.trust ?? 0},${s?.total ?? 0},${km},${joined}`;
  });

  const csv = BOM + header + "\n" + rows.join("\n");

  await auditLog({
    actorId: session.user.id,
    groupId,
    action: "export.athletes_csv",
    metadata: { count: allMembers.length },
  });

  return new NextResponse(csv, {
    headers: {
      "Content-Type": "text/csv; charset=utf-8",
      "Content-Disposition": `attachment; filename="atletas_${new Date().toISOString().slice(0, 10)}.csv"`,
    },
  });
}
