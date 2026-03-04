"use client";

import { useState } from "react";
import { formatUsd } from "@/lib/format";
import { formatDateTimeTz } from "@/lib/export";
import { ExportButton } from "@/components/ui/export-button";
import Link from "next/link";

type LedgerEntry = {
  date: string; type: string; amount: number;
  ref_id: string; ref_type: string; status: string;
};

const DEP_STATUS: Record<string, { label: string; color: string }> = {
  pending: { label: "Pendente", color: "bg-warning-soft text-warning" },
  confirmed: { label: "Confirmado", color: "bg-success-soft text-success" },
  failed: { label: "Falhou", color: "bg-error-soft text-error" },
  refunded: { label: "Reembolsado", color: "bg-surface-elevated text-content-secondary" },
};

const WD_STATUS: Record<string, { label: string; color: string }> = {
  pending: { label: "Pendente", color: "bg-warning-soft text-warning" },
  processing: { label: "Processando", color: "bg-info-soft text-info" },
  completed: { label: "Concluido", color: "bg-success-soft text-success" },
  failed: { label: "Falhou", color: "bg-error-soft text-error" },
  cancelled: { label: "Cancelado", color: "bg-surface-elevated text-content-secondary" },
};

interface CustodyTabsProps {
  ledger: LedgerEntry[];
  deposits: Record<string, unknown>[];
  withdrawals: Record<string, unknown>[];
}

const TABS = ["Extrato", "Depositos", "Retiradas"] as const;

export function CustodyTabs({ ledger, deposits, withdrawals }: CustodyTabsProps) {
  const [tab, setTab] = useState<typeof TABS[number]>("Extrato");

  return (
    <div className="rounded-xl border border-border bg-surface shadow-sm">
      <div className="flex items-center justify-between border-b border-border px-6 py-3">
        <div className="flex gap-1">
          {TABS.map((t) => (
            <button
              key={t}
              onClick={() => setTab(t)}
              className={`rounded-lg px-3 py-1.5 text-sm font-medium transition ${
                tab === t ? "bg-brand-soft text-brand" : "text-content-secondary hover:text-content-secondary"
              }`}
            >
              {t}
            </button>
          ))}
        </div>
        {tab === "Extrato" && (
          <ExportButton
            filename={`custodia-extrato-${new Date().toISOString().slice(0, 10)}`}
            headers={["Data", "Tipo", "Valor USD", "Referencia", "Status"]}
            rows={ledger.map((e) => [formatDateTimeTz(e.date), e.type, e.amount, e.ref_id, e.status])}
          />
        )}
        {tab === "Depositos" && (
          <ExportButton
            filename={`custodia-depositos-${new Date().toISOString().slice(0, 10)}`}
            headers={["Data", "USD", "Coins", "Gateway", "Moeda Orig", "Valor Orig", "FX Rate", "Spread %", "Ref", "Status"]}
            rows={deposits.map((d) => [
              formatDateTimeTz(d.created_at as string),
              d.amount_usd as number,
              d.coins_equivalent as number,
              d.payment_gateway as string,
              (d.original_currency as string) ?? "USD",
              d.original_amount as number ?? "",
              d.fx_rate as number ?? "",
              d.fx_spread_pct as number ?? "",
              d.payment_reference as string ?? "",
              d.status as string,
            ])}
          />
        )}
      </div>

      {tab === "Extrato" && <LedgerTable entries={ledger} />}
      {tab === "Depositos" && <DepositsTable deposits={deposits} />}
      {tab === "Retiradas" && <WithdrawalsTable withdrawals={withdrawals} />}
    </div>
  );
}

function LedgerTable({ entries }: { entries: LedgerEntry[] }) {
  if (entries.length === 0) {
    return <div className="px-6 py-12 text-center text-content-secondary">Nenhuma movimentacao registrada.</div>;
  }

  let runningBalance = 0;
  const withBalance = [...entries].reverse().map((e) => {
    if (e.status === "confirmed" || e.status === "settled" || e.status === "completed" || e.status === "processing") {
      runningBalance += e.amount;
    }
    return { ...e, balance: runningBalance };
  }).reverse();

  return (
    <table className="min-w-full divide-y divide-border">
      <thead className="bg-bg-secondary">
        <tr>
          <th className="px-6 py-3 text-left text-xs font-medium uppercase text-content-secondary">Data/Hora</th>
          <th className="px-6 py-3 text-left text-xs font-medium uppercase text-content-secondary">Tipo</th>
          <th className="px-6 py-3 text-right text-xs font-medium uppercase text-content-secondary">Valor (USD)</th>
          <th className="px-6 py-3 text-right text-xs font-medium uppercase text-content-secondary">Saldo Apos</th>
          <th className="px-6 py-3 text-left text-xs font-medium uppercase text-content-secondary">Referencia</th>
          <th className="px-6 py-3 text-left text-xs font-medium uppercase text-content-secondary">Status</th>
        </tr>
      </thead>
      <tbody className="divide-y divide-border">
        {withBalance.map((e, i) => {
          const linkHref = e.ref_type === "settlement" ? "/audit" : e.ref_type === "deposit" ? "#depositos" : "#retiradas";
          return (
            <tr key={`${e.ref_id}-${i}`}>
              <td className="whitespace-nowrap px-6 py-3 text-sm text-content-secondary">{formatDateTimeTz(e.date)}</td>
              <td className="px-6 py-3 text-sm text-content-primary">{e.type}</td>
              <td className={`whitespace-nowrap px-6 py-3 text-right text-sm font-medium ${e.amount >= 0 ? "text-success" : "text-error"}`}>
                {e.amount >= 0 ? "+" : ""}{formatUsd(e.amount)}
              </td>
              <td className="whitespace-nowrap px-6 py-3 text-right text-sm text-content-secondary">{formatUsd(e.balance)}</td>
              <td className="px-6 py-3 text-sm">
                <Link href={linkHref} className="font-mono text-xs text-brand hover:underline">
                  {e.ref_id.slice(0, 8)}...
                </Link>
              </td>
              <td className="px-6 py-3 text-sm text-content-secondary">{e.status}</td>
            </tr>
          );
        })}
      </tbody>
    </table>
  );
}

function DepositsTable({ deposits }: { deposits: Record<string, unknown>[] }) {
  if (deposits.length === 0) {
    return <div className="px-6 py-12 text-center text-content-secondary">Nenhum deposito registrado.</div>;
  }

  return (
    <table className="min-w-full divide-y divide-border">
      <thead className="bg-bg-secondary">
        <tr>
          <th className="px-6 py-3 text-left text-xs font-medium uppercase text-content-secondary">Data</th>
          <th className="px-6 py-3 text-right text-xs font-medium uppercase text-content-secondary">USD Creditado</th>
          <th className="px-6 py-3 text-right text-xs font-medium uppercase text-content-secondary">Coins</th>
          <th className="px-6 py-3 text-left text-xs font-medium uppercase text-content-secondary">Moeda Orig</th>
          <th className="px-6 py-3 text-right text-xs font-medium uppercase text-content-secondary">Valor Orig</th>
          <th className="px-6 py-3 text-right text-xs font-medium uppercase text-content-secondary">Spread</th>
          <th className="px-6 py-3 text-left text-xs font-medium uppercase text-content-secondary">Gateway</th>
          <th className="px-6 py-3 text-left text-xs font-medium uppercase text-content-secondary">Ref</th>
          <th className="px-6 py-3 text-left text-xs font-medium uppercase text-content-secondary">Status</th>
        </tr>
      </thead>
      <tbody className="divide-y divide-border">
        {deposits.map((d) => {
          const st = DEP_STATUS[(d.status as string)] ?? { label: d.status as string, color: "bg-surface-elevated text-content-secondary" };
          return (
            <tr key={d.id as string}>
              <td className="whitespace-nowrap px-6 py-3 text-sm text-content-secondary">{formatDateTimeTz(d.created_at as string)}</td>
              <td className="whitespace-nowrap px-6 py-3 text-right text-sm font-medium text-content-primary">{formatUsd(d.amount_usd as number)}</td>
              <td className="whitespace-nowrap px-6 py-3 text-right text-sm text-content-secondary">{(d.coins_equivalent as number)?.toLocaleString()}</td>
              <td className="px-6 py-3 text-sm text-content-secondary">{(d.original_currency as string) ?? "USD"}</td>
              <td className="whitespace-nowrap px-6 py-3 text-right text-sm text-content-secondary">
                {d.original_amount ? (d.original_amount as number).toLocaleString("pt-BR", { minimumFractionDigits: 2 }) : "-"}
              </td>
              <td className="whitespace-nowrap px-6 py-3 text-right text-sm text-content-secondary">
                {d.fx_spread_pct ? `${d.fx_spread_pct}%` : "-"}
              </td>
              <td className="px-6 py-3 text-sm text-content-secondary capitalize">{d.payment_gateway as string}</td>
              <td className="px-6 py-3 text-sm">
                <span className="font-mono text-xs text-content-secondary">{d.payment_reference ? (d.payment_reference as string).slice(0, 12) : "-"}</span>
              </td>
              <td className="px-6 py-3">
                <span className={`inline-flex rounded-full px-2 py-0.5 text-xs font-medium ${st.color}`}>{st.label}</span>
              </td>
            </tr>
          );
        })}
      </tbody>
    </table>
  );
}

function WithdrawalsTable({ withdrawals }: { withdrawals: Record<string, unknown>[] }) {
  if (withdrawals.length === 0) {
    return <div className="px-6 py-12 text-center text-content-secondary">Nenhuma retirada registrada.</div>;
  }

  return (
    <table className="min-w-full divide-y divide-border">
      <thead className="bg-bg-secondary">
        <tr>
          <th className="px-6 py-3 text-left text-xs font-medium uppercase text-content-secondary">Data</th>
          <th className="px-6 py-3 text-right text-xs font-medium uppercase text-content-secondary">USD Debitado</th>
          <th className="px-6 py-3 text-left text-xs font-medium uppercase text-content-secondary">Moeda Dest</th>
          <th className="px-6 py-3 text-right text-xs font-medium uppercase text-content-secondary">Cotacao</th>
          <th className="px-6 py-3 text-right text-xs font-medium uppercase text-content-secondary">Spread</th>
          <th className="px-6 py-3 text-right text-xs font-medium uppercase text-content-secondary">Provider Fee</th>
          <th className="px-6 py-3 text-right text-xs font-medium uppercase text-content-secondary">Valor Local</th>
          <th className="px-6 py-3 text-left text-xs font-medium uppercase text-content-secondary">Status</th>
        </tr>
      </thead>
      <tbody className="divide-y divide-border">
        {withdrawals.map((w) => {
          const st = WD_STATUS[(w.status as string)] ?? { label: w.status as string, color: "bg-surface-elevated text-content-secondary" };
          return (
            <tr key={w.id as string}>
              <td className="whitespace-nowrap px-6 py-3 text-sm text-content-secondary">{formatDateTimeTz(w.created_at as string)}</td>
              <td className="whitespace-nowrap px-6 py-3 text-right text-sm font-medium text-error">-{formatUsd(w.amount_usd as number)}</td>
              <td className="px-6 py-3 text-sm text-content-secondary">{w.target_currency as string}</td>
              <td className="whitespace-nowrap px-6 py-3 text-right text-sm text-content-secondary">{(w.fx_rate as number)?.toFixed(4)}</td>
              <td className="whitespace-nowrap px-6 py-3 text-right text-sm text-content-secondary">
                {String(w.fx_spread_pct ?? 0)}% ({formatUsd(w.fx_spread_usd as number)})
              </td>
              <td className="whitespace-nowrap px-6 py-3 text-right text-sm text-content-secondary">{formatUsd(w.provider_fee_usd as number)}</td>
              <td className="whitespace-nowrap px-6 py-3 text-right text-sm font-medium text-content-primary">
                {(w.net_local_amount as number)?.toLocaleString("pt-BR", { minimumFractionDigits: 2 })}
              </td>
              <td className="px-6 py-3">
                <span className={`inline-flex rounded-full px-2 py-0.5 text-xs font-medium ${st.color}`}>{st.label}</span>
              </td>
            </tr>
          );
        })}
      </tbody>
    </table>
  );
}
