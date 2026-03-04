import { createAdminClient } from "@/lib/supabase/admin";
import { logger } from "@/lib/logger";
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
  silver: "bg-surface-elevated text-content-secondary",
  gold: "bg-warning-soft text-warning",
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
    .select("id, name, category, tier, description, xp_reward, coins_reward, criteria_type, is_secret")
    .order("category")
    .order("tier");

  const { count: totalAwards } = await supabase
    .from("badge_awards")
    .select("id", { count: "exact", head: true });

  if (error) {
    logger.error("Failed to fetch badges", error);
  }

  const allBadges = badges ?? [];
  const categories = Array.from(new Set(allBadges.map((b) => b.category as string)));

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-content-primary">Conquistas</h1>
          <p className="mt-1 text-sm text-content-secondary">
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
            <h2 className="mb-3 text-xs font-semibold uppercase tracking-wider text-content-muted">
              {catLabel[cat] ?? cat} ({catBadges.length})
            </h2>
            <div className="overflow-hidden rounded-xl border border-border bg-surface shadow-sm">
              <table className="min-w-full divide-y divide-border-subtle">
                <thead className="bg-bg-secondary">
                  <tr>
                    <th className="px-4 py-3 text-left text-xs font-medium uppercase text-content-secondary">
                      Nome
                    </th>
                    <th className="px-4 py-3 text-left text-xs font-medium uppercase text-content-secondary">
                      Tier
                    </th>
                    <th className="px-4 py-3 text-left text-xs font-medium uppercase text-content-secondary">
                      Descrição
                    </th>
                    <th className="px-4 py-3 text-center text-xs font-medium uppercase text-content-secondary">
                      XP
                    </th>
                    <th className="px-4 py-3 text-center text-xs font-medium uppercase text-content-secondary">
                      Coins
                    </th>
                    <th className="px-4 py-3 text-center text-xs font-medium uppercase text-content-secondary">
                      Critério
                    </th>
                    <th className="px-4 py-3 text-center text-xs font-medium uppercase text-content-secondary">
                      Secreta
                    </th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-border-subtle">
                  {catBadges.map((b) => (
                    <tr key={b.id} className="hover:bg-surface-elevated">
                      <td className="px-4 py-3">
                        <p className="text-sm font-medium text-content-primary">
                          {b.name}
                        </p>
                        <p className="text-xs text-content-muted">{b.id}</p>
                      </td>
                      <td className="px-4 py-3">
                        <span
                          className={`rounded-full px-2 py-0.5 text-xs font-medium ${tierColor[b.tier] ?? "bg-surface-elevated"}`}
                        >
                          {tierLabel[b.tier] ?? b.tier}
                        </span>
                      </td>
                      <td className="px-4 py-3 text-sm text-content-secondary max-w-xs truncate">
                        {b.description}
                      </td>
                      <td className="px-4 py-3 text-center text-sm font-medium text-brand">
                        {b.xp_reward}
                      </td>
                      <td className="px-4 py-3 text-center text-sm font-medium text-amber-600">
                        {b.coins_reward > 0 ? b.coins_reward : "—"}
                      </td>
                      <td className="px-4 py-3 text-center">
                        <code className="rounded bg-surface-elevated px-1.5 py-0.5 text-xs text-content-secondary">
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
