import { cookies } from "next/headers";
import { createClient } from "@/lib/supabase/server";
import { NoGroupSelected } from "@/components/no-group-selected";
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
  if (!groupId) return <NoGroupSelected />;

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
        <h1 className="text-2xl font-bold text-content-primary">Dashboard Financeiro</h1>
        <p className="mt-1 text-sm text-content-secondary">
          Visão geral da saúde financeira do grupo
        </p>
      </div>

      {fetchError && (
        <div className="rounded-lg border border-error/30 bg-error-soft p-6 text-center">
          <p className="text-error">Erro ao carregar dados. Tente recarregar a página.</p>
        </div>
      )}

      {kpis && (
        <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
          <KpiCard
            label="Receita do Mês"
            value={`R$ ${kpis.revenueThisMonth.toFixed(2)}`}
            bg="bg-success-soft"
            color="text-success"
          />
          <KpiCard
            label="Assinantes Ativos"
            value={kpis.activeSubscribers}
            bg="bg-brand-soft"
            color="text-brand"
          />
          <KpiCard
            label="Inadimplentes"
            value={kpis.lateSubscribers}
            bg="bg-error-soft"
            color="text-error"
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
          className="rounded-xl border border-border bg-surface p-6 shadow-sm hover:border-blue-300 hover:shadow transition"
        >
          <h3 className="font-semibold text-content-primary">Assinaturas</h3>
          <p className="mt-1 text-sm text-content-secondary">
            Gerencie assinaturas e status de pagamento dos atletas
          </p>
        </Link>
        <Link
          href="/financial/plans"
          className="rounded-xl border border-border bg-surface p-6 shadow-sm hover:border-blue-300 hover:shadow transition"
        >
          <h3 className="font-semibold text-content-primary">Planos</h3>
          <p className="mt-1 text-sm text-content-secondary">
            Configure planos, preços e ciclos de cobrança
          </p>
        </Link>
      </div>

      <div className="flex justify-end">
        <a
          href="/api/export/financial"
          className="rounded-lg border border-border bg-surface px-3 py-1.5 text-xs font-medium text-content-secondary shadow-sm hover:bg-surface-elevated"
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
  bg = "bg-surface",
  color = "text-content-primary",
}: {
  label: string;
  value: number | string;
  bg?: string;
  color?: string;
}) {
  return (
    <div className={`rounded-xl border border-border ${bg} p-4 shadow-sm`}>
      <p className="text-xs font-medium uppercase tracking-wide text-content-secondary">
        {label}
      </p>
      <p className={`mt-1 text-xl font-bold ${color}`}>{value}</p>
    </div>
  );
}
