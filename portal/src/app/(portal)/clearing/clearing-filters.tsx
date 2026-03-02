"use client";

import { useState } from "react";
import { formatUsd } from "@/lib/format";
import { formatDateTimeTz } from "@/lib/export";
import { ExportButton } from "@/components/ui/export-button";
import Link from "next/link";

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

interface Props {
  receivables: Settlement[];
  payables: Settlement[];
  groupMap: Record<string, string>;
  eventMap: Record<string, ClearingEvent>;
}

const STATUS_LABELS: Record<string, { label: string; color: string }> = {
  pending: { label: "Pendente", color: "bg-yellow-100 text-yellow-800" },
  settled: { label: "Liquidado", color: "bg-green-100 text-green-800" },
  insufficient: { label: "Saldo Insuf.", color: "bg-red-100 text-red-800" },
  failed: { label: "Falhou", color: "bg-gray-100 text-gray-600" },
};

export function ClearingFilters({ receivables, payables, groupMap, eventMap }: Props) {
  const [direction, setDirection] = useState<"all" | "in" | "out">("all");
  const [statusFilter, setStatusFilter] = useState<string>("all");
  const [search, setSearch] = useState("");
  const [expanded, setExpanded] = useState<string | null>(null);

  const all = [
    ...receivables.map((s) => ({ ...s, _dir: "in" as const })),
    ...payables.map((s) => ({ ...s, _dir: "out" as const })),
  ].sort((a, b) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime());

  const filtered = all.filter((s) => {
    if (direction !== "all" && s._dir !== direction) return false;
    if (statusFilter !== "all" && s.status !== statusFilter) return false;
    if (search) {
      const q = search.toLowerCase();
      const event = eventMap[s.clearing_event_id];
      const burnRef = event?.burn_ref_id?.toLowerCase() ?? "";
      const counterparty = s._dir === "in" ? groupMap[s.debtor_group_id] : groupMap[s.creditor_group_id];
      if (!burnRef.includes(q) && !s.id.includes(q) && !(counterparty ?? "").toLowerCase().includes(q)) return false;
    }
    return true;
  });

  return (
    <>
      {/* Filters */}
      <div className="flex flex-wrap items-center gap-3 rounded-xl border border-gray-200 bg-white px-4 py-3 shadow-sm">
        <select
          value={direction}
          onChange={(e) => setDirection(e.target.value as "all" | "in" | "out")}
          className="rounded-lg border border-gray-300 px-3 py-1.5 text-sm"
        >
          <option value="all">Todas direcoes</option>
          <option value="in">A Receber</option>
          <option value="out">A Pagar</option>
        </select>
        <select
          value={statusFilter}
          onChange={(e) => setStatusFilter(e.target.value)}
          className="rounded-lg border border-gray-300 px-3 py-1.5 text-sm"
        >
          <option value="all">Todos status</option>
          <option value="pending">Pendente</option>
          <option value="settled">Liquidado</option>
          <option value="insufficient">Insuficiente</option>
          <option value="failed">Falhou</option>
        </select>
        <input
          type="text"
          placeholder="Buscar por Burn ID, clube, settlement..."
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          className="flex-1 rounded-lg border border-gray-300 px-3 py-1.5 text-sm"
        />
        <span className="text-xs text-gray-500">{filtered.length} resultado(s)</span>
        <ExportButton
          filename={`clearing-${new Date().toISOString().slice(0, 10)}`}
          headers={["Data", "Direcao", "Burn ID", "Contraparte", "Coins", "Bruto", "Taxa", "Liquido", "Status", "Liquidado em"]}
          rows={filtered.map((s) => {
            const event = eventMap[s.clearing_event_id];
            const cp = s._dir === "in" ? groupMap[s.debtor_group_id] : groupMap[s.creditor_group_id];
            return [
              formatDateTimeTz(s.created_at), s._dir === "in" ? "Receber" : "Pagar",
              event?.burn_ref_id ?? "-", cp ?? "-",
              s.coin_amount, s.gross_amount_usd, s.fee_amount_usd, s.net_amount_usd,
              s.status, s.settled_at ? formatDateTimeTz(s.settled_at) : "-",
            ];
          })}
        />
      </div>

      {/* Settlements Table */}
      <div className="rounded-xl border border-gray-200 bg-white shadow-sm">
        {filtered.length === 0 ? (
          <div className="px-6 py-12 text-center text-gray-500">Nenhuma compensacao encontrada.</div>
        ) : (
          <table className="min-w-full divide-y divide-gray-200">
            <thead className="bg-gray-50">
              <tr>
                <th className="px-4 py-3 text-left text-xs font-medium uppercase text-gray-500">Data</th>
                <th className="px-4 py-3 text-left text-xs font-medium uppercase text-gray-500">Dir</th>
                <th className="px-4 py-3 text-left text-xs font-medium uppercase text-gray-500">Burn ID</th>
                <th className="px-4 py-3 text-left text-xs font-medium uppercase text-gray-500">Contraparte</th>
                <th className="px-4 py-3 text-right text-xs font-medium uppercase text-gray-500">Coins</th>
                <th className="px-4 py-3 text-right text-xs font-medium uppercase text-gray-500">Bruto</th>
                <th className="px-4 py-3 text-right text-xs font-medium uppercase text-gray-500">Taxa</th>
                <th className="px-4 py-3 text-right text-xs font-medium uppercase text-gray-500">Liquido</th>
                <th className="px-4 py-3 text-left text-xs font-medium uppercase text-gray-500">Status</th>
                <th className="px-4 py-3 text-left text-xs font-medium uppercase text-gray-500">Liquidado</th>
                <th className="px-4 py-3 text-xs font-medium uppercase text-gray-500"></th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-200">
              {filtered.map((s) => {
                const event = eventMap[s.clearing_event_id];
                const counterparty = s._dir === "in"
                  ? groupMap[s.debtor_group_id] ?? s.debtor_group_id.slice(0, 8)
                  : groupMap[s.creditor_group_id] ?? s.creditor_group_id.slice(0, 8);
                const st = STATUS_LABELS[s.status] ?? { label: s.status, color: "bg-gray-100 text-gray-600" };
                const isExpanded = expanded === s.id;

                return (
                  <>
                    <tr key={s.id} className={isExpanded ? "bg-blue-50" : ""}>
                      <td className="whitespace-nowrap px-4 py-3 text-sm text-gray-700">{formatDateTimeTz(s.created_at)}</td>
                      <td className="px-4 py-3 text-sm">
                        <span className={`font-medium ${s._dir === "in" ? "text-green-700" : "text-red-700"}`}>
                          {s._dir === "in" ? "Receber" : "Pagar"}
                        </span>
                      </td>
                      <td className="px-4 py-3 text-sm">
                        <Link href="/audit" className="font-mono text-xs text-blue-600 hover:underline">
                          {event?.burn_ref_id?.slice(0, 12) ?? "-"}
                        </Link>
                      </td>
                      <td className="px-4 py-3 text-sm text-gray-900">{counterparty}</td>
                      <td className="whitespace-nowrap px-4 py-3 text-right text-sm text-gray-700">{s.coin_amount.toLocaleString()}</td>
                      <td className="whitespace-nowrap px-4 py-3 text-right text-sm text-gray-700">{formatUsd(s.gross_amount_usd)}</td>
                      <td className="whitespace-nowrap px-4 py-3 text-right text-sm text-gray-500">
                        {formatUsd(s.fee_amount_usd)} ({s.fee_rate_pct}%)
                      </td>
                      <td className="whitespace-nowrap px-4 py-3 text-right text-sm font-medium text-gray-900">{formatUsd(s.net_amount_usd)}</td>
                      <td className="px-4 py-3">
                        <span className={`inline-flex rounded-full px-2 py-0.5 text-xs font-medium ${st.color}`}>{st.label}</span>
                      </td>
                      <td className="whitespace-nowrap px-4 py-3 text-sm text-gray-500">
                        {s.settled_at ? formatDateTimeTz(s.settled_at) : "-"}
                      </td>
                      <td className="px-4 py-3">
                        <button
                          onClick={() => setExpanded(isExpanded ? null : s.id)}
                          className="text-xs text-blue-600 hover:underline"
                        >
                          {isExpanded ? "Fechar" : "Detalhes"}
                        </button>
                      </td>
                    </tr>
                    {isExpanded && (
                      <tr key={`${s.id}-detail`}>
                        <td colSpan={11} className="bg-gray-50 px-6 py-4">
                          <div className="grid grid-cols-2 gap-4 text-sm">
                            <div>
                              <p className="font-medium text-gray-700">Settlement ID</p>
                              <p className="font-mono text-xs text-gray-500">{s.id}</p>
                            </div>
                            <div>
                              <p className="font-medium text-gray-700">Clearing Event ID</p>
                              <p className="font-mono text-xs text-gray-500">{s.clearing_event_id}</p>
                            </div>
                            <div>
                              <p className="font-medium text-gray-700">Debtor (Emissor)</p>
                              <p className="text-gray-600">{groupMap[s.debtor_group_id] ?? s.debtor_group_id}</p>
                            </div>
                            <div>
                              <p className="font-medium text-gray-700">Creditor (Resgatante)</p>
                              <p className="text-gray-600">{groupMap[s.creditor_group_id] ?? s.creditor_group_id}</p>
                            </div>
                            <div>
                              <p className="font-medium text-gray-700">Movimentacao Contabil</p>
                              <p className="text-gray-600">
                                {groupMap[s.debtor_group_id] ?? "Emissor"}: D -= {formatUsd(s.gross_amount_usd)}, R -= {s.coin_amount}
                              </p>
                              <p className="text-gray-600">
                                {groupMap[s.creditor_group_id] ?? "Resgatante"}: D += {formatUsd(s.net_amount_usd)}
                              </p>
                              <p className="text-gray-600">
                                Plataforma: +{formatUsd(s.fee_amount_usd)} (taxa)
                              </p>
                            </div>
                            <div>
                              <p className="font-medium text-gray-700">Burn</p>
                              {event && (
                                <>
                                  <p className="text-gray-600">Ref: {event.burn_ref_id}</p>
                                  <p className="text-gray-600">{event.total_coins} coins total</p>
                                  <Link href="/audit" className="text-xs text-blue-600 hover:underline">
                                    Ver na Auditoria
                                  </Link>
                                </>
                              )}
                            </div>
                          </div>
                        </td>
                      </tr>
                    )}
                  </>
                );
              })}
            </tbody>
          </table>
        )}
      </div>
    </>
  );
}
