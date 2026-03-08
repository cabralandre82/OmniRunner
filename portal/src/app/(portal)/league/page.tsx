import type { Metadata } from "next";
import { cookies } from "next/headers";
import { createClient } from "@/lib/supabase/server";
import { NoGroupSelected } from "@/components/no-group-selected";
import { DashboardCard } from "@/components/ui";
import { formatDateMs } from "@/lib/format";

export const metadata: Metadata = { title: "Liga" };
export const dynamic = "force-dynamic";

const STATUS_LABELS: Record<string, string> = {
  upcoming: "Em breve",
  active: "Ativa",
  completed: "Encerrada",
};

export default async function LeaguePage() {
  const groupId = cookies().get("portal_group_id")?.value;
  if (!groupId) return <NoGroupSelected />;

  let currentSeason: {
    id: string;
    name: string;
    start_at_ms: number;
    end_at_ms: number;
    status: string;
  } | null = null;
  let enrollments: Array<{
    id: string;
    group_id: string;
    group_name: string;
  }> = [];
  let rankings: Array<{
    group_id: string;
    group_name: string;
    rank: number;
    cumulative_score: number;
    total_km: number;
    week_key: string;
  }> = [];
  let error: string | null = null;

  try {
    const db = createClient();

    const { data: seasons } = await db
      .from("league_seasons")
      .select("id, name, start_at_ms, end_at_ms, status")
      .order("start_at_ms", { ascending: false })
      .limit(5);

    currentSeason = seasons?.[0] ?? null;

    if (currentSeason) {
      const { data: enrollData } = await db
        .from("league_enrollments")
        .select("id, group_id")
        .eq("season_id", currentSeason.id);

      const groupIds = Array.from(new Set((enrollData ?? []).map((e) => e.group_id)));
      let groupNames = new Map<string, string>();

      if (groupIds.length > 0) {
        const { data: groups } = await db
          .from("coaching_groups")
          .select("id, name")
          .in("id", groupIds);
        for (const g of groups ?? []) {
          groupNames.set((g as { id: string; name: string }).id, (g as { id: string; name: string }).name ?? "—");
        }
      }

      enrollments = (enrollData ?? []).map((e) => ({
        id: (e as { id: string }).id,
        group_id: (e as { group_id: string }).group_id,
        group_name: groupNames.get((e as { group_id: string }).group_id) ?? "—",
      }));

      const { data: snapshots } = await db
        .from("league_snapshots")
        .select("group_id, week_key, cumulative_score, total_km, rank")
        .eq("season_id", currentSeason.id)
        .order("week_key", { ascending: false });

      const snapshotList = snapshots ?? [];
      const latestWeek = snapshotList[0]?.week_key;
      const latestByGroup = new Map<string, { group_id: string; rank: number; cumulative_score: number; total_km: number; week_key: string }>();
      for (const s of snapshotList) {
        const row = s as { group_id: string; week_key: string; cumulative_score: number; total_km: number; rank: number };
        if (row.week_key === latestWeek && !latestByGroup.has(row.group_id)) {
          latestByGroup.set(row.group_id, row);
        }
      }

      rankings = Array.from(latestByGroup.entries())
        .map(([gid, s]) => {
          const r = s as { group_id: string; rank: number; cumulative_score: number; total_km: number; week_key: string };
          return {
            group_id: gid,
            group_name: groupNames.get(gid) ?? "—",
            rank: r.rank,
            cumulative_score: r.cumulative_score,
            total_km: r.total_km,
            week_key: r.week_key,
          };
        })
        .sort((a, b) => a.rank - b.rank);
    }
  } catch (e) {
    error = e instanceof Error ? e.message : "Erro ao carregar";
  }

  if (error) {
    if (/PGRST|does not exist|league_enrollments/.test(error)) {
      return (
        <div className="rounded-xl border border-border bg-surface p-8 text-center">
          <p className="text-lg font-medium text-content-primary">Funcionalidade em desenvolvimento</p>
          <p className="mt-2 text-sm text-content-muted">Este recurso estará disponível em breve.</p>
        </div>
      );
    }
    return (
      <div className="space-y-6">
        <h1 className="text-2xl font-bold text-content-primary">Liga</h1>
        <DashboardCard>
          <p className="py-6 text-center text-sm text-content-muted">{error}</p>
        </DashboardCard>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-content-primary">Liga</h1>
        <p className="mt-1 text-sm text-content-secondary">
          Temporada atual, grupos inscritos e ranking.
          A criação e gestão de temporadas é feita pela administração da plataforma.
        </p>
      </div>

      {!currentSeason ? (
        <DashboardCard>
          <p className="py-6 text-center text-sm text-content-muted">
            Nenhuma temporada de liga configurada
          </p>
        </DashboardCard>
      ) : (
        <>
          <div className="rounded-xl border border-border bg-surface p-4 shadow-sm">
            <h2 className="text-sm font-semibold text-content-primary">Temporada atual</h2>
            <div className="mt-2 flex flex-wrap gap-4 text-sm">
              <span className="text-content-primary font-medium">{currentSeason.name}</span>
              <span
                className={`rounded-full px-2.5 py-0.5 text-xs font-medium ${
                  currentSeason.status === "active"
                    ? "bg-success-soft text-success"
                    : currentSeason.status === "completed"
                    ? "bg-neutral-soft text-content-muted"
                    : "bg-info-soft text-info"
                }`}
              >
                {STATUS_LABELS[currentSeason.status] ?? currentSeason.status}
              </span>
              <span className="text-content-muted">
                {formatDateMs(currentSeason.start_at_ms)} — {formatDateMs(currentSeason.end_at_ms)}
              </span>
            </div>
          </div>

          <div className="grid gap-6 lg:grid-cols-2">
            <div className="overflow-hidden rounded-xl border border-border bg-surface shadow-sm">
              <h3 className="border-b border-border bg-bg-secondary px-4 py-3 text-sm font-semibold text-content-primary">
                Grupos inscritos ({enrollments.length})
              </h3>
              <ul className="divide-y divide-border-subtle">
                {enrollments.length === 0 ? (
                  <li className="px-4 py-4 text-sm text-content-muted">Nenhum grupo inscrito</li>
                ) : (
                  enrollments.map((e) => (
                    <li key={e.id} className="px-4 py-3 text-sm text-content-secondary">
                      {e.group_name}
                    </li>
                  ))
                )}
              </ul>
            </div>

            <div className="overflow-hidden rounded-xl border border-border bg-surface shadow-sm">
              <h3 className="border-b border-border bg-bg-secondary px-4 py-3 text-sm font-semibold text-content-primary">
                Ranking
              </h3>
              {rankings.length === 0 ? (
                <p className="px-4 py-6 text-sm text-content-muted">Sem dados de ranking</p>
              ) : (
                <div className="overflow-x-auto">
                  <table className="min-w-full text-sm">
                    <thead>
                      <tr className="border-b border-border-subtle">
                        <th className="px-4 py-2 text-left text-xs font-medium text-content-muted">#</th>
                        <th className="px-4 py-2 text-left text-xs font-medium text-content-muted">Grupo</th>
                        <th className="px-4 py-2 text-right text-xs font-medium text-content-muted">Pontos</th>
                        <th className="px-4 py-2 text-right text-xs font-medium text-content-muted">Km</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-border-subtle">
                      {rankings.map((r) => (
                        <tr key={r.group_id} className="hover:bg-surface-elevated">
                          <td className="whitespace-nowrap px-4 py-3 font-semibold text-content-primary">
                            {r.rank}
                          </td>
                          <td className="whitespace-nowrap px-4 py-3 text-content-secondary">
                            {r.group_name}
                          </td>
                          <td className="whitespace-nowrap px-4 py-3 text-right font-medium text-brand">
                            {r.cumulative_score.toFixed(1)}
                          </td>
                          <td className="whitespace-nowrap px-4 py-3 text-right text-content-secondary">
                            {r.total_km.toFixed(1)} km
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              )}
            </div>
          </div>
        </>
      )}
    </div>
  );
}
