import type { Metadata } from "next";
import { cookies } from "next/headers";
import { createClient } from "@/lib/supabase/server";
import { NoGroupSelected } from "@/components/no-group-selected";
import { formatUsd } from "@/lib/format";
import { ClearingFilters } from "./clearing-filters";

export const metadata: Metadata = { title: "Transferências OmniCoins" };
export const dynamic = "force-dynamic";

interface Settlement {
  id: string;
  clearing_event_id: string;
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

interface ClearingEvent {
  id: string;
  burn_ref_id: string;
  total_coins: number;
  created_at: string;
}

export default async function ClearingPage() {
  const groupId = cookies().get("portal_group_id")?.value;
  if (!groupId) return <NoGroupSelected />;

  const db = createClient();

  const [receivablesRes, payablesRes, eventsRes] = await Promise.all([
    db.from("clearing_settlements").select("id, clearing_event_id, creditor_group_id, debtor_group_id, coin_amount, gross_amount_usd, fee_rate_pct, fee_amount_usd, net_amount_usd, status, created_at, settled_at").eq("creditor_group_id", groupId).order("created_at", { ascending: false }).limit(100),
    db.from("clearing_settlements").select("id, clearing_event_id, creditor_group_id, debtor_group_id, coin_amount, gross_amount_usd, fee_rate_pct, fee_amount_usd, net_amount_usd, status, created_at, settled_at").eq("debtor_group_id", groupId).order("created_at", { ascending: false }).limit(100),
    db.from("clearing_events").select("id, burn_ref_id, total_coins, created_at").eq("redeemer_group_id", groupId).order("created_at", { ascending: false }).limit(100),
  ]);

  const receivables: Settlement[] = receivablesRes.data ?? [];
  const payables: Settlement[] = payablesRes.data ?? [];
  const events: ClearingEvent[] = eventsRes.data ?? [];

  const referencedGroupIds = Array.from(new Set([
    ...receivables.map((s) => s.creditor_group_id),
    ...receivables.map((s) => s.debtor_group_id),
    ...payables.map((s) => s.creditor_group_id),
    ...payables.map((s) => s.debtor_group_id),
  ].filter((id) => id !== groupId)));

  let groupMap: Record<string, string> = {};
  if (referencedGroupIds.length > 0) {
    const groupsRes = await db.from("coaching_groups").select("id, name").in("id", referencedGroupIds);
    groupMap = Object.fromEntries(
      (groupsRes.data ?? []).map((g: { id: string; name: string }) => [g.id, g.name]),
    );
  }

  const eventMap = Object.fromEntries(events.map((e) => [e.id, e]));

  const totalReceivable = receivables.filter((s) => s.status === "pending").reduce((sum, s) => sum + s.net_amount_usd, 0);
  const totalPayable = payables.filter((s) => s.status === "pending").reduce((sum, s) => sum + s.net_amount_usd, 0);
  const totalSettledIn = receivables.filter((s) => s.status === "settled").reduce((sum, s) => sum + s.net_amount_usd, 0);
  const totalSettledOut = payables.filter((s) => s.status === "settled").reduce((sum, s) => sum + s.gross_amount_usd, 0);
  const totalFeesPaid = payables.filter((s) => s.status === "settled").reduce((sum, s) => sum + s.fee_amount_usd, 0);

  const interclubBurns = events.length;
  const allSettlements = [...receivables, ...payables];

  const settledItems = allSettlements.filter((s) => s.status === "settled" && s.settled_at);
  const avgSettleMs = settledItems.length > 0
    ? settledItems.reduce((sum, s) => sum + (new Date(s.settled_at!).getTime() - new Date(s.created_at).getTime()), 0) / settledItems.length
    : 0;
  const avgSettleSec = Math.round(avgSettleMs / 1000);

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-content-primary">Transferências OmniCoins</h1>
        <p className="mt-1 text-sm text-content-secondary">
          Movimentações de OmniCoins entre assessorias (campeonatos, desafios e trocas)
        </p>
      </div>

      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-6">
        <div className="rounded-xl border border-border bg-surface p-5 shadow-sm">
          <p className="text-sm font-medium text-content-secondary">A Receber</p>
          <p className="mt-1 text-2xl font-bold text-success">{formatUsd(totalReceivable)}</p>
        </div>
        <div className="rounded-xl border border-border bg-surface p-5 shadow-sm">
          <p className="text-sm font-medium text-content-secondary">A Pagar</p>
          <p className="mt-1 text-2xl font-bold text-error">{formatUsd(totalPayable)}</p>
        </div>
        <div className="rounded-xl border border-border bg-surface p-5 shadow-sm">
          <p className="text-sm font-medium text-content-secondary">Recebido</p>
          <p className="mt-1 text-2xl font-bold text-content-primary">{formatUsd(totalSettledIn)}</p>
        </div>
        <div className="rounded-xl border border-border bg-surface p-5 shadow-sm">
          <p className="text-sm font-medium text-content-secondary">Pago</p>
          <p className="mt-1 text-2xl font-bold text-content-primary">{formatUsd(totalSettledOut)}</p>
        </div>
        <div className="rounded-xl border border-border bg-surface p-5 shadow-sm">
          <p className="text-sm font-medium text-content-secondary">Taxas Pagas</p>
          <p className="mt-1 text-2xl font-bold text-orange-600">{formatUsd(totalFeesPaid)}</p>
        </div>
        <div className="rounded-xl border border-border bg-surface p-5 shadow-sm">
          <p className="text-sm font-medium text-content-secondary">Tempo Médio</p>
          <p className="mt-1 text-2xl font-bold text-content-secondary">{avgSettleSec}s</p>
          <p className="text-xs text-content-muted">{interclubBurns} transferências entre assessorias</p>
        </div>
      </div>

      <ClearingFilters
        receivables={receivables}
        payables={payables}
        groupMap={groupMap}
        eventMap={eventMap}
      />
    </div>
  );
}
