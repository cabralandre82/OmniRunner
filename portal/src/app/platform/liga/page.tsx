export const dynamic = "force-dynamic";

import { createClient } from "@/lib/supabase/server";
import { LeagueAdmin } from "./league-admin";

export default async function LigaPage() {
  const supabase = createClient();

  const { data: seasons } = await supabase
    .from("league_seasons")
    .select("*")
    .order("created_at_ms", { ascending: false });

  const activeSeason = (seasons ?? []).find(
    (s: Record<string, unknown>) => s.status === "active",
  );

  let enrollments: Record<string, unknown>[] = [];
  let snapshots: Record<string, unknown>[] = [];

  if (activeSeason) {
    const { data: enrollData } = await supabase
      .from("league_enrollments")
      .select("group_id")
      .eq("season_id", activeSeason.id);

    enrollments = enrollData ?? [];

    const { data: snapData } = await supabase
      .from("league_snapshots")
      .select(
        "group_id, rank, prev_rank, cumulative_score, week_score, total_km, total_sessions, active_members, total_members, week_key",
      )
      .eq("season_id", activeSeason.id)
      .order("rank", { ascending: true });

    // Get latest week only
    if (snapData && snapData.length > 0) {
      const latestWeek = snapData[0].week_key;
      snapshots = snapData.filter(
        (s: Record<string, unknown>) => s.week_key === latestWeek,
      );
    }

    // Enrich with group names
    if (snapshots.length > 0) {
      const groupIds = snapshots.map(
        (s: Record<string, unknown>) => s.group_id,
      );
      const { data: groups } = await supabase
        .from("coaching_groups")
        .select("id, name, city, state")
        .in("id", groupIds as string[]);

      const groupMap: Record<string, Record<string, unknown>> = {};
      for (const g of groups ?? []) {
        groupMap[g.id] = g;
      }

      snapshots = snapshots.map((s: Record<string, unknown>) => ({
        ...s,
        group_name:
          (groupMap[s.group_id as string]?.name as string) ?? "Assessoria",
        city: groupMap[s.group_id as string]?.city ?? null,
        state: groupMap[s.group_id as string]?.state ?? null,
      }));
    }
  }

  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-2xl font-bold text-content-primary">
          Liga de Assessorias
        </h1>
        <p className="mt-1 text-sm text-content-secondary">
          Gerenciar temporadas e visualizar ranking
        </p>
      </div>

      <LeagueAdmin
        seasons={(seasons ?? []) as Record<string, unknown>[]}
        activeSeason={activeSeason as Record<string, unknown> | null}
        enrollments={enrollments}
        snapshots={snapshots}
      />
    </div>
  );
}
