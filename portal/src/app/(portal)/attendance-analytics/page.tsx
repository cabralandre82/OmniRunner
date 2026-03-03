import { Suspense } from "react";
import { cookies } from "next/headers";
import { createServiceClient } from "@/lib/supabase/service";
import Link from "next/link";
import { formatDateISO, formatPercent } from "@/lib/format";
import { AttendanceAnalyticsFilters } from "./attendance-analytics-filters";

export const dynamic = "force-dynamic";

type PeriodDays = 7 | 14 | 30;

function parsePeriod(s: string | null): PeriodDays {
  const n = parseInt(s ?? "30", 10);
  if (n === 7 || n === 14) return n;
  return 30;
}

function getDateRange(period: string | null, from?: string, to?: string) {
  const now = new Date();
  if (period === "custom" && from && to) {
    return {
      from: new Date(from),
      to: new Date(to),
    };
  }
  const days = parsePeriod(period);
  const toDate = new Date(now);
  const fromDate = new Date(now);
  fromDate.setDate(fromDate.getDate() - days);
  return { from: fromDate, to: toDate };
}

async function getAttendanceAnalytics(
  groupId: string,
  from: Date,
  to: Date,
) {
  const db = createServiceClient();

  const fromIso = from.toISOString();
  const toIso = to.toISOString();

  const [sessionsRes, membersRes] = await Promise.all([
    db
      .from("coaching_training_sessions")
      .select("id, title, starts_at, status")
      .eq("group_id", groupId)
      .gte("starts_at", fromIso)
      .lte("starts_at", toIso)
      .order("starts_at", { ascending: true }),
    db
      .from("coaching_members")
      .select("user_id")
      .eq("group_id", groupId)
      .eq("role", "athlete"),
  ]);

  const sessions = (sessionsRes.data ?? []).filter(
    (s: { status: string }) => s.status !== "cancelled",
  ) as { id: string; title: string; starts_at: string; status: string }[];

  const sessionIds = sessions.map((s) => s.id);
  const attendanceRes =
    sessionIds.length > 0
      ? await db
          .from("coaching_training_attendance")
          .select("session_id, athlete_user_id")
          .eq("group_id", groupId)
          .in("session_id", sessionIds)
          .eq("status", "present")
      : { data: [] };
  const attendance = attendanceRes.data ?? [];

  const athleteIds = new Set(
    (membersRes.data ?? []).map((m: { user_id: string }) => m.user_id),
  );
  const totalAthletes = athleteIds.size;

  const attendanceBySession = new Map<string, Set<string>>();
  const attendanceByAthlete = new Map<string, number>();

  for (const a of attendance as { session_id: string; athlete_user_id: string }[]) {
    if (!attendanceBySession.has(a.session_id)) {
      attendanceBySession.set(a.session_id, new Set());
    }
    attendanceBySession.get(a.session_id)!.add(a.athlete_user_id);

    const count = attendanceByAthlete.get(a.athlete_user_id) ?? 0;
    attendanceByAthlete.set(a.athlete_user_id, count + 1);
  }

  let totalCheckIns = 0;
  const sessionsWithCounts = sessions.map((session) => {
    const presentes = attendanceBySession.get(session.id)?.size ?? 0;
    totalCheckIns += presentes;
    const total = totalAthletes || 1;
    const rate = (presentes / total) * 100;
    return {
      ...session,
      presentes,
      totalAthletes: total,
      rate,
    };
  });

  const lowAttendance = [...sessionsWithCounts]
    .filter((s) => s.rate < 50)
    .sort((a, b) => a.rate - b.rate);

  const totalPossible = sessions.length * Math.max(totalAthletes, 1);
  const avgRate = totalPossible > 0 ? (totalCheckIns / totalPossible) * 100 : 0;
  const lowCount = sessionsWithCounts.filter((s) => s.rate < 50).length;

  const athleteStats = Array.from(athleteIds).map((userId) => {
    const count = attendanceByAthlete.get(userId) ?? 0;
    const rate = sessions.length > 0 ? (count / sessions.length) * 100 : 0;
    return { userId, count, rate };
  });

  const userIds = athleteStats.map((a) => a.userId);
  const { data: profiles } =
    userIds.length > 0
      ? await db.from("profiles").select("id, display_name").in("id", userIds)
      : { data: [] };
  const profileMap = new Map(
    (profiles ?? []).map((p: { id: string; display_name: string }) => [
      p.id,
      p.display_name || "Sem nome",
    ]),
  );

  const athleteList = athleteStats
    .map((a) => ({
      ...a,
      display_name: profileMap.get(a.userId) ?? "—",
    }))
    .sort((a, b) => a.rate - b.rate);

  return {
    sessions,
    totalCheckIns,
    totalAthletes,
    avgRate,
    lowAttendance,
    lowCount,
    athleteList,
  };
}

export default async function AttendanceAnalyticsPage({
  searchParams,
}: {
  searchParams: Promise<{ period?: string; from?: string; to?: string }>;
}) {
  const groupId = cookies().get("portal_group_id")?.value;
  if (!groupId) return null;

  const params = await searchParams;
  const { from, to } = getDateRange(
    params.period ?? null,
    params.from,
    params.to,
  );

  const {
    totalCheckIns,
    totalAthletes,
    avgRate,
    lowAttendance,
    lowCount,
    athleteList,
    sessions,
  } = await getAttendanceAnalytics(groupId, from, to);

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-gray-900">
          Análise de Presença
        </h1>
        <p className="mt-1 text-sm text-gray-500">
          Métricas e tendências de presença nos treinos
        </p>
      </div>

      <Suspense fallback={<div className="h-14 animate-pulse rounded-lg border border-gray-200 bg-gray-50" />}>
        <AttendanceAnalyticsFilters />
      </Suspense>

      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <KpiCard
          label="Taxa média de presença"
          value={formatPercent(avgRate)}
          color="text-blue-700"
        />
        <KpiCard label="Total de treinos no período" value={sessions.length} />
        <KpiCard label="Total de check-ins" value={totalCheckIns} color="text-green-700" />
        <KpiCard
          label="Treinos com presença < 50%"
          value={lowCount}
          color={lowCount > 0 ? "text-amber-700" : "text-gray-900"}
        />
      </div>

      <div className="rounded-xl border border-gray-200 bg-white shadow-sm">
        <div className="border-b border-gray-200 px-4 py-3">
          <h2 className="text-sm font-semibold text-gray-900">
            Treinos com Baixa Presença
          </h2>
          <p className="mt-0.5 text-xs text-gray-500">
            Sessões com taxa de presença inferior a 50%
          </p>
        </div>
        <div className="overflow-x-auto">
          <table className="min-w-full divide-y divide-gray-200 text-sm">
            <thead className="bg-gray-50">
              <tr>
                <th className="px-4 py-3 text-left font-medium text-gray-500">
                  Título
                </th>
                <th className="px-4 py-3 text-left font-medium text-gray-500">
                  Data
                </th>
                <th className="px-4 py-3 text-center font-medium text-gray-500">
                  Presentes
                </th>
                <th className="px-4 py-3 text-center font-medium text-gray-500">
                  Total Atletas
                </th>
                <th className="px-4 py-3 text-center font-medium text-gray-500">
                  Taxa (%)
                </th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {lowAttendance.map((session) => (
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
                    {session.presentes}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-center text-gray-600">
                    {session.totalAthletes}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-center font-medium text-amber-700">
                    {formatPercent(session.rate)}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        {lowAttendance.length === 0 && (
          <div className="px-4 py-8 text-center text-sm text-gray-500">
            Nenhum treino com presença inferior a 50% no período.
          </div>
        )}
      </div>

      <div className="rounded-xl border border-gray-200 bg-white shadow-sm">
        <div className="border-b border-gray-200 px-4 py-3">
          <h2 className="text-sm font-semibold text-gray-900">
            Presença por Atleta
          </h2>
          <p className="mt-0.5 text-xs text-gray-500">
            Número de treinos presentes e taxa por atleta
          </p>
        </div>
        <div className="overflow-x-auto">
          <table className="min-w-full divide-y divide-gray-200 text-sm">
            <thead className="bg-gray-50">
              <tr>
                <th className="px-4 py-3 text-left font-medium text-gray-500">
                  Atleta
                </th>
                <th className="px-4 py-3 text-center font-medium text-gray-500">
                  Check-ins
                </th>
                <th className="px-4 py-3 text-center font-medium text-gray-500">
                  Taxa (%)
                </th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {athleteList.map((a) => (
                <tr key={a.userId}>
                  <td className="whitespace-nowrap px-4 py-3">
                    <Link
                      href={`/crm/${a.userId}`}
                      className="font-medium text-blue-600 hover:text-blue-800 hover:underline"
                    >
                      {a.display_name}
                    </Link>
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-center font-medium text-gray-900">
                    {a.count}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-center font-medium text-gray-900">
                    {formatPercent(a.rate)}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        {athleteList.length === 0 && (
          <div className="px-4 py-8 text-center text-sm text-gray-500">
            Nenhum atleta no grupo.
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
