import { cookies } from "next/headers";
import { createServiceClient } from "@/lib/supabase/service";
import Link from "next/link";
import { formatDateISO, formatPercent } from "@/lib/format";

export const dynamic = "force-dynamic";

const PAGE_SIZE = 10;

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

async function getCommunicationsData(
  groupId: string,
  page: number
): Promise<{
  announcements: AnnouncementRow[];
  totalAnnouncements: number;
  avgReadRate: number;
  pinnedCount: number;
  thisWeekCount: number;
}> {
  const db = createServiceClient();

  const { count: totalAnnouncements } = await db
    .from("coaching_announcements")
    .select("id", { count: "exact", head: true })
    .eq("group_id", groupId);

  const { count: totalMembers } = await db
    .from("coaching_members")
    .select("id", { count: "exact", head: true })
    .eq("group_id", groupId);

  const memberCount = totalMembers ?? 0;

  const from = (page - 1) * PAGE_SIZE;

  const { data: announcements } = await db
    .from("coaching_announcements")
    .select("id, title, created_by, created_at, pinned")
    .eq("group_id", groupId)
    .order("pinned", { ascending: false })
    .order("created_at", { ascending: false })
    .range(from, from + PAGE_SIZE - 1);

  if (!announcements || announcements.length === 0) {
    const weekAgo = new Date();
    weekAgo.setDate(weekAgo.getDate() - 7);
    const { count: pinnedCount } = await db
      .from("coaching_announcements")
      .select("id", { count: "exact", head: true })
      .eq("group_id", groupId)
      .eq("pinned", true);
    const { count: thisWeekCount } = await db
      .from("coaching_announcements")
      .select("id", { count: "exact", head: true })
      .eq("group_id", groupId)
      .gte("created_at", weekAgo.toISOString());
    return {
      announcements: [],
      totalAnnouncements: totalAnnouncements ?? 0,
      avgReadRate: 0,
      pinnedCount: pinnedCount ?? 0,
      thisWeekCount: thisWeekCount ?? 0,
    };
  }

  const ids = announcements.map((a) => a.id);
  const { data: reads } = await db
    .from("coaching_announcement_reads")
    .select("announcement_id")
    .in("announcement_id", ids);

  const readCountByAnnouncement = new Map<string, number>();
  for (const r of reads ?? []) {
    const aid = (r as { announcement_id: string }).announcement_id;
    readCountByAnnouncement.set(aid, (readCountByAnnouncement.get(aid) ?? 0) + 1);
  }

  const createdByIds = Array.from(new Set(announcements.map((a) => a.created_by)));
  const { data: profiles } = await db
    .from("profiles")
    .select("id, display_name")
    .in("id", createdByIds);

  const profileMap = new Map(
    (profiles ?? []).map((p: { id: string; display_name: string }) => [
      p.id,
      p.display_name || "Sem nome",
    ])
  );

  const weekAgo = new Date();
  weekAgo.setDate(weekAgo.getDate() - 7);

  let sumRate = 0;
  const rows: AnnouncementRow[] = announcements.map((a) => {
    const readCount = readCountByAnnouncement.get(a.id) ?? 0;
    const rate = memberCount > 0 ? (readCount / memberCount) * 100 : 0;
    sumRate += rate;
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

  const { count: pinnedCount } = await db
    .from("coaching_announcements")
    .select("id", { count: "exact", head: true })
    .eq("group_id", groupId)
    .eq("pinned", true);

  const { count: thisWeekCount } = await db
    .from("coaching_announcements")
    .select("id", { count: "exact", head: true })
    .eq("group_id", groupId)
    .gte("created_at", weekAgo.toISOString());

  return {
    announcements: rows,
    totalAnnouncements: totalAnnouncements ?? 0,
    avgReadRate,
    pinnedCount: pinnedCount ?? 0,
    thisWeekCount: thisWeekCount ?? 0,
  };
}

export default async function CommunicationsPage({
  searchParams,
}: {
  searchParams: Promise<{ page?: string }>;
}) {
  const groupId = cookies().get("portal_group_id")?.value;
  if (!groupId) return null;

  const params = await searchParams;
  const page = Math.max(1, parseInt(params.page ?? "1", 10));

  const {
    announcements,
    totalAnnouncements,
    avgReadRate,
    pinnedCount,
    thisWeekCount,
  } = await getCommunicationsData(groupId, page);

  const totalPages = Math.ceil(totalAnnouncements / PAGE_SIZE) || 1;
  const readRate = (readCount: number, total: number) =>
    total > 0 ? (readCount / total) * 100 : 0;

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-gray-900">Comunicação</h1>
        <p className="mt-1 text-sm text-gray-500">
          Visão geral dos avisos e taxas de leitura
        </p>
      </div>

      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <KpiCard
          label="Total avisos publicados"
          value={totalAnnouncements}
        />
        <KpiCard
          label="Taxa média de leitura (%)"
          value={formatPercent(avgReadRate)}
          color="text-blue-700"
        />
        <KpiCard
          label="Avisos fixados"
          value={pinnedCount}
          color="text-amber-700"
        />
        <KpiCard
          label="Avisos últimos 7 dias"
          value={thisWeekCount}
          color="text-green-700"
        />
      </div>

      <div className="rounded-xl border border-gray-200 bg-white shadow-sm">
        <div className="flex items-center justify-between border-b border-gray-200 px-4 py-3">
          <h2 className="text-sm font-semibold text-gray-900">
            Avisos recentes
          </h2>
          <Link
            href="/announcements"
            className="rounded-lg bg-gray-900 px-3 py-1.5 text-sm font-medium text-white hover:bg-gray-800"
          >
            Ver todos
          </Link>
        </div>
        <div className="overflow-x-auto">
          <table className="min-w-full divide-y divide-gray-200 text-sm">
            <thead className="bg-gray-50">
              <tr>
                <th className="px-4 py-3 text-left font-medium text-gray-500">
                  Título
                </th>
                <th className="px-4 py-3 text-left font-medium text-gray-500">
                  Autor
                </th>
                <th className="px-4 py-3 text-left font-medium text-gray-500">
                  Data
                </th>
                <th className="px-4 py-3 text-center font-medium text-gray-500">
                  Fixado
                </th>
                <th className="px-4 py-3 text-left font-medium text-gray-500">
                  Leituras
                </th>
                <th className="px-4 py-3 text-left font-medium text-gray-500">
                  Taxa (%)
                </th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {announcements.map((a) => {
                const rate = readRate(a.read_count, a.total_members);
                return (
                  <tr key={a.id} className="hover:bg-gray-50">
                    <td className="whitespace-nowrap px-4 py-3">
                      <Link
                        href={`/announcements/${a.id}`}
                        className="font-medium text-blue-600 hover:text-blue-800 hover:underline"
                      >
                        {a.title}
                      </Link>
                    </td>
                    <td className="whitespace-nowrap px-4 py-3 text-gray-600">
                      {a.display_name ?? "—"}
                    </td>
                    <td className="whitespace-nowrap px-4 py-3 text-gray-600">
                      {formatDateISO(a.created_at)}
                    </td>
                    <td className="whitespace-nowrap px-4 py-3 text-center">
                      {a.pinned ? (
                        <span className="inline-flex rounded-full bg-amber-100 px-2.5 py-0.5 text-xs font-medium text-amber-800">
                          Fixado
                        </span>
                      ) : (
                        "—"
                      )}
                    </td>
                    <td className="whitespace-nowrap px-4 py-3 text-gray-600">
                      {a.read_count}
                    </td>
                    <td className="whitespace-nowrap px-4 py-3 text-gray-600">
                      {formatPercent(rate)}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
        {announcements.length === 0 && (
          <div className="px-4 py-8 text-center text-sm text-gray-500">
            Nenhum aviso ainda.
          </div>
        )}
        {totalPages > 1 && (
          <div className="flex items-center justify-between border-t border-gray-200 px-4 py-3">
            <p className="text-xs text-gray-500">
              Página {page} de {totalPages}
            </p>
            <div className="flex gap-2">
              {page > 1 && (
                <Link
                  href={`/communications?page=${page - 1}`}
                  className="rounded-lg border border-gray-300 bg-white px-3 py-1.5 text-sm font-medium text-gray-700 hover:bg-gray-50"
                >
                  Anterior
                </Link>
              )}
              {page < totalPages && (
                <Link
                  href={`/communications?page=${page + 1}`}
                  className="rounded-lg border border-gray-300 bg-white px-3 py-1.5 text-sm font-medium text-gray-700 hover:bg-gray-50"
                >
                  Próxima
                </Link>
              )}
            </div>
          </div>
        )}
      </div>
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
