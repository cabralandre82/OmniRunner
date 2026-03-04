import type { Metadata } from "next";
import { createAdminClient } from "@/lib/supabase/admin";
import { DashboardCard } from "@/components/ui";
import { formatDateISO } from "@/lib/format";

export const metadata: Metadata = { title: "Matchmaking" };
export const dynamic = "force-dynamic";

const STATUS_LABELS: Record<string, string> = {
  waiting: "Aguardando",
  matched: "Pareado",
  expired: "Expirado",
  cancelled: "Cancelado",
};

const METRIC_LABELS: Record<string, string> = {
  distance: "Distância",
  pace: "Pace",
  time: "Tempo",
};

const SKILL_LABELS: Record<string, string> = {
  beginner: "Iniciante",
  intermediate: "Intermediário",
  advanced: "Avançado",
  elite: "Elite",
};

export default async function MatchmakingPage() {
  let rows: Array<{
    id: string;
    user_id: string;
    metric: string;
    target: number | null;
    entry_fee_coins: number;
    window_ms: number;
    skill_bracket: string;
    status: string;
    created_at: string;
    expires_at: string;
  }> = [];
  let error: string | null = null;

  try {
    const db = createAdminClient();
    const { data, error: fetchError } = await db
      .from("challenge_queue")
      .select("id, user_id, metric, target, entry_fee_coins, window_ms, skill_bracket, status, created_at, expires_at")
      .order("created_at", { ascending: false })
      .limit(100);

    if (fetchError) {
      error = fetchError.message;
    } else {
      rows = (data ?? []).map((r) => ({
        ...r,
        created_at: r.created_at ?? "",
        expires_at: r.expires_at ?? "",
      }));
    }
  } catch (e) {
    error = e instanceof Error ? e.message : "Erro ao carregar dados";
  }

  if (error) {
    return (
      <div className="space-y-6">
        <h1 className="text-2xl font-bold text-content-primary">Matchmaking</h1>
        <DashboardCard>
          <p className="py-6 text-center text-sm text-content-muted">
            Matchmaking — dados indisponíveis
          </p>
          <p className="text-center text-xs text-content-muted">
            {error}
          </p>
        </DashboardCard>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-content-primary">Matchmaking</h1>
        <p className="mt-1 text-sm text-content-secondary">
          Fila de matchmaking para desafios 1v1 (somente leitura)
        </p>
      </div>

      {rows.length === 0 ? (
        <DashboardCard>
          <p className="py-6 text-center text-sm text-content-muted">
            Nenhuma entrada na fila de matchmaking
          </p>
        </DashboardCard>
      ) : (
        <div className="overflow-hidden rounded-xl border border-border bg-surface shadow-sm">
          <div className="overflow-x-auto">
            <table className="min-w-full divide-y divide-border text-sm">
              <thead className="bg-bg-secondary">
                <tr>
                  <th className="px-4 py-3 text-left text-xs font-medium uppercase tracking-wide text-content-muted">
                    Usuário
                  </th>
                  <th className="px-4 py-3 text-left text-xs font-medium uppercase tracking-wide text-content-muted">
                    Métrica
                  </th>
                  <th className="px-4 py-3 text-right text-xs font-medium uppercase tracking-wide text-content-muted">
                    Alvo
                  </th>
                  <th className="px-4 py-3 text-center text-xs font-medium uppercase tracking-wide text-content-muted">
                    Taxa
                  </th>
                  <th className="px-4 py-3 text-left text-xs font-medium uppercase tracking-wide text-content-muted">
                    Nível
                  </th>
                  <th className="px-4 py-3 text-left text-xs font-medium uppercase tracking-wide text-content-muted">
                    Status
                  </th>
                  <th className="px-4 py-3 text-left text-xs font-medium uppercase tracking-wide text-content-muted">
                    Criado
                  </th>
                  <th className="px-4 py-3 text-left text-xs font-medium uppercase tracking-wide text-content-muted">
                    Expira
                  </th>
                </tr>
              </thead>
              <tbody className="divide-y divide-border-subtle">
                {rows.map((r) => (
                  <tr key={r.id} className="hover:bg-surface-elevated">
                    <td className="whitespace-nowrap px-4 py-3 font-mono text-xs text-content-secondary">
                      {r.user_id.slice(0, 8)}…
                    </td>
                    <td className="whitespace-nowrap px-4 py-3 text-content-secondary">
                      {METRIC_LABELS[r.metric] ?? r.metric}
                    </td>
                    <td className="whitespace-nowrap px-4 py-3 text-right text-content-secondary">
                      {r.target != null ? String(r.target) : "—"}
                    </td>
                    <td className="whitespace-nowrap px-4 py-3 text-center text-content-secondary">
                      {r.entry_fee_coins} coins
                    </td>
                    <td className="whitespace-nowrap px-4 py-3 text-content-secondary">
                      {SKILL_LABELS[r.skill_bracket] ?? r.skill_bracket}
                    </td>
                    <td className="whitespace-nowrap px-4 py-3">
                      <span
                        className={`inline-flex rounded-full px-2.5 py-0.5 text-xs font-medium ${
                          r.status === "waiting"
                            ? "bg-info-soft text-info"
                            : r.status === "matched"
                            ? "bg-success-soft text-success"
                            : "bg-neutral-soft text-content-muted"
                        }`}
                      >
                        {STATUS_LABELS[r.status] ?? r.status}
                      </span>
                    </td>
                    <td className="whitespace-nowrap px-4 py-3 text-content-muted text-xs">
                      {formatDateISO(r.created_at)}
                    </td>
                    <td className="whitespace-nowrap px-4 py-3 text-content-muted text-xs">
                      {formatDateISO(r.expires_at)}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </div>
  );
}
