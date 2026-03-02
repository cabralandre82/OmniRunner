import type { Metadata } from "next";
import { cookies } from "next/headers";
import { createServiceClient } from "@/lib/supabase/service";
import { DepositButton } from "./deposit-button";
import { formatUsd } from "@/lib/format";

export const metadata: Metadata = { title: "Custódia" };
export const dynamic = "force-dynamic";

export default async function CustodyPage() {
  const groupId = cookies().get("portal_group_id")?.value;
  if (!groupId) return null;

  const db = createServiceClient();

  const [accountRes, depositsRes] = await Promise.all([
    db
      .from("custody_accounts")
      .select("*")
      .eq("group_id", groupId)
      .maybeSingle(),
    db
      .from("custody_deposits")
      .select("*")
      .eq("group_id", groupId)
      .order("created_at", { ascending: false })
      .limit(20),
  ]);

  const account = accountRes.data;
  const deposits = depositsRes.data ?? [];

  const deposited = account?.total_deposited_usd ?? 0;
  const committed = account?.total_committed ?? 0;
  const available = deposited - committed;
  const settled = account?.total_settled_usd ?? 0;
  const isBlocked = account?.is_blocked ?? false;

  const statusLabels: Record<string, { label: string; color: string }> = {
    pending: { label: "Pendente", color: "bg-yellow-100 text-yellow-800" },
    confirmed: { label: "Confirmado", color: "bg-green-100 text-green-800" },
    failed: { label: "Falhou", color: "bg-red-100 text-red-800" },
    refunded: { label: "Reembolsado", color: "bg-gray-100 text-gray-600" },
  };

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Custódia</h1>
          <p className="mt-1 text-sm text-gray-500">
            Lastro obrigatório — 1 coin = US$ 1.00
          </p>
        </div>
        <DepositButton />
      </div>

      {isBlocked && (
        <div className="rounded-lg border border-red-200 bg-red-50 p-4">
          <p className="font-medium text-red-800">
            Emissão bloqueada — {account?.blocked_reason ?? "saldo insuficiente"}
          </p>
        </div>
      )}

      {/* KPI Cards */}
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <div className="rounded-xl border border-gray-200 bg-white p-5 shadow-sm">
          <p className="text-sm font-medium text-gray-500">Total Depositado</p>
          <p className="mt-1 text-2xl font-bold text-gray-900">
            {formatUsd(deposited)}
          </p>
        </div>
        <div className="rounded-xl border border-gray-200 bg-white p-5 shadow-sm">
          <p className="text-sm font-medium text-gray-500">Em Circulação</p>
          <p className="mt-1 text-2xl font-bold text-blue-600">
            {committed.toLocaleString()} coins
          </p>
        </div>
        <div className="rounded-xl border border-gray-200 bg-white p-5 shadow-sm">
          <p className="text-sm font-medium text-gray-500">Disponível</p>
          <p className={`mt-1 text-2xl font-bold ${available > 0 ? "text-green-600" : "text-red-600"}`}>
            {formatUsd(available)}
          </p>
        </div>
        <div className="rounded-xl border border-gray-200 bg-white p-5 shadow-sm">
          <p className="text-sm font-medium text-gray-500">Total Liquidado</p>
          <p className="mt-1 text-2xl font-bold text-gray-600">
            {formatUsd(settled)}
          </p>
        </div>
      </div>

      {/* Deposit History */}
      <div className="rounded-xl border border-gray-200 bg-white shadow-sm">
        <div className="border-b border-gray-200 px-6 py-4">
          <h2 className="text-lg font-semibold text-gray-900">
            Histórico de Depósitos
          </h2>
        </div>

        {deposits.length === 0 ? (
          <div className="px-6 py-12 text-center text-gray-500">
            Nenhum depósito realizado ainda.
          </div>
        ) : (
          <table className="min-w-full divide-y divide-gray-200">
            <thead className="bg-gray-50">
              <tr>
                <th className="px-6 py-3 text-left text-xs font-medium uppercase text-gray-500">
                  Data
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium uppercase text-gray-500">
                  Valor (USD)
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium uppercase text-gray-500">
                  Coins
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium uppercase text-gray-500">
                  Gateway
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium uppercase text-gray-500">
                  Status
                </th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-200">
              {deposits.map((d: Record<string, unknown>) => {
                const st = statusLabels[(d.status as string) ?? ""] ?? {
                  label: d.status,
                  color: "bg-gray-100 text-gray-600",
                };
                return (
                  <tr key={d.id as string}>
                    <td className="whitespace-nowrap px-6 py-4 text-sm text-gray-700">
                      {new Date(d.created_at as string).toLocaleDateString(
                        "pt-BR",
                        {
                          day: "2-digit",
                          month: "2-digit",
                          year: "numeric",
                          hour: "2-digit",
                          minute: "2-digit",
                        },
                      )}
                    </td>
                    <td className="whitespace-nowrap px-6 py-4 text-sm font-medium text-gray-900">
                      {formatUsd(d.amount_usd as number)}
                    </td>
                    <td className="whitespace-nowrap px-6 py-4 text-sm text-gray-700">
                      {(d.coins_equivalent as number).toLocaleString()}
                    </td>
                    <td className="whitespace-nowrap px-6 py-4 text-sm text-gray-500 capitalize">
                      {d.payment_gateway as string}
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
