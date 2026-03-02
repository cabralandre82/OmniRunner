import type { Metadata } from "next";
import { cookies } from "next/headers";
import { createServiceClient } from "@/lib/supabase/service";
import { formatUsd } from "@/lib/format";

export const metadata: Metadata = { title: "Compensações" };
export const dynamic = "force-dynamic";

const STATUS_LABELS: Record<string, { label: string; color: string }> = {
  pending: { label: "Pendente", color: "bg-yellow-100 text-yellow-800" },
  settled: { label: "Liquidado", color: "bg-green-100 text-green-800" },
  insufficient: { label: "Saldo Insuficiente", color: "bg-red-100 text-red-800" },
  failed: { label: "Falhou", color: "bg-gray-100 text-gray-600" },
};

interface Settlement {
  id: string;
  creditor_group_id: string;
  debtor_group_id: string;
  coin_amount: number;
  gross_amount_usd: number;
  fee_rate_pct: number;
  fee_amount_usd: number;
  net_amount_usd: number;
  status: string;
  created_at: string;
  settled_at: string | null;
}

export default async function ClearingPage() {
  const groupId = cookies().get("portal_group_id")?.value;
  if (!groupId) return null;

  const db = createServiceClient();

  const [receivablesRes, payablesRes, groupsRes] = await Promise.all([
    db
      .from("clearing_settlements")
      .select("*")
      .eq("creditor_group_id", groupId)
      .order("created_at", { ascending: false })
      .limit(50),
    db
      .from("clearing_settlements")
      .select("*")
      .eq("debtor_group_id", groupId)
      .order("created_at", { ascending: false })
      .limit(50),
    db.from("coaching_groups").select("id, name"),
  ]);

  const receivables: Settlement[] = receivablesRes.data ?? [];
  const payables: Settlement[] = payablesRes.data ?? [];
  const groupMap = new Map(
    (groupsRes.data ?? []).map((g: { id: string; name: string }) => [g.id, g.name]),
  );

  const totalReceivable = receivables
    .filter((s) => s.status === "pending")
    .reduce((sum, s) => sum + s.net_amount_usd, 0);

  const totalPayable = payables
    .filter((s) => s.status === "pending")
    .reduce((sum, s) => sum + s.net_amount_usd, 0);

  const totalSettledIn = receivables
    .filter((s) => s.status === "settled")
    .reduce((sum, s) => sum + s.net_amount_usd, 0);

  const totalSettledOut = payables
    .filter((s) => s.status === "settled")
    .reduce((sum, s) => sum + s.net_amount_usd, 0);

  function renderTable(items: Settlement[], direction: "in" | "out") {
    if (items.length === 0) {
      return (
        <div className="px-6 py-8 text-center text-gray-500">
          Nenhuma compensação registrada.
        </div>
      );
    }

    return (
      <table className="min-w-full divide-y divide-gray-200">
        <thead className="bg-gray-50">
          <tr>
            <th className="px-6 py-3 text-left text-xs font-medium uppercase text-gray-500">
              Data
            </th>
            <th className="px-6 py-3 text-left text-xs font-medium uppercase text-gray-500">
              {direction === "in" ? "Emissor (devedor)" : "Resgatante (credor)"}
            </th>
            <th className="px-6 py-3 text-right text-xs font-medium uppercase text-gray-500">
              Coins
            </th>
            <th className="px-6 py-3 text-right text-xs font-medium uppercase text-gray-500">
              Bruto
            </th>
            <th className="px-6 py-3 text-right text-xs font-medium uppercase text-gray-500">
              Taxa
            </th>
            <th className="px-6 py-3 text-right text-xs font-medium uppercase text-gray-500">
              Líquido
            </th>
            <th className="px-6 py-3 text-left text-xs font-medium uppercase text-gray-500">
              Status
            </th>
          </tr>
        </thead>
        <tbody className="divide-y divide-gray-200">
          {items.map((s) => {
            const counterpartyId =
              direction === "in" ? s.debtor_group_id : s.creditor_group_id;
            const st = STATUS_LABELS[s.status] ?? {
              label: s.status,
              color: "bg-gray-100 text-gray-600",
            };

            return (
              <tr key={s.id}>
                <td className="whitespace-nowrap px-6 py-4 text-sm text-gray-700">
                  {new Date(s.created_at).toLocaleDateString("pt-BR", {
                    day: "2-digit",
                    month: "2-digit",
                    year: "2-digit",
                  })}
                </td>
                <td className="px-6 py-4 text-sm text-gray-900">
                  {groupMap.get(counterpartyId) ?? counterpartyId.slice(0, 8)}
                </td>
                <td className="whitespace-nowrap px-6 py-4 text-right text-sm text-gray-700">
                  {s.coin_amount.toLocaleString()}
                </td>
                <td className="whitespace-nowrap px-6 py-4 text-right text-sm text-gray-700">
                  {formatUsd(s.gross_amount_usd)}
                </td>
                <td className="whitespace-nowrap px-6 py-4 text-right text-sm text-gray-500">
                  {formatUsd(s.fee_amount_usd)} ({s.fee_rate_pct}%)
                </td>
                <td className="whitespace-nowrap px-6 py-4 text-right text-sm font-medium text-gray-900">
                  {formatUsd(s.net_amount_usd)}
                </td>
                <td className="whitespace-nowrap px-6 py-4">
                  <span
                    className={`inline-flex rounded-full px-2 py-1 text-xs font-medium ${st.color}`}
                  >
                    {st.label}
                  </span>
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
    );
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-gray-900">Compensações</h1>
        <p className="mt-1 text-sm text-gray-500">
          Clearing automático de coins interclub
        </p>
      </div>

      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <div className="rounded-xl border border-gray-200 bg-white p-5 shadow-sm">
          <p className="text-sm font-medium text-gray-500">A Receber (pendente)</p>
          <p className="mt-1 text-2xl font-bold text-green-600">
            {formatUsd(totalReceivable)}
          </p>
        </div>
        <div className="rounded-xl border border-gray-200 bg-white p-5 shadow-sm">
          <p className="text-sm font-medium text-gray-500">A Pagar (pendente)</p>
          <p className="mt-1 text-2xl font-bold text-red-600">
            {formatUsd(totalPayable)}
          </p>
        </div>
        <div className="rounded-xl border border-gray-200 bg-white p-5 shadow-sm">
          <p className="text-sm font-medium text-gray-500">Recebido (liquidado)</p>
          <p className="mt-1 text-2xl font-bold text-gray-900">
            {formatUsd(totalSettledIn)}
          </p>
        </div>
        <div className="rounded-xl border border-gray-200 bg-white p-5 shadow-sm">
          <p className="text-sm font-medium text-gray-500">Pago (liquidado)</p>
          <p className="mt-1 text-2xl font-bold text-gray-900">
            {formatUsd(totalSettledOut)}
          </p>
        </div>
      </div>

      {/* Receivables */}
      <div className="rounded-xl border border-gray-200 bg-white shadow-sm">
        <div className="border-b border-gray-200 px-6 py-4">
          <h2 className="text-lg font-semibold text-gray-900">
            Recebíveis (coins queimadas de outros emissores no seu clube)
          </h2>
        </div>
        {renderTable(receivables, "in")}
      </div>

      {/* Payables */}
      <div className="rounded-xl border border-gray-200 bg-white shadow-sm">
        <div className="border-b border-gray-200 px-6 py-4">
          <h2 className="text-lg font-semibold text-gray-900">
            Obrigações (suas coins queimadas em outros clubes)
          </h2>
        </div>
        {renderTable(payables, "out")}
      </div>
    </div>
  );
}
