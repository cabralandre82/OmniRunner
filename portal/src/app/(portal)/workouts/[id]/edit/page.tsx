import { cookies } from "next/headers";
import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { NoGroupSelected } from "@/components/no-group-selected";
import { TemplateBuilder } from "../../template-builder";

export const dynamic = "force-dynamic";

export default async function EditWorkoutPage({
  params,
}: {
  params: { id: string };
}) {
  const groupId = cookies().get("portal_group_id")?.value;
  if (!groupId) return <NoGroupSelected />;

  const supabase = createClient();

  const { data: template } = await supabase
    .from("coaching_workout_templates")
    .select("id, name, description, workout_type")
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
    .select(
      "id, order_index, block_type, duration_seconds, distance_meters, target_pace_min_sec_per_km, target_pace_max_sec_per_km, target_hr_zone, target_hr_min, target_hr_max, rpe_target, repeat_count, notes",
    )
    .eq("template_id", params.id)
    .order("order_index");

  return (
    <div className="space-y-4">
      <Link
        href={`/workouts/${params.id}`}
        className="text-sm text-content-secondary hover:text-primary"
      >
        ← Voltar ao template
      </Link>
      <TemplateBuilder
        templateId={template.id}
        initialName={template.name}
        initialDescription={template.description ?? ""}
        initialWorkoutType={template.workout_type ?? "free"}
        initialBlocks={(blocks ?? []).map((b) => ({
          id: b.id,
          order_index: b.order_index,
          block_type: b.block_type,
          duration_seconds: b.duration_seconds,
          distance_meters: b.distance_meters,
          target_pace_min_sec_per_km: b.target_pace_min_sec_per_km,
          target_pace_max_sec_per_km: b.target_pace_max_sec_per_km,
          target_hr_zone: b.target_hr_zone,
          target_hr_min: b.target_hr_min,
          target_hr_max: b.target_hr_max,
          rpe_target: b.rpe_target,
          repeat_count: b.repeat_count,
          notes: b.notes,
        }))}
      />
    </div>
  );
}
