import { createClient } from "@/lib/supabase/server";
import Link from "next/link";

export const dynamic = "force-dynamic";

interface Purchase {
  id: string;
  group_id: string;
  credits_amount: number;
  price_cents: number;
  currency: string;
  status: string;
  payment_method: string | null;
  source: string;
  created_at: string;
  group_name?: string;
}

export default async function FinanceiroPage({
  searchParams,
}: {
  searchParams: { status?: string; period?: string };
}) {
  const supabase = createClient();
  const filterStatus = searchParams.status;
  const filterPeriod = searchParams.period;

  let query = supabase
    .from("billing_purchases")
    .select(
      "id, group_id, credits_amount, price_cents, currency, status, payment_method, source, created_at",
    )
    .order("created_at", { ascending: false });

  if (filterStatus && filterStatus !== "all") {
    query = query.eq("status", filterStatus);
  }

  if (filterPeriod === "month") {
    const start = new Date();
    start.setDate(1);
    start.setHours(0, 0, 0, 0);
    query = query.gte("created_at", start.toISOString());
  } else if (filterPeriod === "week") {
    const start = new Date();
    start.setDate(start.getDate() - 7);
    query = query.gte("created_at", start.toISOString());
  }

  const { data: rawPurchases } = await query;

  const groupIds = Array.from(new Set((rawPurchases ?? []).map((p) => p.group_id)));
  const groupMap: Record<string, string> = {};
  if (groupIds.length > 0) {
    const { data: groups } = await supabase
      .from("coaching_groups")
      .select("id, name")
      .in("id", groupIds);
    for (const g of groups ?? []) {
      groupMap[g.id] = g.name;
    }
  }

  const purchases: Purchase[] = (rawPurchases ?? []).map((p) => ({
    ...p,
    group_name: groupMap[p.group_id] ?? "—",
  }));

  const totalRevenue = purchases
    .filter((p) => p.status === "fulfilled")
    .reduce((s, p) => s + p.price_cents, 0);
  const totalPending = purchases
    .filter((p) => p.status === "pending" || p.status === "paid")
    .reduce((s, p) => s + p.price_cents, 0);

  const fmt = (cents: number) =>
    (cents / 100).toLocaleString("pt-BR", {
      style: "currency",
      currency: "BRL",
    });

  const statusLabel: Record<string, string> = {
    pending: "Pendente",
    paid: "Pago",
    fulfilled: "Entregue",
    cancelled: "Cancelado",
    refunded: "Reembolsado",
  };

  const statusColor: Record<string, string> = {
    pending: "bg-orange-100 text-orange-700",
    paid: "bg-blue-100 text-blue-700",
    fulfilled: "bg-green-100 text-green-700",
    cancelled: "bg-gray-200 text-gray-600",
    refunded: "bg-red-100 text-red-700",
  };

  const statuses = ["all", "pending", "paid", "fulfilled", "cancelled", "refunded"];
  const periods = [
    { key: "all", label: "Todas" },
    { key: "week", label: "7 dias" },
    { key: "month", label: "Este mês" },
  ];

  return (
    <div className="space-y-6">
      <div className="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Financeiro</h1>
          <p className="mt-1 text-sm text-gray-500">
            Todas as compras de créditos das assessorias
          </p>
        </div>
        <Link
          href="/platform"
          className="text-sm text-gray-500 hover:text-gray-700"
        >
          ← Dashboard
        </Link>
      </div>

      {/* Revenue cards */}
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 sm:gap-4">
        <div className="rounded-xl border border-gray-200 bg-emerald-50 p-5 shadow-sm">
          <p className="text-xs font-medium uppercase tracking-wide text-gray-500">
            Receita (filtro atual)
          </p>
          <p className="mt-2 text-2xl font-bold text-emerald-600">
            {fmt(totalRevenue)}
          </p>
        </div>
        <div className="rounded-xl border border-gray-200 bg-orange-50 p-5 shadow-sm">
          <p className="text-xs font-medium uppercase tracking-wide text-gray-500">
            Pendente
          </p>
          <p className="mt-2 text-2xl font-bold text-orange-600">
            {fmt(totalPending)}
          </p>
        </div>
        <div className="rounded-xl border border-gray-200 bg-gray-50 p-5 shadow-sm">
          <p className="text-xs font-medium uppercase tracking-wide text-gray-500">
            Compras
          </p>
          <p className="mt-2 text-2xl font-bold text-gray-700">
            {purchases.length}
          </p>
        </div>
      </div>

      {/* Filters */}
      <div className="flex flex-wrap gap-4">
        <div className="flex flex-wrap gap-1.5">
          <span className="self-center text-xs font-medium text-gray-500 mr-1">
            Status:
          </span>
          {statuses.map((s) => {
            const active =
              (filterStatus ?? "all") === s || (!filterStatus && s === "all");
            return (
              <Link
                key={s}
                href={`/platform/financeiro?status=${s}&period=${filterPeriod ?? "all"}`}
                className={`rounded-full px-3 py-1 text-xs font-medium transition ${
                  active
                    ? "bg-gray-900 text-white"
                    : "bg-gray-100 text-gray-600 hover:bg-gray-200"
                }`}
              >
                {statusLabel[s] ?? "Todos"}
              </Link>
            );
          })}
        </div>
        <div className="flex flex-wrap gap-1.5">
          <span className="self-center text-xs font-medium text-gray-500 mr-1">
            Período:
          </span>
          {periods.map((p) => {
            const active =
              (filterPeriod ?? "all") === p.key ||
              (!filterPeriod && p.key === "all");
            return (
              <Link
                key={p.key}
                href={`/platform/financeiro?status=${filterStatus ?? "all"}&period=${p.key}`}
                className={`rounded-full px-3 py-1 text-xs font-medium transition ${
                  active
                    ? "bg-gray-900 text-white"
                    : "bg-gray-100 text-gray-600 hover:bg-gray-200"
                }`}
              >
                {p.label}
              </Link>
            );
          })}
        </div>
      </div>

      {/* Table */}
      {purchases.length === 0 ? (
        <div className="py-16 text-center">
          <p className="text-sm text-gray-400">
            Nenhuma compra encontrada com esses filtros.
          </p>
        </div>
      ) : (
        <div className="overflow-x-auto rounded-xl border border-gray-200 bg-white shadow-sm">
          <table className="min-w-full text-sm">
            <thead>
              <tr className="border-b border-gray-100 bg-gray-50 text-left">
                <th className="px-4 py-3 font-medium text-gray-500">Assessoria</th>
                <th className="px-4 py-3 font-medium text-gray-500">Créditos</th>
                <th className="px-4 py-3 font-medium text-gray-500">Valor</th>
                <th className="px-4 py-3 font-medium text-gray-500">Status</th>
                <th className="px-4 py-3 font-medium text-gray-500">Método</th>
                <th className="px-4 py-3 font-medium text-gray-500">Origem</th>
                <th className="px-4 py-3 font-medium text-gray-500">Data</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {purchases.map((p) => (
                <tr key={p.id} className="hover:bg-gray-50">
                  <td className="px-4 py-3 font-medium text-gray-900">
                    {p.group_name}
                  </td>
                  <td className="px-4 py-3 text-gray-700">
                    {p.credits_amount}
                  </td>
                  <td className="px-4 py-3 text-gray-700">
                    {fmt(p.price_cents)}
                  </td>
                  <td className="px-4 py-3">
                    <span
                      className={`rounded-full px-2 py-0.5 text-xs font-medium ${
                        statusColor[p.status] ?? "bg-gray-100"
                      }`}
                    >
                      {statusLabel[p.status] ?? p.status}
                    </span>
                  </td>
                  <td className="px-4 py-3 text-gray-500">
                    {p.payment_method ?? "—"}
                  </td>
                  <td className="px-4 py-3 text-gray-500">
                    {p.source === "auto_topup" ? "Auto" : "Manual"}
                  </td>
                  <td className="px-4 py-3 text-gray-500">
                    {new Date(p.created_at).toLocaleDateString("pt-BR", {
                      day: "2-digit",
                      month: "short",
                      year: "numeric",
                    })}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
