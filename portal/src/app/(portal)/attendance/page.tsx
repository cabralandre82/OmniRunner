import { Suspense } from "react";
import { cookies } from "next/headers";
import { createClient } from "@/lib/supabase/server";
import Link from "next/link";
import { formatDateISO, formatPercent } from "@/lib/format";
import { AttendanceFilters } from "./attendance-filters";

export const dynamic = "force-dynamic";

async function getAttendanceData(groupId: string, from?: string, to?: string, sessionId?: string) {
  const supabase = createClient();

  const now = new Date();
  const defaultFrom = new Date(now);
  defaultFrom.setDate(defaultFrom.getDate() - 30);
  const fromDate = from ? new Date(from) : defaultFrom;
  const toDate = to ? new Date(to) : now;

  let sessionsQuery = supabase
    .from("coaching_training_sessions")
    .select("id, title, starts_at, location_name, status")
    .eq("group_id", groupId)
    .gte("starts_at", fromDate.toISOString())
    .lte("starts_at", toDate.toISOString())
    .order("starts_at", { ascending: false });

  if (sessionId) {
    sessionsQuery = sessionsQuery.eq("id", sessionId);
  }

  const { data: sessions } = await sessionsQuery;

  if (!sessions || sessions.length === 0) {
    return {
      sessions: [],
      attendanceBySession: new Map<string, number>(),
      totalCheckIns: 0,
      athleteCount: 0,
    };
  }

  const sessionIds = sessions.map((s) => s.id);

  const { data: attendance } = await supabase
    .from("coaching_training_attendance")
    .select("session_id")
    .in("session_id", sessionIds)
    .eq("group_id", groupId)
    .eq("status", "present");

  const attendanceBySession = new Map<string, number>();
  let totalCheckIns = 0;
  for (const a of attendance ?? []) {
    const count = attendanceBySession.get(a.session_id) ?? 0;
    attendanceBySession.set(a.session_id, count + 1);
    totalCheckIns++;
  }

  const { count: athleteCount } = await supabase
    .from("coaching_members")
    .select("id", { count: "exact", head: true })
    .eq("group_id", groupId)
    .eq("role", "athlete");

  return {
    sessions,
    attendanceBySession,
    totalCheckIns,
    athleteCount: athleteCount ?? 0,
  };
}

export default async function AttendancePage({
  searchParams,
}: {
  searchParams: Promise<{ from?: string; to?: string; session_id?: string }>;
}) {
  const groupId = cookies().get("portal_group_id")?.value;
  if (!groupId) return null;

  const params = await searchParams;

  let sessions: Awaited<ReturnType<typeof getAttendanceData>>["sessions"] = [];
  let attendanceBySession = new Map<string, number>();
  let totalCheckIns = 0;
  let athleteCount = 0;
  let allSessionsForFilter: typeof sessions = [];
  let fetchError: string | null = null;

  try {
    const result = await getAttendanceData(
      groupId,
      params.from,
      params.to,
      params.session_id,
    );
    sessions = result.sessions;
    attendanceBySession = result.attendanceBySession;
    totalCheckIns = result.totalCheckIns;
    athleteCount = result.athleteCount;

    const filterResult = await getAttendanceData(groupId, params.from, params.to);
    allSessionsForFilter = filterResult.sessions;
  } catch (e) {
    fetchError = String(e);
  }

  const totalSessions = sessions.length;
  const validSessions = sessions.filter((s) => s.status !== "cancelled");
  const totalPossible = validSessions.length * Math.max(athleteCount, 1);
  const avgAttendancePct = totalPossible > 0 ? (totalCheckIns / totalPossible) * 100 : 0;

  const exportParams = new URLSearchParams();
  if (params.from) exportParams.set("from", params.from);
  if (params.to) exportParams.set("to", params.to);
  if (params.session_id) exportParams.set("session_id", params.session_id);
  const exportQuery = exportParams.toString();
  const exportHref = `/api/export/attendance${exportQuery ? `?${exportQuery}` : ""}`;

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-gray-900">Relatório de Presença</h1>
        <p className="mt-1 text-sm text-gray-500">
          Treinos e check-ins dos últimos 30 dias
        </p>
      </div>

      {fetchError && (
        <div className="rounded-lg border border-red-200 bg-red-50 p-6 text-center">
          <p className="text-red-600">Erro ao carregar dados. Tente recarregar a página.</p>
        </div>
      )}

      <Suspense fallback={<div className="h-24 animate-pulse rounded-lg border border-gray-200 bg-gray-50" />}>
        <AttendanceFilters from={params.from} to={params.to} sessionId={params.session_id} sessions={allSessionsForFilter} />
      </Suspense>

      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <KpiCard label="Treinos (período)" value={totalSessions} />
        <KpiCard label="Presença média" value={formatPercent(avgAttendancePct)} color="text-blue-700" />
        <KpiCard label="Total check-ins" value={totalCheckIns} color="text-green-700" />
        <KpiCard label="Atletas no grupo" value={athleteCount} />
      </div>

      <div className="flex justify-end">
        <a
          href={exportHref}
          className="rounded-lg border border-gray-300 bg-white px-3 py-1.5 text-xs font-medium text-gray-700 shadow-sm hover:bg-gray-50"
        >
          Exportar CSV
        </a>
      </div>

      <div className="overflow-hidden rounded-xl border border-gray-200 bg-white shadow-sm">
        <div className="overflow-x-auto">
          <table className="min-w-full divide-y divide-gray-200 text-sm">
            <thead className="bg-gray-50">
              <tr>
                <th className="px-4 py-3 text-left font-medium text-gray-500">Treino</th>
                <th className="px-4 py-3 text-left font-medium text-gray-500">Data</th>
                <th className="px-4 py-3 text-center font-medium text-gray-500">Presentes</th>
                <th className="px-4 py-3 text-center font-medium text-gray-500">Total Atletas</th>
                <th className="px-4 py-3 text-center font-medium text-gray-500">%</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {sessions.map((session) => {
                const presentes = attendanceBySession.get(session.id) ?? 0;
                const total = athleteCount || 1;
                const pct = (presentes / total) * 100;
                return (
                  <tr key={session.id}>
                    <td className="whitespace-nowrap px-4 py-3">
                      <Link
                        href={`/attendance/${session.id}`}
                        className="font-medium text-blue-600 hover:text-blue-800 hover:underline"
                      >
                        {session.title}
                      </Link>
                    </td>
                    <td className="whitespace-nowrap px-4 py-3 text-gray-600">
                      {formatDateISO(session.starts_at)}
                    </td>
                    <td className="whitespace-nowrap px-4 py-3 text-center font-medium text-gray-900">
                      {presentes}
                    </td>
                    <td className="whitespace-nowrap px-4 py-3 text-center text-gray-600">
                      {athleteCount}
                    </td>
                    <td className="whitespace-nowrap px-4 py-3 text-center font-medium text-gray-900">
                      {formatPercent(pct)}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </div>

      {sessions.length === 0 && (
        <div className="rounded-xl border border-gray-200 bg-white p-8 text-center shadow-sm">
          <p className="text-sm text-gray-500">
            Nenhum treino encontrado no período.
          </p>
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
