import type { Metadata } from "next";
import { cookies } from "next/headers";
import { createClient } from "@/lib/supabase/server";
import { createServiceClient } from "@/lib/supabase/service";
import { formatKm } from "@/lib/format";
import { DashboardCharts } from "./dashboard-charts";

export const metadata: Metadata = { title: "Dashboard" };
export const dynamic = "force-dynamic";

const LOW_CREDIT_THRESHOLD = 50;

export default async function DashboardPage() {
  const groupId = cookies().get("portal_group_id")?.value;
  const role = cookies().get("portal_role")?.value ?? "assistant";
  if (!groupId) return null;

  let credits = 0;
  let athleteCount = 0;
  let purchasesFulfilled = 0;
  let totalCreditsBought = 0;
  let weekSessions: { user_id: string; total_distance_m: number; start_time_ms: number }[] = [];
  let verifiedCount = 0;
  let challengeCount = 0;
  let wau = 0;
  let weekDistance = 0;
  let distanceTrend = 0;
  let sessionsTrend = 0;
  let dailyBreakdown: { label: string; date: string; sessions: number }[] = [];
  let lowCredits = false;
  let fetchError = false;

  try {
    const supabase = createClient();
    const db = createServiceClient();

    const now = Date.now();
    const dayMs = 86_400_000;
    const todayStart = now - (now % dayMs);
    const weekStart = todayStart - 6 * dayMs;
    const prevWeekStart = weekStart - 7 * dayMs;
    const monthStart = todayStart - 29 * dayMs;

    const [inventoryRes, athleteMembersRes, purchasesRes] =
      await Promise.all([
        supabase
          .from("coaching_token_inventory")
          .select("available_tokens")
          .eq("group_id", groupId)
          .maybeSingle(),
        db
          .from("coaching_members")
          .select("user_id")
          .eq("group_id", groupId)
          .eq("role", "athlete"),
        role === "admin_master"
          ? supabase
              .from("billing_purchases")
              .select("status, credits_amount")
              .eq("group_id", groupId)
          : Promise.resolve({ data: null }),
      ]);

    credits = inventoryRes.data?.available_tokens ?? 0;
    const athleteIds = (athleteMembersRes.data ?? []).map(
      (m: { user_id: string }) => m.user_id,
    );
    athleteCount = athleteIds.length;

    if (purchasesRes.data) {
      for (const p of purchasesRes.data) {
        if ((p as { status: string }).status === "fulfilled") {
          purchasesFulfilled++;
          totalCreditsBought += (p as { credits_amount: number }).credits_amount;
        }
      }
    }

    let prevWeekSessions: { user_id: string; total_distance_m: number; start_time_ms: number }[] = [];

    if (athleteIds.length > 0) {
      const [allSessionsRes, verRes, challengeRes] = await Promise.all([
        db
          .from("sessions")
          .select("user_id, total_distance_m, start_time_ms")
          .in("user_id", athleteIds)
          .gte("start_time_ms", prevWeekStart)
          .gte("status", 3),
        db
          .from("athlete_verification")
          .select("user_id", { count: "exact", head: true })
          .in("user_id", athleteIds)
          .eq("verification_status", "VERIFIED"),
        db
          .from("challenge_participants")
          .select("id", { count: "exact", head: true })
          .in("user_id", athleteIds)
          .gte("joined_at_ms", monthStart),
      ]);

      const allSessions = (allSessionsRes.data ?? []) as typeof weekSessions;
      weekSessions = allSessions.filter((s) => s.start_time_ms >= weekStart);
      prevWeekSessions = allSessions.filter((s) => s.start_time_ms < weekStart);
      verifiedCount = verRes.count ?? 0;
      challengeCount = challengeRes.count ?? 0;
    }

    wau = new Set(weekSessions.map((s) => s.user_id)).size;
    weekDistance = weekSessions.reduce((s, r) => s + (r.total_distance_m ?? 0), 0);
    const prevWeekDistance = prevWeekSessions.reduce((s, r) => s + (r.total_distance_m ?? 0), 0);

    distanceTrend =
      prevWeekDistance > 0
        ? Math.round(((weekDistance - prevWeekDistance) / prevWeekDistance) * 100)
        : weekSessions.length > 0
          ? 100
          : 0;

    sessionsTrend =
      prevWeekSessions.length > 0
        ? Math.round(
            ((weekSessions.length - prevWeekSessions.length) / prevWeekSessions.length) * 100,
          )
        : weekSessions.length > 0
          ? 100
          : 0;

    const dayLabels = ["Dom", "Seg", "Ter", "Qua", "Qui", "Sex", "Sáb"];
    for (let i = 6; i >= 0; i--) {
      const dStart = todayStart - i * dayMs;
      const dEnd = dStart + dayMs;
      const cnt = weekSessions.filter(
        (s) => s.start_time_ms >= dStart && s.start_time_ms < dEnd,
      ).length;
      const d = new Date(dStart);
      dailyBreakdown.push({
        label: dayLabels[d.getDay()],
        date: d.toLocaleDateString("pt-BR", { day: "2-digit", month: "2-digit" }),
        sessions: cnt,
      });
    }
    lowCredits = credits < LOW_CREDIT_THRESHOLD;
  } catch {
    fetchError = true;
  }

  if (fetchError) {
    return (
      <div className="p-6">
        <div className="rounded-xl border border-red-200 bg-red-50 p-8 text-center">
          <h2 className="text-lg font-semibold text-red-800">Erro ao carregar dados</h2>
          <p className="mt-2 text-sm text-red-600">Não foi possível conectar ao servidor. Tente recarregar a página.</p>
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-gray-900">Dashboard</h1>
        <p className="mt-1 text-sm text-gray-500">Visão geral da assessoria</p>
      </div>

      {/* Credit alert */}
      {lowCredits && (
        <div className="flex items-start gap-3 rounded-lg border border-red-200 bg-red-50 p-4">
          <svg
            className="mt-0.5 h-5 w-5 flex-shrink-0 text-red-600"
            fill="none"
            viewBox="0 0 24 24"
            strokeWidth={2}
            stroke="currentColor"
          >
            <path
              strokeLinecap="round"
              strokeLinejoin="round"
              d="M12 9v3.75m-9.303 3.376c-.866 1.5.217 3.374 1.948 3.374h14.71c1.73 0 2.813-1.874 1.948-3.374L13.949 3.378c-.866-1.5-3.032-1.5-3.898 0L2.697 16.126zM12 15.75h.007v.008H12v-.008z"
            />
          </svg>
          <div>
            <p className="text-sm font-medium text-red-800">
              Créditos baixos: {credits} restantes
            </p>
            <p className="mt-1 text-xs text-red-700">
              Recarregue para continuar distribuindo OmniCoins aos atletas.
            </p>
            {role === "admin_master" && (
              <a
                href="/credits"
                className="mt-2 inline-block rounded-lg bg-red-600 px-3 py-1.5 text-xs font-medium text-white hover:bg-red-700"
              >
                Recarregar Agora
              </a>
            )}
          </div>
        </div>
      )}

      {/* KPIs row 1 */}
      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <KpiCard
          label="Créditos Disponíveis"
          value={credits.toLocaleString("pt-BR")}
          color={lowCredits ? "text-red-600" : "text-gray-900"}
        />
        <KpiCard label="Atletas" value={athleteCount.toLocaleString("pt-BR")} />
        <KpiCard
          label="Verificados"
          value={verifiedCount.toLocaleString("pt-BR")}
          color="text-green-700"
          detail={
            athleteCount > 0
              ? `${Math.round((verifiedCount / athleteCount) * 100)}% do total`
              : undefined
          }
        />
        <KpiCard
          label="Ativos (7d)"
          value={wau.toLocaleString("pt-BR")}
          color="text-blue-700"
          detail={
            athleteCount > 0
              ? `${Math.round((wau / athleteCount) * 100)}% do total`
              : undefined
          }
        />
      </div>

      {/* KPIs row 2 — activity */}
      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <KpiCard
          label="Corridas (7d)"
          value={weekSessions.length.toLocaleString("pt-BR")}
          trend={sessionsTrend}
        />
        <KpiCard
          label="Km (7d)"
          value={formatKm(weekDistance)}
          trend={distanceTrend}
        />
        <KpiCard
          label="Desafios (30d)"
          value={challengeCount.toLocaleString("pt-BR")}
          color="text-indigo-700"
        />
        {role === "admin_master" && (
          <KpiCard
            label="Compras"
            value={purchasesFulfilled.toLocaleString("pt-BR")}
            detail={`${totalCreditsBought.toLocaleString("pt-BR")} créditos adquiridos`}
          />
        )}
      </div>

      {/* Activity charts */}
      <DashboardCharts dailyBreakdown={dailyBreakdown} />

      {/* Quick links */}
      {role === "admin_master" && (
        <div className="rounded-xl border border-gray-200 bg-white p-6 shadow-sm">
          <h2 className="text-sm font-semibold text-gray-900">Acesso Rápido</h2>
          <div className="mt-3 flex flex-wrap gap-2">
            <a
              href="/credits"
              className="rounded-lg bg-blue-50 px-3 py-1.5 text-xs font-medium text-blue-700 hover:bg-blue-100"
            >
              Comprar Créditos
            </a>
            <a
              href="/athletes"
              className="rounded-lg bg-gray-100 px-3 py-1.5 text-xs font-medium text-gray-700 hover:bg-gray-200"
            >
              Ver Atletas
            </a>
            <a
              href="/engagement"
              className="rounded-lg bg-gray-100 px-3 py-1.5 text-xs font-medium text-gray-700 hover:bg-gray-200"
            >
              Engajamento
            </a>
            <a
              href="/verification"
              className="rounded-lg bg-gray-100 px-3 py-1.5 text-xs font-medium text-gray-700 hover:bg-gray-200"
            >
              Verificação
            </a>
            <a
              href="/settings"
              className="rounded-lg bg-gray-100 px-3 py-1.5 text-xs font-medium text-gray-700 hover:bg-gray-200"
            >
              Configurações
            </a>
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
  detail,
  trend,
}: {
  label: string;
  value: string;
  color?: string;
  detail?: string;
  trend?: number;
}) {
  return (
    <div className="rounded-xl border border-gray-200 bg-white p-5 shadow-sm">
      <p className="text-xs font-medium uppercase tracking-wide text-gray-500">
        {label}
      </p>
      <div className="mt-2 flex items-baseline gap-2">
        <p className={`text-2xl font-bold ${color}`}>{value}</p>
        {trend !== undefined && trend !== 0 && (
          <span
            className={`text-xs font-semibold ${trend > 0 ? "text-green-600" : "text-red-500"}`}
          >
            {trend > 0 ? "+" : ""}
            {trend}%
          </span>
        )}
      </div>
      {detail && <p className="mt-1 text-xs text-gray-400">{detail}</p>}
    </div>
  );
}
