import { cookies } from "next/headers";
import { createClient } from "@/lib/supabase/server";
import { formatDateISO } from "@/lib/format";

export const dynamic = "force-dynamic";

interface WorkoutTemplate {
  id: string;
  name: string;
  description: string | null;
  created_at: string;
  block_count: number;
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
    .select("template_id")
    .in("template_id", templateIds);

  const blockCountMap = new Map<string, number>();
  for (const b of blocks ?? []) {
    const tid = (b as { template_id: string }).template_id;
    blockCountMap.set(tid, (blockCountMap.get(tid) ?? 0) + 1);
  }

  return templates.map((t) => ({
    id: t.id,
    name: t.name,
    description: t.description,
    created_at: t.created_at,
    block_count: blockCountMap.get(t.id) ?? 0,
  }));
}

export default async function WorkoutsPage() {
  const groupId = cookies().get("portal_group_id")?.value;
  if (!groupId) return null;

  let templates: WorkoutTemplate[] = [];
  let fetchError: string | null = null;

  try {
    templates = await getTemplates(groupId);
  } catch (e) {
    fetchError = String(e);
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-gray-900">Templates de Treino</h1>
        <p className="mt-1 text-sm text-gray-500">
          Gerencie os templates de treino do grupo
        </p>
      </div>

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
                <th className="px-4 py-3 text-left font-medium text-gray-500">Nome</th>
                <th className="px-4 py-3 text-left font-medium text-gray-500">Descrição</th>
                <th className="px-4 py-3 text-center font-medium text-gray-500">Blocos</th>
                <th className="px-4 py-3 text-left font-medium text-gray-500">Criado em</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {templates.map((t) => (
                <tr key={t.id} className="hover:bg-gray-50">
                  <td className="whitespace-nowrap px-4 py-3 font-medium text-gray-900">
                    {t.name}
                  </td>
                  <td className="max-w-[300px] truncate px-4 py-3 text-gray-600">
                    {t.description ?? "—"}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-center text-gray-700">
                    {t.block_count}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-gray-600">
                    {formatDateISO(t.created_at)}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      {templates.length === 0 && !fetchError && (
        <div className="rounded-xl border border-gray-200 bg-white p-8 text-center shadow-sm">
          <p className="text-sm text-gray-500">Nenhum template criado.</p>
        </div>
      )}
    </div>
  );
}
