import { cookies } from "next/headers";
import { createClient } from "@/lib/supabase/server";
import { NoGroupSelected } from "@/components/no-group-selected";
import { LastUpdated } from "@/components/last-updated";
import Link from "next/link";
import { formatDateISO } from "@/lib/format";
import { CrmFilters } from "./crm-filters";

export const dynamic = "force-dynamic";

const STATUS_LABELS: Record<string, { label: string; color: string }> = {
  active: { label: "Ativo", color: "bg-success-soft text-success" },
  paused: { label: "Pausado", color: "bg-orange-100 text-orange-800" },
  injured: { label: "Lesionado", color: "bg-error-soft text-error" },
  inactive: { label: "Inativo", color: "bg-surface-elevated text-content-primary" },
  trial: { label: "Teste", color: "bg-info-soft text-info" },
};

interface CrmAthlete {
  user_id: string;
  display_name: string;
  status: string | null;
  tags: string[];
  attendance_count: number;
  active_alerts: number;
  last_note: string | null;
  last_note_at: string | null;
}

async function getCrmData(
  groupId: string,
  tagId?: string,
  status?: string,
  search?: string
): Promise<{ athletes: CrmAthlete[]; totalCount: number }> {
  const supabase = createClient();

  const [{ data: members }, { count: totalCount }] = await Promise.all([
    supabase
      .from("coaching_members")
      .select("user_id")
      .eq("group_id", groupId)
      .in("role", ["athlete", "atleta"])
      .range(0, 499),
    supabase
      .from("coaching_members")
      .select("user_id", { count: "exact", head: true })
      .eq("group_id", groupId)
      .in("role", ["athlete", "atleta"]),
  ]);

  if (!members || members.length === 0) return { athletes: [], totalCount: totalCount ?? 0 };

  const userIds = members.map((m) => m.user_id);

  const [profilesRes, statusRes, tagsRes, attendanceRes, alertsRes, notesRes] =
    await Promise.all([
      supabase
        .from("profiles")
        .select("id, display_name")
        .in("id", userIds),
      supabase
        .from("coaching_member_status")
        .select("user_id, status")
        .eq("group_id", groupId)
        .in("user_id", userIds),
      supabase
        .from("coaching_athlete_tags")
        .select("athlete_user_id, coaching_tags(name)")
        .eq("group_id", groupId)
        .in("athlete_user_id", userIds),
      supabase
        .from("coaching_training_attendance")
        .select("athlete_user_id")
        .eq("group_id", groupId)
        .eq("status", "present")
        .in("athlete_user_id", userIds),
      supabase
        .from("coaching_alerts")
        .select("user_id")
        .eq("group_id", groupId)
        .in("user_id", userIds)
        .eq("resolved", false),
      supabase
        .from("coaching_athlete_notes")
        .select("athlete_user_id, note, created_at")
        .eq("group_id", groupId)
        .in("athlete_user_id", userIds)
        .order("created_at", { ascending: false }),
    ]);

  const profileMap = new Map(
    (profilesRes.data ?? []).map((p: { id: string; display_name: string }) => [
      p.id,
      p.display_name || "Sem nome",
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
  const lastNoteByUser = new Map<string, { note: string; at: string }>();
  for (const n of notesRes.data ?? []) {
    const uid = (n as { athlete_user_id: string }).athlete_user_id;
    if (!lastNoteByUser.has(uid)) {
      lastNoteByUser.set(uid, {
        note: (n as { note: string }).note,
        at: (n as { created_at: string }).created_at,
      });
    }
  }

  let athletes: CrmAthlete[] = userIds.map((uid) => {
    const displayName = profileMap.get(uid) ?? "Sem nome";
    const st = statusMap.get(uid);
    const tags = tagsByUser.get(uid) ?? [];
    const lastNote = lastNoteByUser.get(uid);
    return {
      user_id: uid,
      display_name: displayName,
      status: st ?? null,
      tags,
      attendance_count: attendanceCount.get(uid) ?? 0,
      active_alerts: alertsByUser.get(uid) ?? 0,
      last_note: lastNote?.note ?? null,
      last_note_at: lastNote?.at ?? null,
    };
  });

  if (tagId) {
    const { data: tagAssignments } = await supabase
      .from("coaching_athlete_tags")
      .select("athlete_user_id")
      .eq("group_id", groupId)
      .eq("tag_id", tagId);
    const withTag = new Set(
      (tagAssignments ?? []).map((a: { athlete_user_id: string }) => a.athlete_user_id)
    );
    athletes = athletes.filter((a) => withTag.has(a.user_id));
  }
  if (status) {
    athletes = athletes.filter((a) => a.status === status);
  }
  if (search && search.trim()) {
    const q = search.trim().toLowerCase();
    athletes = athletes.filter((a) =>
      a.display_name.toLowerCase().includes(q)
    );
  }

  return { athletes, totalCount: totalCount ?? 0 };
}

export default async function CrmPage({
  searchParams,
}: {
  searchParams: Promise<{ tag?: string; status?: string; q?: string }>;
}) {
  const groupId = cookies().get("portal_group_id")?.value;
  if (!groupId) return <NoGroupSelected />;

  const params = await searchParams;

  let athletes: CrmAthlete[] = [];
  let totalCount = 0;
  let fetchError: string | null = null;

  try {
    const result = await getCrmData(
      groupId,
      params.tag,
      params.status,
      params.q
    );
    athletes = result.athletes;
    totalCount = result.totalCount;
  } catch (e) {
    fetchError = String(e);
  }

  const activeCount = athletes.filter((a) => a.status === "active").length;
  const atRiskCount = athletes.filter((a) => a.active_alerts > 0).length;

  const exportHref = `/api/export/crm?${new URLSearchParams({
    ...(params.tag && { tag: params.tag }),
    ...(params.status && { status: params.status }),
    ...(params.q && { q: params.q }),
  }).toString()}`;

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-content-primary">CRM de Atletas</h1>
          <p className="mt-1 text-sm text-content-secondary">
            Status, tags, treinos e alertas dos atletas
          </p>
        </div>
        <Link
          href="/crm/at-risk"
          className="rounded-lg border border-orange-300 bg-orange-50 px-3 py-1.5 text-sm font-medium text-orange-700 hover:bg-orange-100"
        >
          Atletas em Risco
        </Link>
      </div>

      {fetchError && (
        <div className="rounded-lg border border-error/30 bg-error-soft p-6 text-center">
          <p className="text-error">Erro ao carregar dados. Tente recarregar a página.</p>
        </div>
      )}

      <CrmFilters
        groupId={groupId}
        tagId={params.tag}
        status={params.status}
        search={params.q}
      />

      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <KpiCard label="Total atletas" value={athletes.length} />
        <KpiCard label="Ativos" value={activeCount} color="text-success" />
        <KpiCard label="Em risco" value={atRiskCount} color="text-orange-700" />
      </div>

      <div className="flex items-center justify-between">
        {totalCount > athletes.length && (
          <p className="text-sm text-content-secondary">
            Mostrando {athletes.length} de {totalCount} atletas
          </p>
        )}
        <a
          href={exportHref}
          className="ml-auto rounded-lg border border-border bg-surface px-3 py-1.5 text-xs font-medium text-content-secondary shadow-sm hover:bg-surface-elevated"
        >
          Exportar CSV
        </a>
      </div>

      <div className="overflow-hidden rounded-xl border border-border bg-surface shadow-sm">
        <div className="overflow-x-auto">
          <table className="min-w-full divide-y divide-border text-sm">
            <thead className="bg-bg-secondary">
              <tr>
                <th className="px-4 py-3 text-left font-medium text-content-secondary">
                  Nome
                </th>
                <th className="px-4 py-3 text-left font-medium text-content-secondary">
                  Status
                </th>
                <th className="px-4 py-3 text-left font-medium text-content-secondary">
                  Tags
                </th>
                <th className="px-4 py-3 text-center font-medium text-content-secondary">
                  Treinos
                </th>
                <th className="px-4 py-3 text-center font-medium text-content-secondary">
                  Alertas
                </th>
                <th className="px-4 py-3 text-left font-medium text-content-secondary">
                  Última Nota
                </th>
              </tr>
            </thead>
            <tbody className="divide-y divide-border-subtle">
              {athletes.map((a) => {
                const statusInfo = a.status
                  ? STATUS_LABELS[a.status] ?? { label: a.status, color: "bg-surface-elevated text-content-primary" }
                  : null;
                return (
                  <tr key={a.user_id} className="hover:bg-surface-elevated">
                    <td className="whitespace-nowrap px-4 py-3">
                      <Link
                        href={`/crm/${a.user_id}`}
                        className="font-medium text-brand hover:text-brand hover:underline"
                      >
                        {a.display_name}
                      </Link>
                    </td>
                    <td className="whitespace-nowrap px-4 py-3">
                      {statusInfo ? (
                        <span
                          className={`inline-flex rounded-full px-2.5 py-0.5 text-xs font-medium ${statusInfo.color}`}
                        >
                          {statusInfo.label}
                        </span>
                      ) : (
                        <span className="text-content-muted">—</span>
                      )}
                    </td>
                    <td className="px-4 py-3">
                      <div className="flex flex-wrap gap-1">
                        {a.tags.length > 0
                          ? a.tags.slice(0, 3).map((t) => (
                              <span
                                key={t}
                                className="inline-flex rounded bg-surface-elevated px-1.5 py-0.5 text-xs text-content-secondary"
                              >
                                {t}
                              </span>
                            ))
                          : "—"}
                      </div>
                    </td>
                    <td className="whitespace-nowrap px-4 py-3 text-center text-content-secondary">
                      {a.attendance_count}
                    </td>
                    <td className="whitespace-nowrap px-4 py-3 text-center">
                      {a.active_alerts > 0 ? (
                        <span className="font-medium text-orange-600">
                          {a.active_alerts}
                        </span>
                      ) : (
                        <span className="text-content-muted">0</span>
                      )}
                    </td>
                    <td className="max-w-[200px] truncate px-4 py-3 text-content-secondary">
                      {a.last_note ? (
                        <span title={a.last_note}>
                          {a.last_note.slice(0, 50)}
                          {a.last_note.length > 50 ? "…" : ""}
                        </span>
                      ) : (
                        "—"
                      )}
                      {a.last_note_at && (
                        <span className="ml-1 text-xs text-content-muted">
                          ({formatDateISO(a.last_note_at)})
                        </span>
                      )}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </div>

      {athletes.length === 0 && (
        <div className="rounded-xl border border-border bg-surface p-8 text-center shadow-sm">
          <p className="text-sm text-content-secondary">Nenhum atleta encontrado.</p>
        </div>
      )}

      <LastUpdated />
    </div>
  );
}

function KpiCard({
  label,
  value,
  color = "text-content-primary",
}: {
  label: string;
  value: number | string;
  color?: string;
}) {
  return (
    <div className="rounded-xl border border-border bg-surface p-4 shadow-sm">
      <p className="text-xs font-medium uppercase tracking-wide text-content-secondary">
        {label}
      </p>
      <p className={`mt-1 text-xl font-bold ${color}`}>{value}</p>
    </div>
  );
}
