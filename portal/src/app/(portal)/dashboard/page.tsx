import { cookies } from "next/headers";
import { createClient } from "@/lib/supabase/server";

interface KPI {
  label: string;
  value: string;
  detail?: string;
}

export default async function DashboardPage() {
  const groupId = cookies().get("portal_group_id")?.value;
  const role = cookies().get("portal_role")?.value ?? "assistente";

  if (!groupId) return null;

  const supabase = createClient();

  const [inventoryRes, membersRes, purchasesRes] = await Promise.all([
    supabase
      .from("coaching_token_inventory")
      .select("available_tokens")
      .eq("group_id", groupId)
      .maybeSingle(),

    supabase
      .from("coaching_members")
      .select("role", { count: "exact", head: true })
      .eq("group_id", groupId)
      .eq("role", "atleta"),

    role === "admin_master"
      ? supabase
          .from("billing_purchases")
          .select("status, credits_amount")
          .eq("group_id", groupId)
      : Promise.resolve({ data: null }),
  ]);

  const credits = inventoryRes.data?.available_tokens ?? 0;
  const athleteCount = membersRes.count ?? 0;

  let purchasesFulfilled = 0;
  let totalCreditsBought = 0;
  if (purchasesRes.data) {
    for (const p of purchasesRes.data) {
      if ((p as { status: string }).status === "fulfilled") {
        purchasesFulfilled++;
        totalCreditsBought += (p as { credits_amount: number }).credits_amount;
      }
    }
  }

  const kpis: KPI[] = [
    {
      label: "Créditos Disponíveis",
      value: credits.toLocaleString("pt-BR"),
    },
    {
      label: "Atletas",
      value: athleteCount.toLocaleString("pt-BR"),
    },
  ];

  if (role === "admin_master") {
    kpis.push(
      {
        label: "Compras Realizadas",
        value: purchasesFulfilled.toLocaleString("pt-BR"),
      },
      {
        label: "Total Créditos Adquiridos",
        value: totalCreditsBought.toLocaleString("pt-BR"),
      },
    );
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-gray-900">Dashboard</h1>
        <p className="mt-1 text-sm text-gray-500">
          Visão geral da assessoria
        </p>
      </div>

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        {kpis.map((kpi) => (
          <div
            key={kpi.label}
            className="rounded-xl border border-gray-200 bg-white p-5 shadow-sm"
          >
            <p className="text-xs font-medium uppercase tracking-wide text-gray-500">
              {kpi.label}
            </p>
            <p className="mt-2 text-2xl font-bold text-gray-900">{kpi.value}</p>
            {kpi.detail && (
              <p className="mt-1 text-xs text-gray-400">{kpi.detail}</p>
            )}
          </div>
        ))}
      </div>

      {role === "admin_master" && (
        <div className="rounded-xl border border-gray-200 bg-white p-6 shadow-sm">
          <h2 className="text-sm font-semibold text-gray-900">Acesso Rápido</h2>
          <div className="mt-3 flex flex-wrap gap-2">
            <a
              href="/billing"
              className="rounded-lg bg-blue-50 px-3 py-1.5 text-xs font-medium text-blue-700 hover:bg-blue-100"
            >
              Comprar Créditos
            </a>
            <a
              href="/credits"
              className="rounded-lg bg-gray-100 px-3 py-1.5 text-xs font-medium text-gray-700 hover:bg-gray-200"
            >
              Ver Estoque
            </a>
            <a
              href="/athletes"
              className="rounded-lg bg-gray-100 px-3 py-1.5 text-xs font-medium text-gray-700 hover:bg-gray-200"
            >
              Ver Atletas
            </a>
          </div>
        </div>
      )}
    </div>
  );
}
