import { cookies } from "next/headers";
import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { NoGroupSelected } from "@/components/no-group-selected";
import { formatDateISO } from "@/lib/format";

export const dynamic = "force-dynamic";

interface WorkoutBlock {
  template_id: string;
  block_type: string;
  distance_meters: number | null;
  repeat_count: number | null;
}

interface WorkoutTemplate {
  id: string;
  name: string;
  description: string | null;
  created_at: string;
  block_count: number;
  total_distance_m: number;
}

function calcTotalDistance(blocks: WorkoutBlock[]): number {
  let total = 0;
  let repeatMult = 1;
  let inRepeat = false;
  for (const b of blocks) {
    if (b.block_type === "repeat") {
      repeatMult = b.repeat_count ?? 1;
      inRepeat = true;
      continue;
    }
    if (b.block_type !== "rest" && b.distance_meters) {
      total += b.distance_meters * (inRepeat ? repeatMult : 1);
    }
    if (!["interval", "recovery"].includes(b.block_type)) {
      inRepeat = false;
      repeatMult = 1;
    }
  }
  return total;
}

async function getTemplates(groupId: string): Promise<WorkoutTemplate[]> {
  const supabase = createClient();

  const { data: templates } = await supabase
    .from("coaching_workout_templates")
    .select("id, name, description, created_at")
    .eq("group_id", groupId)
    .order("created_at", { ascending: false })
    .range(0, 49);

  if (!templates || templates.length === 0) return [];

  const templateIds = templates.map((t) => t.id);

  const { data: blocks } = await supabase
    .from("coaching_workout_blocks")
    .select("template_id, block_type, distance_meters, repeat_count")
    .in("template_id", templateIds)
    .order("order_index");

  const blocksByTemplate = new Map<string, WorkoutBlock[]>();
  const blockCountMap = new Map<string, number>();
  for (const b of (blocks ?? []) as WorkoutBlock[]) {
    const tid = b.template_id;
    blockCountMap.set(tid, (blockCountMap.get(tid) ?? 0) + 1);
    if (!blocksByTemplate.has(tid)) blocksByTemplate.set(tid, []);
    blocksByTemplate.get(tid)!.push(b);
  }

  return templates.map((t) => ({
    id: t.id,
    name: t.name,
    description: t.description,
    created_at: t.created_at,
    block_count: blockCountMap.get(t.id) ?? 0,
    total_distance_m: calcTotalDistance(blocksByTemplate.get(t.id) ?? []),
  }));
}

export default async function WorkoutsPage() {
  const groupId = cookies().get("portal_group_id")?.value;
  if (!groupId) return <NoGroupSelected />;

  let templates: WorkoutTemplate[] = [];
  let fetchError: string | null = null;

  try {
    templates = await getTemplates(groupId);
  } catch (e) {
    fetchError = String(e);
  }

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-content-primary">Templates de Treino</h1>
          <p className="mt-1 text-sm text-content-secondary">
            Gerencie os templates de treino do grupo
          </p>
        </div>
        <Link
          href="/workouts/new"
          className="rounded-lg bg-brand px-5 py-2.5 text-sm font-medium text-white hover:bg-brand/90"
        >
          + Novo Template
        </Link>
      </div>

      {fetchError && (
        <div className="rounded-lg border border-error/30 bg-error-soft p-6 text-center">
          <p className="text-error">Erro ao carregar dados. Tente recarregar a página.</p>
        </div>
      )}

      <div className="overflow-hidden rounded-xl border border-border bg-surface shadow-sm">
        <div className="overflow-x-auto">
          <table className="min-w-full divide-y divide-border text-sm">
            <thead className="bg-bg-secondary">
              <tr>
                <th className="px-4 py-3 text-left font-medium text-content-secondary">Nome</th>
                <th className="px-4 py-3 text-left font-medium text-content-secondary">Descrição</th>
                <th className="px-4 py-3 text-center font-medium text-content-secondary">Blocos</th>
                <th className="px-4 py-3 text-center font-medium text-content-secondary">Distância</th>
                <th className="px-4 py-3 text-left font-medium text-content-secondary">Criado em</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-border-subtle">
              {templates.map((t) => (
                <tr key={t.id} className="hover:bg-surface-elevated">
                  <td className="whitespace-nowrap px-4 py-3 font-medium text-content-primary">
                    <Link href={`/workouts/${t.id}`} className="text-primary hover:underline">
                      {t.name}
                    </Link>
                  </td>
                  <td className="max-w-[300px] truncate px-4 py-3 text-content-secondary">
                    {t.description ?? "—"}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-center text-content-secondary">
                    {t.block_count}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-center text-content-secondary">
                    {t.total_distance_m > 0
                      ? `${(t.total_distance_m / 1000).toFixed(1)} km`
                      : "—"}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-content-secondary">
                    {formatDateISO(t.created_at)}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      {templates.length === 0 && !fetchError && (
        <div className="rounded-xl border border-border bg-surface p-8 text-center shadow-sm">
          <p className="text-sm text-content-secondary">Nenhum template criado.</p>
        </div>
      )}
    </div>
  );
}
