import type { Metadata } from "next";
import { cookies } from "next/headers";
import { createServiceClient } from "@/lib/supabase/service";
import { StatBlock, DashboardCard } from "@/components/ui";
import { DistributeButton } from "./distribute-button";

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

const STATUS_LABELS: Record<string, { label: string; color: string }> = {
  VERIFIED: { label: "Verificado", color: "bg-success-soft text-success" },
  CALIBRATING: { label: "Calibrando", color: "bg-info-soft text-info" },
  MONITORED: { label: "Observação", color: "bg-warning-soft text-warning" },
  DOWNGRADED: { label: "Rebaixado", color: "bg-error-soft text-error" },
  UNVERIFIED: { label: "Sem status", color: "bg-neutral-soft text-content-muted" },
};

import { formatKm, formatDateISO, formatDateMs } from "@/lib/format";

const formatDate = formatDateISO;
const formatJoinDate = formatDateMs;

export default async function AthletesPage() {
  const groupId = cookies().get("portal_group_id")?.value;
  const role = cookies().get("portal_role")?.value;
  if (!groupId) return null;
  const isAdmin = role === "admin_master";

  let athletes: Athlete[] = [];
  let activeCount = 0;
  let verifiedCount = 0;
  let totalKm = 0;
  let fetchError = false;

  try {
    const db = createServiceClient();

    const { data: members } = await db
      .from("coaching_members")
      .select("user_id, display_name, joined_at_ms")
      .eq("group_id", groupId)
      .eq("role", "athlete")
      .order("joined_at_ms", { ascending: false });

    const allMembers = members ?? [];
    const userIds = allMembers.map((m: { user_id: string }) => m.user_id);

    const verMap = new Map<string, { verification_status: string; trust_score: number }>();
    const sessionMap = new Map<string, { total: number; distance: number; last_at: string | null }>();

    if (userIds.length > 0) {
      const [verRes, sessionsRes] = await Promise.all([
        db
          .from("athlete_verification")
          .select("user_id, verification_status, trust_score")
          .in("user_id", userIds),
        db
          .from("sessions")
          .select("user_id, total_distance_m, start_time_ms")
          .in("user_id", userIds)
          .gte("status", 3),
      ]);

      for (const v of verRes.data ?? []) {
        const row = v as { user_id: string; verification_status: string; trust_score: number };
        verMap.set(row.user_id, { verification_status: row.verification_status, trust_score: row.trust_score });
      }

      for (const s of sessionsRes.data ?? []) {
        const row = s as { user_id: string; total_distance_m: number; start_time_ms: number };
        const existing = sessionMap.get(row.user_id);
        const startIso = new Date(row.start_time_ms).toISOString();
        if (existing) {
          existing.total++;
          existing.distance += row.total_distance_m ?? 0;
          if (!existing.last_at || startIso > existing.last_at) existing.last_at = startIso;
        } else {
          sessionMap.set(row.user_id, {
            total: 1,
            distance: row.total_distance_m ?? 0,
            last_at: startIso,
          });
        }
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
        <div className="overflow-hidden rounded-xl border border-border bg-surface shadow-sm">
          <div className="overflow-x-auto">
            <table className="min-w-full divide-y divide-border text-sm">
              <thead className="bg-bg-secondary">
                <tr>
                  <th className="px-4 py-3 text-left text-xs font-medium uppercase tracking-wide text-content-muted">
                    Atleta
                  </th>
                  <th className="px-4 py-3 text-left text-xs font-medium uppercase tracking-wide text-content-muted">
                    Status
                  </th>
                  <th className="px-4 py-3 text-center text-xs font-medium uppercase tracking-wide text-content-muted">
                    Trust
                  </th>
                  <th className="px-4 py-3 text-center text-xs font-medium uppercase tracking-wide text-content-muted">
                    Corridas
                  </th>
                  <th className="px-4 py-3 text-right text-xs font-medium uppercase tracking-wide text-content-muted">
                    Distância
                  </th>
                  <th className="px-4 py-3 text-left text-xs font-medium uppercase tracking-wide text-content-muted">
                    Última Corrida
                  </th>
                  <th className="px-4 py-3 text-left text-xs font-medium uppercase tracking-wide text-content-muted">
                    Membro Desde
                  </th>
                  {isAdmin && (
                    <th className="px-4 py-3 text-center text-xs font-medium uppercase tracking-wide text-content-muted">
                      OmniCoins
                    </th>
                  )}
                </tr>
              </thead>
              <tbody className="divide-y divide-border-subtle">
                {athletes.map((a) => {
                  const s = STATUS_LABELS[a.verification_status] ?? STATUS_LABELS.UNVERIFIED;
                  return (
                    <tr key={a.user_id} className="hover:bg-surface-elevated transition-colors">
                      <td className="whitespace-nowrap px-4 py-3">
                        <p className="font-medium text-content-primary">
                          {a.display_name}
                        </p>
                      </td>
                      <td className="whitespace-nowrap px-4 py-3">
                        <span
                          className={`inline-flex rounded-full px-2.5 py-0.5 text-xs font-medium ${s.color}`}
                        >
                          {s.label}
                        </span>
                      </td>
                      <td className="whitespace-nowrap px-4 py-3 text-center">
                        <span className="font-semibold text-content-primary">
                          {a.trust_score}
                        </span>
                        <span className="text-xs text-content-muted">/100</span>
                      </td>
                      <td className="whitespace-nowrap px-4 py-3 text-center text-content-secondary">
                        {a.total_sessions}
                      </td>
                      <td className="whitespace-nowrap px-4 py-3 text-right text-content-secondary">
                        {formatKm(a.total_distance_m)} km
                      </td>
                      <td className="whitespace-nowrap px-4 py-3 text-content-muted">
                        {formatDate(a.last_session_at)}
                      </td>
                      <td className="whitespace-nowrap px-4 py-3 text-content-muted">
                        {formatJoinDate(a.joined_at_ms)}
                      </td>
                      {isAdmin && (
                        <td className="whitespace-nowrap px-4 py-3 text-center">
                          <DistributeButton
                            athleteId={a.user_id}
                            athleteName={a.display_name}
                          />
                        </td>
                      )}
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </div>
  );
}
