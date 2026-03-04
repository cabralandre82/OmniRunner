import type { Metadata } from "next";
import { cookies } from "next/headers";
import { createClient } from "@/lib/supabase/server";
import { createServiceClient } from "@/lib/supabase/service";
import { formatKm } from "@/lib/format";
import { StatBlock, DashboardCard } from "@/components/ui";
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
        <div className="rounded-xl border border-error/30 bg-error-soft p-8 text-center">
          <h2 className="text-lg font-semibold text-error">Erro ao carregar dados</h2>
          <p className="mt-2 text-sm text-content-secondary">Não foi possível conectar ao servidor. Tente recarregar a página.</p>
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-content-primary">Dashboard</h1>
        <p className="mt-1 text-sm text-content-secondary">Visão geral da assessoria</p>
      </div>

      {lowCredits && (
        <div className="flex items-start gap-3 rounded-xl border border-error/30 bg-error-soft p-4">
          <svg
            className="mt-0.5 h-5 w-5 flex-shrink-0 text-error"
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
            <p className="text-sm font-medium text-error">
              Créditos baixos: {credits} restantes
            </p>
            <p className="mt-1 text-xs text-content-secondary">
              Recarregue para continuar distribuindo OmniCoins aos atletas.
            </p>
            {role === "admin_master" && (
              <a
                href="/credits"
                className="mt-2 inline-block rounded-lg bg-error px-3 py-1.5 text-xs font-medium text-white hover:brightness-110 transition-all"
              >
                Recarregar Agora
              </a>
            )}
          </div>
        </div>
      )}

      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <StatBlock
          label="Créditos Disponíveis"
          value={credits.toLocaleString("pt-BR")}
          alert={lowCredits}
          accentClass={lowCredits ? "text-error" : undefined}
        />
        <StatBlock label="Atletas" value={athleteCount.toLocaleString("pt-BR")} />
        <StatBlock
          label="Verificados"
          value={verifiedCount.toLocaleString("pt-BR")}
          accentClass="text-success"
          detail={
            athleteCount > 0
              ? `${Math.round((verifiedCount / athleteCount) * 100)}% do total`
              : undefined
          }
        />
        <StatBlock
          label="Ativos (7d)"
          value={wau.toLocaleString("pt-BR")}
          accentClass="text-info"
          detail={
            athleteCount > 0
              ? `${Math.round((wau / athleteCount) * 100)}% do total`
              : undefined
          }
        />
      </div>

      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <StatBlock
          label="Corridas (7d)"
          value={weekSessions.length.toLocaleString("pt-BR")}
          trend={sessionsTrend}
        />
        <StatBlock
          label="Km (7d)"
          value={formatKm(weekDistance)}
          trend={distanceTrend}
        />
        <StatBlock
          label="Desafios (30d)"
          value={challengeCount.toLocaleString("pt-BR")}
          accentClass="text-brand"
        />
        {role === "admin_master" && (
          <StatBlock
            label="Compras"
            value={purchasesFulfilled.toLocaleString("pt-BR")}
            detail={`${totalCreditsBought.toLocaleString("pt-BR")} créditos adquiridos`}
          />
        )}
      </div>

      <DashboardCharts dailyBreakdown={dailyBreakdown} />

      {role === "admin_master" && (
        <DashboardCard title="Acesso Rápido">
          <div className="flex flex-wrap gap-2">
            <a
              href="/credits"
              className="rounded-lg bg-brand-soft px-3 py-1.5 text-xs font-medium text-brand hover:brightness-110 transition-all"
            >
              Comprar Créditos
            </a>
            {[
              { href: "/athletes", label: "Ver Atletas" },
              { href: "/engagement", label: "Engajamento" },
              { href: "/verification", label: "Verificação" },
              { href: "/settings", label: "Configurações" },
            ].map((link) => (
              <a
                key={link.href}
                href={link.href}
                className="rounded-lg bg-surface-elevated px-3 py-1.5 text-xs font-medium text-content-secondary hover:text-content-primary hover:bg-bg-secondary transition-colors"
              >
                {link.label}
              </a>
            ))}
          </div>
        </DashboardCard>
      )}
    </div>
  );
}
