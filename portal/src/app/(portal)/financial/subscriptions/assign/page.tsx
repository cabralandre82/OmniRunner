import { cookies } from "next/headers";
import { createClient } from "@/lib/supabase/server";
import { NoGroupSelected } from "@/components/no-group-selected";
import { AssignSubscriptionClient } from "./assign-client";

export const dynamic = "force-dynamic";

interface Athlete {
  member_id: string;
  user_id: string;
  display_name: string;
  email: string | null;
  cpf: string | null;
  current_plan: string | null;
  current_status: string | null;
  next_due_date: string | null;
}

interface Plan {
  id: string;
  name: string;
  monthly_price: number;
  billing_cycle: string;
}

async function getData(groupId: string) {
  const supabase = createClient();

  const { data: members } = await supabase
    .from("coaching_members")
    .select("id, user_id, display_name, cpf")
    .eq("group_id", groupId)
    .in("role", ["athlete", "atleta"])
    .order("display_name");

  if (!members || members.length === 0) {
    return { athletes: [] as Athlete[], plans: [] as Plan[] };
  }

  const athleteIds = members.map((m) => m.user_id);

  const { data: subs } = await supabase
    .from("coaching_subscriptions")
    .select("athlete_user_id, status, next_due_date, coaching_plans(name)")
    .eq("group_id", groupId)
    .in("athlete_user_id", athleteIds);

  const subMap = new Map<
    string,
    { plan_name: string; status: string; next_due_date: string | null }
  >();
  for (const s of subs ?? []) {
    const planObj = s.coaching_plans as unknown as { name: string } | null;
    subMap.set(s.athlete_user_id, {
      plan_name: planObj?.name ?? "—",
      status: s.status,
      next_due_date: s.next_due_date,
    });
  }

  const athletes: Athlete[] = members.map((m) => {
    const sub = subMap.get(m.user_id);
    return {
      member_id: m.id,
      user_id: m.user_id,
      display_name: m.display_name,
      email: null,
      cpf: m.cpf ?? null,
      current_plan: sub?.plan_name ?? null,
      current_status: sub?.status ?? null,
      next_due_date: sub?.next_due_date ?? null,
    };
  });

  const { data: plans } = await supabase
    .from("coaching_plans")
    .select("id, name, monthly_price, billing_cycle")
    .eq("group_id", groupId)
    .eq("status", "active")
    .order("name");

  // Check if Asaas is active for this group
  const { data: asaasConfig } = await supabase
    .from("payment_provider_config")
    .select("is_active")
    .eq("group_id", groupId)
    .eq("provider", "asaas")
    .maybeSingle();

  return {
    athletes,
    plans: (plans ?? []) as Plan[],
    asaasActive: asaasConfig?.is_active ?? false,
  };
}

export default async function AssignSubscriptionPage() {
  const groupId = cookies().get("portal_group_id")?.value;
  if (!groupId) return <NoGroupSelected />;

  const { athletes, plans, asaasActive } = await getData(groupId);

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-content-primary">
          Atribuir Plano
        </h1>
        <p className="mt-1 text-sm text-content-secondary">
          Selecione atletas, escolha um plano e defina as datas
        </p>
      </div>

      <AssignSubscriptionClient
        athletes={athletes}
        plans={plans}
        asaasActive={asaasActive}
      />
    </div>
  );
}
