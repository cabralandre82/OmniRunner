import { cookies } from "next/headers";
import { createClient } from "@/lib/supabase/server";
import { trackBillingEvent } from "@/lib/analytics";
import { formatBRL, formatDateTime } from "@/lib/format";

export const dynamic = "force-dynamic";
import Link from "next/link";

const STATUS_LABELS: Record<string, { label: string; color: string }> = {
  pending:   { label: "Pendente",   color: "bg-yellow-100 text-yellow-800" },
  paid:      { label: "Pago",       color: "bg-blue-100 text-blue-800" },
  fulfilled: { label: "Concluído",  color: "bg-green-100 text-green-800" },
  cancelled: { label: "Cancelado",  color: "bg-gray-100 text-gray-500" },
};

const METHOD_LABELS: Record<string, string> = {
  card:   "Cartão",
  pix:    "Pix",
  boleto: "Boleto",
};

const formatDate = formatDateTime;

interface Purchase {
  id: string;
  credits_amount: number;
  price_cents: number;
  currency: string;
  status: string;
  payment_method: string | null;
  payment_reference: string | null;
  invoice_url: string | null;
  created_at: string;
  updated_at: string;
}

interface SummaryByStatus {
  status: string;
  count: number;
  total_cents: number;
  total_credits: number;
}

export default async function BillingPage() {
  // LEGACY: Deprecated in favor of Custody model (ADR-007).
  const { isFeatureEnabled } = await import("@/lib/feature-flags");
  const legacyEnabled = await isFeatureEnabled("legacy_billing_enabled");
  if (!legacyEnabled) {
    const { redirect } = await import("next/navigation");
    redirect("/custody");
  }

  const groupId = cookies().get("portal_group_id")?.value;
  if (!groupId) return null;

  const supabase = createClient();

  const { data: purchases, count } = await supabase
    .from("billing_purchases")
    .select("id, credits_amount, price_cents, currency, status, payment_method, payment_reference, invoice_url, created_at, updated_at", { count: "exact" })
    .eq("group_id", groupId)
    .order("created_at", { ascending: false })
    .limit(50);

  const rows = (purchases ?? []) as Purchase[];

  await trackBillingEvent("billing_purchases_viewed", {
    group_id: groupId,
    total_count: count ?? 0,
  });

  const summary = rows.reduce<Record<string, SummaryByStatus>>((acc, p) => {
    if (!acc[p.status]) {
      acc[p.status] = { status: p.status, count: 0, total_cents: 0, total_credits: 0 };
    }
    acc[p.status].count++;
    acc[p.status].total_cents += p.price_cents;
    acc[p.status].total_credits += p.credits_amount;
    return acc;
  }, {});

  const totalPaid = (summary["paid"]?.total_cents ?? 0) + (summary["fulfilled"]?.total_cents ?? 0);
  const totalCredits = (summary["paid"]?.total_credits ?? 0) + (summary["fulfilled"]?.total_credits ?? 0);

  return (
    <div className="space-y-8">
      <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Faturamento</h1>
          <p className="mt-1 text-sm text-gray-500">
            Histórico de compras e recibos da assessoria
          </p>
        </div>
        <Link
          href="/credits"
          className="inline-flex items-center gap-2 rounded-lg bg-blue-600 px-4 py-2.5 text-sm font-medium text-white shadow-sm transition hover:bg-blue-700"
        >
          Adquirir Créditos
        </Link>
      </div>

      {/* Summary cards */}
      <div className="grid gap-4 sm:grid-cols-3">
        <div className="rounded-xl border border-gray-200 bg-white p-5 shadow-sm">
          <p className="text-xs font-medium uppercase tracking-wide text-gray-500">Total Compras</p>
          <p className="mt-2 text-2xl font-bold text-gray-900">{count ?? 0}</p>
        </div>
        <div className="rounded-xl border border-gray-200 bg-white p-5 shadow-sm">
          <p className="text-xs font-medium uppercase tracking-wide text-gray-500">Total Pago</p>
          <p className="mt-2 text-2xl font-bold text-gray-900">{formatBRL(totalPaid)}</p>
        </div>
        <div className="rounded-xl border border-gray-200 bg-white p-5 shadow-sm">
          <p className="text-xs font-medium uppercase tracking-wide text-gray-500">Créditos Adquiridos</p>
          <p className="mt-2 text-2xl font-bold text-gray-900">{totalCredits.toLocaleString("pt-BR")}</p>
          <p className="mt-1 text-xs text-gray-400">OmniCoins</p>
        </div>
      </div>

      {/* Status breakdown */}
      {Object.keys(summary).length > 0 && (
        <div className="flex flex-wrap gap-3">
          {Object.values(summary).map((s) => {
            const cfg = STATUS_LABELS[s.status] ?? { label: s.status, color: "bg-gray-100 text-gray-600" };
            return (
              <span
                key={s.status}
                className={`inline-flex items-center gap-1.5 rounded-full px-3 py-1 text-xs font-medium ${cfg.color}`}
              >
                {cfg.label}: {s.count}
              </span>
            );
          })}
        </div>
      )}

      {/* Purchases table */}
      {rows.length === 0 ? (
        <div className="rounded-xl border border-gray-200 bg-white p-8 text-center shadow-sm">
          <p className="text-sm text-gray-500">Nenhuma compra registrada.</p>
          <Link
            href="/credits"
            className="mt-3 inline-block text-sm font-medium text-blue-600 hover:text-blue-700"
          >
            Adquirir créditos
          </Link>
        </div>
      ) : (
        <div className="overflow-hidden rounded-xl border border-gray-200 bg-white shadow-sm">
          <div className="overflow-x-auto">
            <table className="min-w-full divide-y divide-gray-200 text-sm">
              <thead className="bg-gray-50">
                <tr>
                  <th className="px-4 py-3 text-left font-medium text-gray-500">Data</th>
                  <th className="px-4 py-3 text-left font-medium text-gray-500">Créditos</th>
                  <th className="px-4 py-3 text-left font-medium text-gray-500">Valor</th>
                  <th className="px-4 py-3 text-left font-medium text-gray-500">Método</th>
                  <th className="px-4 py-3 text-left font-medium text-gray-500">Status</th>
                  <th className="px-4 py-3 text-left font-medium text-gray-500">Recibo</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {rows.map((p) => {
                  const cfg = STATUS_LABELS[p.status] ?? { label: p.status, color: "bg-gray-100 text-gray-600" };
                  const method = p.payment_method ? (METHOD_LABELS[p.payment_method] ?? p.payment_method) : "—";

                  return (
                    <tr key={p.id} className="hover:bg-gray-50">
                      <td className="whitespace-nowrap px-4 py-3 text-gray-700">
                        {formatDate(p.created_at)}
                      </td>
                      <td className="whitespace-nowrap px-4 py-3 font-medium text-gray-900">
                        {p.credits_amount.toLocaleString("pt-BR")}
                      </td>
                      <td className="whitespace-nowrap px-4 py-3 text-gray-700">
                        {formatBRL(p.price_cents)}
                      </td>
                      <td className="whitespace-nowrap px-4 py-3 text-gray-600">
                        {method}
                      </td>
                      <td className="whitespace-nowrap px-4 py-3">
                        <span className={`inline-flex rounded-full px-2.5 py-0.5 text-xs font-medium ${cfg.color}`}>
                          {cfg.label}
                        </span>
                      </td>
                      <td className="whitespace-nowrap px-4 py-3">
                        {p.invoice_url ? (
                          <a
                            href={p.invoice_url}
                            target="_blank"
                            rel="noopener noreferrer"
                            className="text-blue-600 hover:text-blue-700 hover:underline"
                          >
                            Ver recibo
                          </a>
                        ) : p.status === "pending" ? (
                          <span className="text-gray-400">Aguardando</span>
                        ) : (
                          <span className="text-gray-400">—</span>
                        )}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </div>
  );
}
