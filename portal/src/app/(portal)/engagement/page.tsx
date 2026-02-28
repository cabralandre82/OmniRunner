import { cookies } from "next/headers";
import { createServiceClient } from "@/lib/supabase/service";

export const dynamic = "force-dynamic";

function formatKm(meters: number): string {
  return (meters / 1000).toLocaleString("pt-BR", {
    minimumFractionDigits: 0,
    maximumFractionDigits: 0,
  });
}

export default async function EngagementPage() {
  const groupId = cookies().get("portal_group_id")?.value;
  if (!groupId) return null;

  const db = createServiceClient();

  const now = Date.now();
  const dayMs = 86_400_000;
  const todayStart = now - (now % dayMs);
  const weekStart = todayStart - 6 * dayMs;
  const monthStart = todayStart - 29 * dayMs;

  const { data: members } = await db
    .from("coaching_members")
    .select("user_id")
    .eq("group_id", groupId)
    .eq("role", "atleta");

  const athleteIds = (members ?? []).map((m: { user_id: string }) => m.user_id);
  const totalAthletes = athleteIds.length;

  let weekSessions: { user_id: string; total_distance_m: number; start_time_ms: number }[] = [];
  let monthSessions: { user_id: string; total_distance_m: number; start_time_ms: number }[] = [];
  let challengeCount = 0;

  if (athleteIds.length > 0) {
    const [weekRes, monthRes, challengeRes] = await Promise.all([
      db
        .from("sessions")
        .select("user_id, total_distance_m, start_time_ms")
        .in("user_id", athleteIds)
        .gte("start_time_ms", weekStart)
        .gte("status", 3),
      db
        .from("sessions")
        .select("user_id, total_distance_m, start_time_ms")
        .in("user_id", athleteIds)
        .gte("start_time_ms", monthStart)
        .gte("status", 3),
      db
        .from("challenge_participants")
        .select("id", { count: "exact", head: true })
        .in("user_id", athleteIds)
        .gte("joined_at_ms", monthStart),
    ]);

    weekSessions = (weekRes.data ?? []) as typeof weekSessions;
    monthSessions = (monthRes.data ?? []) as typeof monthSessions;
    challengeCount = challengeRes.count ?? 0;
  }

  // DAU: unique users with sessions today
  const todayUsers = new Set(
    weekSessions
      .filter((s) => s.start_time_ms >= todayStart)
      .map((s) => s.user_id),
  );
  const dau = todayUsers.size;

  // WAU: unique users with sessions in last 7 days
  const weekUsers = new Set(weekSessions.map((s) => s.user_id));
  const wau = weekUsers.size;

  // MAU: unique users with sessions in last 30 days
  const monthUsers = new Set(monthSessions.map((s) => s.user_id));
  const mau = monthUsers.size;

  const weekDistance = weekSessions.reduce((s, r) => s + (r.total_distance_m ?? 0), 0);
  const monthDistance = monthSessions.reduce((s, r) => s + (r.total_distance_m ?? 0), 0);

  const retentionRate = totalAthletes > 0
    ? Math.round((mau / totalAthletes) * 100)
    : 0;

  // Daily activity breakdown (last 7 days)
  const dayLabels = ["Dom", "Seg", "Ter", "Qua", "Qui", "Sex", "Sáb"];
  const dailyBreakdown: { label: string; date: string; sessions: number; users: number }[] = [];
  for (let i = 6; i >= 0; i--) {
    const dayStart = todayStart - i * dayMs;
    const dayEnd = dayStart + dayMs;
    const daySessions = weekSessions.filter(
      (s) => s.start_time_ms >= dayStart && s.start_time_ms < dayEnd,
    );
    const dayUserSet = new Set(daySessions.map((s) => s.user_id));
    const d = new Date(dayStart);
    dailyBreakdown.push({
      label: dayLabels[d.getDay()],
      date: d.toLocaleDateString("pt-BR", { day: "2-digit", month: "2-digit" }),
      sessions: daySessions.length,
      users: dayUserSet.size,
    });
  }

  const maxSessions = Math.max(...dailyBreakdown.map((d) => d.sessions), 1);

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-gray-900">Engajamento</h1>
        <p className="mt-1 text-sm text-gray-500">
          Métricas de atividade e retenção dos atletas
        </p>
      </div>

      {/* KPIs */}
      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <KpiCard label="DAU (hoje)" value={dau} color="text-blue-700" />
        <KpiCard label="WAU (7 dias)" value={wau} color="text-blue-700" />
        <KpiCard label="MAU (30 dias)" value={mau} color="text-blue-700" />
        <KpiCard
          label="Retenção 30d"
          value={`${retentionRate}%`}
          color={retentionRate >= 50 ? "text-green-700" : retentionRate >= 25 ? "text-yellow-700" : "text-red-700"}
        />
      </div>

      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <KpiCard label="Corridas (7d)" value={weekSessions.length} />
        <KpiCard label="Km (7d)" value={formatKm(weekDistance)} />
        <KpiCard label="Corridas (30d)" value={monthSessions.length} />
        <KpiCard label="Km (30d)" value={formatKm(monthDistance)} />
        <KpiCard label="Desafios (30d)" value={challengeCount} color="text-indigo-700" />
      </div>

      {/* Activity bar chart */}
      <div className="rounded-xl border border-gray-200 bg-white p-6 shadow-sm">
        <h2 className="text-sm font-semibold text-gray-900">
          Atividade dos últimos 7 dias
        </h2>
        <p className="mt-1 text-xs text-gray-500">
          Corridas por dia · Atletas únicos ativos
        </p>

        <div className="mt-6 flex items-end gap-2 sm:gap-3" style={{ height: 160 }}>
          {dailyBreakdown.map((d) => {
            const heightPct = Math.max((d.sessions / maxSessions) * 100, 4);
            return (
              <div key={d.date} className="flex flex-1 flex-col items-center gap-1">
                <span className="text-xs font-semibold text-gray-900">
                  {d.sessions}
                </span>
                <div
                  className="w-full rounded-t-md bg-blue-500 transition-all"
                  style={{ height: `${heightPct}%`, minHeight: 4 }}
                />
                <span className="text-[10px] text-gray-500">{d.label}</span>
                <span className="text-[10px] text-gray-400">{d.date}</span>
              </div>
            );
          })}
        </div>
      </div>

      {/* Inactive athletes alert */}
      {totalAthletes > 0 && mau < totalAthletes && (
        <div className="flex items-start gap-3 rounded-lg border border-yellow-200 bg-yellow-50 p-4">
          <svg
            className="mt-0.5 h-5 w-5 flex-shrink-0 text-yellow-600"
            fill="none"
            viewBox="0 0 24 24"
            strokeWidth={2}
            stroke="currentColor"
          >
            <path
              strokeLinecap="round"
              strokeLinejoin="round"
              d="M12 9v3.75m9-.75a9 9 0 11-18 0 9 9 0 0118 0zm-9 3.75h.008v.008H12v-.008z"
            />
          </svg>
          <div>
            <p className="text-sm font-medium text-yellow-800">
              {totalAthletes - mau} atleta(s) sem atividade nos últimos 30 dias
            </p>
            <p className="mt-1 text-xs text-yellow-700">
              Considere enviar uma mensagem de motivação ou verificar se estão com dificuldades.
            </p>
          </div>
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
