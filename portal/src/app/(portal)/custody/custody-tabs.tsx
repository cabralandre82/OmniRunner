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
  pending: { label: "Pendente", color: "bg-yellow-100 text-yellow-800" },
  confirmed: { label: "Confirmado", color: "bg-green-100 text-green-800" },
  failed: { label: "Falhou", color: "bg-red-100 text-red-800" },
  refunded: { label: "Reembolsado", color: "bg-gray-100 text-gray-600" },
};

const WD_STATUS: Record<string, { label: string; color: string }> = {
  pending: { label: "Pendente", color: "bg-yellow-100 text-yellow-800" },
  processing: { label: "Processando", color: "bg-blue-100 text-blue-800" },
  completed: { label: "Concluido", color: "bg-green-100 text-green-800" },
  failed: { label: "Falhou", color: "bg-red-100 text-red-800" },
  cancelled: { label: "Cancelado", color: "bg-gray-100 text-gray-600" },
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
    <div className="rounded-xl border border-gray-200 bg-white shadow-sm">
      <div className="flex items-center justify-between border-b border-gray-200 px-6 py-3">
        <div className="flex gap-1">
          {TABS.map((t) => (
            <button
              key={t}
              onClick={() => setTab(t)}
              className={`rounded-lg px-3 py-1.5 text-sm font-medium transition ${
                tab === t ? "bg-blue-50 text-blue-700" : "text-gray-500 hover:text-gray-700"
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
    return <div className="px-6 py-12 text-center text-gray-500">Nenhuma movimentacao registrada.</div>;
  }

  let runningBalance = 0;
  const withBalance = [...entries].reverse().map((e) => {
    if (e.status === "confirmed" || e.status === "settled" || e.status === "completed" || e.status === "processing") {
      runningBalance += e.amount;
    }
    return { ...e, balance: runningBalance };
  }).reverse();

  return (
    <table className="min-w-full divide-y divide-gray-200">
      <thead className="bg-gray-50">
        <tr>
          <th className="px-6 py-3 text-left text-xs font-medium uppercase text-gray-500">Data/Hora</th>
          <th className="px-6 py-3 text-left text-xs font-medium uppercase text-gray-500">Tipo</th>
          <th className="px-6 py-3 text-right text-xs font-medium uppercase text-gray-500">Valor (USD)</th>
          <th className="px-6 py-3 text-right text-xs font-medium uppercase text-gray-500">Saldo Apos</th>
          <th className="px-6 py-3 text-left text-xs font-medium uppercase text-gray-500">Referencia</th>
          <th className="px-6 py-3 text-left text-xs font-medium uppercase text-gray-500">Status</th>
        </tr>
      </thead>
      <tbody className="divide-y divide-gray-200">
        {withBalance.map((e, i) => {
          const linkHref = e.ref_type === "settlement" ? "/audit" : e.ref_type === "deposit" ? "#depositos" : "#retiradas";
          return (
            <tr key={`${e.ref_id}-${i}`}>
              <td className="whitespace-nowrap px-6 py-3 text-sm text-gray-700">{formatDateTimeTz(e.date)}</td>
              <td className="px-6 py-3 text-sm text-gray-900">{e.type}</td>
              <td className={`whitespace-nowrap px-6 py-3 text-right text-sm font-medium ${e.amount >= 0 ? "text-green-700" : "text-red-700"}`}>
                {e.amount >= 0 ? "+" : ""}{formatUsd(e.amount)}
              </td>
              <td className="whitespace-nowrap px-6 py-3 text-right text-sm text-gray-600">{formatUsd(e.balance)}</td>
              <td className="px-6 py-3 text-sm">
                <Link href={linkHref} className="font-mono text-xs text-blue-600 hover:underline">
                  {e.ref_id.slice(0, 8)}...
                </Link>
              </td>
              <td className="px-6 py-3 text-sm text-gray-500">{e.status}</td>
            </tr>
          );
        })}
      </tbody>
    </table>
  );
}

function DepositsTable({ deposits }: { deposits: Record<string, unknown>[] }) {
  if (deposits.length === 0) {
    return <div className="px-6 py-12 text-center text-gray-500">Nenhum deposito registrado.</div>;
  }

  return (
    <table className="min-w-full divide-y divide-gray-200">
      <thead className="bg-gray-50">
        <tr>
          <th className="px-6 py-3 text-left text-xs font-medium uppercase text-gray-500">Data</th>
          <th className="px-6 py-3 text-right text-xs font-medium uppercase text-gray-500">USD Creditado</th>
          <th className="px-6 py-3 text-right text-xs font-medium uppercase text-gray-500">Coins</th>
          <th className="px-6 py-3 text-left text-xs font-medium uppercase text-gray-500">Moeda Orig</th>
          <th className="px-6 py-3 text-right text-xs font-medium uppercase text-gray-500">Valor Orig</th>
          <th className="px-6 py-3 text-right text-xs font-medium uppercase text-gray-500">Spread</th>
          <th className="px-6 py-3 text-left text-xs font-medium uppercase text-gray-500">Gateway</th>
          <th className="px-6 py-3 text-left text-xs font-medium uppercase text-gray-500">Ref</th>
          <th className="px-6 py-3 text-left text-xs font-medium uppercase text-gray-500">Status</th>
        </tr>
      </thead>
      <tbody className="divide-y divide-gray-200">
        {deposits.map((d) => {
          const st = DEP_STATUS[(d.status as string)] ?? { label: d.status as string, color: "bg-gray-100 text-gray-600" };
          return (
            <tr key={d.id as string}>
              <td className="whitespace-nowrap px-6 py-3 text-sm text-gray-700">{formatDateTimeTz(d.created_at as string)}</td>
              <td className="whitespace-nowrap px-6 py-3 text-right text-sm font-medium text-gray-900">{formatUsd(d.amount_usd as number)}</td>
              <td className="whitespace-nowrap px-6 py-3 text-right text-sm text-gray-700">{(d.coins_equivalent as number)?.toLocaleString()}</td>
              <td className="px-6 py-3 text-sm text-gray-700">{(d.original_currency as string) ?? "USD"}</td>
              <td className="whitespace-nowrap px-6 py-3 text-right text-sm text-gray-700">
                {d.original_amount ? (d.original_amount as number).toLocaleString("pt-BR", { minimumFractionDigits: 2 }) : "-"}
              </td>
              <td className="whitespace-nowrap px-6 py-3 text-right text-sm text-gray-500">
                {d.fx_spread_pct ? `${d.fx_spread_pct}%` : "-"}
              </td>
              <td className="px-6 py-3 text-sm text-gray-500 capitalize">{d.payment_gateway as string}</td>
              <td className="px-6 py-3 text-sm">
                <span className="font-mono text-xs text-gray-500">{d.payment_reference ? (d.payment_reference as string).slice(0, 12) : "-"}</span>
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
    return <div className="px-6 py-12 text-center text-gray-500">Nenhuma retirada registrada.</div>;
  }

  return (
    <table className="min-w-full divide-y divide-gray-200">
      <thead className="bg-gray-50">
        <tr>
          <th className="px-6 py-3 text-left text-xs font-medium uppercase text-gray-500">Data</th>
          <th className="px-6 py-3 text-right text-xs font-medium uppercase text-gray-500">USD Debitado</th>
          <th className="px-6 py-3 text-left text-xs font-medium uppercase text-gray-500">Moeda Dest</th>
          <th className="px-6 py-3 text-right text-xs font-medium uppercase text-gray-500">Cotacao</th>
          <th className="px-6 py-3 text-right text-xs font-medium uppercase text-gray-500">Spread</th>
          <th className="px-6 py-3 text-right text-xs font-medium uppercase text-gray-500">Provider Fee</th>
          <th className="px-6 py-3 text-right text-xs font-medium uppercase text-gray-500">Valor Local</th>
          <th className="px-6 py-3 text-left text-xs font-medium uppercase text-gray-500">Status</th>
        </tr>
      </thead>
      <tbody className="divide-y divide-gray-200">
        {withdrawals.map((w) => {
          const st = WD_STATUS[(w.status as string)] ?? { label: w.status as string, color: "bg-gray-100 text-gray-600" };
          return (
            <tr key={w.id as string}>
              <td className="whitespace-nowrap px-6 py-3 text-sm text-gray-700">{formatDateTimeTz(w.created_at as string)}</td>
              <td className="whitespace-nowrap px-6 py-3 text-right text-sm font-medium text-red-700">-{formatUsd(w.amount_usd as number)}</td>
              <td className="px-6 py-3 text-sm text-gray-700">{w.target_currency as string}</td>
              <td className="whitespace-nowrap px-6 py-3 text-right text-sm text-gray-700">{(w.fx_rate as number)?.toFixed(4)}</td>
              <td className="whitespace-nowrap px-6 py-3 text-right text-sm text-gray-500">
                {String(w.fx_spread_pct ?? 0)}% ({formatUsd(w.fx_spread_usd as number)})
              </td>
              <td className="whitespace-nowrap px-6 py-3 text-right text-sm text-gray-500">{formatUsd(w.provider_fee_usd as number)}</td>
              <td className="whitespace-nowrap px-6 py-3 text-right text-sm font-medium text-gray-900">
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
