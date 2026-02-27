import { createAdminClient } from "@/lib/supabase/admin";
import Link from "next/link";

export const dynamic = "force-dynamic";

export default async function PlatformDashboard() {
  const supabase = createAdminClient();

  const [
    { count: totalGroups },
    { count: activeGroups },
    { count: totalAthletes },
    { data: purchasesData },
    { count: openTickets },
    { count: pendingRefunds },
  ] = await Promise.all([
    supabase
      .from("coaching_groups")
      .select("id", { count: "exact", head: true }),
    supabase
      .from("coaching_groups")
      .select("id", { count: "exact", head: true })
      .eq("approval_status", "approved"),
    supabase
      .from("coaching_members")
      .select("id", { count: "exact", head: true })
      .eq("role", "athlete"),
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
  ]);

  const now = new Date();
  const thisMonthStart = new Date(now.getFullYear(), now.getMonth(), 1).toISOString();

  const allPurchases = purchasesData ?? [];
  const fulfilledPurchases = allPurchases.filter((p) => p.status === "fulfilled");
  const totalRevenue = fulfilledPurchases.reduce(
    (sum, p) => sum + (p.price_cents ?? 0),
    0,
  );
  const monthPurchases = fulfilledPurchases.filter(
    (p) => p.created_at >= thisMonthStart,
  );
  const monthRevenue = monthPurchases.reduce(
    (sum, p) => sum + (p.price_cents ?? 0),
    0,
  );
  const pendingPurchases = allPurchases.filter(
    (p) => p.status === "pending" || p.status === "paid",
  );

  const fmt = (cents: number) =>
    (cents / 100).toLocaleString("pt-BR", {
      style: "currency",
      currency: "BRL",
    });

  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-2xl font-bold text-gray-900">Dashboard</h1>
        <p className="mt-1 text-sm text-gray-500">
          Visão geral da plataforma Omni Runner
        </p>
      </div>

      {/* KPIs */}
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4 sm:gap-4">
        <KpiCard label="Assessorias ativas" value={activeGroups ?? 0} color="text-green-600" bg="bg-green-50" />
        <KpiCard label="Total assessorias" value={totalGroups ?? 0} color="text-gray-700" bg="bg-gray-50" />
        <KpiCard label="Atletas" value={totalAthletes ?? 0} color="text-blue-600" bg="bg-blue-50" />
        <KpiCard label="Receita total" value={fmt(totalRevenue)} color="text-emerald-600" bg="bg-emerald-50" />
        <KpiCard label="Receita do mês" value={fmt(monthRevenue)} color="text-emerald-600" bg="bg-emerald-50" />
        <KpiCard label="Compras do mês" value={monthPurchases.length} color="text-indigo-600" bg="bg-indigo-50" />
        <KpiCard label="Compras pendentes" value={pendingPurchases.length} color="text-orange-600" bg="bg-orange-50" />
        <KpiCard label="Reembolsos pendentes" value={pendingRefunds ?? 0} color="text-red-600" bg="bg-red-50" />
      </div>

      {/* Quick links */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        <QuickLink
          href="/platform/assessorias"
          title="Assessorias"
          desc="Aprovar, rejeitar, suspender"
          icon="🏢"
        />
        <QuickLink
          href="/platform/financeiro"
          title="Financeiro"
          desc="Todas as compras e receita"
          icon="💰"
        />
        <QuickLink
          href="/platform/reembolsos"
          title="Reembolsos"
          desc={`${pendingRefunds ?? 0} pendentes`}
          icon="↩️"
        />
        <QuickLink
          href="/platform/produtos"
          title="Produtos"
          desc="Pacotes de créditos"
          icon="📦"
        />
        <QuickLink
          href="/platform/support"
          title="Suporte"
          desc={`${openTickets ?? 0} chamados abertos`}
          icon="💬"
        />
      </div>
    </div>
  );
}

function KpiCard({
  label,
  value,
  color,
  bg,
}: {
  label: string;
  value: string | number;
  color: string;
  bg: string;
}) {
  return (
    <div className={`rounded-xl border border-gray-200 ${bg} p-5 shadow-sm`}>
      <p className="text-xs font-medium uppercase tracking-wide text-gray-500">
        {label}
      </p>
      <p className={`mt-2 text-2xl font-bold ${color}`}>{value}</p>
    </div>
  );
}

function QuickLink({
  href,
  title,
  desc,
  icon,
}: {
  href: string;
  title: string;
  desc: string;
  icon: string;
}) {
  return (
    <Link
      href={href}
      className="flex items-center gap-3 rounded-xl border border-gray-200 bg-white p-4 shadow-sm transition hover:border-gray-300 hover:shadow"
    >
      <span className="text-2xl">{icon}</span>
      <div>
        <p className="text-sm font-semibold text-gray-900">{title}</p>
        <p className="text-xs text-gray-500">{desc}</p>
      </div>
    </Link>
  );
}
