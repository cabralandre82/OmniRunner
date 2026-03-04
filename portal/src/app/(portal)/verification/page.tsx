import { cookies } from "next/headers";
import { createClient } from "@/lib/supabase/server";
import { createServiceClient } from "@/lib/supabase/service";
import { formatDateISO } from "@/lib/format";

export const dynamic = "force-dynamic";
import { ReevaluateButton } from "./reevaluate-button";

interface AthleteRow {
  user_id: string;
  display_name: string;
  verification_status: string;
  trust_score: number;
  calibration_valid_runs: number;
  verified_at: string | null;
  last_eval_at: string | null;
  verification_flags: string[];
  last_integrity_flag_at: string | null;
}

const STATUS_LABELS: Record<string, { label: string; color: string }> = {
  VERIFIED: { label: "Verificado", color: "bg-success-soft text-success" },
  CALIBRATING: { label: "Calibrando", color: "bg-info-soft text-info" },
  MONITORED: { label: "Em Observação", color: "bg-warning-soft text-warning" },
  DOWNGRADED: { label: "Rebaixado", color: "bg-error-soft text-error" },
  UNVERIFIED: { label: "Não Verificado", color: "bg-surface-elevated text-content-secondary" },
};

const formatDate = formatDateISO;

export default async function VerificationPage() {
  const groupId = cookies().get("portal_group_id")?.value;
  const role = cookies().get("portal_role")?.value ?? "assistant";

  if (!groupId) return null;

  const supabase = createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) return null;

  const db = createServiceClient();

  // Fetch athletes in this assessoria
  const { data: members } = await db
    .from("coaching_members")
    .select("user_id, display_name")
    .eq("group_id", groupId)
    .eq("role", "athlete");

  const athleteIds = (members ?? []).map(
    (m: { user_id: string }) => m.user_id,
  );

  let athletes: AthleteRow[] = [];

  if (athleteIds.length > 0) {
    const { data: verifications } = await db
      .from("athlete_verification")
      .select(
        "user_id, verification_status, trust_score, calibration_valid_runs, verified_at, last_eval_at, verification_flags, last_integrity_flag_at",
      )
      .in("user_id", athleteIds);

    type VerRow = Omit<AthleteRow, "display_name">;
    const verMap = new Map(
      (verifications ?? []).map((v: VerRow) => [v.user_id, v]),
    );

    athletes = (members ?? []).map(
      (m: { user_id: string; display_name: string }) => {
        const v = verMap.get(m.user_id);
        return {
          user_id: m.user_id,
          display_name: m.display_name || "Sem nome",
          verification_status: v?.verification_status ?? "UNVERIFIED",
          trust_score: v?.trust_score ?? 0,
          calibration_valid_runs: v?.calibration_valid_runs ?? 0,
          verified_at: v?.verified_at ?? null,
          last_eval_at: v?.last_eval_at ?? null,
          verification_flags: v?.verification_flags ?? [],
          last_integrity_flag_at: v?.last_integrity_flag_at ?? null,
        };
      },
    );

    athletes.sort((a, b) => {
      const order = ["DOWNGRADED", "MONITORED", "CALIBRATING", "UNVERIFIED", "VERIFIED"];
      return order.indexOf(a.verification_status) - order.indexOf(b.verification_status);
    });
  }

  // Summary counts
  const counts = {
    total: athletes.length,
    verified: athletes.filter((a) => a.verification_status === "VERIFIED").length,
    calibrating: athletes.filter((a) => a.verification_status === "CALIBRATING").length,
    monitored: athletes.filter((a) => a.verification_status === "MONITORED").length,
    downgraded: athletes.filter((a) => a.verification_status === "DOWNGRADED").length,
    unverified: athletes.filter((a) => a.verification_status === "UNVERIFIED").length,
  };

  const canEval = ["admin_master", "coach"].includes(role);

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-content-primary">
          Verificação de Atletas
        </h1>
        <p className="mt-1 text-sm text-content-secondary">
          Status de verificação dos atletas da assessoria. Somente leitura —
          o servidor decide automaticamente.
        </p>
      </div>

      {/* KPI cards */}
      <div className="grid gap-3 sm:grid-cols-3 lg:grid-cols-6">
        <KpiCard label="Total" value={counts.total} />
        <KpiCard label="Verificados" value={counts.verified} color="text-success" />
        <KpiCard label="Calibrando" value={counts.calibrating} color="text-brand" />
        <KpiCard label="Observação" value={counts.monitored} color="text-warning" />
        <KpiCard label="Rebaixados" value={counts.downgraded} color="text-error" />
        <KpiCard label="Sem Status" value={counts.unverified} color="text-content-secondary" />
      </div>

      {/* Info banner */}
      <div className="flex items-start gap-3 rounded-lg border border-blue-200 bg-brand-soft p-4">
        <svg
          className="mt-0.5 h-5 w-5 flex-shrink-0 text-brand"
          fill="none"
          viewBox="0 0 24 24"
          strokeWidth={2}
          stroke="currentColor"
        >
          <path
            strokeLinecap="round"
            strokeLinejoin="round"
            d="M13 16h-1v-4h-1m1-4h.01M12 2a10 10 0 100 20 10 10 0 000-20z"
          />
        </svg>
        <p className="text-sm text-info">
          A verificação é automática e baseada no histórico de corridas de cada
          atleta. Nenhum ajuste manual é possível. O botão &quot;Reavaliar&quot;
          apenas executa as mesmas regras novamente — não é um override.
        </p>
      </div>

      {/* Athlete table */}
      {athletes.length === 0 ? (
        <div className="rounded-xl border border-border bg-surface p-8 text-center">
          <p className="text-sm text-content-secondary">
            Nenhum atleta vinculado à assessoria.
          </p>
        </div>
      ) : (
        <div className="overflow-hidden rounded-xl border border-border bg-surface shadow-sm">
          <div className="overflow-x-auto">
            <table className="min-w-full divide-y divide-border">
              <thead className="bg-bg-secondary">
                <tr>
                  <th className="px-4 py-3 text-left text-xs font-medium uppercase tracking-wide text-content-secondary">
                    Atleta
                  </th>
                  <th className="px-4 py-3 text-left text-xs font-medium uppercase tracking-wide text-content-secondary">
                    Status
                  </th>
                  <th className="px-4 py-3 text-center text-xs font-medium uppercase tracking-wide text-content-secondary">
                    Trust
                  </th>
                  <th className="px-4 py-3 text-center text-xs font-medium uppercase tracking-wide text-content-secondary">
                    Corridas
                  </th>
                  <th className="px-4 py-3 text-left text-xs font-medium uppercase tracking-wide text-content-secondary">
                    Flags
                  </th>
                  <th className="px-4 py-3 text-left text-xs font-medium uppercase tracking-wide text-content-secondary">
                    Última Avaliação
                  </th>
                  {canEval && (
                    <th className="px-4 py-3 text-center text-xs font-medium uppercase tracking-wide text-content-secondary">
                      Ação
                    </th>
                  )}
                </tr>
              </thead>
              <tbody className="divide-y divide-border-subtle">
                {athletes.map((a) => {
                  const s = STATUS_LABELS[a.verification_status] ?? STATUS_LABELS.UNVERIFIED;
                  return (
                    <tr key={a.user_id} className="hover:bg-surface-elevated">
                      <td className="whitespace-nowrap px-4 py-3">
                        <p className="text-sm font-medium text-content-primary">
                          {a.display_name}
                        </p>
                        <p className="text-xs text-content-muted">
                          {a.user_id.slice(0, 8)}...
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
                        <span className="text-sm font-semibold text-content-primary">
                          {a.trust_score}
                        </span>
                        <span className="text-xs text-content-muted">/100</span>
                      </td>
                      <td className="whitespace-nowrap px-4 py-3 text-center text-sm text-content-secondary">
                        {a.calibration_valid_runs}
                      </td>
                      <td className="px-4 py-3">
                        {a.verification_flags.length > 0 ? (
                          <div className="flex flex-wrap gap-1">
                            {a.verification_flags.slice(0, 3).map((f) => (
                              <span
                                key={f}
                                className="rounded bg-error-soft px-1.5 py-0.5 text-[10px] font-medium text-error"
                              >
                                {f}
                              </span>
                            ))}
                            {a.verification_flags.length > 3 && (
                              <span className="text-[10px] text-content-muted">
                                +{a.verification_flags.length - 3}
                              </span>
                            )}
                          </div>
                        ) : (
                          <span className="text-xs text-content-muted">—</span>
                        )}
                      </td>
                      <td className="whitespace-nowrap px-4 py-3 text-xs text-content-secondary">
                        {formatDate(a.last_eval_at)}
                      </td>
                      {canEval && (
                        <td className="whitespace-nowrap px-4 py-3 text-center">
                          <ReevaluateButton userId={a.user_id} />
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

function KpiCard({
  label,
  value,
  color = "text-content-primary",
}: {
  label: string;
  value: number;
  color?: string;
}) {
  return (
    <div className="rounded-xl border border-border bg-surface p-4 shadow-sm">
      <p className="text-xs font-medium uppercase tracking-wide text-content-secondary">
        {label}
      </p>
      <p className={`mt-1 text-xl font-bold ${color}`}>{value}</p>
    </div>
  );
}
