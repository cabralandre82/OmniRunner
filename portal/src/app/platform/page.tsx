import { createAdminClient } from "@/lib/supabase/admin";
import Link from "next/link";

export const dynamic = "force-dynamic";

function fmt(cents: number) {
  return (cents / 100).toLocaleString("pt-BR", {
    style: "currency",
    currency: "BRL",
  });
}

function fmtNum(n: number) {
  return n.toLocaleString("pt-BR");
}

export default async function PlatformDashboard() {
  const supabase = createAdminClient();

  const now = new Date();
  const dayMs = 86_400_000;
  const todayStart = now.getTime() - (now.getTime() % dayMs);
  const weekStart = todayStart - 6 * dayMs;
  const monthStart = new Date(now.getFullYear(), now.getMonth(), 1).toISOString();
  const prevMonthStart = new Date(now.getFullYear(), now.getMonth() - 1, 1).toISOString();

  const [
    { count: totalGroups },
    { count: activeGroups },
    { count: pendingGroups },
    { count: totalAthletes },
    { count: verifiedAthletes },
    { data: purchasesData },
    { count: openTickets },
    { count: pendingRefunds },
    { count: weekSessions },
    { data: recentGroups },
  ] = await Promise.all([
    supabase
      .from("coaching_groups")
      .select("id", { count: "exact", head: true }),
    supabase
      .from("coaching_groups")
      .select("id", { count: "exact", head: true })
      .eq("approval_status", "approved"),
    supabase
      .from("coaching_groups")
      .select("id", { count: "exact", head: true })
      .eq("approval_status", "pending_approval"),
    supabase
      .from("coaching_members")
      .select("id", { count: "exact", head: true })
      .eq("role", "atleta"),
    supabase
      .from("athlete_verification")
      .select("user_id", { count: "exact", head: true })
      .eq("verification_status", "VERIFIED"),
    supabase
      .from("billing_purchases")
      .select("price_cents, status, created_at"),
    supabase
      .from("support_tickets")
      .select("id", { count: "exact", head: true })
      .eq("status", "open"),
    supabase
      .from("billing_refund_requests")
      .select("id", { count: "exact", head: true })
      .in("status", ["requested", "approved"]),
    supabase
      .from("sessions")
      .select("id", { count: "exact", head: true })
      .gte("start_time_ms", weekStart)
      .gte("status", 3),
    supabase
      .from("coaching_groups")
      .select("id, name, city, approval_status, created_at")
      .order("created_at", { ascending: false })
      .limit(5),
  ]);

  const allPurchases = purchasesData ?? [];
  const fulfilledPurchases = allPurchases.filter((p) => p.status === "fulfilled");
  const totalRevenue = fulfilledPurchases.reduce((s, p) => s + (p.price_cents ?? 0), 0);
  const monthPurchases = fulfilledPurchases.filter((p) => p.created_at >= monthStart);
  const monthRevenue = monthPurchases.reduce((s, p) => s + (p.price_cents ?? 0), 0);
  const prevMonthPurchases = fulfilledPurchases.filter(
    (p) => p.created_at >= prevMonthStart && p.created_at < monthStart,
  );
  const prevMonthRevenue = prevMonthPurchases.reduce((s, p) => s + (p.price_cents ?? 0), 0);

  const revenueTrend =
    prevMonthRevenue > 0
      ? Math.round(((monthRevenue - prevMonthRevenue) / prevMonthRevenue) * 100)
      : monthRevenue > 0
        ? 100
        : 0;

  const pendingPurchases = allPurchases.filter(
    (p) => p.status === "pending" || p.status === "paid",
  );

  const avgAthletesPerGroup =
    (activeGroups ?? 0) > 0
      ? Math.round((totalAthletes ?? 0) / (activeGroups ?? 1))
      : 0;

  const verificationRate =
    (totalAthletes ?? 0) > 0
      ? Math.round(((verifiedAthletes ?? 0) / (totalAthletes ?? 1)) * 100)
      : 0;

  const statusColor: Record<string, string> = {
    pending_approval: "bg-orange-100 text-orange-700",
    approved: "bg-green-100 text-green-700",
    rejected: "bg-red-100 text-red-700",
    suspended: "bg-gray-200 text-gray-700",
  };

  const statusLabel: Record<string, string> = {
    pending_approval: "Pendente",
    approved: "Aprovada",
    rejected: "Rejeitada",
    suspended: "Suspensa",
  };

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-gray-900">
          Dashboard da Plataforma
        </h1>
        <p className="mt-1 text-sm text-gray-500">
          Visão estratégica do Omni Runner
        </p>
      </div>

      {/* Alerts */}
      {(pendingGroups ?? 0) > 0 && (
        <Link
          href="/platform/assessorias"
          className="flex items-start gap-3 rounded-lg border border-orange-200 bg-orange-50 p-4 hover:bg-orange-100 transition"
        >
          <span className="text-xl">🔔</span>
          <div>
            <p className="text-sm font-medium text-orange-800">
              {pendingGroups} assessoria(s) aguardando aprovação
            </p>
            <p className="text-xs text-orange-700">
              Clique para revisar
            </p>
          </div>
        </Link>
      )}

      {(pendingRefunds ?? 0) > 0 && (
        <Link
          href="/platform/reembolsos"
          className="flex items-start gap-3 rounded-lg border border-red-200 bg-red-50 p-4 hover:bg-red-100 transition"
        >
          <span className="text-xl">↩️</span>
          <div>
            <p className="text-sm font-medium text-red-800">
              {pendingRefunds} reembolso(s) pendentes
            </p>
            <p className="text-xs text-red-700">
              Clique para processar
            </p>
          </div>
        </Link>
      )}

      {/* KPI Row 1: Overview */}
      <div>
        <h2 className="mb-3 text-xs font-semibold uppercase tracking-wider text-gray-400">
          Visão Geral
        </h2>
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4">
          <KpiCard
            label="Assessorias Ativas"
            value={fmtNum(activeGroups ?? 0)}
            detail={`${fmtNum(totalGroups ?? 0)} total`}
            color="text-green-700"
            bg="bg-green-50"
          />
          <KpiCard
            label="Atletas"
            value={fmtNum(totalAthletes ?? 0)}
            detail={`~${avgAthletesPerGroup} por assessoria`}
            color="text-blue-700"
            bg="bg-blue-50"
          />
          <KpiCard
            label="Verificados"
            value={`${verificationRate}%`}
            detail={`${fmtNum(verifiedAthletes ?? 0)} atletas`}
            color="text-indigo-700"
            bg="bg-indigo-50"
          />
          <KpiCard
            label="Corridas (7d)"
            value={fmtNum(weekSessions ?? 0)}
            color="text-purple-700"
            bg="bg-purple-50"
          />
        </div>
      </div>

      {/* KPI Row 2: Financial */}
      <div>
        <h2 className="mb-3 text-xs font-semibold uppercase tracking-wider text-gray-400">
          Financeiro
        </h2>
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4">
          <KpiCard
            label="Receita Total"
            value={fmt(totalRevenue)}
            color="text-emerald-700"
            bg="bg-emerald-50"
          />
          <KpiCard
            label="Receita do Mês"
            value={fmt(monthRevenue)}
            trend={revenueTrend}
            color="text-emerald-700"
            bg="bg-emerald-50"
          />
          <KpiCard
            label="Compras do Mês"
            value={fmtNum(monthPurchases.length)}
            color="text-gray-700"
            bg="bg-gray-50"
          />
          <KpiCard
            label="Pendentes"
            value={fmtNum(pendingPurchases.length)}
            color={pendingPurchases.length > 0 ? "text-orange-700" : "text-gray-700"}
            bg={pendingPurchases.length > 0 ? "bg-orange-50" : "bg-gray-50"}
          />
        </div>
      </div>

      {/* KPI Row 3: Operations */}
      <div>
        <h2 className="mb-3 text-xs font-semibold uppercase tracking-wider text-gray-400">
          Operações
        </h2>
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4">
          <KpiCard
            label="Chamados Abertos"
            value={fmtNum(openTickets ?? 0)}
            color={openTickets && openTickets > 0 ? "text-yellow-700" : "text-gray-700"}
            bg={openTickets && openTickets > 0 ? "bg-yellow-50" : "bg-gray-50"}
          />
          <KpiCard
            label="Reembolsos"
            value={fmtNum(pendingRefunds ?? 0)}
            color={pendingRefunds && pendingRefunds > 0 ? "text-red-700" : "text-gray-700"}
            bg={pendingRefunds && pendingRefunds > 0 ? "bg-red-50" : "bg-gray-50"}
          />
          <KpiCard
            label="Aprovações Pendentes"
            value={fmtNum(pendingGroups ?? 0)}
            color={pendingGroups && pendingGroups > 0 ? "text-orange-700" : "text-gray-700"}
            bg={pendingGroups && pendingGroups > 0 ? "bg-orange-50" : "bg-gray-50"}
          />
        </div>
      </div>

      {/* Recent assessorias */}
      <div className="rounded-xl border border-gray-200 bg-white shadow-sm">
        <div className="flex items-center justify-between border-b border-gray-200 px-5 py-4">
          <h2 className="text-sm font-semibold text-gray-900">
            Assessorias Recentes
          </h2>
          <Link
            href="/platform/assessorias"
            className="text-xs font-medium text-blue-600 hover:text-blue-800"
          >
            Ver todas →
          </Link>
        </div>
        <div className="divide-y divide-gray-100">
          {(recentGroups ?? []).map((g) => (
            <div key={g.id} className="flex items-center justify-between px-5 py-3">
              <div>
                <p className="text-sm font-medium text-gray-900">{g.name}</p>
                <p className="text-xs text-gray-500">{g.city ?? "Sem cidade"}</p>
              </div>
              <div className="flex items-center gap-3">
                <span
                  className={`rounded-full px-2 py-0.5 text-xs font-medium ${statusColor[g.approval_status] ?? "bg-gray-100"}`}
                >
                  {statusLabel[g.approval_status] ?? g.approval_status}
                </span>
                <span className="text-xs text-gray-400">
                  {new Date(g.created_at).toLocaleDateString("pt-BR")}
                </span>
              </div>
            </div>
          ))}
        </div>
      </div>

      {/* Quick links */}
      <div>
        <h2 className="mb-3 text-xs font-semibold uppercase tracking-wider text-gray-400">
          Acesso Rápido
        </h2>
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-5">
          <QuickLink href="/platform/assessorias" title="Assessorias" icon="🏢" />
          <QuickLink href="/platform/financeiro" title="Financeiro" icon="💰" />
          <QuickLink href="/platform/reembolsos" title="Reembolsos" icon="↩️" />
          <QuickLink href="/platform/produtos" title="Produtos" icon="📦" />
          <QuickLink href="/platform/support" title="Suporte" icon="💬" />
        </div>
      </div>
    </div>
  );
}

function KpiCard({
  label,
  value,
  detail,
  color,
  bg,
  trend,
}: {
  label: string;
  value: string | number;
  detail?: string;
  color: string;
  bg: string;
  trend?: number;
}) {
  return (
    <div className={`rounded-xl border border-gray-200 ${bg} p-4 sm:p-5 shadow-sm`}>
      <p className="text-xs font-medium uppercase tracking-wide text-gray-500">
        {label}
      </p>
      <div className="mt-2 flex items-baseline gap-2">
        <p className={`text-xl sm:text-2xl font-bold ${color}`}>{value}</p>
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

function QuickLink({
  href,
  title,
  icon,
}: {
  href: string;
  title: string;
  icon: string;
}) {
  return (
    <Link
      href={href}
      className="flex items-center gap-2.5 rounded-xl border border-gray-200 bg-white p-3.5 shadow-sm transition hover:border-gray-300 hover:shadow"
    >
      <span className="text-xl">{icon}</span>
      <p className="text-sm font-semibold text-gray-900">{title}</p>
    </Link>
  );
}
