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
    !["admin_master", "coach", "assistant"].includes(
      (callerMembership as { role: string }).role
    )
  ) {
    return NextResponse.json({ error: "Forbidden" }, { status: 403 });
  }

  const { searchParams } = new URL(request.url);
  const tagId = searchParams.get("tag");
  const statusFilter = searchParams.get("status");
  const search = searchParams.get("q");

  const { data: members } = await db
    .from("coaching_members")
    .select("user_id")
    .eq("group_id", groupId)
    .eq("role", "athlete");

  if (!members || members.length === 0) {
    const BOM = "\uFEFF";
    const header = "Nome,Status,Tags,Total Presenças,Alertas Ativas,Última Nota";
    return new NextResponse(BOM + header + "\n", {
      headers: {
        "Content-Type": "text/csv; charset=utf-8",
        "Content-Disposition": 'attachment; filename="crm.csv"',
      },
    });
  }

  const userIds = members.map((m: { user_id: string }) => m.user_id);

  const [
    profilesRes,
    statusRes,
    tagsRes,
    attendanceRes,
    alertsRes,
    notesRes,
  ] = await Promise.all([
    db.from("profiles").select("id, display_name").in("id", userIds),
    db
      .from("coaching_member_status")
      .select("user_id, status")
      .eq("group_id", groupId)
      .in("user_id", userIds),
    db
      .from("coaching_athlete_tags")
      .select("athlete_user_id, coaching_tags(name)")
      .eq("group_id", groupId)
      .in("athlete_user_id", userIds),
    db
      .from("coaching_training_attendance")
      .select("athlete_user_id")
      .eq("group_id", groupId)
      .eq("status", "present")
      .in("athlete_user_id", userIds),
    db
      .from("coaching_alerts")
      .select("user_id")
      .eq("group_id", groupId)
      .in("user_id", userIds)
      .eq("resolved", false),
    db
      .from("coaching_athlete_notes")
      .select("athlete_user_id, note, created_at")
      .eq("group_id", groupId)
      .in("athlete_user_id", userIds)
      .order("created_at", { ascending: false }),
  ]);

  const profileMap = new Map(
    (profilesRes.data ?? []).map((p: { id: string; display_name: string }) => [
      p.id,
      (p.display_name || "Sem nome").replace(/[,;"\n]/g, " "),
    ])
  );
  const statusMap = new Map(
    (statusRes.data ?? []).map((s: { user_id: string; status: string }) => [
      s.user_id,
      s.status,
    ])
  );
  const tagsByUser = new Map<string, string[]>();
  for (const t of tagsRes.data ?? []) {
    const uid = (t as any).athlete_user_id;
    const rawTag = (t as any).coaching_tags;
    const tag = Array.isArray(rawTag) ? rawTag[0] : rawTag;
    if (tag?.name) {
      const arr = tagsByUser.get(uid) ?? [];
      arr.push(tag.name);
      tagsByUser.set(uid, arr);
    }
  }
  const attendanceCount = new Map<string, number>();
  for (const a of attendanceRes.data ?? []) {
    const uid = (a as { athlete_user_id: string }).athlete_user_id;
    attendanceCount.set(uid, (attendanceCount.get(uid) ?? 0) + 1);
  }
  const alertsByUser = new Map<string, number>();
  for (const a of alertsRes.data ?? []) {
    const uid = (a as { user_id: string }).user_id;
    alertsByUser.set(uid, (alertsByUser.get(uid) ?? 0) + 1);
  }
  const lastNoteByUser = new Map<string, string>();
  for (const n of notesRes.data ?? []) {
    const uid = (n as { athlete_user_id: string }).athlete_user_id;
    if (!lastNoteByUser.has(uid)) {
      lastNoteByUser.set(
        uid,
        ((n as { note: string }).note || "").replace(/[,;"\n]/g, " ")
      );
    }
  }

  let athletes = userIds.map((uid) => ({
    uid,
    name: profileMap.get(uid) ?? "Sem nome",
    status: statusMap.get(uid) ?? "",
    tags: (tagsByUser.get(uid) ?? []).join("; "),
    attendance: attendanceCount.get(uid) ?? 0,
    alerts: alertsByUser.get(uid) ?? 0,
    lastNote: lastNoteByUser.get(uid) ?? "",
  }));

  if (tagId) {
    const { data: tagAssignments } = await db
      .from("coaching_athlete_tags")
      .select("athlete_user_id")
      .eq("group_id", groupId)
      .eq("tag_id", tagId);
    const withTag = new Set(
      (tagAssignments ?? []).map((a: { athlete_user_id: string }) => a.athlete_user_id)
    );
    athletes = athletes.filter((a) => withTag.has(a.uid));
  }
  if (statusFilter) {
    athletes = athletes.filter((a) => a.status === statusFilter);
  }
  if (search?.trim()) {
    const q = search.trim().toLowerCase();
    athletes = athletes.filter((a) => a.name.toLowerCase().includes(q));
  }

  const STATUS_LABELS: Record<string, string> = {
    active: "Ativo",
    paused: "Pausado",
    injured: "Lesionado",
    inactive: "Inativo",
    trial: "Teste",
  };

  const escape = (s: string) =>
    s.includes(",") || s.includes('"') || s.includes("\n")
      ? `"${s.replace(/"/g, '""')}"`
      : s;

  const rows = athletes.map(
    (a) =>
      `${escape(a.name)},${escape(STATUS_LABELS[a.status] ?? a.status)},${escape(a.tags)},${a.attendance},${a.alerts},${escape(a.lastNote)}`
  );

  const BOM = "\uFEFF";
  const header = "Nome,Status,Tags,Total Presenças,Alertas Ativas,Última Nota";
  const csv = BOM + header + "\n" + rows.join("\n");

  return new NextResponse(csv, {
    headers: {
      "Content-Type": "text/csv; charset=utf-8",
      "Content-Disposition": 'attachment; filename="crm.csv"',
    },
  });
}
