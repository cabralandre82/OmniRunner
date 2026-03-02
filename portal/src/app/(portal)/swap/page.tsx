import type { Metadata } from "next";
import { cookies } from "next/headers";
import { createServiceClient } from "@/lib/supabase/service";
import { SwapActions } from "./swap-actions";
import { formatUsd } from "@/lib/format";

export const metadata: Metadata = { title: "Swap de Lastro" };
export const dynamic = "force-dynamic";

interface SwapOrder {
  id: string;
  seller_group_id: string;
  buyer_group_id: string | null;
  amount_usd: number;
  fee_rate_pct: number;
  fee_amount_usd: number;
  status: string;
  created_at: string;
  settled_at: string | null;
}

const STATUS_LABELS: Record<string, { label: string; color: string }> = {
  open: { label: "Aberta", color: "bg-blue-100 text-blue-800" },
  matched: { label: "Aceita", color: "bg-yellow-100 text-yellow-800" },
  settled: { label: "Liquidada", color: "bg-green-100 text-green-800" },
  cancelled: { label: "Cancelada", color: "bg-gray-100 text-gray-600" },
};

export default async function SwapPage() {
  const groupId = cookies().get("portal_group_id")?.value;
  if (!groupId) return null;

  const db = createServiceClient();

  const [openRes, myRes, groupsRes, feeRes] = await Promise.all([
    db
      .from("swap_orders")
      .select("*")
      .eq("status", "open")
      .neq("seller_group_id", groupId)
      .order("created_at", { ascending: false })
      .limit(20),
    db
      .from("swap_orders")
      .select("*")
      .or(`seller_group_id.eq.${groupId},buyer_group_id.eq.${groupId}`)
      .order("created_at", { ascending: false })
      .limit(20),
    db.from("coaching_groups").select("id, name"),
    db
      .from("platform_fee_config")
      .select("rate_pct")
      .eq("fee_type", "swap")
      .eq("is_active", true)
      .maybeSingle(),
  ]);

  const openOffers: SwapOrder[] = openRes.data ?? [];
  const myOrders: SwapOrder[] = myRes.data ?? [];
  const groupMap = new Map(
    (groupsRes.data ?? []).map((g: { id: string; name: string }) => [g.id, g.name]),
  );
  const feeRate = feeRes.data?.rate_pct ?? 1.0;

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Swap de Lastro</h1>
          <p className="mt-1 text-sm text-gray-500">
            Mercado B2B de liquidez entre assessorias — Taxa: {feeRate}%
          </p>
        </div>
        <SwapActions groupId={groupId} />
      </div>

      {/* Available Offers */}
      <div className="rounded-xl border border-gray-200 bg-white shadow-sm">
        <div className="border-b border-gray-200 px-6 py-4">
          <h2 className="text-lg font-semibold text-gray-900">
            Ofertas Disponíveis
          </h2>
        </div>

        {openOffers.length === 0 ? (
          <div className="px-6 py-8 text-center text-gray-500">
            Nenhuma oferta disponível no momento.
          </div>
        ) : (
          <table className="min-w-full divide-y divide-gray-200">
            <thead className="bg-gray-50">
              <tr>
                <th className="px-6 py-3 text-left text-xs font-medium uppercase text-gray-500">
                  Vendedor
                </th>
                <th className="px-6 py-3 text-right text-xs font-medium uppercase text-gray-500">
                  Valor
                </th>
                <th className="px-6 py-3 text-right text-xs font-medium uppercase text-gray-500">
                  Taxa
                </th>
                <th className="px-6 py-3 text-right text-xs font-medium uppercase text-gray-500">
                  Custo Total
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium uppercase text-gray-500">
                  Data
                </th>
                <th className="px-6 py-3 text-right text-xs font-medium uppercase text-gray-500">
                  Ação
                </th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-200">
              {openOffers.map((o) => (
                <tr key={o.id}>
                  <td className="px-6 py-4 text-sm text-gray-900">
                    {groupMap.get(o.seller_group_id) ?? o.seller_group_id.slice(0, 8)}
                  </td>
                  <td className="whitespace-nowrap px-6 py-4 text-right text-sm font-medium text-gray-900">
                    {formatUsd(o.amount_usd)}
                  </td>
                  <td className="whitespace-nowrap px-6 py-4 text-right text-sm text-gray-500">
                    {formatUsd(o.fee_amount_usd)}
                  </td>
                  <td className="whitespace-nowrap px-6 py-4 text-right text-sm font-bold text-gray-900">
                    {formatUsd(o.amount_usd + o.fee_amount_usd)}
                  </td>
                  <td className="whitespace-nowrap px-6 py-4 text-sm text-gray-500">
                    {new Date(o.created_at).toLocaleDateString("pt-BR")}
                  </td>
                  <td className="whitespace-nowrap px-6 py-4 text-right">
                    <SwapActions groupId={groupId} acceptOrderId={o.id} />
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      {/* My Orders */}
      <div className="rounded-xl border border-gray-200 bg-white shadow-sm">
        <div className="border-b border-gray-200 px-6 py-4">
          <h2 className="text-lg font-semibold text-gray-900">Minhas Ordens</h2>
        </div>

        {myOrders.length === 0 ? (
          <div className="px-6 py-8 text-center text-gray-500">
            Nenhuma ordem registrada.
          </div>
        ) : (
          <table className="min-w-full divide-y divide-gray-200">
            <thead className="bg-gray-50">
              <tr>
                <th className="px-6 py-3 text-left text-xs font-medium uppercase text-gray-500">
                  Data
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium uppercase text-gray-500">
                  Tipo
                </th>
                <th className="px-6 py-3 text-right text-xs font-medium uppercase text-gray-500">
                  Valor
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium uppercase text-gray-500">
                  Contraparte
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium uppercase text-gray-500">
                  Status
                </th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-200">
              {myOrders.map((o) => {
                const isSeller = o.seller_group_id === groupId;
                const counterpartyId = isSeller
                  ? o.buyer_group_id
                  : o.seller_group_id;
                const st = STATUS_LABELS[o.status] ?? {
                  label: o.status,
                  color: "bg-gray-100 text-gray-600",
                };

                return (
                  <tr key={o.id}>
                    <td className="whitespace-nowrap px-6 py-4 text-sm text-gray-700">
                      {new Date(o.created_at).toLocaleDateString("pt-BR")}
                    </td>
                    <td className="px-6 py-4 text-sm">
                      <span
                        className={`font-medium ${isSeller ? "text-orange-600" : "text-blue-600"}`}
                      >
                        {isSeller ? "Venda" : "Compra"}
                      </span>
                    </td>
                    <td className="whitespace-nowrap px-6 py-4 text-right text-sm font-medium text-gray-900">
                      {formatUsd(o.amount_usd)}
                    </td>
                    <td className="px-6 py-4 text-sm text-gray-700">
                      {counterpartyId
                        ? groupMap.get(counterpartyId) ?? counterpartyId.slice(0, 8)
                        : "—"}
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
        )}
      </div>
    </div>
  );
}
