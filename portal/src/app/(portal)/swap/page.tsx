import type { Metadata } from "next";
import { cookies } from "next/headers";
import { createClient } from "@/lib/supabase/server";
import { NoGroupSelected } from "@/components/no-group-selected";
import { SwapActions } from "./swap-actions";
import { SwapHistory } from "./swap-history";
import { formatUsd } from "@/lib/format";

export const metadata: Metadata = { title: "Swap de Lastro" };
export const dynamic = "force-dynamic";

export default async function SwapPage() {
  const groupId = cookies().get("portal_group_id")?.value;
  if (!groupId) return <NoGroupSelected />;

  try {
  const db = createClient();

  const [openRes, myRes, feeRes, accountRes] = await Promise.all([
    db.from("swap_orders").select("id, seller_group_id, buyer_group_id, amount_usd, fee_amount_usd, status, created_at").eq("status", "open").neq("seller_group_id", groupId).order("created_at", { ascending: false }).limit(20),
    db.from("swap_orders").select("id, seller_group_id, buyer_group_id, amount_usd, fee_amount_usd, status, created_at").or(`seller_group_id.eq.${groupId},buyer_group_id.eq.${groupId}`).order("created_at", { ascending: false }).limit(50),
    db.from("platform_fee_config").select("rate_pct").eq("fee_type", "swap").eq("is_active", true).maybeSingle(),
    db.from("custody_accounts").select("total_deposited_usd, total_committed").eq("group_id", groupId).maybeSingle(),
  ]);

  const openOffers = openRes.data ?? [];
  const myOrders = myRes.data ?? [];

  const referencedGroupIds = Array.from(new Set([
    ...openOffers.map((o) => o.seller_group_id as string),
    ...openOffers.map((o) => o.buyer_group_id as string),
    ...myOrders.map((o) => o.seller_group_id as string),
    ...myOrders.map((o) => o.buyer_group_id as string),
  ].filter((id): id is string => !!id && id !== groupId)));

  let groupMap: Record<string, string> = {};
  if (referencedGroupIds.length > 0) {
    const groupsRes = await db.from("coaching_groups").select("id, name").in("id", referencedGroupIds);
    groupMap = Object.fromEntries(
      (groupsRes.data ?? []).map((g: { id: string; name: string }) => [g.id, g.name]),
    );
  }
  const feeRate = feeRes.data?.rate_pct ?? 1.0;
  const deposited = accountRes.data?.total_deposited_usd ?? 0;
  const committed = accountRes.data?.total_committed ?? 0;
  const available = deposited - committed;

  const now = Date.now();
  const d7 = now - 7 * 86400000;
  const d30 = now - 30 * 86400000;
  const vol7d = myOrders.filter((o) => o.status === "settled" && new Date(o.created_at).getTime() > d7).reduce((s: number, o) => s + (o.amount_usd ?? 0), 0);
  const vol30d = myOrders.filter((o) => o.status === "settled" && new Date(o.created_at).getTime() > d30).reduce((s: number, o) => s + (o.amount_usd ?? 0), 0);
  const feesPaid = myOrders.filter((o) => o.status === "settled" && o.seller_group_id === groupId).reduce((s: number, o) => s + (o.fee_amount_usd ?? 0), 0);
  const openCount = openOffers.length;
  const bestOffer = openOffers.length > 0 ? Math.min(...openOffers.map((o) => o.amount_usd as number)) : 0;

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-content-primary">Swap de Lastro</h1>
          <p className="mt-1 text-sm text-content-secondary">
            Mercado B2B de liquidez entre assessorias &mdash; Taxa: {feeRate}%
          </p>
        </div>
        <SwapActions />
      </div>

      {/* KPIs */}
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-5">
        <div className="rounded-xl border border-border bg-surface p-5 shadow-sm">
          <p className="text-sm font-medium text-content-secondary">Disponivel para Swap</p>
          <p className={`mt-1 text-2xl font-bold ${available > 0 ? "text-success" : "text-error"}`}>{formatUsd(available)}</p>
        </div>
        <div className="rounded-xl border border-border bg-surface p-5 shadow-sm">
          <p className="text-sm font-medium text-content-secondary">Volume 7d / 30d</p>
          <p className="mt-1 text-lg font-bold text-content-primary">{formatUsd(vol7d)} / {formatUsd(vol30d)}</p>
        </div>
        <div className="rounded-xl border border-border bg-surface p-5 shadow-sm">
          <p className="text-sm font-medium text-content-secondary">Taxas Pagas</p>
          <p className="mt-1 text-2xl font-bold text-orange-600">{formatUsd(feesPaid)}</p>
        </div>
        <div className="rounded-xl border border-border bg-surface p-5 shadow-sm">
          <p className="text-sm font-medium text-content-secondary">Ofertas Abertas</p>
          <p className="mt-1 text-2xl font-bold text-brand">{openCount}</p>
        </div>
        <div className="rounded-xl border border-border bg-surface p-5 shadow-sm">
          <p className="text-sm font-medium text-content-secondary">Melhor Oferta</p>
          <p className="mt-1 text-2xl font-bold text-content-primary">{bestOffer > 0 ? formatUsd(bestOffer) : "-"}</p>
        </div>
      </div>

      {/* Open offers */}
      <div className="rounded-xl border border-border bg-surface shadow-sm">
        <div className="border-b border-border px-6 py-4">
          <h2 className="text-lg font-semibold text-content-primary">Ofertas Disponiveis</h2>
        </div>
        {openOffers.length === 0 ? (
          <div className="px-6 py-8 text-center text-content-secondary">Nenhuma oferta disponivel.</div>
        ) : (
          <table className="min-w-full divide-y divide-border">
            <thead className="bg-bg-secondary">
              <tr>
                <th className="px-6 py-3 text-left text-xs font-medium uppercase text-content-secondary">Vendedor</th>
                <th className="px-6 py-3 text-right text-xs font-medium uppercase text-content-secondary">Valor</th>
                <th className="px-6 py-3 text-right text-xs font-medium uppercase text-content-secondary">Taxa ({feeRate}%)</th>
                <th className="px-6 py-3 text-right text-xs font-medium uppercase text-content-secondary">Voce Recebe</th>
                <th className="px-6 py-3 text-left text-xs font-medium uppercase text-content-secondary">Data</th>
                <th className="px-6 py-3 text-right text-xs font-medium uppercase text-content-secondary">Acao</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-border">
              {openOffers.map((o) => {
                const fee = o.fee_amount_usd ?? 0;
                const net = (o.amount_usd ?? 0) - fee;
                return (
                  <tr key={o.id}>
                    <td className="px-6 py-4 text-sm text-content-primary">{groupMap[o.seller_group_id] ?? (o.seller_group_id as string).slice(0, 8)}</td>
                    <td className="whitespace-nowrap px-6 py-4 text-right text-sm font-medium text-content-primary">{formatUsd(o.amount_usd as number)}</td>
                    <td className="whitespace-nowrap px-6 py-4 text-right text-sm text-content-secondary">{formatUsd(fee)}</td>
                    <td className="whitespace-nowrap px-6 py-4 text-right text-sm font-bold text-success">{formatUsd(net)}</td>
                    <td className="whitespace-nowrap px-6 py-4 text-sm text-content-secondary">
                      {new Date(o.created_at as string).toLocaleDateString("pt-BR")}
                    </td>
                    <td className="whitespace-nowrap px-6 py-4 text-right">
                      <SwapActions acceptOrderId={o.id as string} />
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        )}
      </div>

      {/* History */}
      <SwapHistory orders={myOrders} groupMap={groupMap} groupId={groupId} />
    </div>
  );
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    if (/PGRST|does not exist|custody_accounts|swap_orders/.test(msg)) {
      return (
        <div className="rounded-xl border border-border bg-surface p-8 text-center">
          <p className="text-lg font-medium text-content-primary">Funcionalidade em desenvolvimento</p>
          <p className="mt-2 text-sm text-content-muted">Este recurso estará disponível em breve.</p>
        </div>
      );
    }
    throw err;
  }
}
