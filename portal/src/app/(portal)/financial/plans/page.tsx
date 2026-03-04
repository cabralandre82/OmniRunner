import { cookies } from "next/headers";
import { createClient } from "@/lib/supabase/server";
import Link from "next/link";

export const dynamic = "force-dynamic";

interface Plan {
  id: string;
  name: string;
  monthly_price: number;
  billing_cycle: string;
  max_workouts_per_week: number | null;
  status: string;
  subscriber_count: number;
}

async function getPlans(groupId: string): Promise<Plan[]> {
  const supabase = createClient();

  const { data: plans } = await supabase
    .from("coaching_plans")
    .select("id, name, monthly_price, billing_cycle, max_workouts_per_week, status")
    .eq("group_id", groupId)
    .order("name");

  if (!plans || plans.length === 0) return [];

  const planIds = plans.map((p) => p.id);

  const { data: subs } = await supabase
    .from("coaching_subscriptions")
    .select("plan_id")
    .in("plan_id", planIds)
    .eq("status", "active");

  const countMap = new Map<string, number>();
  for (const s of subs ?? []) {
    const pid = (s as { plan_id: string }).plan_id;
    countMap.set(pid, (countMap.get(pid) ?? 0) + 1);
  }

  return plans.map((p) => ({
    id: p.id,
    name: p.name,
    monthly_price: p.monthly_price,
    billing_cycle: p.billing_cycle,
    max_workouts_per_week: p.max_workouts_per_week,
    status: p.status,
    subscriber_count: countMap.get(p.id) ?? 0,
  }));
}

const CYCLE_LABEL: Record<string, string> = {
  monthly: "Mensal",
  quarterly: "Trimestral",
};

export default async function PlansPage() {
  const groupId = cookies().get("portal_group_id")?.value;
  if (!groupId) return null;

  let plans: Plan[] = [];
  let fetchError: string | null = null;

  try {
    plans = await getPlans(groupId);
  } catch (e) {
    fetchError = String(e);
  }

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-content-primary">Planos</h1>
          <p className="mt-1 text-sm text-content-secondary">
            Configure planos e preços da assessoria
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

      <div className="overflow-hidden rounded-xl border border-border bg-surface shadow-sm">
        <div className="overflow-x-auto">
          <table className="min-w-full divide-y divide-border text-sm">
            <thead className="bg-bg-secondary">
              <tr>
                <th className="px-4 py-3 text-left font-medium text-content-secondary">Nome</th>
                <th className="px-4 py-3 text-right font-medium text-content-secondary">Preço Mensal</th>
                <th className="px-4 py-3 text-center font-medium text-content-secondary">Ciclo</th>
                <th className="px-4 py-3 text-center font-medium text-content-secondary">Limite Treinos/Sem</th>
                <th className="px-4 py-3 text-center font-medium text-content-secondary">Status</th>
                <th className="px-4 py-3 text-center font-medium text-content-secondary">Assinantes</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-border-subtle">
              {plans.map((plan) => (
                <tr key={plan.id} className="hover:bg-surface-elevated">
                  <td className="whitespace-nowrap px-4 py-3 font-medium text-content-primary">
                    {plan.name}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-right text-content-secondary">
                    R$ {plan.monthly_price.toFixed(2)}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-center text-content-secondary">
                    {CYCLE_LABEL[plan.billing_cycle] ?? plan.billing_cycle}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-center text-content-secondary">
                    {plan.max_workouts_per_week ?? "Ilimitado"}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-center">
                    <span
                      className={`inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium ${
                        plan.status === "active"
                          ? "bg-success-soft text-success"
                          : "bg-surface-elevated text-content-secondary"
                      }`}
                    >
                      {plan.status === "active" ? "Ativo" : "Inativo"}
                    </span>
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-center font-medium text-content-primary">
                    {plan.subscriber_count}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      {plans.length === 0 && !fetchError && (
        <div className="rounded-xl border border-border bg-surface p-8 text-center shadow-sm">
          <p className="text-sm text-content-secondary">Nenhum plano criado.</p>
        </div>
      )}
    </div>
  );
}
