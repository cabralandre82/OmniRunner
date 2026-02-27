import { createAdminClient } from "@/lib/supabase/admin";
import { RefundActions } from "./actions";
import Link from "next/link";

export const dynamic = "force-dynamic";

interface RefundRequest {
  id: string;
  purchase_id: string;
  group_id: string;
  status: string;
  reason: string;
  refund_type: string;
  amount_cents: number | null;
  credits_to_debit: number | null;
  requested_at: string;
  reviewed_at: string | null;
  review_notes: string | null;
  group_name?: string;
  purchase_price_cents?: number;
  purchase_credits?: number;
}

export default async function ReembolsosPage({
  searchParams,
}: {
  searchParams: { status?: string };
}) {
  const supabase = createAdminClient();
  const filterStatus = searchParams.status;

  let query = supabase
    .from("billing_refund_requests")
    .select(
      "id, purchase_id, group_id, status, reason, refund_type, amount_cents, credits_to_debit, requested_at, reviewed_at, review_notes",
    )
    .order("requested_at", { ascending: false });

  if (filterStatus && filterStatus !== "all") {
    query = query.eq("status", filterStatus);
  }

  const { data: rawRequests } = await query;

  const groupIds = Array.from(new Set((rawRequests ?? []).map((r) => r.group_id)));
  const purchaseIds = Array.from(
    new Set((rawRequests ?? []).map((r) => r.purchase_id)),
  );
  const groupMap: Record<string, string> = {};
  const purchaseMap: Record<string, { price_cents: number; credits_amount: number }> = {};

  if (groupIds.length > 0) {
    const { data: groups } = await supabase
      .from("coaching_groups")
      .select("id, name")
      .in("id", groupIds);
    for (const g of groups ?? []) {
      groupMap[g.id] = g.name;
    }
  }

  if (purchaseIds.length > 0) {
    const { data: purchases } = await supabase
      .from("billing_purchases")
      .select("id, price_cents, credits_amount")
      .in("id", purchaseIds);
    for (const p of purchases ?? []) {
      purchaseMap[p.id] = {
        price_cents: p.price_cents,
        credits_amount: p.credits_amount,
      };
    }
  }

  const requests: RefundRequest[] = (rawRequests ?? []).map((r) => ({
    ...r,
    group_name: groupMap[r.group_id] ?? "—",
    purchase_price_cents: purchaseMap[r.purchase_id]?.price_cents ?? 0,
    purchase_credits: purchaseMap[r.purchase_id]?.credits_amount ?? 0,
  }));

  const pendingCount = requests.filter(
    (r) => r.status === "requested" || r.status === "approved",
  ).length;

  const fmt = (cents: number) =>
    (cents / 100).toLocaleString("pt-BR", {
      style: "currency",
      currency: "BRL",
    });

  const statusLabel: Record<string, string> = {
    requested: "Solicitado",
    approved: "Aprovado",
    processed: "Processado",
    rejected: "Rejeitado",
  };

  const statusColor: Record<string, string> = {
    requested: "bg-orange-100 text-orange-700",
    approved: "bg-blue-100 text-blue-700",
    processed: "bg-green-100 text-green-700",
    rejected: "bg-red-100 text-red-700",
  };

  const filters = [
    { key: "all", label: "Todos" },
    { key: "requested", label: "Solicitados" },
    { key: "approved", label: "Aprovados" },
    { key: "processed", label: "Processados" },
    { key: "rejected", label: "Rejeitados" },
  ];

  return (
    <div className="space-y-6">
      <div className="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Reembolsos</h1>
          <p className="mt-1 text-sm text-gray-500">
            {pendingCount > 0
              ? `${pendingCount} reembolso(s) aguardando ação`
              : "Nenhum reembolso pendente"}
          </p>
        </div>
        <Link
          href="/platform"
          className="text-sm text-gray-500 hover:text-gray-700"
        >
          ← Dashboard
        </Link>
      </div>

      {/* Filters */}
      <div className="flex flex-wrap gap-1.5">
        {filters.map((f) => {
          const active =
            (filterStatus ?? "all") === f.key ||
            (!filterStatus && f.key === "all");
          return (
            <Link
              key={f.key}
              href={`/platform/reembolsos?status=${f.key}`}
              className={`rounded-full px-3.5 py-1.5 text-sm font-medium transition ${
                active
                  ? "bg-gray-900 text-white"
                  : "bg-gray-100 text-gray-600 hover:bg-gray-200"
              }`}
            >
              {f.label}
            </Link>
          );
        })}
      </div>

      {/* List */}
      {requests.length === 0 ? (
        <div className="py-16 text-center">
          <p className="text-sm text-gray-400">
            Nenhum reembolso encontrado.
          </p>
        </div>
      ) : (
        <div className="space-y-3">
          {requests.map((r) => {
            const refundAmount =
              r.refund_type === "partial" && r.amount_cents
                ? r.amount_cents
                : r.purchase_price_cents ?? 0;

            return (
              <div
                key={r.id}
                className="rounded-xl border border-gray-200 bg-white p-4 sm:p-5 shadow-sm"
              >
                <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
                  <div className="min-w-0 flex-1">
                    <div className="flex flex-wrap items-center gap-2">
                      <h3 className="text-sm font-semibold text-gray-900">
                        {r.group_name}
                      </h3>
                      <span
                        className={`rounded-full px-2 py-0.5 text-xs font-medium ${
                          statusColor[r.status] ?? "bg-gray-100"
                        }`}
                      >
                        {statusLabel[r.status] ?? r.status}
                      </span>
                      <span className="text-xs text-gray-400">
                        {r.refund_type === "partial" ? "Parcial" : "Total"}
                      </span>
                    </div>

                    <div className="mt-2 flex flex-wrap gap-x-4 gap-y-1 text-xs text-gray-500">
                      <span>
                        Valor: <strong>{fmt(refundAmount)}</strong>
                      </span>
                      <span>
                        Compra original: {fmt(r.purchase_price_cents ?? 0)} /{" "}
                        {r.purchase_credits} créditos
                      </span>
                      <span>
                        {new Date(r.requested_at).toLocaleDateString("pt-BR", {
                          day: "2-digit",
                          month: "short",
                          year: "numeric",
                        })}
                      </span>
                    </div>

                    <p className="mt-2 text-xs text-gray-600">
                      Motivo: {r.reason}
                    </p>

                    {r.review_notes && (
                      <p className="mt-1 text-xs text-blue-600">
                        Nota: {r.review_notes}
                      </p>
                    )}
                  </div>

                  <div className="flex shrink-0 flex-wrap gap-2">
                    {r.status === "requested" && (
                      <>
                        <RefundActions
                          refundId={r.id}
                          action="approve"
                          label="Aprovar"
                          className="rounded-lg bg-blue-600 px-3 py-1.5 text-xs font-medium text-white hover:bg-blue-700"
                        />
                        <RefundActions
                          refundId={r.id}
                          action="reject"
                          label="Rejeitar"
                          className="rounded-lg bg-red-50 px-3 py-1.5 text-xs font-medium text-red-600 hover:bg-red-100"
                          requireNotes
                        />
                      </>
                    )}
                    {r.status === "approved" && (
                      <RefundActions
                        refundId={r.id}
                        action="process"
                        label="Processar"
                        className="rounded-lg bg-green-600 px-3 py-1.5 text-xs font-medium text-white hover:bg-green-700"
                      />
                    )}
                  </div>
                </div>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
