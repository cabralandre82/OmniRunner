import { cookies } from "next/headers";
import { createClient } from "@/lib/supabase/server";
import { NoGroupSelected } from "@/components/no-group-selected";
import { formatDateISO } from "@/lib/format";
import Link from "next/link";

export const dynamic = "force-dynamic";

interface Subscription {
  id: string;
  athlete_user_id: string;
  plan_id: string;
  status: string;
  next_due_date: string | null;
  last_payment_at: string | null;
  started_at: string;
  athlete_display_name: string;
  plan_name: string;
}

async function getSubscriptions(
  groupId: string,
  statusFilter?: string,
): Promise<Subscription[]> {
  const supabase = createClient();

  let query = supabase
    .from("coaching_subscriptions")
    .select(
      "id, athlete_user_id, plan_id, status, next_due_date, last_payment_at, started_at, coaching_plans(name), profiles!athlete_user_id(display_name)",
    )
    .eq("group_id", groupId)
    .order("created_at", { ascending: false });

  if (statusFilter && statusFilter !== "all") {
    query = query.eq("status", statusFilter);
  }

  const { data } = await query;
  if (!data || data.length === 0) return [];

  return data.map((r: Record<string, unknown>) => ({
    id: r.id as string,
    athlete_user_id: r.athlete_user_id as string,
    plan_id: r.plan_id as string,
    status: r.status as string,
    next_due_date: r.next_due_date as string | null,
    last_payment_at: r.last_payment_at as string | null,
    started_at: r.started_at as string,
    athlete_display_name:
      ((r.profiles as Record<string, unknown> | null)?.display_name as string) ?? "—",
    plan_name:
      ((r.coaching_plans as Record<string, unknown> | null)?.name as string) ?? "—",
  }));
}

const STATUS_BADGE: Record<string, { label: string; cls: string }> = {
  active: { label: "Ativo", cls: "bg-success-soft text-success" },
  late: { label: "Inadimplente", cls: "bg-error-soft text-error" },
  paused: { label: "Pausado", cls: "bg-warning-soft text-warning" },
  cancelled: { label: "Cancelado", cls: "bg-surface-elevated text-content-secondary" },
};

export default async function SubscriptionsPage({
  searchParams,
}: {
  searchParams: Promise<{ status?: string }>;
}) {
  const groupId = cookies().get("portal_group_id")?.value;
  if (!groupId) return <NoGroupSelected />;

  const params = await searchParams;
  const statusFilter = params.status ?? "all";

  let subscriptions: Subscription[] = [];
  let fetchError: string | null = null;

  try {
    subscriptions = await getSubscriptions(groupId, statusFilter);
  } catch (e) {
    fetchError = String(e);
  }

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-content-primary">Assinaturas</h1>
          <p className="mt-1 text-sm text-content-secondary">
            Gerencie as assinaturas dos atletas
          </p>
        </div>
        <Link
          href="/financial"
          className="text-sm text-brand hover:text-brand hover:underline"
        >
          ← Dashboard
        </Link>
      </div>

      {fetchError && (
        <div className="rounded-lg border border-error/30 bg-error-soft p-6 text-center">
          <p className="text-error">Erro ao carregar dados. Tente recarregar a página.</p>
        </div>
      )}

      <div className="flex gap-2">
        {["all", "active", "late", "paused", "cancelled"].map((s) => (
          <Link
            key={s}
            href={`/financial/subscriptions${s !== "all" ? `?status=${s}` : ""}`}
            className={`rounded-lg px-3 py-1.5 text-xs font-medium transition ${
              statusFilter === s
                ? "bg-brand text-white"
                : "bg-surface-elevated text-content-secondary hover:bg-bg-secondary"
            }`}
          >
            {s === "all" ? "Todos" : (STATUS_BADGE[s]?.label ?? s)}
          </Link>
        ))}
      </div>

      <div className="overflow-hidden rounded-xl border border-border bg-surface shadow-sm">
        <div className="overflow-x-auto">
          <table className="min-w-full divide-y divide-border text-sm">
            <thead className="bg-bg-secondary">
              <tr>
                <th className="px-4 py-3 text-left font-medium text-content-secondary">Atleta</th>
                <th className="px-4 py-3 text-left font-medium text-content-secondary">Plano</th>
                <th className="px-4 py-3 text-center font-medium text-content-secondary">Status</th>
                <th className="px-4 py-3 text-left font-medium text-content-secondary">Próximo Vencimento</th>
                <th className="px-4 py-3 text-left font-medium text-content-secondary">Último Pagamento</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-border-subtle">
              {subscriptions.map((sub) => {
                const badge = STATUS_BADGE[sub.status] ?? {
                  label: sub.status,
                  cls: "bg-surface-elevated text-content-secondary",
                };
                return (
                  <tr key={sub.id} className="hover:bg-surface-elevated">
                    <td className="whitespace-nowrap px-4 py-3 font-medium text-content-primary">
                      {sub.athlete_display_name}
                    </td>
                    <td className="whitespace-nowrap px-4 py-3 text-content-secondary">
                      {sub.plan_name}
                    </td>
                    <td className="whitespace-nowrap px-4 py-3 text-center">
                      <span
                        className={`inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium ${badge.cls}`}
                      >
                        {badge.label}
                      </span>
                    </td>
                    <td className="whitespace-nowrap px-4 py-3 text-content-secondary">
                      {sub.next_due_date ? formatDateISO(sub.next_due_date) : "—"}
                    </td>
                    <td className="whitespace-nowrap px-4 py-3 text-content-secondary">
                      {sub.last_payment_at ? formatDateISO(sub.last_payment_at) : "—"}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </div>

      {subscriptions.length === 0 && !fetchError && (
        <div className="rounded-xl border border-border bg-surface p-8 text-center shadow-sm">
          <p className="text-sm text-content-secondary">Nenhuma assinatura encontrada.</p>
        </div>
      )}
    </div>
  );
}
