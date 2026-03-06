import { cookies } from "next/headers";
import { createClient } from "@/lib/supabase/server";
import { NoGroupSelected } from "@/components/no-group-selected";
import Link from "next/link";
import { PlansClient } from "./plans-client";

export const dynamic = "force-dynamic";

interface Plan {
  id: string;
  name: string;
  description: string | null;
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
    .select(
      "id, name, description, monthly_price, billing_cycle, max_workouts_per_week, status",
    )
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
    description: p.description,
    monthly_price: p.monthly_price,
    billing_cycle: p.billing_cycle,
    max_workouts_per_week: p.max_workouts_per_week,
    status: p.status,
    subscriber_count: countMap.get(p.id) ?? 0,
  }));
}

export default async function PlansPage() {
  const groupId = cookies().get("portal_group_id")?.value;
  if (!groupId) return <NoGroupSelected />;

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
          className="text-sm text-content-secondary hover:text-primary"
        >
          ← Dashboard Financeiro
        </Link>
      </div>

      {fetchError && (
        <div className="rounded-lg border border-error/30 bg-error-soft p-6 text-center">
          <p className="text-error">Erro ao carregar dados.</p>
        </div>
      )}

      <PlansClient plans={plans} />
    </div>
  );
}
