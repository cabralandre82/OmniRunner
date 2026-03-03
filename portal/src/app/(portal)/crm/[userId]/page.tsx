import { cookies } from "next/headers";
import { createClient } from "@/lib/supabase/server";
import Link from "next/link";
import { formatDateISO, formatDateTime } from "@/lib/format";
import { AddNoteForm } from "./add-note-form";

export const dynamic = "force-dynamic";

const STATUS_LABELS: Record<string, { label: string; color: string }> = {
  active: { label: "Ativo", color: "bg-green-100 text-green-800" },
  paused: { label: "Pausado", color: "bg-orange-100 text-orange-800" },
  injured: { label: "Lesionado", color: "bg-red-100 text-red-800" },
  inactive: { label: "Inativo", color: "bg-gray-100 text-gray-800" },
  trial: { label: "Teste", color: "bg-blue-100 text-blue-800" },
};

interface AthleteDetail {
  user_id: string;
  display_name: string;
  status: string | null;
  tags: { id: string; name: string }[];
  notes: { id: string; note: string; created_at: string; author_name: string }[];
  attendanceByDay: { date: string; count: number }[];
  alerts: { id: string; alert_type: string; title: string; day: string; severity: string }[];
}

async function getAthleteDetail(
  groupId: string,
  userId: string
): Promise<AthleteDetail | null> {
  const supabase = createClient();

  const { data: profile } = await supabase
    .from("profiles")
    .select("id, display_name")
    .eq("id", userId)
    .single();

  if (!profile) return null;

  const { data: membership } = await supabase
    .from("coaching_members")
    .select("user_id")
    .eq("group_id", groupId)
    .eq("user_id", userId)
    .eq("role", "athlete")
    .maybeSingle();

  if (!membership) return null;

  const thirtyDaysAgo = new Date();
  thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);

  const [statusRes, tagsRes, notesRes, attendanceRes, alertsRes] =
    await Promise.all([
    supabase
      .from("coaching_member_status")
      .select("status")
      .eq("group_id", groupId)
      .eq("user_id", userId)
      .maybeSingle(),
    supabase
      .from("coaching_athlete_tags")
      .select("tag_id, coaching_tags(id, name)")
      .eq("group_id", groupId)
      .eq("athlete_user_id", userId),
    supabase
      .from("coaching_athlete_notes")
      .select("id, note, created_at, profiles!created_by(display_name)")
      .eq("group_id", groupId)
      .eq("athlete_user_id", userId)
      .order("created_at", { ascending: false })
      .limit(50),
    supabase
      .from("coaching_training_attendance")
      .select("session_id, coaching_training_sessions(starts_at)")
      .eq("group_id", groupId)
      .eq("athlete_user_id", userId)
      .eq("status", "present"),
    supabase
      .from("coaching_alerts")
      .select("id, alert_type, title, day, severity")
      .eq("group_id", groupId)
      .eq("user_id", userId)
      .eq("resolved", false)
      .order("day", { ascending: false }),
  ]);

  const tags = (tagsRes.data ?? []).map((t: any) => {
    const ct = Array.isArray(t.coaching_tags) ? t.coaching_tags[0] : t.coaching_tags;
    return { id: ct?.id ?? t.tag_id, name: ct?.name ?? "" };
  });

  const notes = (notesRes.data ?? []).map((n: any) => {
    const profile = Array.isArray(n.profiles) ? n.profiles[0] : n.profiles;
    return {
      id: n.id,
      note: n.note,
      created_at: n.created_at,
      author_name: profile?.display_name ?? "Desconhecido",
    };
  });

  const sessionDates = new Map<string, number>();
  for (const a of attendanceRes.data ?? []) {
    const raw = (a as any).coaching_training_sessions;
    const sess = Array.isArray(raw) ? raw[0] : raw;
    if (sess?.starts_at) {
      const day = sess.starts_at.slice(0, 10);
      sessionDates.set(day, (sessionDates.get(day) ?? 0) + 1);
    }
  }

  const attendanceByDay: { date: string; count: number }[] = [];
  for (let i = 29; i >= 0; i--) {
    const d = new Date();
    d.setDate(d.getDate() - i);
    const dayStr = d.toISOString().slice(0, 10);
    attendanceByDay.push({
      date: dayStr,
      count: sessionDates.get(dayStr) ?? 0,
    });
  }

  const alerts = (alertsRes.data ?? []).map(
    (a: { id: string; alert_type: string; title: string; day: string; severity: string }) => ({
      id: a.id,
      alert_type: a.alert_type,
      title: a.title,
      day: a.day,
      severity: a.severity,
    })
  );

  return {
    user_id: userId,
    display_name: (profile as { display_name: string }).display_name || "Sem nome",
    status: (statusRes.data as { status: string } | null)?.status ?? null,
    tags,
    notes,
    attendanceByDay,
    alerts,
  };
}

export default async function AthleteDetailPage({
  params,
}: {
  params: Promise<{ userId: string }>;
}) {
  const groupId = cookies().get("portal_group_id")?.value;
  const { userId } = await params;
  if (!groupId) return null;

  const athlete = await getAthleteDetail(groupId, userId);

  if (!athlete) {
    return (
      <div className="rounded-xl border border-gray-200 bg-white p-8 text-center shadow-sm">
        <p className="text-sm text-gray-500">Atleta não encontrado.</p>
        <Link href="/crm" className="mt-4 inline-block text-blue-600 hover:underline">
          Voltar ao CRM
        </Link>
      </div>
    );
  }

  const statusInfo = athlete.status
    ? STATUS_LABELS[athlete.status] ?? {
        label: athlete.status,
        color: "bg-gray-100 text-gray-800",
      }
    : null;

  const maxCount = Math.max(1, ...athlete.attendanceByDay.map((d) => d.count));

  return (
    <div className="space-y-6">
      <div className="flex items-center gap-4">
        <Link
          href="/crm"
          className="text-sm text-blue-600 hover:underline"
        >
          ← CRM
        </Link>
      </div>

      <div>
        <h1 className="text-2xl font-bold text-gray-900">{athlete.display_name}</h1>
        <p className="mt-1 text-sm text-gray-500">Detalhes do atleta</p>
      </div>

      <div className="grid gap-4 lg:grid-cols-2">
        <div className="rounded-xl border border-gray-200 bg-white p-4 shadow-sm">
          <h2 className="font-semibold text-gray-900">Status e Tags</h2>
          <div className="mt-2 flex flex-wrap items-center gap-2">
            {statusInfo ? (
              <span
                className={`inline-flex rounded-full px-2.5 py-0.5 text-xs font-medium ${statusInfo.color}`}
              >
                {statusInfo.label}
              </span>
            ) : (
              <span className="text-gray-400">Sem status</span>
            )}
            {athlete.tags.map((t) => (
              <span
                key={t.id}
                className="rounded bg-gray-100 px-2 py-0.5 text-xs text-gray-700"
              >
                {t.name}
              </span>
            ))}
          </div>
        </div>
      </div>

      <div className="grid gap-4 lg:grid-cols-2">
        <div className="rounded-xl border border-gray-200 bg-white p-4 shadow-sm">
          <h2 className="font-semibold text-gray-900">Notas</h2>
          <AddNoteForm groupId={groupId} athleteUserId={userId} />
          <div className="mt-4 space-y-3 max-h-64 overflow-y-auto">
            {athlete.notes.length === 0 ? (
              <p className="text-sm text-gray-500">Nenhuma nota.</p>
            ) : (
              athlete.notes.map((n) => (
                <div
                  key={n.id}
                  className="rounded-lg border border-gray-100 bg-gray-50 p-3"
                >
                  <p className="text-sm text-gray-900">{n.note}</p>
                  <p className="mt-1 text-xs text-gray-500">
                    {n.author_name} · {formatDateTime(n.created_at)}
                  </p>
                </div>
              ))
            )}
          </div>
        </div>

        <div className="rounded-xl border border-gray-200 bg-white p-4 shadow-sm">
          <h2 className="font-semibold text-gray-900">Presença (últimos 30 dias)</h2>
          <div className="mt-4 flex items-end gap-0.5 h-24">
            {athlete.attendanceByDay.map((d) => (
              <div
                key={d.date}
                className="flex-1 min-w-0"
                title={`${d.date}: ${d.count}`}
              >
                <div
                  className="w-full rounded-t bg-blue-500 transition-opacity hover:opacity-80"
                  style={{
                    height: `${(d.count / maxCount) * 100}%`,
                    minHeight: d.count > 0 ? "4px" : "0",
                  }}
                />
              </div>
            ))}
          </div>
          <p className="mt-2 text-xs text-gray-500">
            Total: {athlete.attendanceByDay.reduce((s, d) => s + d.count, 0)} presenças
          </p>
        </div>
      </div>

      {athlete.alerts.length > 0 && (
        <div className="rounded-xl border border-gray-200 bg-white p-4 shadow-sm">
          <h2 className="font-semibold text-gray-900">Alertas Ativos</h2>
          <ul className="mt-2 space-y-2">
            {athlete.alerts.map((a) => (
              <li
                key={a.id}
                className={
                  a.severity === "critical"
                    ? "rounded-lg border border-red-200 bg-red-50 p-3 text-red-800"
                    : a.severity === "warning"
                      ? "rounded-lg border border-orange-200 bg-orange-50 p-3 text-orange-800"
                      : "rounded-lg border border-gray-200 bg-gray-50 p-3"
                }
              >
                <p className="font-medium">{a.title}</p>
                <p className="text-xs text-gray-500">
                  {formatDateISO(a.day)} · {a.alert_type}
                </p>
              </li>
            ))}
          </ul>
        </div>
      )}
    </div>
  );
}
