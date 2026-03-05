import { Suspense } from "react";
import { cookies } from "next/headers";
import { createClient } from "@/lib/supabase/server";
import { NoGroupSelected } from "@/components/no-group-selected";
import { LastUpdated } from "@/components/last-updated";
import { formatKm } from "@/lib/format";
import { StatBlock, DashboardCard } from "@/components/ui";
import { EngagementFilters } from "./engagement-filters";

export const dynamic = "force-dynamic";

type PeriodDays = 7 | 14 | 30;

function parsePeriod(s: string | null): PeriodDays {
  const n = parseInt(s ?? "30", 10);
  if (n === 7 || n === 14) return n;
  return 30;
}

export default async function EngagementPage({
  searchParams,
}: {
  searchParams: Promise<{ period?: string }>;
}) {
  const groupId = cookies().get("portal_group_id")?.value;
  if (!groupId) return <NoGroupSelected />;

  const params = await searchParams;
  const period = parsePeriod(params.period ?? null);

  const db = createClient();

  const now = Date.now();
  const dayMs = 86_400_000;
  const todayStart = now - (now % dayMs);
  const weekStart = todayStart - (period - 1) * dayMs;
  const monthStart = todayStart - 29 * dayMs;
  const thirtyDaysAgo = new Date(todayStart - 30 * dayMs).toISOString().slice(0, 10);

  let athleteIds: string[] = [];
  let totalAthletes = 0;
  let weekSessions: { user_id: string; total_distance_m: number; start_time_ms: number }[] = [];
  let monthSessions: { user_id: string; total_distance_m: number; start_time_ms: number }[] = [];
  let challengeCount = 0;
  let kpisDaily: { day: string; engagement_score: number; churn_risk_count: number; total_athletes: number; total_coaches: number }[] = [];
  let avgEngagement30d = 0;
  let inactiveList: { user_id: string; display_name: string }[] = [];
  let fetchError: string | null = null;

  try {
    const { data: members } = await db
      .from("coaching_members")
      .select("user_id")
      .eq("group_id", groupId)
      .in("role", ["athlete", "atleta"]);

    athleteIds = (members ?? []).map((m: { user_id: string }) => m.user_id);
    totalAthletes = athleteIds.length;

    if (athleteIds.length > 0) {
      const [weekRes, monthRes, challengeRes, kpisRes, athleteKpisRes] = await Promise.all([
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
        db
          .from("coaching_kpis_daily")
          .select("day, total_athletes, total_coaches")
          .eq("group_id", groupId)
          .gte("day", thirtyDaysAgo)
          .order("day", { ascending: false })
          .limit(30),
        db
          .from("coaching_athlete_kpis_daily")
          .select("day, engagement_score, risk_level")
          .eq("group_id", groupId)
          .gte("day", thirtyDaysAgo)
          .order("day", { ascending: false }),
      ]);

      weekSessions = (weekRes.data ?? []) as typeof weekSessions;
      monthSessions = (monthRes.data ?? []) as typeof monthSessions;
      challengeCount = challengeRes.count ?? 0;

      const kpisRows = (kpisRes.data ?? []) as { day: string; total_athletes: number; total_coaches: number }[];
      const athleteKpis = (athleteKpisRes.data ?? []) as { day: string; engagement_score: number; risk_level: string }[];

      const byDay = new Map<string, { scores: number[]; risks: number }>();
      for (const row of athleteKpis) {
        const d = row.day;
        if (!byDay.has(d)) byDay.set(d, { scores: [], risks: 0 });
        const entry = byDay.get(d)!;
        entry.scores.push(row.engagement_score ?? 0);
        if (row.risk_level === "medium" || row.risk_level === "high") entry.risks++;
      }

      const kpisMap = new Map(kpisRows.map((r) => [r.day, { total_athletes: r.total_athletes, total_coaches: r.total_coaches }]));

      kpisDaily = Array.from(byDay.entries())
        .map(([day, { scores, risks }]) => {
          const kpi = kpisMap.get(day);
          const avg = scores.length ? Math.round(scores.reduce((a, b) => a + b, 0) / scores.length) : 0;
          return {
            day,
            engagement_score: avg,
            churn_risk_count: risks,
            total_athletes: kpi?.total_athletes ?? 0,
            total_coaches: kpi?.total_coaches ?? 0,
          };
        })
        .sort((a, b) => (a.day > b.day ? -1 : 1))
        .slice(0, 30);

      if (kpisDaily.length > 0) {
        const sum = kpisDaily.reduce((s, r) => s + r.engagement_score, 0);
        avgEngagement30d = Math.round(sum / kpisDaily.length);
      }
    }

    const monthUsers = new Set(monthSessions.map((s) => s.user_id));
    const inactiveAthletes = athleteIds.filter((id) => !monthUsers.has(id));
    const { data: profiles } =
      inactiveAthletes.length > 0
        ? await db
            .from("profiles")
            .select("id, display_name")
            .in("id", inactiveAthletes)
        : { data: [] };
    const profileMap = new Map(
      (profiles ?? []).map((p: { id: string; display_name: string }) => [
        p.id,
        p.display_name || "Sem nome",
      ]),
    );
    inactiveList = inactiveAthletes.map((id) => ({
      user_id: id,
      display_name: profileMap.get(id) ?? "—",
    }));
  } catch (e) {
    fetchError = String(e);
  }

  const todayUsers = new Set(
    weekSessions
      .filter((s) => s.start_time_ms >= todayStart)
      .map((s) => s.user_id),
  );
  const dau = todayUsers.size;
  const weekUsers = new Set(weekSessions.map((s) => s.user_id));
  const wau = weekUsers.size;
  const monthUsers = new Set(monthSessions.map((s) => s.user_id));
  const mau = monthUsers.size;

  const weekDistance = weekSessions.reduce((s, r) => s + (r.total_distance_m ?? 0), 0);
  const monthDistance = monthSessions.reduce((s, r) => s + (r.total_distance_m ?? 0), 0);

  const retentionRate =
    totalAthletes > 0 ? Math.round((mau / totalAthletes) * 100) : 0;

  const dayLabels = ["Dom", "Seg", "Ter", "Qua", "Qui", "Sex", "Sáb"];
  const dailyBreakdown: { label: string; date: string; sessions: number; users: number }[] = [];
  const bars = Math.min(period, 30);
  for (let i = bars - 1; i >= 0; i--) {
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
  const maxScore = Math.max(...kpisDaily.map((d) => d.engagement_score), 1);

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-content-primary">Engajamento</h1>
        <p className="mt-1 text-sm text-content-secondary">
          Métricas de atividade e retenção dos atletas
        </p>
      </div>

      {fetchError && (
        <div className="rounded-lg border border-error/30 bg-error-soft p-6 text-center">
          <h2 className="text-lg font-semibold text-error">Erro ao carregar dados</h2>
          <p className="mt-2 text-sm text-content-secondary">
            Não foi possível carregar as métricas de engajamento. Tente recarregar a página.
          </p>
        </div>
      )}

      <Suspense fallback={<div className="h-14 animate-shimmer rounded-xl border border-border" />}>
        <EngagementFilters />
      </Suspense>

      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <StatBlock label="DAU (hoje)" value={dau} accentClass="text-info" />
        <StatBlock label="WAU (7 dias)" value={wau} accentClass="text-info" />
        <StatBlock label="MAU (30 dias)" value={mau} accentClass="text-info" />
        <StatBlock
          label="Retenção 30d"
          value={`${retentionRate}%`}
          accentClass={
            retentionRate >= 50
              ? "text-success"
              : retentionRate >= 25
                ? "text-warning"
                : "text-error"
          }
        />
      </div>

      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-5">
        <StatBlock label="Corridas (7d)" value={weekSessions.length} />
        <StatBlock label="Km (7d)" value={formatKm(weekDistance)} />
        <StatBlock label="Corridas (30d)" value={monthSessions.length} />
        <StatBlock label="Km (30d)" value={formatKm(monthDistance)} />
        <StatBlock label="Desafios (30d)" value={challengeCount} accentClass="text-brand" />
        <StatBlock
          label="Score Médio (30d)"
          value={avgEngagement30d}
          accentClass="text-success"
        />
      </div>

      <DashboardCard
        title={`Atividade dos últimos ${period} dias`}
        description="Corridas por dia · Atletas únicos ativos"
      >
        <div className="flex items-end gap-2 sm:gap-3" style={{ height: 160 }}>
          {dailyBreakdown.map((d) => {
            const heightPct = Math.max((d.sessions / maxSessions) * 100, 4);
            return (
              <div key={d.date} className="flex flex-1 flex-col items-center gap-1">
                <span className="text-xs font-semibold text-content-primary">
                  {d.sessions}
                </span>
                <div
                  className="w-full rounded-t-md bg-brand transition-all"
                  style={{ height: `${heightPct}%`, minHeight: 4 }}
                />
                <span className="text-[10px] text-content-secondary">{d.label}</span>
                <span className="text-[10px] text-content-muted">{d.date}</span>
              </div>
            );
          })}
        </div>
      </DashboardCard>

      {kpisDaily.length > 0 && (
        <DashboardCard
          title="Tendência de Score"
          description="Score de engajamento médio por dia (últimos 30 dias)"
        >
          <div
            className="flex items-end gap-1"
            style={{ height: 120 }}
          >
            {[...kpisDaily].reverse().slice(-14).map((d) => {
              const heightPct = Math.max((d.engagement_score / maxScore) * 100, 4);
              return (
                <div
                  key={d.day}
                  className="flex flex-1 flex-col items-center gap-0.5"
                  title={`${d.day}: ${d.engagement_score}`}
                >
                  <span className="text-[10px] font-medium text-content-secondary">
                    {d.engagement_score}
                  </span>
                  <div
                    className="w-full rounded-t bg-success transition-all"
                    style={{ height: `${heightPct}%`, minHeight: 4 }}
                  />
                  <span className="text-[9px] text-content-muted">
                    {new Date(d.day).toLocaleDateString("pt-BR", {
                      day: "2-digit",
                      month: "2-digit",
                    })}
                  </span>
                </div>
              );
            })}
          </div>
        </DashboardCard>
      )}

      {totalAthletes > 0 && mau < totalAthletes && (
        <div className="flex items-start gap-3 rounded-xl border border-warning/30 bg-warning-soft p-4">
          <svg
            className="mt-0.5 h-5 w-5 flex-shrink-0 text-warning"
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
            <p className="text-sm font-medium text-warning">
              {totalAthletes - mau} atleta(s) sem atividade nos últimos 30 dias
            </p>
            <p className="mt-1 text-xs text-content-secondary">
              Considere enviar uma mensagem de motivação ou verificar se estão
              com dificuldades.
            </p>
          </div>
        </div>
      )}

      {inactiveList.length > 0 && (
        <DashboardCard
          title="Atletas Inativos (30d)"
          description="Membros do grupo sem sessões nos últimos 30 dias"
        >
          <ul className="space-y-2">
            {inactiveList.map((a) => (
              <li
                key={a.user_id}
                className="flex items-center justify-between rounded-lg border border-border-subtle bg-bg-secondary px-4 py-2 text-sm"
              >
                <span className="font-medium text-content-primary">{a.display_name}</span>
                <a
                  href={`/crm/${a.user_id}`}
                  className="text-xs text-brand hover:brightness-125 hover:underline transition-all"
                >
                  Ver perfil
                </a>
              </li>
            ))}
          </ul>
        </DashboardCard>
      )}

      <LastUpdated />
    </div>
  );
}
