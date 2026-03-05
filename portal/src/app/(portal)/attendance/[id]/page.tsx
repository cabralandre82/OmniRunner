import { cookies } from "next/headers";
import { createClient } from "@/lib/supabase/server";
import { NoGroupSelected } from "@/components/no-group-selected";
import Link from "next/link";
import { formatDateISO, formatDateTime } from "@/lib/format";

export const dynamic = "force-dynamic";

const STATUS_LABELS: Record<string, string> = {
  present: "Presente",
  late: "Atrasado",
  excused: "Justificado",
  absent: "Ausente",
  completed: "Concluído",
  partial: "Parcial",
};

const STATUS_COLORS: Record<string, string> = {
  present: "bg-success-soft text-success",
  completed: "bg-success-soft text-success",
  late: "bg-warning-soft text-warning",
  partial: "bg-warning-soft text-warning",
  excused: "bg-info-soft text-info",
  absent: "bg-error-soft text-error",
};

const METHOD_LABELS: Record<string, string> = {
  qr: "QR",
  manual: "Manual",
  auto: "Automático",
};

export default async function AttendanceDetailPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id: sessionId } = await params;
  const groupId = cookies().get("portal_group_id")?.value;
  const role = cookies().get("portal_role")?.value;
  if (!groupId) return <NoGroupSelected />;

  const supabase = createClient();

  const { data: session } = await supabase
    .from("coaching_training_sessions")
    .select("id, title, starts_at, ends_at, location_name, status, distance_target_m, pace_min_sec_km, pace_max_sec_km")
    .eq("id", sessionId)
    .eq("group_id", groupId)
    .single();

  if (!session) {
    return (
      <div className="space-y-6">
        <Link href="/attendance" className="text-sm text-brand hover:underline">
          ← Voltar ao relatório
        </Link>
        <div className="rounded-xl border border-border bg-surface p-8 text-center shadow-sm">
          <p className="text-sm text-content-secondary">Treino não encontrado.</p>
        </div>
      </div>
    );
  }

  const { data: attendance } = await supabase
    .from("coaching_training_attendance")
    .select("id, athlete_user_id, checked_at, method, status")
    .eq("session_id", sessionId)
    .eq("group_id", groupId)
    .order("checked_at", { ascending: true });

  const athleteIds = Array.from(new Set((attendance ?? []).map((a) => a.athlete_user_id)));
  const profileMap = new Map<string, string>();

  if (athleteIds.length > 0) {
    const { data: profiles } = await supabase
      .from("profiles")
      .select("id, display_name")
      .in("id", athleteIds);

    for (const p of profiles ?? []) {
      profileMap.set(p.id, p.display_name || "Sem nome");
    }
  }

  const { count: athleteCount } = await supabase
    .from("coaching_members")
    .select("id", { count: "exact", head: true })
    .eq("group_id", groupId)
    .in("role", ["athlete", "atleta"]);

  const presentes = (attendance ?? []).filter(
    (a) => a.status === "present" || a.status === "completed",
  ).length;
  const parciais = (attendance ?? []).filter((a) => a.status === "partial").length;
  const ausentes = (attendance ?? []).filter((a) => a.status === "absent").length;
  const total = athleteCount ?? 0;
  const pct = total > 0 ? (presentes / total) * 100 : 0;

  const canMarkAttendance = role === "admin_master" || role === "coach";

  return (
    <div className="space-y-6">
      <Link href="/attendance" className="text-sm text-brand hover:underline">
        ← Voltar ao relatório
      </Link>

      <div>
        <h1 className="text-2xl font-bold text-content-primary">{session.title}</h1>
        <p className="mt-1 text-sm text-content-secondary">
          Detalhes da presença no treino
        </p>
      </div>

      <div className="rounded-xl border border-border bg-surface p-6 shadow-sm">
        <h2 className="text-sm font-semibold text-content-primary">Informações do treino</h2>
        <dl className="mt-3 grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
          <div>
            <dt className="text-xs text-content-secondary">Data</dt>
            <dd className="text-sm font-medium text-content-primary">{formatDateISO(session.starts_at)}</dd>
          </div>
          <div>
            <dt className="text-xs text-content-secondary">Local</dt>
            <dd className="text-sm font-medium text-content-primary">{session.location_name || "—"}</dd>
          </div>
          <div>
            <dt className="text-xs text-content-secondary">Status</dt>
            <dd className="text-sm font-medium text-content-primary">
              <span
                className={`inline-flex rounded-full px-2 py-0.5 text-xs font-medium ${
                  session.status === "done"
                    ? "bg-success-soft text-success"
                    : session.status === "cancelled"
                      ? "bg-error-soft text-error"
                      : "bg-info-soft text-info"
                }`}
              >
                {session.status === "done" ? "Realizado" : session.status === "cancelled" ? "Cancelado" : "Agendado"}
              </span>
            </dd>
          </div>
          {session.distance_target_m && (
            <div>
              <dt className="text-xs text-content-secondary">Distância alvo</dt>
              <dd className="text-sm font-medium text-content-primary">
                {(session.distance_target_m / 1000).toFixed(1)} km
              </dd>
            </div>
          )}
          {session.pace_min_sec_km && session.pace_max_sec_km && (
            <div>
              <dt className="text-xs text-content-secondary">Faixa de pace</dt>
              <dd className="text-sm font-medium text-content-primary">
                {fmtPace(session.pace_min_sec_km)} ~ {fmtPace(session.pace_max_sec_km)} /km
              </dd>
            </div>
          )}
        </dl>
      </div>

      <div className="rounded-xl border border-border bg-surface p-6 shadow-sm">
        <h2 className="text-sm font-semibold text-content-primary">Presença</h2>
        <p className="mt-2 text-2xl font-bold text-content-primary">
          {presentes} / {total} atletas = {pct.toFixed(1)}%
        </p>
        <div className="mt-2 flex gap-4 text-xs text-content-secondary">
          <span className="text-success">{presentes} concluídos</span>
          <span className="text-warning">{parciais} parciais</span>
          <span className="text-error">{ausentes} ausentes</span>
        </div>
      </div>

      <div className="overflow-hidden rounded-xl border border-border bg-surface shadow-sm">
        <div className="overflow-x-auto">
          <table className="min-w-full divide-y divide-border text-sm">
            <thead className="bg-bg-secondary">
              <tr>
                <th className="px-4 py-3 text-left font-medium text-content-secondary">Nome</th>
                <th className="px-4 py-3 text-left font-medium text-content-secondary">Check-in</th>
                <th className="px-4 py-3 text-left font-medium text-content-secondary">Método</th>
                <th className="px-4 py-3 text-left font-medium text-content-secondary">Status</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-border-subtle">
              {(attendance ?? []).map((a) => (
                <tr key={a.id} className="hover:bg-surface-elevated">
                  <td className="whitespace-nowrap px-4 py-3 font-medium text-content-primary">
                    {profileMap.get(a.athlete_user_id) ?? "—"}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-content-secondary">
                    {formatDateTime(a.checked_at)}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-content-secondary">
                    {METHOD_LABELS[a.method] ?? a.method}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3">
                    <span
                      className={`inline-flex rounded-full px-2.5 py-0.5 text-xs font-medium ${
                        STATUS_COLORS[a.status] ?? "bg-surface-elevated text-content-secondary"
                      }`}
                    >
                      {STATUS_LABELS[a.status] ?? a.status}
                    </span>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      {(attendance ?? []).length === 0 && (
        <div className="rounded-xl border border-border bg-surface p-8 text-center shadow-sm">
          <p className="text-sm text-content-secondary">
            Nenhuma avaliação registrada neste treino.
          </p>
        </div>
      )}
    </div>
  );
}

function fmtPace(secPerKm: number): string {
  const min = Math.floor(secPerKm / 60);
  const sec = Math.round(secPerKm % 60);
  return `${min}:${sec.toString().padStart(2, "0")}`;
}
