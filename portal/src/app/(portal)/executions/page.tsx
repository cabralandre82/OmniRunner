import { cookies } from "next/headers";
import { createClient } from "@/lib/supabase/server";
import { formatDateISO } from "@/lib/format";

export const dynamic = "force-dynamic";

interface Execution {
  id: string;
  athlete_name: string | null;
  template_name: string | null;
  actual_duration_seconds: number | null;
  actual_distance_meters: number | null;
  avg_pace_seconds_per_km: number | null;
  avg_hr: number | null;
  max_hr: number | null;
  calories: number | null;
  source: string;
  completed_at: string;
}

function formatDuration(seconds: number | null): string {
  if (!seconds) return "—";
  const m = Math.floor(seconds / 60);
  const s = seconds % 60;
  return `${m}min${s > 0 ? ` ${s}s` : ""}`;
}

function formatDistance(meters: number | null): string {
  if (!meters) return "—";
  return `${(meters / 1000).toFixed(1)} km`;
}

function formatPace(secPerKm: number | null): string {
  if (!secPerKm) return "—";
  const m = Math.floor(secPerKm / 60);
  const s = secPerKm % 60;
  return `${m}:${s.toString().padStart(2, "0")} /km`;
}

async function getExecutions(
  groupId: string,
  dateFrom?: string,
  dateTo?: string,
): Promise<Execution[]> {
  const supabase = createClient();

  let query = supabase
    .from("coaching_workout_executions")
    .select(
      "id, actual_duration_seconds, actual_distance_meters, avg_pace_seconds_per_km, avg_hr, max_hr, calories, source, completed_at, athlete_user_id, coaching_workout_assignments(scheduled_date, coaching_workout_templates(name)), profiles!athlete_user_id(display_name)",
    )
    .eq("group_id", groupId)
    .order("completed_at", { ascending: false })
    .limit(200);

  if (dateFrom) {
    query = query.gte("completed_at", dateFrom);
  }
  if (dateTo) {
    query = query.lte("completed_at", dateTo + "T23:59:59Z");
  }

  const { data, error } = await query;
  if (error) throw error;

  return (data ?? []).map((r: Record<string, unknown>) => {
    const assignment = r.coaching_workout_assignments as Record<string, unknown> | null;
    const template = assignment?.coaching_workout_templates as Record<string, unknown> | null;
    const profile = r.profiles as Record<string, unknown> | null;

    return {
      id: r.id as string,
      athlete_name: (profile?.display_name as string) ?? null,
      template_name: (template?.name as string) ?? null,
      actual_duration_seconds: r.actual_duration_seconds as number | null,
      actual_distance_meters: r.actual_distance_meters as number | null,
      avg_pace_seconds_per_km: r.avg_pace_seconds_per_km as number | null,
      avg_hr: r.avg_hr as number | null,
      max_hr: r.max_hr as number | null,
      calories: r.calories as number | null,
      source: r.source as string,
      completed_at: r.completed_at as string,
    };
  });
}

export default async function ExecutionsPage({
  searchParams,
}: {
  searchParams: { from?: string; to?: string };
}) {
  const groupId = cookies().get("portal_group_id")?.value;
  if (!groupId) return null;

  let executions: Execution[] = [];
  let fetchError: string | null = null;

  try {
    executions = await getExecutions(groupId, searchParams.from, searchParams.to);
  } catch (e) {
    fetchError = String(e);
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-gray-900">Execuções de Treino</h1>
        <p className="mt-1 text-sm text-gray-500">
          Histórico de execuções dos atletas do grupo
        </p>
      </div>

      {/* Date range filters */}
      <form className="flex flex-wrap items-end gap-4">
        <div>
          <label htmlFor="from" className="block text-xs font-medium text-gray-500 mb-1">
            De
          </label>
          <input
            type="date"
            id="from"
            name="from"
            defaultValue={searchParams.from ?? ""}
            className="rounded-lg border border-gray-300 px-3 py-2 text-sm"
          />
        </div>
        <div>
          <label htmlFor="to" className="block text-xs font-medium text-gray-500 mb-1">
            Até
          </label>
          <input
            type="date"
            id="to"
            name="to"
            defaultValue={searchParams.to ?? ""}
            className="rounded-lg border border-gray-300 px-3 py-2 text-sm"
          />
        </div>
        <button
          type="submit"
          className="rounded-lg bg-blue-600 px-4 py-2 text-sm font-medium text-white hover:bg-blue-700"
        >
          Filtrar
        </button>
      </form>

      {fetchError && (
        <div className="rounded-lg border border-red-200 bg-red-50 p-6 text-center">
          <p className="text-red-600">Erro ao carregar dados. Tente recarregar a página.</p>
        </div>
      )}

      <div className="overflow-hidden rounded-xl border border-gray-200 bg-white shadow-sm">
        <div className="overflow-x-auto">
          <table className="min-w-full divide-y divide-gray-200 text-sm">
            <thead className="bg-gray-50">
              <tr>
                <th className="px-4 py-3 text-left font-medium text-gray-500">Atleta</th>
                <th className="px-4 py-3 text-left font-medium text-gray-500">Treino</th>
                <th className="px-4 py-3 text-right font-medium text-gray-500">Duração</th>
                <th className="px-4 py-3 text-right font-medium text-gray-500">Distância</th>
                <th className="px-4 py-3 text-right font-medium text-gray-500">Pace</th>
                <th className="px-4 py-3 text-right font-medium text-gray-500">FC</th>
                <th className="px-4 py-3 text-center font-medium text-gray-500">Fonte</th>
                <th className="px-4 py-3 text-left font-medium text-gray-500">Data</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {executions.map((ex) => (
                <tr key={ex.id} className="hover:bg-gray-50">
                  <td className="whitespace-nowrap px-4 py-3 font-medium text-gray-900">
                    {ex.athlete_name ?? "—"}
                  </td>
                  <td className="max-w-[200px] truncate px-4 py-3 text-gray-600">
                    {ex.template_name ?? "—"}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-right text-gray-700">
                    {formatDuration(ex.actual_duration_seconds)}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-right text-gray-700">
                    {formatDistance(ex.actual_distance_meters)}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-right text-gray-700">
                    {formatPace(ex.avg_pace_seconds_per_km)}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-right text-gray-700">
                    {ex.avg_hr ? `${ex.avg_hr} bpm` : "—"}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-center">
                    <span className="inline-block rounded-full bg-gray-100 px-2 py-0.5 text-xs font-medium text-gray-700">
                      {ex.source}
                    </span>
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-gray-600">
                    {formatDateISO(ex.completed_at)}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      {executions.length === 0 && !fetchError && (
        <div className="rounded-xl border border-gray-200 bg-white p-8 text-center shadow-sm">
          <p className="text-sm text-gray-500">Nenhuma execução registrada.</p>
        </div>
      )}
    </div>
  );
}
