import type { Metadata } from "next";
import { cookies } from "next/headers";
import { createServiceClient } from "@/lib/supabase/service";
import { NoGroupSelected } from "@/components/no-group-selected";

export const metadata: Metadata = { title: "Análise de Treinos" };
export const dynamic = "force-dynamic";

export default async function WorkoutAnalyticsPage() {
  const groupId = cookies().get("portal_group_id")?.value;
  if (!groupId) return <NoGroupSelected />;

  const db = createServiceClient();
  const now = Date.now();
  const dayMs = 86_400_000;
  const monthStart = now - 30 * dayMs;

  let activeTemplates = 0;
  let monthAssignments = 0;
  let completedCount = 0;
  let totalAssignments = 0;
  let avgDurationMin = 0;
  let error: string | null = null;

  try {
    const [templatesRes, assignmentsRes, executionsRes] = await Promise.all([
      db
        .from("coaching_workout_templates")
        .select("id", { count: "exact", head: true })
        .eq("group_id", groupId)
        .eq("is_active", true),
      db
        .from("coaching_workout_assignments")
        .select("id, status")
        .eq("group_id", groupId)
        .gte("created_at_ms", monthStart),
      db
        .from("coaching_workout_executions")
        .select("duration_min")
        .eq("group_id", groupId)
        .gte("completed_at_ms", monthStart),
    ]);

    activeTemplates = templatesRes.count ?? 0;

    const assignments = (assignmentsRes.data ?? []) as { id: string; status: string }[];
    monthAssignments = assignments.length;
    completedCount = assignments.filter((a) => a.status === "completed").length;
    totalAssignments = assignments.length;

    const executions = (executionsRes.data ?? []) as { duration_min: number }[];
    if (executions.length > 0) {
      const totalMin = executions.reduce((s, e) => s + (e.duration_min ?? 0), 0);
      avgDurationMin = Math.round(totalMin / executions.length);
    }
  } catch (e) {
    error = e instanceof Error ? e.message : "Erro ao carregar dados";
  }

  const completionRate =
    totalAssignments > 0 ? Math.round((completedCount / totalAssignments) * 100) : 0;

  if (error) {
    return (
      <div className="space-y-6">
        <div>
          <h1 className="text-2xl font-bold text-content-primary">Análise de Treinos</h1>
          <p className="mt-1 text-sm text-content-secondary">Métricas de treinos e execuções</p>
        </div>
        <div className="rounded-lg border border-error/30 bg-error-soft p-4">
          <p className="text-sm text-error">Erro ao carregar dados: {error}</p>
        </div>
      </div>
    );
  }

  const isEmpty =
    activeTemplates === 0 && monthAssignments === 0 && completedCount === 0;

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-content-primary">Análise de Treinos</h1>
        <p className="mt-1 text-sm text-content-secondary">
          Métricas de treinos e execuções (últimos 30 dias)
        </p>
      </div>

      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <KpiCard label="Templates Ativos" value={activeTemplates} color="text-brand" />
        <KpiCard label="Atribuições (mês)" value={monthAssignments} />
        <KpiCard
          label="Taxa de Conclusão %"
          value={`${completionRate}%`}
          color={
            completionRate >= 70
              ? "text-success"
              : completionRate >= 40
                ? "text-warning"
                : "text-error"
          }
        />
        <KpiCard
          label="Carga Média (min)"
          value={avgDurationMin}
          color="text-brand"
        />
      </div>

      {isEmpty && (
        <div className="rounded-xl border border-border bg-surface p-8 text-center shadow-sm">
          <svg
            className="mx-auto h-12 w-12 text-content-muted"
            fill="none"
            viewBox="0 0 24 24"
            strokeWidth={1.5}
            stroke="currentColor"
          >
            <path
              strokeLinecap="round"
              strokeLinejoin="round"
              d="M3.75 3v11.25A2.25 2.25 0 006 16.5h2.25M3.75 3h-1.5m1.5 0h16.5m0 0h1.5m-1.5 0v11.25A2.25 2.25 0 0118 16.5h-2.25m-7.5 0h7.5m-7.5 0l-1 3m8.5-3l1 3m0 0l.5 1.5m-.5-1.5h-9.5m0 0l-.5 1.5"
            />
          </svg>
          <h3 className="mt-4 text-sm font-semibold text-content-primary">
            Sem dados de treinos
          </h3>
          <p className="mt-1 text-xs text-content-secondary">
            Crie templates e atribua treinos para ver as métricas aqui.
          </p>
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
  value: number | string;
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
