import { cookies } from "next/headers";
import { createClient } from "@/lib/supabase/server";
import Link from "next/link";
import { formatDateISO, formatPercent } from "@/lib/format";
import { AnnouncementsClient } from "./announcements-client";

export const dynamic = "force-dynamic";

interface AnnouncementRow {
  id: string;
  title: string;
  created_by: string;
  created_at: string;
  pinned: boolean;
  display_name: string | null;
  read_count: number;
  total_members: number;
}

async function getAnnouncementsData(groupId: string): Promise<{
  announcements: AnnouncementRow[];
  total: number;
  avgReadRate: number;
  thisWeek: number;
}> {
  const supabase = createClient();

  const { data: announcements } = await supabase
    .from("coaching_announcements")
    .select("id, title, created_by, created_at, pinned")
    .eq("group_id", groupId)
    .order("pinned", { ascending: false })
    .order("created_at", { ascending: false })
    .range(0, 49);

  if (!announcements || announcements.length === 0) {
    return { announcements: [], total: 0, avgReadRate: 0, thisWeek: 0 };
  }

  const { count: totalMembers } = await supabase
    .from("coaching_members")
    .select("id", { count: "exact", head: true })
    .eq("group_id", groupId);

  const memberCount = totalMembers ?? 0;

  const ids = announcements.map((a) => a.id);
  const { data: reads } = await supabase
    .from("coaching_announcement_reads")
    .select("announcement_id")
    .in("announcement_id", ids);

  const readCountByAnnouncement = new Map<string, number>();
  for (const r of reads ?? []) {
    const aid = (r as { announcement_id: string }).announcement_id;
    readCountByAnnouncement.set(aid, (readCountByAnnouncement.get(aid) ?? 0) + 1);
  }

  const createdByIds = Array.from(new Set(announcements.map((a) => a.created_by)));
  const { data: profiles } = await supabase
    .from("profiles")
    .select("id, display_name")
    .in("id", createdByIds);

  const profileMap = new Map(
    (profiles ?? []).map((p: { id: string; display_name: string }) => [
      p.id,
      p.display_name || "Sem nome",
    ])
  );

  const now = new Date();
  const weekAgo = new Date(now);
  weekAgo.setDate(weekAgo.getDate() - 7);

  let sumRate = 0;
  let thisWeekCount = 0;

  const rows: AnnouncementRow[] = announcements.map((a) => {
    const readCount = readCountByAnnouncement.get(a.id) ?? 0;
    const rate = memberCount > 0 ? (readCount / memberCount) * 100 : 0;
    sumRate += rate;
    const created = new Date(a.created_at);
    if (created >= weekAgo) thisWeekCount++;
    return {
      id: a.id,
      title: a.title,
      created_by: a.created_by,
      created_at: a.created_at,
      pinned: a.pinned ?? false,
      display_name: profileMap.get(a.created_by) ?? null,
      read_count: readCount,
      total_members: memberCount,
    };
  });

  const avgReadRate = rows.length > 0 ? sumRate / rows.length : 0;

  return {
    announcements: rows,
    total: rows.length,
    avgReadRate,
    thisWeek: thisWeekCount,
  };
}

export default async function AnnouncementsPage() {
  const groupId = cookies().get("portal_group_id")?.value;
  const role = cookies().get("portal_role")?.value;
  if (!groupId) return null;

  let announcements: AnnouncementRow[] = [];
  let total = 0;
  let avgReadRate = 0;
  let thisWeek = 0;
  let fetchError: string | null = null;

  try {
    const result = await getAnnouncementsData(groupId);
    announcements = result.announcements;
    total = result.total;
    avgReadRate = result.avgReadRate;
    thisWeek = result.thisWeek;
  } catch (e) {
    fetchError = String(e);
  }

  const canEdit = role === "admin_master" || role === "coach";

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Mural de Avisos</h1>
          <p className="mt-1 text-sm text-gray-500">
            Avisos do grupo e taxa de leitura
          </p>
        </div>
      </div>

      {fetchError && (
        <div className="rounded-lg border border-red-200 bg-red-50 p-6 text-center">
          <p className="text-red-600">Erro ao carregar dados. Tente recarregar a página.</p>
        </div>
      )}

      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <KpiCard label="Total de avisos" value={total} />
        <KpiCard
          label="Taxa média de leitura"
          value={formatPercent(avgReadRate)}
          color="text-blue-700"
        />
        <KpiCard
          label="Avisos esta semana"
          value={thisWeek}
          color="text-green-700"
        />
      </div>

      <AnnouncementsClient
        groupId={groupId}
        canEdit={canEdit}
        announcements={announcements}
      />

      {!fetchError && announcements.length === 0 && (
        <div className="rounded-xl border border-gray-200 bg-white p-8 text-center shadow-sm">
          <p className="text-sm text-gray-500">Nenhum aviso publicado ainda.</p>
        </div>
      )}
    </div>
  );
}

function KpiCard({
  label,
  value,
  color = "text-gray-900",
}: {
  label: string;
  value: number | string;
  color?: string;
}) {
  return (
    <div className="rounded-xl border border-gray-200 bg-white p-4 shadow-sm">
      <p className="text-xs font-medium uppercase tracking-wide text-gray-500">
        {label}
      </p>
      <p className={`mt-1 text-xl font-bold ${color}`}>{value}</p>
    </div>
  );
}
