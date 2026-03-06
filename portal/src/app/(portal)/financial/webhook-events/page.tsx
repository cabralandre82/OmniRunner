import { cookies } from "next/headers";
import { createClient } from "@/lib/supabase/server";
import { NoGroupSelected } from "@/components/no-group-selected";

export const dynamic = "force-dynamic";

const EVENT_BADGE: Record<string, { label: string; cls: string }> = {
  PAYMENT_CONFIRMED: { label: "Confirmado", cls: "bg-green-100 text-green-800 dark:bg-green-900/30 dark:text-green-300" },
  PAYMENT_RECEIVED: { label: "Recebido", cls: "bg-green-100 text-green-800 dark:bg-green-900/30 dark:text-green-300" },
  PAYMENT_OVERDUE: { label: "Vencido", cls: "bg-red-100 text-red-800 dark:bg-red-900/30 dark:text-red-300" },
  PAYMENT_REFUNDED: { label: "Reembolsado", cls: "bg-yellow-100 text-yellow-800 dark:bg-yellow-900/30 dark:text-yellow-300" },
  PAYMENT_DELETED: { label: "Deletado", cls: "bg-gray-100 text-gray-600 dark:bg-gray-700/30 dark:text-gray-400" },
  SUBSCRIPTION_INACTIVATED: { label: "Sub Inativada", cls: "bg-orange-100 text-orange-800 dark:bg-orange-900/30 dark:text-orange-300" },
  SUBSCRIPTION_DELETED: { label: "Sub Deletada", cls: "bg-red-100 text-red-800 dark:bg-red-900/30 dark:text-red-300" },
};

export default async function WebhookEventsPage() {
  const groupId = cookies().get("portal_group_id")?.value;
  const role = cookies().get("portal_role")?.value;

  if (!groupId) return <NoGroupSelected />;

  if (role !== "admin_master") {
    return (
      <div className="rounded-xl border border-border bg-surface p-6 shadow-sm">
        <p className="text-content-secondary">Acesso restrito a administradores.</p>
      </div>
    );
  }

  const supabase = createClient();

  const { data: events, count } = await supabase
    .from("payment_webhook_events")
    .select("id, asaas_event_id, event_type, asaas_payment_id, processed, error_message, created_at, processed_at", { count: "exact" })
    .eq("group_id", groupId)
    .order("created_at", { ascending: false })
    .limit(100);

  const total = count ?? 0;
  const processed = (events ?? []).filter((e) => e.processed).length;
  const failed = (events ?? []).filter((e) => !e.processed && e.error_message).length;
  const pending = (events ?? []).filter((e) => !e.processed && !e.error_message).length;

  const formatDate = (d: string | null) => {
    if (!d) return "—";
    try {
      return new Date(d).toLocaleDateString("pt-BR", {
        day: "2-digit", month: "2-digit", year: "2-digit",
        hour: "2-digit", minute: "2-digit",
      });
    } catch { return d; }
  };

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-content-primary">Eventos de Webhook</h1>
        <p className="mt-1 text-sm text-content-secondary">
          Log de eventos recebidos do Asaas — últimos 100
        </p>
      </div>

      {/* KPI badges */}
      <div className="flex flex-wrap gap-3">
        <div className="rounded-lg border border-border bg-surface px-4 py-2 text-sm">
          <span className="font-semibold text-content-primary">{total}</span>{" "}
          <span className="text-content-secondary">total</span>
        </div>
        <div className="rounded-lg border border-green-200 bg-green-50 px-4 py-2 text-sm dark:border-green-800 dark:bg-green-900/20">
          <span className="font-semibold text-green-800 dark:text-green-300">{processed}</span>{" "}
          <span className="text-green-700 dark:text-green-400">processados</span>
        </div>
        {pending > 0 && (
          <div className="rounded-lg border border-yellow-200 bg-yellow-50 px-4 py-2 text-sm dark:border-yellow-800 dark:bg-yellow-900/20">
            <span className="font-semibold text-yellow-800 dark:text-yellow-300">{pending}</span>{" "}
            <span className="text-yellow-700 dark:text-yellow-400">pendentes</span>
          </div>
        )}
        {failed > 0 && (
          <div className="rounded-lg border border-red-200 bg-red-50 px-4 py-2 text-sm dark:border-red-800 dark:bg-red-900/20">
            <span className="font-semibold text-red-800 dark:text-red-300">{failed}</span>{" "}
            <span className="text-red-700 dark:text-red-400">com erro</span>
          </div>
        )}
      </div>

      {/* Events table */}
      <div className="rounded-xl border border-border bg-surface shadow-sm">
        <div className="overflow-x-auto">
          <table className="min-w-full divide-y divide-border text-sm">
            <thead className="bg-bg-secondary">
              <tr>
                <th className="px-4 py-3 text-left font-medium text-content-secondary">Evento</th>
                <th className="px-4 py-3 text-left font-medium text-content-secondary">Payment ID</th>
                <th className="px-4 py-3 text-center font-medium text-content-secondary">Status</th>
                <th className="px-4 py-3 text-left font-medium text-content-secondary">Recebido</th>
                <th className="px-4 py-3 text-left font-medium text-content-secondary">Processado</th>
                <th className="px-4 py-3 text-left font-medium text-content-secondary">Erro</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-border-subtle">
              {(events ?? []).map((ev) => {
                const badge = EVENT_BADGE[ev.event_type];
                return (
                  <tr key={ev.id} className="hover:bg-surface-elevated">
                    <td className="whitespace-nowrap px-4 py-3">
                      {badge ? (
                        <span className={`inline-flex rounded-full px-2.5 py-0.5 text-xs font-medium ${badge.cls}`}>
                          {badge.label}
                        </span>
                      ) : (
                        <span className="text-xs text-content-muted">{ev.event_type}</span>
                      )}
                    </td>
                    <td className="whitespace-nowrap px-4 py-3 font-mono text-xs text-content-secondary">
                      {ev.asaas_payment_id ? ev.asaas_payment_id.slice(0, 16) : "—"}
                    </td>
                    <td className="whitespace-nowrap px-4 py-3 text-center">
                      {ev.processed ? (
                        <span className="inline-flex h-5 w-5 items-center justify-center rounded-full bg-green-100 text-green-600 dark:bg-green-900/30 dark:text-green-400">
                          ✓
                        </span>
                      ) : (
                        <span className="inline-flex h-5 w-5 items-center justify-center rounded-full bg-yellow-100 text-yellow-600 dark:bg-yellow-900/30 dark:text-yellow-400">
                          ○
                        </span>
                      )}
                    </td>
                    <td className="whitespace-nowrap px-4 py-3 text-xs text-content-secondary">
                      {formatDate(ev.created_at)}
                    </td>
                    <td className="whitespace-nowrap px-4 py-3 text-xs text-content-secondary">
                      {formatDate(ev.processed_at)}
                    </td>
                    <td className="px-4 py-3 text-xs text-error max-w-[200px] truncate">
                      {ev.error_message ?? "—"}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>

        {(events ?? []).length === 0 && (
          <div className="p-6 text-center text-sm text-content-secondary">
            Nenhum evento de webhook recebido ainda.
          </div>
        )}
      </div>
    </div>
  );
}
