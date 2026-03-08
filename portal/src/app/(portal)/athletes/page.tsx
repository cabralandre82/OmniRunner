import type { Metadata } from "next";
import { cookies } from "next/headers";
import { createClient } from "@/lib/supabase/server";
import { NoGroupSelected } from "@/components/no-group-selected";
import { LastUpdated } from "@/components/last-updated";
import { StatBlock, DashboardCard } from "@/components/ui";
import { AthletesTableClient } from "./athletes-table-client";

export const metadata: Metadata = { title: "Atletas" };
export const dynamic = "force-dynamic";

interface Athlete {
  user_id: string;
  display_name: string;
  joined_at_ms: number;
  verification_status: string;
  trust_score: number;
  total_sessions: number;
  total_distance_m: number;
  last_session_at: string | null;
}

import { formatKm } from "@/lib/format";

export default async function AthletesPage() {
  const groupId = cookies().get("portal_group_id")?.value;
  const role = cookies().get("portal_role")?.value;
  if (!groupId) return <NoGroupSelected />;
  const isAdmin = role === "admin_master";

  let athletes: Athlete[] = [];
  let activeCount = 0;
  let verifiedCount = 0;
  let totalKm = 0;
  let fetchError = false;

  try {
    const db = createClient();

    const { data: members } = await db
      .from("coaching_members")
      .select("user_id, display_name, joined_at_ms")
      .eq("group_id", groupId)
      .in("role", ["athlete", "atleta"])
      .order("joined_at_ms", { ascending: false })
      .limit(200);

    const allMembers = members ?? [];
    const userIds = allMembers.map((m: { user_id: string }) => m.user_id);

    const verMap = new Map<string, { verification_status: string; trust_score: number }>();
    const sessionMap = new Map<string, { total: number; distance: number; last_at: string | null }>();

    if (userIds.length > 0) {
      const [verRes, statsRes] = await Promise.all([
        db
          .from("athlete_verification")
          .select("user_id, verification_status, trust_score")
          .in("user_id", userIds),
        db.rpc("fn_athlete_session_stats", { p_user_ids: userIds }),
      ]);

      for (const v of verRes.data ?? []) {
        const row = v as { user_id: string; verification_status: string; trust_score: number };
        verMap.set(row.user_id, { verification_status: row.verification_status, trust_score: row.trust_score });
      }

      for (const s of statsRes.data ?? []) {
        const row = s as { user_id: string; session_count: number; total_distance_m: number; total_duration_s: number; last_session_at: string | null };
        sessionMap.set(row.user_id, {
          total: row.session_count ?? 0,
          distance: row.total_distance_m ?? 0,
          last_at: row.last_session_at ?? null,
        });
      }
    }

    athletes = allMembers.map((m: { user_id: string; display_name: string; joined_at_ms: number }) => {
      const ver = verMap.get(m.user_id);
      const sess = sessionMap.get(m.user_id);
      return {
        user_id: m.user_id,
        display_name: m.display_name || "Sem nome",
        joined_at_ms: m.joined_at_ms,
        verification_status: ver?.verification_status ?? "UNVERIFIED",
        trust_score: ver?.trust_score ?? 0,
        total_sessions: sess?.total ?? 0,
        total_distance_m: sess?.distance ?? 0,
        last_session_at: sess?.last_at ?? null,
      };
    });

    activeCount = athletes.filter((a) => a.total_sessions > 0).length;
    verifiedCount = athletes.filter((a) => a.verification_status === "VERIFIED").length;
    totalKm = athletes.reduce((s, a) => s + a.total_distance_m, 0);
  } catch {
    fetchError = true;
  }

  if (fetchError) {
    return (
      <div className="p-6">
        <div className="rounded-xl border border-error/30 bg-error-soft p-8 text-center">
          <h2 className="text-lg font-semibold text-error">Erro ao carregar dados</h2>
          <p className="mt-2 text-sm text-content-secondary">Não foi possível conectar ao servidor. Tente recarregar a página.</p>
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-content-primary">Atletas</h1>
          <p className="mt-1 text-sm text-content-secondary">
            Todos os atletas vinculados à assessoria
          </p>
        </div>
        {athletes.length > 0 && (
          <a
            href="/api/export/athletes"
            className="rounded-lg border border-border bg-surface px-3 py-1.5 text-xs font-medium text-content-secondary shadow-sm hover:bg-surface-elevated hover:text-content-primary transition-colors"
          >
            Exportar CSV
          </a>
        )}
      </div>

      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <StatBlock label="Total" value={athletes.length} />
        <StatBlock label="Ativos (1+ corrida)" value={activeCount} accentClass="text-info" />
        <StatBlock label="Verificados" value={verifiedCount} accentClass="text-success" />
        <StatBlock label="Km totais" value={formatKm(totalKm)} accentClass="text-brand" />
      </div>

      {athletes.length === 0 ? (
        <DashboardCard>
          <p className="py-4 text-center text-sm text-content-muted">
            Nenhum atleta vinculado à assessoria.
          </p>
        </DashboardCard>
      ) : (
        <AthletesTableClient athletes={athletes} isAdmin={isAdmin} />
      )}

      <LastUpdated />
    </div>
  );
}
