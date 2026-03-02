import type { Metadata } from "next";
import { cookies } from "next/headers";
import { createServiceClient } from "@/lib/supabase/service";
import { formatUsd } from "@/lib/format";
import { WithdrawButton } from "./withdraw-button";
import { FxSimulator } from "./fx-simulator";

export const metadata: Metadata = { title: "Conversao Cambial" };
export const dynamic = "force-dynamic";

const STATUS_LABELS: Record<string, { label: string; color: string }> = {
  pending: { label: "Pendente", color: "bg-yellow-100 text-yellow-800" },
  processing: { label: "Processando", color: "bg-blue-100 text-blue-800" },
  completed: { label: "Concluido", color: "bg-green-100 text-green-800" },
  failed: { label: "Falhou", color: "bg-red-100 text-red-800" },
  cancelled: { label: "Cancelado", color: "bg-gray-100 text-gray-600" },
  confirmed: { label: "Confirmado", color: "bg-green-100 text-green-800" },
};

interface FxOperation {
  id: string;
  type: "deposit" | "withdrawal";
  amount_usd: number;
  original_currency?: string;
  original_amount?: number;
  target_currency?: string;
  fx_rate: number;
  fx_spread_pct: number;
  fx_spread_usd?: number;
  provider_fee_usd?: number;
  net_local_amount?: number;
  status: string;
  created_at: string;
}

export default async function FxPage() {
  const groupId = cookies().get("portal_group_id")?.value;
  if (!groupId) return null;

  const db = createServiceClient();

  const [depositsRes, withdrawalsRes, feeRes, accountRes] = await Promise.all([
    db
      .from("custody_deposits")
      .select("*")
      .eq("group_id", groupId)
      .order("created_at", { ascending: false })
      .limit(30),
    db
      .from("custody_withdrawals")
      .select("*")
      .eq("group_id", groupId)
      .order("created_at", { ascending: false })
      .limit(30),
    db
      .from("platform_fee_config")
      .select("rate_pct")
      .eq("fee_type", "fx_spread")
      .eq("is_active", true)
      .maybeSingle(),
    db
      .from("custody_accounts")
      .select("total_deposited_usd, total_committed")
      .eq("group_id", groupId)
      .maybeSingle(),
  ]);

  const fxDeposits: FxOperation[] = (depositsRes.data ?? [])
    .filter((d: Record<string, unknown>) => d.original_currency && d.original_currency !== "USD")
    .map((d: Record<string, unknown>) => ({
      id: d.id as string,
      type: "deposit" as const,
      amount_usd: d.amount_usd as number,
      original_currency: d.original_currency as string,
      original_amount: d.original_amount as number | undefined,
      fx_rate: (d.fx_rate as number) ?? 1,
      fx_spread_pct: (d.fx_spread_pct as number) ?? 0,
      status: d.status as string,
      created_at: d.created_at as string,
    }));

  const withdrawals: FxOperation[] = (withdrawalsRes.data ?? []).map(
    (w: Record<string, unknown>) => ({
      id: w.id as string,
      type: "withdrawal" as const,
      amount_usd: w.amount_usd as number,
      target_currency: (w.target_currency as string) ?? "BRL",
      fx_rate: w.fx_rate as number,
      fx_spread_pct: w.fx_spread_pct as number,
      fx_spread_usd: w.fx_spread_usd as number,
      provider_fee_usd: w.provider_fee_usd as number,
      net_local_amount: w.net_local_amount as number,
      status: w.status as string,
      created_at: w.created_at as string,
    }),
  );

  const allOps = [...fxDeposits, ...withdrawals].sort(
    (a, b) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime(),
  );

  const spreadRate = feeRes.data?.rate_pct ?? 0.75;
  const deposited = accountRes.data?.total_deposited_usd ?? 0;
  const committed = accountRes.data?.total_committed ?? 0;
  const available = deposited - committed;

  const totalSpreadPaid = withdrawals.reduce((sum, w) => sum + (w.fx_spread_usd ?? 0), 0);
  const totalProviderFees = withdrawals.reduce((sum, w) => sum + (w.provider_fee_usd ?? 0), 0);

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Conversao Cambial (FX)</h1>
          <p className="mt-1 text-sm text-gray-500">
            Spread atual: {spreadRate}% &mdash; Depositos com FX e retiradas em moeda local
          </p>
        </div>
        <WithdrawButton available={available} />
      </div>

      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <div className="rounded-xl border border-gray-200 bg-white p-5 shadow-sm">
          <p className="text-sm font-medium text-gray-500">Disponivel para Retirada</p>
          <p className={`mt-1 text-2xl font-bold ${available > 0 ? "text-green-600" : "text-red-600"}`}>
            {formatUsd(available)}
          </p>
        </div>
        <div className="rounded-xl border border-gray-200 bg-white p-5 shadow-sm">
          <p className="text-sm font-medium text-gray-500">Spread Atual</p>
          <p className="mt-1 text-2xl font-bold text-gray-900">{spreadRate}%</p>
        </div>
        <div className="rounded-xl border border-gray-200 bg-white p-5 shadow-sm">
          <p className="text-sm font-medium text-gray-500">Spread Pago (total)</p>
          <p className="mt-1 text-2xl font-bold text-orange-600">{formatUsd(totalSpreadPaid)}</p>
        </div>
        <div className="rounded-xl border border-gray-200 bg-white p-5 shadow-sm">
          <p className="text-sm font-medium text-gray-500">Taxas de Provedor</p>
          <p className="mt-1 text-2xl font-bold text-gray-600">{formatUsd(totalProviderFees)}</p>
        </div>
      </div>

      <div className="rounded-xl border border-gray-200 bg-white shadow-sm">
        <div className="border-b border-gray-200 px-6 py-4">
          <h2 className="text-lg font-semibold text-gray-900">Historico de Operacoes FX</h2>
        </div>

        {allOps.length === 0 ? (
          <div className="px-6 py-12 text-center text-gray-500">
            Nenhuma operacao de conversao cambial registrada.
          </div>
        ) : (
          <table className="min-w-full divide-y divide-gray-200">
            <thead className="bg-gray-50">
              <tr>
                <th className="px-6 py-3 text-left text-xs font-medium uppercase text-gray-500">Data</th>
                <th className="px-6 py-3 text-left text-xs font-medium uppercase text-gray-500">Tipo</th>
                <th className="px-6 py-3 text-right text-xs font-medium uppercase text-gray-500">USD</th>
                <th className="px-6 py-3 text-left text-xs font-medium uppercase text-gray-500">Moeda</th>
                <th className="px-6 py-3 text-right text-xs font-medium uppercase text-gray-500">Cotacao</th>
                <th className="px-6 py-3 text-right text-xs font-medium uppercase text-gray-500">Spread</th>
                <th className="px-6 py-3 text-right text-xs font-medium uppercase text-gray-500">Valor Local</th>
                <th className="px-6 py-3 text-left text-xs font-medium uppercase text-gray-500">Status</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-200">
              {allOps.map((op) => {
                const st = STATUS_LABELS[op.status] ?? { label: op.status, color: "bg-gray-100 text-gray-600" };
                const currency = op.type === "deposit" ? op.original_currency : op.target_currency;
                const localAmount = op.type === "deposit" ? op.original_amount : op.net_local_amount;

                return (
                  <tr key={op.id}>
                    <td className="whitespace-nowrap px-6 py-4 text-sm text-gray-700">
                      {new Date(op.created_at).toLocaleDateString("pt-BR", {
                        day: "2-digit", month: "2-digit", year: "2-digit", hour: "2-digit", minute: "2-digit",
                      })}
                    </td>
                    <td className="px-6 py-4 text-sm">
                      <span className={`font-medium ${op.type === "deposit" ? "text-green-600" : "text-orange-600"}`}>
                        {op.type === "deposit" ? "Entrada" : "Saida"}
                      </span>
                    </td>
                    <td className="whitespace-nowrap px-6 py-4 text-right text-sm font-medium text-gray-900">
                      {formatUsd(op.amount_usd)}
                    </td>
                    <td className="px-6 py-4 text-sm text-gray-700">{currency ?? "USD"}</td>
                    <td className="whitespace-nowrap px-6 py-4 text-right text-sm text-gray-700">
                      {op.fx_rate?.toFixed(4) ?? "-"}
                    </td>
                    <td className="whitespace-nowrap px-6 py-4 text-right text-sm text-gray-500">
                      {op.fx_spread_pct}%
                      {op.fx_spread_usd != null && (
                        <span className="ml-1 text-xs text-gray-400">({formatUsd(op.fx_spread_usd)})</span>
                      )}
                    </td>
                    <td className="whitespace-nowrap px-6 py-4 text-right text-sm text-gray-700">
                      {localAmount != null
                        ? localAmount.toLocaleString("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 2 })
                        : "-"}
                    </td>
                    <td className="whitespace-nowrap px-6 py-4">
                      <span className={`inline-flex rounded-full px-2 py-1 text-xs font-medium ${st.color}`}>
                        {st.label}
                      </span>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        )}
      </div>

      <FxSimulator spreadRate={spreadRate} />

      <div className="rounded-xl border border-gray-200 bg-white p-6 shadow-sm">
        <h2 className="text-lg font-semibold text-gray-900">Politica de Cambio</h2>
        <div className="mt-3 space-y-2 text-sm text-gray-600">
          <p><strong>Cotacao:</strong> Determinada pela cotacao de referencia do provedor no momento da operacao.</p>
          <p><strong>Travamento:</strong> A cotacao e travada no momento da confirmacao pelo gateway.</p>
          <p><strong>Spread:</strong> Aplicado sobre o valor convertido. Configuravel pela plataforma.</p>
          <p><strong>SLA:</strong> Depositos confirmados em ate 5s apos webhook. Retiradas em ate 2 dias uteis.</p>
        </div>
      </div>
    </div>
  );
}
