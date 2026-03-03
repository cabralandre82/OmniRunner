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
  const announcementId = searchParams.get("announcement_id");
  const from = searchParams.get("from");
  const to = searchParams.get("to");

  let announcementsQuery = db
    .from("coaching_announcements")
    .select("id, title, created_at")
    .eq("group_id", groupId)
    .order("created_at", { ascending: false });

  if (announcementId) {
    announcementsQuery = announcementsQuery.eq("id", announcementId);
  }

  if (from) {
    announcementsQuery = announcementsQuery.gte("created_at", from);
  }
  if (to) {
    announcementsQuery = announcementsQuery.lte("created_at", to);
  }

  const { data: announcements } = await announcementsQuery;

  if (!announcements || announcements.length === 0) {
    const BOM = "\uFEFF";
    const header = "Título,Membro,Lido Em";
    return new NextResponse(BOM + header + "\n", {
      headers: {
        "Content-Type": "text/csv; charset=utf-8",
        "Content-Disposition": 'attachment; filename="announcements-reads.csv"',
      },
    });
  }

  const ids = announcements.map((a) => a.id);

  let readsQuery = db
    .from("coaching_announcement_reads")
    .select("announcement_id, user_id, read_at")
    .in("announcement_id", ids)
    .order("read_at", { ascending: true });

  if (from) {
    readsQuery = readsQuery.gte("read_at", from);
  }
  if (to) {
    readsQuery = readsQuery.lte("read_at", to);
  }

  const { data: reads } = await readsQuery;

  const userIds = Array.from(new Set((reads ?? []).map((r) => r.user_id)));
  const profileMap = new Map<string, string>();

  if (userIds.length > 0) {
    const { data: profiles } = await db
      .from("profiles")
      .select("id, display_name")
      .in("id", userIds);
    for (const p of profiles ?? []) {
      profileMap.set(
        (p as { id: string }).id,
        (p as { display_name: string }).display_name || "Sem nome"
      );
    }
  }

  const announcementMap = new Map(
    announcements.map((a) => [a.id, a])
  );

  const rows: string[] = [];
  for (const r of reads ?? []) {
    const a = announcementMap.get(r.announcement_id);
    const title = (a?.title ?? "").replace(/,/g, " ").replace(/"/g, '""');
    const member = (profileMap.get(r.user_id) ?? "—").replace(/,/g, " ").replace(/"/g, '""');
    const readAt = new Date(r.read_at).toLocaleString("pt-BR");
    rows.push(`"${title}","${member}",${readAt}`);
  }

  const BOM = "\uFEFF";
  const header = "Título,Membro,Lido Em";
  const csv = BOM + header + "\n" + rows.join("\n");

  return new NextResponse(csv, {
    headers: {
      "Content-Type": "text/csv; charset=utf-8",
      "Content-Disposition": 'attachment; filename="announcements-reads.csv"',
    },
  });
}
