import type { Metadata } from "next";
import { cookies } from "next/headers";
import { createServiceClient } from "@/lib/supabase/service";
import { formatUsd } from "@/lib/format";

export const metadata: Metadata = { title: "Auditoria" };
export const dynamic = "force-dynamic";

interface ClearingEvent {
  id: string;
  burn_ref_id: string;
  athlete_user_id: string;
  redeemer_group_id: string;
  total_coins: number;
  breakdown: { issuer_group_id: string; amount: number }[];
  created_at: string;
}

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
  settled_at: string | null;
}

const STATUS_COLORS: Record<string, string> = {
  pending: "bg-yellow-100 text-yellow-800",
  settled: "bg-green-100 text-green-800",
  insufficient: "bg-red-100 text-red-800",
  failed: "bg-gray-100 text-gray-600",
};

export default async function AuditPage() {
  const groupId = cookies().get("portal_group_id")?.value;
  if (!groupId) return null;

  const db = createServiceClient();

  const [eventsRes, settlementsRes, groupsRes] = await Promise.all([
    db
      .from("clearing_events")
      .select("*")
      .eq("redeemer_group_id", groupId)
      .order("created_at", { ascending: false })
      .limit(50),
    db
      .from("clearing_settlements")
      .select("*")
      .or(`creditor_group_id.eq.${groupId},debtor_group_id.eq.${groupId}`)
      .order("created_at", { ascending: false })
      .limit(100),
    db.from("coaching_groups").select("id, name"),
  ]);

  const events: ClearingEvent[] = eventsRes.data ?? [];
  const settlements: Settlement[] = settlementsRes.data ?? [];
  const groupMap = new Map(
    (groupsRes.data ?? []).map((g: { id: string; name: string }) => [g.id, g.name]),
  );

  const settlementsByEvent = new Map<string, Settlement[]>();
  for (const s of settlements) {
    const list = settlementsByEvent.get(s.clearing_event_id) ?? [];
    list.push(s);
    settlementsByEvent.set(s.clearing_event_id, list);
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-gray-900">Auditoria</h1>
        <p className="mt-1 text-sm text-gray-500">
          Trilha completa: burn &rarr; breakdown &rarr; settlements (por burn_id)
        </p>
      </div>

      <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
        <div className="rounded-xl border border-gray-200 bg-white p-5 shadow-sm">
          <p className="text-sm font-medium text-gray-500">Total de Burns</p>
          <p className="mt-1 text-2xl font-bold text-gray-900">{events.length}</p>
        </div>
        <div className="rounded-xl border border-gray-200 bg-white p-5 shadow-sm">
          <p className="text-sm font-medium text-gray-500">Settlements Gerados</p>
          <p className="mt-1 text-2xl font-bold text-blue-600">{settlements.length}</p>
        </div>
        <div className="rounded-xl border border-gray-200 bg-white p-5 shadow-sm">
          <p className="text-sm font-medium text-gray-500">Burns Interclub</p>
          <p className="mt-1 text-2xl font-bold text-orange-600">
            {events.filter((e) => e.breakdown.some((b) => b.issuer_group_id !== e.redeemer_group_id)).length}
          </p>
        </div>
      </div>

      {events.length === 0 ? (
        <div className="rounded-xl border border-gray-200 bg-white px-6 py-12 text-center text-gray-500 shadow-sm">
          Nenhum burn registrado para este clube.
        </div>
      ) : (
        <div className="space-y-4">
          {events.map((event) => {
            const eventSettlements = settlementsByEvent.get(event.id) ?? [];
            const hasInterclub = event.breakdown.some(
              (b) => b.issuer_group_id !== event.redeemer_group_id,
            );

            return (
              <div
                key={event.id}
                className="rounded-xl border border-gray-200 bg-white shadow-sm"
              >
                <div className="flex items-center justify-between border-b border-gray-100 px-6 py-4">
                  <div>
                    <h3 className="text-sm font-semibold text-gray-900">
                      Burn: <code className="rounded bg-gray-100 px-1.5 py-0.5 text-xs">{event.burn_ref_id}</code>
                    </h3>
                    <p className="mt-0.5 text-xs text-gray-500">
                      {new Date(event.created_at).toLocaleString("pt-BR")} &bull;{" "}
                      {event.total_coins} coins &bull;{" "}
                      {hasInterclub ? "Interclub" : "Intra-club"}
                    </p>
                  </div>
                  <span
                    className={`inline-flex rounded-full px-2 py-1 text-xs font-medium ${hasInterclub ? "bg-orange-100 text-orange-800" : "bg-green-100 text-green-800"}`}
                  >
                    {hasInterclub ? "Interclub" : "Intra-club"}
                  </span>
                </div>

                <div className="px-6 py-3">
                  <p className="mb-2 text-xs font-medium uppercase text-gray-500">
                    Breakdown por Emissor
                  </p>
                  <div className="flex flex-wrap gap-2">
                    {event.breakdown.map((b, i) => (
                      <span
                        key={i}
                        className={`inline-flex items-center rounded-lg px-3 py-1.5 text-xs font-medium ${
                          b.issuer_group_id === event.redeemer_group_id
                            ? "bg-green-50 text-green-700"
                            : "bg-orange-50 text-orange-700"
                        }`}
                      >
                        {groupMap.get(b.issuer_group_id) ?? b.issuer_group_id.slice(0, 8)}
                        : {b.amount} coins
                        {b.issuer_group_id === event.redeemer_group_id && " (proprio)"}
                      </span>
                    ))}
                  </div>
                </div>

                {eventSettlements.length > 0 && (
                  <div className="border-t border-gray-100 px-6 py-3">
                    <p className="mb-2 text-xs font-medium uppercase text-gray-500">
                      Settlements
                    </p>
                    <table className="min-w-full text-sm">
                      <thead>
                        <tr className="text-left text-xs text-gray-500">
                          <th className="pb-1 pr-4">Devedor</th>
                          <th className="pb-1 pr-4">Credor</th>
                          <th className="pb-1 pr-4 text-right">Coins</th>
                          <th className="pb-1 pr-4 text-right">Bruto</th>
                          <th className="pb-1 pr-4 text-right">Taxa</th>
                          <th className="pb-1 pr-4 text-right">Liquido</th>
                          <th className="pb-1">Status</th>
                        </tr>
                      </thead>
                      <tbody>
                        {eventSettlements.map((s) => (
                          <tr key={s.id}>
                            <td className="pr-4 py-1 text-gray-700">
                              {groupMap.get(s.debtor_group_id) ?? s.debtor_group_id.slice(0, 8)}
                            </td>
                            <td className="pr-4 py-1 text-gray-700">
                              {groupMap.get(s.creditor_group_id) ?? s.creditor_group_id.slice(0, 8)}
                            </td>
                            <td className="pr-4 py-1 text-right text-gray-700">{s.coin_amount}</td>
                            <td className="pr-4 py-1 text-right text-gray-700">{formatUsd(s.gross_amount_usd)}</td>
                            <td className="pr-4 py-1 text-right text-gray-500">
                              {formatUsd(s.fee_amount_usd)} ({s.fee_rate_pct}%)
                            </td>
                            <td className="pr-4 py-1 text-right font-medium text-gray-900">{formatUsd(s.net_amount_usd)}</td>
                            <td className="py-1">
                              <span className={`inline-flex rounded-full px-2 py-0.5 text-xs font-medium ${STATUS_COLORS[s.status] ?? "bg-gray-100 text-gray-600"}`}>
                                {s.status}
                              </span>
                            </td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                )}
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
