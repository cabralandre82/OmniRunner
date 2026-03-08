import { cookies } from "next/headers";
import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { NoGroupSelected } from "@/components/no-group-selected";
import { DeleteTemplateButton } from "./delete-button";

export const dynamic = "force-dynamic";

const BLOCK_TYPE_LABELS: Record<string, string> = {
  warmup: "Aquecimento",
  interval: "Intervalo",
  recovery: "Recuperação",
  cooldown: "Desaquecimento",
  steady: "Contínuo",
  rest: "Descanso",
  repeat: "Repetir",
};

const BLOCK_TYPE_COLORS: Record<string, string> = {
  warmup: "bg-yellow-100 text-yellow-800 dark:bg-yellow-900/30 dark:text-yellow-300",
  interval: "bg-red-100 text-red-800 dark:bg-red-900/30 dark:text-red-300",
  recovery: "bg-green-100 text-green-800 dark:bg-green-900/30 dark:text-green-300",
  cooldown: "bg-blue-100 text-blue-800 dark:bg-blue-900/30 dark:text-blue-300",
  steady: "bg-emerald-100 text-emerald-800 dark:bg-emerald-900/30 dark:text-emerald-300",
  rest: "bg-gray-100 text-gray-800 dark:bg-gray-700/30 dark:text-gray-300",
  repeat: "bg-purple-100 text-purple-800 dark:bg-purple-900/30 dark:text-purple-300",
};

function fmtPace(secPerKm: number): string {
  const m = Math.floor(secPerKm / 60);
  const s = secPerKm % 60;
  return `${m}:${String(s).padStart(2, "0")}`;
}

function fmtDistance(meters: number): string {
  return meters >= 1000
    ? `${(meters / 1000).toFixed(1)} km`
    : `${meters} m`;
}

function fmtDuration(seconds: number): string {
  const m = Math.floor(seconds / 60);
  const s = seconds % 60;
  return s > 0 ? `${m}m${s}s` : `${m} min`;
}

interface Block {
  id: string;
  order_index: number;
  block_type: string;
  duration_seconds: number | null;
  distance_meters: number | null;
  target_pace_min_sec_per_km: number | null;
  target_pace_max_sec_per_km: number | null;
  target_hr_zone: number | null;
  target_hr_min: number | null;
  target_hr_max: number | null;
  rpe_target: number | null;
  repeat_count: number | null;
  notes: string | null;
}

export default async function WorkoutDetailPage({
  params,
}: {
  params: { id: string };
}) {
  const groupId = cookies().get("portal_group_id")?.value;
  if (!groupId) return <NoGroupSelected />;

  const supabase = createClient();

  const { data: template } = await supabase
    .from("coaching_workout_templates")
    .select("id, name, description, created_at")
    .eq("id", params.id)
    .eq("group_id", groupId)
    .single();

  if (!template) {
    return (
      <div className="p-8 text-center text-content-secondary">
        Template não encontrado.
      </div>
    );
  }

  const { data: blocks } = await supabase
    .from("coaching_workout_blocks")
    .select("*")
    .eq("template_id", params.id)
    .order("order_index");

  const blockList = (blocks ?? []) as Block[];

  const { count: assignmentCount } = await supabase
    .from("coaching_workout_assignments")
    .select("id", { count: "exact", head: true })
    .eq("template_id", params.id);

  let inRepeat = false;

  return (
    <div className="space-y-6">
      <div className="flex items-center gap-4">
        <Link
          href="/workouts"
          className="text-sm text-content-secondary hover:text-primary"
        >
          ← Voltar aos templates
        </Link>
      </div>

      <div className="rounded-xl border border-border bg-surface p-6 shadow-sm">
        <div className="flex items-start justify-between">
          <div>
            <h1 className="text-2xl font-bold text-content-primary">
              {template.name}
            </h1>
            {template.description && (
              <p className="mt-2 text-sm text-content-secondary">
                {template.description}
              </p>
            )}
            <div className="mt-4 flex gap-6 text-sm text-content-secondary">
              <span>{blockList.length} blocos</span>
              <span>{assignmentCount ?? 0} atribuições</span>
            </div>
          </div>
          <div className="flex items-center gap-2">
            <Link
              href={`/workouts/${params.id}/edit`}
              className="rounded-lg border border-brand bg-transparent px-4 py-2 text-sm font-medium text-brand hover:bg-brand/5"
            >
              Editar
            </Link>
            <DeleteTemplateButton templateId={params.id} />
          </div>
        </div>
      </div>

      {blockList.length > 0 && (() => {
        const totalDist = blockList.reduce((s, b) => s + (b.distance_meters ?? 0), 0);
        const totalDur = blockList.reduce((s, b) => s + (b.duration_seconds ?? 0), 0);
        const repeatBlocks = blockList.filter(b => b.block_type === "repeat");
        const totalRepeats = repeatBlocks.reduce((s, b) => s + (b.repeat_count ?? 0), 0);
        return (
          <div className="flex gap-4 flex-wrap">
            {totalDist > 0 && (
              <div className="flex-1 min-w-[140px] rounded-xl border border-border bg-surface p-4 text-center shadow-sm">
                <p className="text-2xl font-bold text-content-primary">{fmtDistance(totalDist)}</p>
                <p className="text-xs text-content-secondary">Distância total</p>
              </div>
            )}
            {totalDur > 0 && (
              <div className="flex-1 min-w-[140px] rounded-xl border border-border bg-surface p-4 text-center shadow-sm">
                <p className="text-2xl font-bold text-content-primary">{fmtDuration(totalDur)}</p>
                <p className="text-xs text-content-secondary">Duração total</p>
              </div>
            )}
            {totalRepeats > 0 && (
              <div className="flex-1 min-w-[140px] rounded-xl border border-border bg-surface p-4 text-center shadow-sm">
                <p className="text-2xl font-bold text-content-primary">{totalRepeats}x</p>
                <p className="text-xs text-content-secondary">Repetições</p>
              </div>
            )}
            <div className="flex-1 min-w-[140px] rounded-xl border border-border bg-surface p-4 text-center shadow-sm">
              <p className="text-2xl font-bold text-content-primary">{blockList.length}</p>
              <p className="text-xs text-content-secondary">Blocos</p>
            </div>
          </div>
        );
      })()}

      <div className="rounded-xl border border-border bg-surface shadow-sm">
        <div className="border-b border-border px-6 py-4">
          <h2 className="text-lg font-semibold text-content-primary">
            Estrutura do Treino
          </h2>
        </div>
        <div className="divide-y divide-border-subtle">
          {blockList.length === 0 && (
            <div className="p-8 text-center text-sm text-content-secondary">
              Nenhum bloco neste template.
            </div>
          )}
          {blockList.map((block) => {
            const isRepeat = block.block_type === "repeat";
            if (isRepeat) inRepeat = true;
            if (
              !isRepeat &&
              !["interval", "recovery"].includes(block.block_type)
            ) {
              inRepeat = false;
            }

            const details: string[] = [];
            if (isRepeat && block.repeat_count) {
              details.push(`${block.repeat_count}x`);
            }
            if (block.duration_seconds) {
              details.push(fmtDuration(block.duration_seconds));
            }
            if (block.distance_meters) {
              details.push(fmtDistance(block.distance_meters));
            }
            if (
              !block.duration_seconds &&
              !block.distance_meters &&
              !isRepeat
            ) {
              details.push("livre");
            }
            if (
              block.target_pace_min_sec_per_km &&
              block.target_pace_max_sec_per_km
            ) {
              const min = fmtPace(block.target_pace_min_sec_per_km);
              const max = fmtPace(block.target_pace_max_sec_per_km);
              details.push(
                min === max ? `${min}/km` : `${min}–${max}/km`
              );
            }
            if (block.target_hr_zone) {
              details.push(`Z${block.target_hr_zone}`);
            }
            if (block.target_hr_min && block.target_hr_max) {
              details.push(
                `${block.target_hr_min}–${block.target_hr_max} bpm`
              );
            }
            if (block.rpe_target) {
              details.push(`RPE ${block.rpe_target}`);
            }

            const indent =
              inRepeat && !isRepeat ? "ml-8" : "";

            return (
              <div
                key={block.id}
                className={`flex items-center gap-4 px-6 py-3 ${indent}`}
              >
                <div
                  className={`w-2 self-stretch rounded-full ${
                    BLOCK_TYPE_COLORS[block.block_type]?.split(" ")[0] ??
                    "bg-gray-300"
                  }`}
                />
                <span
                  className={`inline-block rounded px-2 py-0.5 text-xs font-semibold ${
                    BLOCK_TYPE_COLORS[block.block_type] ??
                    "bg-gray-100 text-gray-800"
                  }`}
                >
                  {BLOCK_TYPE_LABELS[block.block_type] ?? block.block_type}
                </span>
                <span className="text-sm text-content-primary">
                  {details.join(" · ")}
                </span>
                {block.notes && (
                  <span className="text-xs italic text-content-secondary">
                    {block.notes}
                  </span>
                )}
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
}
