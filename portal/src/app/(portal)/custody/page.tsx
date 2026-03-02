import type { Metadata } from "next";
import { cookies } from "next/headers";
import { createServiceClient } from "@/lib/supabase/service";
import { DepositButton } from "./deposit-button";
import { CustodyTabs } from "./custody-tabs";
import { formatUsd } from "@/lib/format";
import Link from "next/link";

export const metadata: Metadata = { title: "Custodia" };
export const dynamic = "force-dynamic";

export default async function CustodyPage() {
  const groupId = cookies().get("portal_group_id")?.value;
  if (!groupId) return null;

  const db = createServiceClient();

  const [accountRes, depositsRes, withdrawalsRes, coinsRes, settlementsInRes, settlementsOutRes] =
    await Promise.all([
      db.from("custody_accounts").select("*").eq("group_id", groupId).maybeSingle(),
      db.from("custody_deposits").select("*").eq("group_id", groupId).order("created_at", { ascending: false }).limit(50),
      db.from("custody_withdrawals").select("*").eq("group_id", groupId).order("created_at", { ascending: false }).limit(50),
      db.from("coin_ledger").select("delta_coins").eq("issuer_group_id", groupId),
      db.from("clearing_settlements").select("id, net_amount_usd, status, created_at, settled_at").eq("creditor_group_id", groupId).order("created_at", { ascending: false }).limit(30),
      db.from("clearing_settlements").select("id, gross_amount_usd, status, created_at").eq("debtor_group_id", groupId).order("created_at", { ascending: false }).limit(30),
    ]);

  const account = accountRes.data;
  const deposits = depositsRes.data ?? [];
  const withdrawals = withdrawalsRes.data ?? [];

  const deposited = account?.total_deposited_usd ?? 0;
  const committed = account?.total_committed ?? 0;
  const available = deposited - committed;
  const settled = account?.total_settled_usd ?? 0;
  const isBlocked = account?.is_blocked ?? false;

  const coinsAlive = (coinsRes.data ?? []).reduce(
    (sum: number, r: { delta_coins: number }) => sum + r.delta_coins, 0,
  );

  const invTotalOk = Math.abs(deposited - (committed + available)) < 0.01;
  const invReservedOk = Math.abs(committed - coinsAlive) < 0.01;

  // Build custody ledger (extrato)
  type LedgerEntry = {
    date: string; type: string; amount: number;
    ref_id: string; ref_type: string; status: string;
  };
  const ledger: LedgerEntry[] = [];

  for (const d of deposits) {
    ledger.push({
      date: d.created_at, type: "Deposito",
      amount: d.status === "confirmed" ? d.amount_usd : 0,
      ref_id: d.id, ref_type: "deposit", status: d.status,
    });
  }
  for (const w of withdrawals) {
    ledger.push({
      date: w.created_at, type: "Retirada",
      amount: -(w.amount_usd ?? 0),
      ref_id: w.id, ref_type: "withdrawal", status: w.status,
    });
  }
  for (const s of (settlementsInRes.data ?? [])) {
    if (s.status === "settled") {
      ledger.push({
        date: s.settled_at ?? s.created_at, type: "Clearing Recebido",
        amount: s.net_amount_usd, ref_id: s.id, ref_type: "settlement", status: s.status,
      });
    }
  }
  for (const s of (settlementsOutRes.data ?? [])) {
    if (s.status === "settled") {
      ledger.push({
        date: s.created_at, type: "Clearing Pago",
        amount: -(s.gross_amount_usd ?? 0), ref_id: s.id, ref_type: "settlement", status: s.status,
      });
    }
  }
  ledger.sort((a, b) => new Date(b.date).getTime() - new Date(a.date).getTime());

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Custodia</h1>
          <p className="mt-1 text-sm text-gray-500">
            Lastro obrigatorio &mdash; 1 coin = US$ 1.00
          </p>
        </div>
        <div className="flex items-center gap-2">
          <Link href="/swap" className="rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50">
            Swap
          </Link>
          <DepositButton />
        </div>
      </div>

      {isBlocked && (
        <div className="rounded-lg border border-red-200 bg-red-50 p-4">
          <p className="font-medium text-red-800">
            Emissao bloqueada &mdash; {account?.blocked_reason ?? "saldo insuficiente"}
          </p>
        </div>
      )}

      {/* KPI Cards */}
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-5">
        <div className="rounded-xl border border-gray-200 bg-white p-5 shadow-sm">
          <p className="text-sm font-medium text-gray-500">Total Depositado</p>
          <p className="mt-1 text-2xl font-bold text-gray-900">{formatUsd(deposited)}</p>
        </div>
        <div className="rounded-xl border border-gray-200 bg-white p-5 shadow-sm">
          <p className="text-sm font-medium text-gray-500">Reservado (Lastro)</p>
          <p className="mt-1 text-2xl font-bold text-blue-600">{formatUsd(committed)}</p>
        </div>
        <div className="rounded-xl border border-gray-200 bg-white p-5 shadow-sm">
          <p className="text-sm font-medium text-gray-500">Disponivel</p>
          <p className={`mt-1 text-2xl font-bold ${available > 0 ? "text-green-600" : "text-red-600"}`}>
            {formatUsd(available)}
          </p>
        </div>
        <div className="rounded-xl border border-gray-200 bg-white p-5 shadow-sm">
          <p className="text-sm font-medium text-gray-500">Coins Vivas</p>
          <p className="mt-1 text-2xl font-bold text-purple-600">{coinsAlive.toLocaleString()}</p>
        </div>
        <div className="rounded-xl border border-gray-200 bg-white p-5 shadow-sm">
          <p className="text-sm font-medium text-gray-500">Total Liquidado</p>
          <p className="mt-1 text-2xl font-bold text-gray-600">{formatUsd(settled)}</p>
        </div>
      </div>

      {/* Invariant Badges */}
      <div className="flex flex-wrap gap-3">
        <span className={`inline-flex items-center gap-1.5 rounded-full px-3 py-1 text-xs font-medium ${invTotalOk ? "bg-green-100 text-green-800" : "bg-red-100 text-red-800"}`}>
          {invTotalOk ? "\u2713" : "\u26A0"} Total = Reservado + Disponivel
        </span>
        <span className={`inline-flex items-center gap-1.5 rounded-full px-3 py-1 text-xs font-medium ${invReservedOk ? "bg-green-100 text-green-800" : "bg-red-100 text-red-800"}`}>
          {invReservedOk ? "\u2713" : "\u26A0"} Reservado = Coins Vivas ({coinsAlive})
        </span>
        {(!invTotalOk || !invReservedOk) && (
          <Link href="/audit" className="text-xs font-medium text-red-600 underline">
            Ver Auditoria
          </Link>
        )}
      </div>

      {/* Tabs: Extrato / Depositos / Retiradas */}
      <CustodyTabs
        ledger={ledger}
        deposits={deposits}
        withdrawals={withdrawals}
      />
    </div>
  );
}
