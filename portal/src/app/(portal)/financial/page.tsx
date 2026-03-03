import { cookies } from "next/headers";
import { createClient } from "@/lib/supabase/server";
import Link from "next/link";

export const dynamic = "force-dynamic";

interface FinancialKpis {
  revenueThisMonth: number;
  activeSubscribers: number;
  lateSubscribers: number;
  growthPct: number;
}

async function getFinancialKpis(groupId: string): Promise<FinancialKpis> {
  const supabase = createClient();

  const now = new Date();
  const startOfMonth = new Date(now.getFullYear(), now.getMonth(), 1);
  const startOfPrevMonth = new Date(now.getFullYear(), now.getMonth() - 1, 1);

  const [ledgerRes, subsRes, prevLedgerRes] = await Promise.all([
    supabase
      .from("coaching_financial_ledger")
      .select("amount")
      .eq("group_id", groupId)
      .eq("type", "revenue")
      .gte("created_at", startOfMonth.toISOString()),
    supabase
      .from("coaching_subscriptions")
      .select("status")
      .eq("group_id", groupId),
    supabase
      .from("coaching_financial_ledger")
      .select("amount")
      .eq("group_id", groupId)
      .eq("type", "revenue")
      .gte("created_at", startOfPrevMonth.toISOString())
      .lt("created_at", startOfMonth.toISOString()),
  ]);

  const revenueThisMonth = (ledgerRes.data ?? []).reduce(
    (sum, r) => sum + ((r as { amount: number }).amount ?? 0),
    0,
  );

  const prevRevenue = (prevLedgerRes.data ?? []).reduce(
    (sum, r) => sum + ((r as { amount: number }).amount ?? 0),
    0,
  );

  const allSubs = subsRes.data ?? [];
  const activeSubscribers = allSubs.filter(
    (s) => (s as { status: string }).status === "active",
  ).length;
  const lateSubscribers = allSubs.filter(
    (s) => (s as { status: string }).status === "late",
  ).length;

  const growthPct =
    prevRevenue > 0
      ? ((revenueThisMonth - prevRevenue) / prevRevenue) * 100
      : 0;

  return { revenueThisMonth, activeSubscribers, lateSubscribers, growthPct };
}

export default async function FinancialDashboardPage() {
  const groupId = cookies().get("portal_group_id")?.value;
  if (!groupId) return null;

  let kpis: FinancialKpis | null = null;
  let fetchError: string | null = null;

  try {
    kpis = await getFinancialKpis(groupId);
  } catch (e) {
    fetchError = String(e);
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-gray-900">Dashboard Financeiro</h1>
        <p className="mt-1 text-sm text-gray-500">
          Visão geral da saúde financeira do grupo
        </p>
      </div>

      {fetchError && (
        <div className="rounded-lg border border-red-200 bg-red-50 p-6 text-center">
          <p className="text-red-600">Erro ao carregar dados. Tente recarregar a página.</p>
        </div>
      )}

      {kpis && (
        <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
          <KpiCard
            label="Receita do Mês"
            value={`R$ ${kpis.revenueThisMonth.toFixed(2)}`}
            bg="bg-green-50"
            color="text-green-700"
          />
          <KpiCard
            label="Assinantes Ativos"
            value={kpis.activeSubscribers}
            bg="bg-blue-50"
            color="text-blue-700"
          />
          <KpiCard
            label="Inadimplentes"
            value={kpis.lateSubscribers}
            bg="bg-red-50"
            color="text-red-700"
          />
          <KpiCard
            label="Crescimento %"
            value={`${kpis.growthPct >= 0 ? "+" : ""}${kpis.growthPct.toFixed(1)}%`}
            bg="bg-purple-50"
            color="text-purple-700"
          />
        </div>
      )}

      <div className="grid gap-4 sm:grid-cols-2">
        <Link
          href="/financial/subscriptions"
          className="rounded-xl border border-gray-200 bg-white p-6 shadow-sm hover:border-blue-300 hover:shadow transition"
        >
          <h3 className="font-semibold text-gray-900">Assinaturas</h3>
          <p className="mt-1 text-sm text-gray-500">
            Gerencie assinaturas e status de pagamento dos atletas
          </p>
        </Link>
        <Link
          href="/financial/plans"
          className="rounded-xl border border-gray-200 bg-white p-6 shadow-sm hover:border-blue-300 hover:shadow transition"
        >
          <h3 className="font-semibold text-gray-900">Planos</h3>
          <p className="mt-1 text-sm text-gray-500">
            Configure planos, preços e ciclos de cobrança
          </p>
        </Link>
      </div>

      <div className="flex justify-end">
        <a
          href="/api/export/financial"
          className="rounded-lg border border-gray-300 bg-white px-3 py-1.5 text-xs font-medium text-gray-700 shadow-sm hover:bg-gray-50"
        >
          Exportar Ledger CSV
        </a>
      </div>
    </div>
  );
}

function KpiCard({
  label,
  value,
  bg = "bg-white",
  color = "text-gray-900",
}: {
  label: string;
  value: number | string;
  bg?: string;
  color?: string;
}) {
  return (
    <div className={`rounded-xl border border-gray-200 ${bg} p-4 shadow-sm`}>
      <p className="text-xs font-medium uppercase tracking-wide text-gray-500">
        {label}
      </p>
      <p className={`mt-1 text-xl font-bold ${color}`}>{value}</p>
    </div>
  );
}
