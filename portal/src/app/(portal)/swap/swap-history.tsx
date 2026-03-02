"use client";

import { formatUsd } from "@/lib/format";
import { formatDateTimeTz } from "@/lib/export";
import { ExportButton } from "@/components/ui/export-button";

const STATUS_LABELS: Record<string, { label: string; color: string }> = {
  open: { label: "Aberta", color: "bg-blue-100 text-blue-800" },
  matched: { label: "Aceita", color: "bg-yellow-100 text-yellow-800" },
  settled: { label: "Liquidada", color: "bg-green-100 text-green-800" },
  cancelled: { label: "Cancelada", color: "bg-gray-100 text-gray-600" },
};

interface Props {
  orders: Record<string, unknown>[];
  groupMap: Record<string, string>;
  groupId: string;
}

export function SwapHistory({ orders, groupMap, groupId }: Props) {
  if (orders.length === 0) {
    return (
      <div className="rounded-xl border border-gray-200 bg-white px-6 py-12 text-center text-gray-500 shadow-sm">
        Nenhuma ordem registrada.
      </div>
    );
  }

  return (
    <div className="rounded-xl border border-gray-200 bg-white shadow-sm">
      <div className="flex items-center justify-between border-b border-gray-200 px-6 py-4">
        <h2 className="text-lg font-semibold text-gray-900">Historico de Swaps</h2>
        <ExportButton
          filename={`swaps-${new Date().toISOString().slice(0, 10)}`}
          headers={["Data", "Tipo", "Bruto USD", "Taxa USD", "Liquido USD", "Contraparte", "Status", "Swap ID"]}
          rows={orders.map((o) => {
            const isSeller = o.seller_group_id === groupId;
            const cp = isSeller ? o.buyer_group_id : o.seller_group_id;
            return [
              formatDateTimeTz(o.created_at as string),
              isSeller ? "Venda" : "Compra",
              o.amount_usd as number,
              o.fee_amount_usd as number,
              (o.amount_usd as number) - (o.fee_amount_usd as number),
              cp ? groupMap[cp as string] ?? (cp as string).slice(0, 8) : "-",
              o.status as string,
              o.id as string,
            ];
          })}
        />
      </div>
      <table className="min-w-full divide-y divide-gray-200">
        <thead className="bg-gray-50">
          <tr>
            <th className="px-6 py-3 text-left text-xs font-medium uppercase text-gray-500">Data</th>
            <th className="px-6 py-3 text-left text-xs font-medium uppercase text-gray-500">Tipo</th>
            <th className="px-6 py-3 text-right text-xs font-medium uppercase text-gray-500">Bruto</th>
            <th className="px-6 py-3 text-right text-xs font-medium uppercase text-gray-500">Taxa</th>
            <th className="px-6 py-3 text-right text-xs font-medium uppercase text-gray-500">Liquido</th>
            <th className="px-6 py-3 text-left text-xs font-medium uppercase text-gray-500">Contraparte</th>
            <th className="px-6 py-3 text-left text-xs font-medium uppercase text-gray-500">Status</th>
            <th className="px-6 py-3 text-left text-xs font-medium uppercase text-gray-500">Swap ID</th>
          </tr>
        </thead>
        <tbody className="divide-y divide-gray-200">
          {orders.map((o) => {
            const isSeller = o.seller_group_id === groupId;
            const cp = isSeller ? o.buyer_group_id : o.seller_group_id;
            const st = STATUS_LABELS[(o.status as string)] ?? { label: o.status as string, color: "bg-gray-100 text-gray-600" };
            const fee = (o.fee_amount_usd as number) ?? 0;

            return (
              <tr key={o.id as string}>
                <td className="whitespace-nowrap px-6 py-3 text-sm text-gray-700">{formatDateTimeTz(o.created_at as string)}</td>
                <td className="px-6 py-3 text-sm">
                  <span className={`font-medium ${isSeller ? "text-orange-600" : "text-blue-600"}`}>
                    {isSeller ? "Venda" : "Compra"}
                  </span>
                </td>
                <td className="whitespace-nowrap px-6 py-3 text-right text-sm font-medium text-gray-900">{formatUsd(o.amount_usd as number)}</td>
                <td className="whitespace-nowrap px-6 py-3 text-right text-sm text-gray-500">{formatUsd(fee)}</td>
                <td className="whitespace-nowrap px-6 py-3 text-right text-sm font-medium text-gray-900">
                  {formatUsd((o.amount_usd as number) - fee)}
                </td>
                <td className="px-6 py-3 text-sm text-gray-700">
                  {cp ? groupMap[cp as string] ?? (cp as string).slice(0, 8) : "-"}
                </td>
                <td className="px-6 py-3">
                  <span className={`inline-flex rounded-full px-2 py-0.5 text-xs font-medium ${st.color}`}>{st.label}</span>
                </td>
                <td className="px-6 py-3 text-sm font-mono text-xs text-gray-500">{(o.id as string).slice(0, 8)}</td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}
