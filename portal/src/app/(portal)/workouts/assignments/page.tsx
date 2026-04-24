import { cookies } from "next/headers";
import { createClient } from "@/lib/supabase/server";
import { NoGroupSelected } from "@/components/no-group-selected";
import { formatDateISO } from "@/lib/format";
import Link from "next/link";

export const dynamic = "force-dynamic";

const STATUS_LABELS: Record<string, { label: string; color: string }> = {
  planned: { label: "Planejado", color: "bg-info-soft text-info" },
  completed: { label: "Concluído", color: "bg-success-soft text-success" },
  missed: { label: "Perdido", color: "bg-error-soft text-error" },
};

const PAGE_SIZE = 25;

// L05-26 — humaniza "faz X h/d" para a coluna Relógio. Inputs curtos
// viram "agora", >7 dias mostra data crua.
function timeAgo(iso: string): string {
  const ageMs = Date.now() - new Date(iso).getTime();
  const minutes = Math.floor(ageMs / 60_000);
  if (minutes < 1) return "agora";
  if (minutes < 60) return `${minutes} min`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h`;
  const days = Math.floor(hours / 24);
  if (days < 7) return `${days}d`;
  return formatDateISO(iso.slice(0, 10));
}

interface Assignment {
  id: string;
  scheduled_date: string;
  status: string;
  athlete_name: string;
  template_name: string;
  last_export_at: string | null;
  last_export_surface: "app" | "portal" | null;
}

async function getAssignments(
  groupId: string,
  from?: string,
  to?: string,
  page = 1,
): Promise<{ assignments: Assignment[]; total: number }> {
  const supabase = createClient();

  const now = new Date();
  const defaultFrom = new Date(now);
  defaultFrom.setDate(defaultFrom.getDate() - 30);
  const fromDate = from ?? defaultFrom.toISOString().slice(0, 10);
  const toDate = to ?? now.toISOString().slice(0, 10);

  const offset = (page - 1) * PAGE_SIZE;

  const { data: assignments, count } = await supabase
    .from("coaching_workout_assignments")
    .select(
      "id, scheduled_date, status, athlete_user_id, template_id",
      { count: "exact" },
    )
    .eq("group_id", groupId)
    .gte("scheduled_date", fromDate)
    .lte("scheduled_date", toDate)
    .order("scheduled_date", { ascending: false })
    .range(offset, offset + PAGE_SIZE - 1);

  if (!assignments || assignments.length === 0) {
    return { assignments: [], total: 0 };
  }

  const athleteIds = Array.from(new Set(assignments.map((a) => a.athlete_user_id)));
  const templateIds = Array.from(new Set(assignments.map((a) => a.template_id)));
  const assignmentIds = assignments.map((a) => a.id);

  const [profilesRes, templatesRes, exportsRes] = await Promise.all([
    supabase
      .from("profiles")
      .select("id, display_name")
      .in("id", athleteIds),
    supabase
      .from("coaching_workout_templates")
      .select("id, name")
      .in("id", templateIds),
    // L05-26 — last export per assignment, via the view (RLS-compliant).
    supabase
      .from("v_assignment_last_export")
      .select("assignment_id, last_export_at, surface")
      .in("assignment_id", assignmentIds),
  ]);

  const profileMap = new Map(
    (profilesRes.data ?? []).map((p: { id: string; display_name: string }) => [
      p.id,
      p.display_name || "Sem nome",
    ]),
  );
  const templateMap = new Map(
    (templatesRes.data ?? []).map((t: { id: string; name: string }) => [
      t.id,
      t.name,
    ]),
  );
  const exportMap = new Map(
    (exportsRes.data ?? []).map(
      (e: {
        assignment_id: string;
        last_export_at: string;
        surface: "app" | "portal";
      }) => [e.assignment_id, { at: e.last_export_at, surface: e.surface }],
    ),
  );

  return {
    assignments: assignments.map((a) => {
      const exp = exportMap.get(a.id);
      return {
        id: a.id,
        scheduled_date: a.scheduled_date,
        status: a.status,
        athlete_name: profileMap.get(a.athlete_user_id) ?? "Sem nome",
        template_name: templateMap.get(a.template_id) ?? "Template removido",
        last_export_at: exp?.at ?? null,
        last_export_surface: exp?.surface ?? null,
      };
    }),
    total: count ?? 0,
  };
}

export default async function WorkoutAssignmentsPage({
  searchParams,
}: {
  searchParams: Promise<{ from?: string; to?: string; page?: string }>;
}) {
  const groupId = cookies().get("portal_group_id")?.value;
  if (!groupId) return <NoGroupSelected />;

  const params = await searchParams;
  const page = Math.max(1, parseInt(params.page ?? "1", 10) || 1);

  let assignments: Assignment[] = [];
  let total = 0;
  let fetchError: string | null = null;

  try {
    const result = await getAssignments(groupId, params.from, params.to, page);
    assignments = result.assignments;
    total = result.total;
  } catch (e) {
    fetchError = String(e);
  }

  const totalPages = Math.ceil(total / PAGE_SIZE);

  const buildPageUrl = (p: number) => {
    const sp = new URLSearchParams();
    if (params.from) sp.set("from", params.from);
    if (params.to) sp.set("to", params.to);
    sp.set("page", String(p));
    return `/workouts/assignments?${sp.toString()}`;
  };

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-content-primary">Atribuições de Treino</h1>
        <p className="mt-1 text-sm text-content-secondary">
          Treinos atribuídos aos atletas
        </p>
      </div>

      {fetchError && (
        <div className="rounded-lg border border-error/30 bg-error-soft p-6 text-center">
          <p className="text-error">Erro ao carregar dados. Tente recarregar a página.</p>
        </div>
      )}

      <form className="flex flex-wrap items-end gap-3">
        <div>
          <label htmlFor="from" className="block text-xs font-medium text-content-secondary">
            De
          </label>
          <input
            type="date"
            id="from"
            name="from"
            defaultValue={params.from ?? ""}
            className="mt-1 rounded-lg border border-border px-3 py-1.5 text-sm shadow-sm focus:border-brand focus:ring-1 focus:ring-brand"
          />
        </div>
        <div>
          <label htmlFor="to" className="block text-xs font-medium text-content-secondary">
            Até
          </label>
          <input
            type="date"
            id="to"
            name="to"
            defaultValue={params.to ?? ""}
            className="mt-1 rounded-lg border border-border px-3 py-1.5 text-sm shadow-sm focus:border-brand focus:ring-1 focus:ring-brand"
          />
        </div>
        <button
          type="submit"
          className="rounded-lg bg-brand px-4 py-1.5 text-sm font-medium text-white shadow-sm hover:brightness-110"
        >
          Filtrar
        </button>
      </form>

      <div className="overflow-hidden rounded-xl border border-border bg-surface shadow-sm">
        <div className="overflow-x-auto">
          <table className="min-w-full divide-y divide-border text-sm">
            <thead className="bg-bg-secondary">
              <tr>
                <th className="px-4 py-3 text-left font-medium text-content-secondary">Atleta</th>
                <th className="px-4 py-3 text-left font-medium text-content-secondary">Template</th>
                <th className="px-4 py-3 text-left font-medium text-content-secondary">Data</th>
                <th className="px-4 py-3 text-center font-medium text-content-secondary">Status</th>
                <th
                  className="px-4 py-3 text-center font-medium text-content-secondary"
                  title="Última vez que o .fit foi gerado para este treino"
                >
                  Relógio
                </th>
              </tr>
            </thead>
            <tbody className="divide-y divide-border-subtle">
              {assignments.map((a) => {
                const statusInfo =
                  STATUS_LABELS[a.status] ?? { label: a.status, color: "bg-surface-elevated text-content-primary" };
                return (
                  <tr key={a.id} className="hover:bg-surface-elevated">
                    <td className="whitespace-nowrap px-4 py-3 font-medium text-content-primary">
                      {a.athlete_name}
                    </td>
                    <td className="whitespace-nowrap px-4 py-3 text-content-secondary">
                      {a.template_name}
                    </td>
                    <td className="whitespace-nowrap px-4 py-3 text-content-secondary">
                      {formatDateISO(a.scheduled_date)}
                    </td>
                    <td className="whitespace-nowrap px-4 py-3 text-center">
                      <span
                        className={`inline-flex rounded-full px-2.5 py-0.5 text-xs font-medium ${statusInfo.color}`}
                      >
                        {statusInfo.label}
                      </span>
                    </td>
                    <td className="whitespace-nowrap px-4 py-3 text-center">
                      {a.last_export_at ? (
                        <span
                          className={`inline-flex items-center gap-1 rounded-full px-2.5 py-0.5 text-xs font-medium ${
                            a.last_export_surface === "app"
                              ? "bg-success-soft text-success"
                              : "bg-info-soft text-info"
                          }`}
                          title={`Gerado ${
                            a.last_export_surface === "app"
                              ? "pelo atleta"
                              : "pelo coach (portal)"
                          } em ${new Date(a.last_export_at).toLocaleString("pt-BR")}`}
                        >
                          {a.last_export_surface === "app" ? "Atleta" : "Coach"}{" "}
                          · {timeAgo(a.last_export_at)}
                        </span>
                      ) : (
                        <span className="text-xs text-content-muted">—</span>
                      )}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </div>

      {assignments.length === 0 && !fetchError && (
        <div className="rounded-xl border border-border bg-surface p-8 text-center shadow-sm">
          <p className="text-sm text-content-secondary">Nenhuma atribuição encontrada.</p>
        </div>
      )}

      {totalPages > 1 && (
        <div className="flex items-center justify-center gap-2">
          {page > 1 && (
            <Link
              href={buildPageUrl(page - 1)}
              className="rounded-lg border border-border bg-surface px-3 py-1.5 text-xs font-medium text-content-secondary shadow-sm hover:bg-surface-elevated"
            >
              Anterior
            </Link>
          )}
          <span className="text-sm text-content-secondary">
            Página {page} de {totalPages}
          </span>
          {page < totalPages && (
            <Link
              href={buildPageUrl(page + 1)}
              className="rounded-lg border border-border bg-surface px-3 py-1.5 text-xs font-medium text-content-secondary shadow-sm hover:bg-surface-elevated"
            >
              Próxima
            </Link>
          )}
        </div>
      )}
    </div>
  );
}
