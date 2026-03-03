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
          <h1 className="text-2xl font-bold text-gray-900">Planos</h1>
          <p className="mt-1 text-sm text-gray-500">
            Configure planos e preços da assessoria
          </p>
        </div>
        <Link
          href="/financial"
          className="text-sm text-blue-600 hover:text-blue-800 hover:underline"
        >
          ← Dashboard
        </Link>
      </div>

      {fetchError && (
        <div className="rounded-lg border border-red-200 bg-red-50 p-6 text-center">
          <p className="text-red-600">Erro ao carregar dados. Tente recarregar a página.</p>
        </div>
      )}

      <div className="overflow-hidden rounded-xl border border-gray-200 bg-white shadow-sm">
        <div className="overflow-x-auto">
          <table className="min-w-full divide-y divide-gray-200 text-sm">
            <thead className="bg-gray-50">
              <tr>
                <th className="px-4 py-3 text-left font-medium text-gray-500">Nome</th>
                <th className="px-4 py-3 text-right font-medium text-gray-500">Preço Mensal</th>
                <th className="px-4 py-3 text-center font-medium text-gray-500">Ciclo</th>
                <th className="px-4 py-3 text-center font-medium text-gray-500">Limite Treinos/Sem</th>
                <th className="px-4 py-3 text-center font-medium text-gray-500">Status</th>
                <th className="px-4 py-3 text-center font-medium text-gray-500">Assinantes</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {plans.map((plan) => (
                <tr key={plan.id} className="hover:bg-gray-50">
                  <td className="whitespace-nowrap px-4 py-3 font-medium text-gray-900">
                    {plan.name}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-right text-gray-700">
                    R$ {plan.monthly_price.toFixed(2)}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-center text-gray-600">
                    {CYCLE_LABEL[plan.billing_cycle] ?? plan.billing_cycle}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-center text-gray-600">
                    {plan.max_workouts_per_week ?? "Ilimitado"}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-center">
                    <span
                      className={`inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium ${
                        plan.status === "active"
                          ? "bg-green-100 text-green-800"
                          : "bg-gray-100 text-gray-600"
                      }`}
                    >
                      {plan.status === "active" ? "Ativo" : "Inativo"}
                    </span>
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-center font-medium text-gray-900">
                    {plan.subscriber_count}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      {plans.length === 0 && !fetchError && (
        <div className="rounded-xl border border-gray-200 bg-white p-8 text-center shadow-sm">
          <p className="text-sm text-gray-500">Nenhum plano criado.</p>
        </div>
      )}
    </div>
  );
}
