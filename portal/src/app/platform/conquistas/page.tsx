import { createAdminClient } from "@/lib/supabase/admin";
import { BadgeForm } from "./badge-form";

export const dynamic = "force-dynamic";

const tierLabel: Record<string, string> = {
  bronze: "Bronze",
  silver: "Prata",
  gold: "Ouro",
  diamond: "Diamante",
};
const tierColor: Record<string, string> = {
  bronze: "bg-orange-100 text-orange-700",
  silver: "bg-gray-100 text-gray-700",
  gold: "bg-yellow-100 text-yellow-700",
  diamond: "bg-purple-100 text-purple-700",
};
const catLabel: Record<string, string> = {
  distance: "Distância",
  frequency: "Frequência",
  speed: "Velocidade",
  endurance: "Resistência",
  social: "Social",
  special: "Especial",
};

export default async function ConquistasPage() {
  const supabase = createAdminClient();

  const { data: badges, error } = await supabase
    .from("badges")
    .select("*")
    .order("category")
    .order("tier");

  const { count: totalAwards } = await supabase
    .from("badge_awards")
    .select("id", { count: "exact", head: true });

  if (error) {
    console.error("Failed to fetch badges:", error);
  }

  const allBadges = badges ?? [];
  const categories = [...new Set(allBadges.map((b) => b.category as string))];

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Conquistas</h1>
          <p className="mt-1 text-sm text-gray-500">
            {allBadges.length} conquistas cadastradas · {totalAwards ?? 0}{" "}
            desbloqueios totais
          </p>
        </div>
      </div>

      <BadgeForm />

      {categories.map((cat) => {
        const catBadges = allBadges.filter((b) => b.category === cat);
        return (
          <div key={cat}>
            <h2 className="mb-3 text-xs font-semibold uppercase tracking-wider text-gray-400">
              {catLabel[cat] ?? cat} ({catBadges.length})
            </h2>
            <div className="overflow-hidden rounded-xl border border-gray-200 bg-white shadow-sm">
              <table className="min-w-full divide-y divide-gray-100">
                <thead className="bg-gray-50">
                  <tr>
                    <th className="px-4 py-3 text-left text-xs font-medium uppercase text-gray-500">
                      Nome
                    </th>
                    <th className="px-4 py-3 text-left text-xs font-medium uppercase text-gray-500">
                      Tier
                    </th>
                    <th className="px-4 py-3 text-left text-xs font-medium uppercase text-gray-500">
                      Descrição
                    </th>
                    <th className="px-4 py-3 text-center text-xs font-medium uppercase text-gray-500">
                      XP
                    </th>
                    <th className="px-4 py-3 text-center text-xs font-medium uppercase text-gray-500">
                      Coins
                    </th>
                    <th className="px-4 py-3 text-center text-xs font-medium uppercase text-gray-500">
                      Critério
                    </th>
                    <th className="px-4 py-3 text-center text-xs font-medium uppercase text-gray-500">
                      Secreta
                    </th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-100">
                  {catBadges.map((b) => (
                    <tr key={b.id} className="hover:bg-gray-50">
                      <td className="px-4 py-3">
                        <p className="text-sm font-medium text-gray-900">
                          {b.name}
                        </p>
                        <p className="text-xs text-gray-400">{b.id}</p>
                      </td>
                      <td className="px-4 py-3">
                        <span
                          className={`rounded-full px-2 py-0.5 text-xs font-medium ${tierColor[b.tier] ?? "bg-gray-100"}`}
                        >
                          {tierLabel[b.tier] ?? b.tier}
                        </span>
                      </td>
                      <td className="px-4 py-3 text-sm text-gray-600 max-w-xs truncate">
                        {b.description}
                      </td>
                      <td className="px-4 py-3 text-center text-sm font-medium text-blue-600">
                        {b.xp_reward}
                      </td>
                      <td className="px-4 py-3 text-center text-sm font-medium text-amber-600">
                        {b.coins_reward > 0 ? b.coins_reward : "—"}
                      </td>
                      <td className="px-4 py-3 text-center">
                        <code className="rounded bg-gray-100 px-1.5 py-0.5 text-xs text-gray-600">
                          {b.criteria_type}
                        </code>
                      </td>
                      <td className="px-4 py-3 text-center text-sm">
                        {b.is_secret ? "🔒" : "—"}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        );
      })}
    </div>
  );
}
