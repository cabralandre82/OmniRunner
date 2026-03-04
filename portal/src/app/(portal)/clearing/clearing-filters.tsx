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
  pending: { label: "Pendente", color: "bg-warning-soft text-warning" },
  settled: { label: "Liquidado", color: "bg-success-soft text-success" },
  insufficient: { label: "Saldo Insuf.", color: "bg-error-soft text-error" },
  failed: { label: "Falhou", color: "bg-surface-elevated text-content-secondary" },
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
      <div className="flex flex-wrap items-center gap-3 rounded-xl border border-border bg-surface px-4 py-3 shadow-sm">
        <select
          value={direction}
          onChange={(e) => setDirection(e.target.value as "all" | "in" | "out")}
          className="rounded-lg border border-border px-3 py-1.5 text-sm"
        >
          <option value="all">Todas direcoes</option>
          <option value="in">A Receber</option>
          <option value="out">A Pagar</option>
        </select>
        <select
          value={statusFilter}
          onChange={(e) => setStatusFilter(e.target.value)}
          className="rounded-lg border border-border px-3 py-1.5 text-sm"
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
          className="flex-1 rounded-lg border border-border px-3 py-1.5 text-sm"
        />
        <span className="text-xs text-content-secondary">{filtered.length} resultado(s)</span>
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
      <div className="rounded-xl border border-border bg-surface shadow-sm">
        {filtered.length === 0 ? (
          <div className="px-6 py-12 text-center text-content-secondary">Nenhuma compensacao encontrada.</div>
        ) : (
          <table className="min-w-full divide-y divide-border">
            <thead className="bg-bg-secondary">
              <tr>
                <th className="px-4 py-3 text-left text-xs font-medium uppercase text-content-secondary">Data</th>
                <th className="px-4 py-3 text-left text-xs font-medium uppercase text-content-secondary">Dir</th>
                <th className="px-4 py-3 text-left text-xs font-medium uppercase text-content-secondary">Burn ID</th>
                <th className="px-4 py-3 text-left text-xs font-medium uppercase text-content-secondary">Contraparte</th>
                <th className="px-4 py-3 text-right text-xs font-medium uppercase text-content-secondary">Coins</th>
                <th className="px-4 py-3 text-right text-xs font-medium uppercase text-content-secondary">Bruto</th>
                <th className="px-4 py-3 text-right text-xs font-medium uppercase text-content-secondary">Taxa</th>
                <th className="px-4 py-3 text-right text-xs font-medium uppercase text-content-secondary">Liquido</th>
                <th className="px-4 py-3 text-left text-xs font-medium uppercase text-content-secondary">Status</th>
                <th className="px-4 py-3 text-left text-xs font-medium uppercase text-content-secondary">Liquidado</th>
                <th className="px-4 py-3 text-xs font-medium uppercase text-content-secondary"></th>
              </tr>
            </thead>
            <tbody className="divide-y divide-border">
              {filtered.map((s) => {
                const event = eventMap[s.clearing_event_id];
                const counterparty = s._dir === "in"
                  ? groupMap[s.debtor_group_id] ?? s.debtor_group_id.slice(0, 8)
                  : groupMap[s.creditor_group_id] ?? s.creditor_group_id.slice(0, 8);
                const st = STATUS_LABELS[s.status] ?? { label: s.status, color: "bg-surface-elevated text-content-secondary" };
                const isExpanded = expanded === s.id;

                return (
                  <>
                    <tr key={s.id} className={isExpanded ? "bg-brand-soft" : ""}>
                      <td className="whitespace-nowrap px-4 py-3 text-sm text-content-secondary">{formatDateTimeTz(s.created_at)}</td>
                      <td className="px-4 py-3 text-sm">
                        <span className={`font-medium ${s._dir === "in" ? "text-success" : "text-error"}`}>
                          {s._dir === "in" ? "Receber" : "Pagar"}
                        </span>
                      </td>
                      <td className="px-4 py-3 text-sm">
                        <Link href="/audit" className="font-mono text-xs text-brand hover:underline">
                          {event?.burn_ref_id?.slice(0, 12) ?? "-"}
                        </Link>
                      </td>
                      <td className="px-4 py-3 text-sm text-content-primary">{counterparty}</td>
                      <td className="whitespace-nowrap px-4 py-3 text-right text-sm text-content-secondary">{s.coin_amount.toLocaleString()}</td>
                      <td className="whitespace-nowrap px-4 py-3 text-right text-sm text-content-secondary">{formatUsd(s.gross_amount_usd)}</td>
                      <td className="whitespace-nowrap px-4 py-3 text-right text-sm text-content-secondary">
                        {formatUsd(s.fee_amount_usd)} ({s.fee_rate_pct}%)
                      </td>
                      <td className="whitespace-nowrap px-4 py-3 text-right text-sm font-medium text-content-primary">{formatUsd(s.net_amount_usd)}</td>
                      <td className="px-4 py-3">
                        <span className={`inline-flex rounded-full px-2 py-0.5 text-xs font-medium ${st.color}`}>{st.label}</span>
                      </td>
                      <td className="whitespace-nowrap px-4 py-3 text-sm text-content-secondary">
                        {s.settled_at ? formatDateTimeTz(s.settled_at) : "-"}
                      </td>
                      <td className="px-4 py-3">
                        <button
                          onClick={() => setExpanded(isExpanded ? null : s.id)}
                          className="text-xs text-brand hover:underline"
                        >
                          {isExpanded ? "Fechar" : "Detalhes"}
                        </button>
                      </td>
                    </tr>
                    {isExpanded && (
                      <tr key={`${s.id}-detail`}>
                        <td colSpan={11} className="bg-bg-secondary px-6 py-4">
                          <div className="grid grid-cols-2 gap-4 text-sm">
                            <div>
                              <p className="font-medium text-content-secondary">Settlement ID</p>
                              <p className="font-mono text-xs text-content-secondary">{s.id}</p>
                            </div>
                            <div>
                              <p className="font-medium text-content-secondary">Clearing Event ID</p>
                              <p className="font-mono text-xs text-content-secondary">{s.clearing_event_id}</p>
                            </div>
                            <div>
                              <p className="font-medium text-content-secondary">Debtor (Emissor)</p>
                              <p className="text-content-secondary">{groupMap[s.debtor_group_id] ?? s.debtor_group_id}</p>
                            </div>
                            <div>
                              <p className="font-medium text-content-secondary">Creditor (Resgatante)</p>
                              <p className="text-content-secondary">{groupMap[s.creditor_group_id] ?? s.creditor_group_id}</p>
                            </div>
                            <div>
                              <p className="font-medium text-content-secondary">Movimentacao Contabil</p>
                              <p className="text-content-secondary">
                                {groupMap[s.debtor_group_id] ?? "Emissor"}: D -= {formatUsd(s.gross_amount_usd)}, R -= {s.coin_amount}
                              </p>
                              <p className="text-content-secondary">
                                {groupMap[s.creditor_group_id] ?? "Resgatante"}: D += {formatUsd(s.net_amount_usd)}
                              </p>
                              <p className="text-content-secondary">
                                Plataforma: +{formatUsd(s.fee_amount_usd)} (taxa)
                              </p>
                            </div>
                            <div>
                              <p className="font-medium text-content-secondary">Burn</p>
                              {event && (
                                <>
                                  <p className="text-content-secondary">Ref: {event.burn_ref_id}</p>
                                  <p className="text-content-secondary">{event.total_coins} coins total</p>
                                  <Link href="/audit" className="text-xs text-brand hover:underline">
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
