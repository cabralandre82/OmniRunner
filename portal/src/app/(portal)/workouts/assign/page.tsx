import { cookies } from "next/headers";
import { createClient } from "@/lib/supabase/server";
import { NoGroupSelected } from "@/components/no-group-selected";
import { AssignWorkoutClient } from "./assign-client";

export const dynamic = "force-dynamic";

interface Athlete {
  member_id: string;
  user_id: string;
  display_name: string;
  watch_type: string | null;
  linked_provider: string | null;
  recent_assignments: {
    id: string;
    scheduled_date: string;
    status: string;
    template_name: string;
  }[];
}

interface Template {
  id: string;
  name: string;
  block_count: number;
}

async function getData(groupId: string) {
  const supabase = createClient();

  // Athletes with watch type (from view)
  const { data: members } = await supabase
    .from("coaching_members")
    .select("id, user_id, display_name, watch_type")
    .eq("group_id", groupId)
    .in("role", ["athlete", "atleta"])
    .order("display_name");

  if (!members || members.length === 0) {
    return { athletes: [] as Athlete[], templates: [] as Template[] };
  }

  const athleteIds = members.map((m) => m.user_id);

  // Device links for auto-detection
  const { data: deviceLinks } = await supabase
    .from("coaching_device_links")
    .select("athlete_user_id, provider")
    .eq("group_id", groupId)
    .in("athlete_user_id", athleteIds);

  const deviceMap = new Map<string, string>();
  for (const dl of deviceLinks ?? []) {
    deviceMap.set(dl.athlete_user_id, dl.provider);
  }

  // Recent assignments (last 14 days)
  const twoWeeksAgo = new Date();
  twoWeeksAgo.setDate(twoWeeksAgo.getDate() - 14);
  const fromDate = twoWeeksAgo.toISOString().split("T")[0];

  const { data: assignments } = await supabase
    .from("coaching_workout_assignments")
    .select("id, athlete_user_id, scheduled_date, status, template_id, coaching_workout_templates(name)")
    .eq("group_id", groupId)
    .gte("scheduled_date", fromDate)
    .in("athlete_user_id", athleteIds)
    .order("scheduled_date", { ascending: false });

  const assignmentsByAthlete = new Map<string, Athlete["recent_assignments"]>();
  for (const a of assignments ?? []) {
    const uid = a.athlete_user_id;
    if (!assignmentsByAthlete.has(uid)) assignmentsByAthlete.set(uid, []);
    assignmentsByAthlete.get(uid)!.push({
      id: a.id,
      scheduled_date: a.scheduled_date,
      status: a.status,
      template_name:
        (a.coaching_workout_templates as any)?.name ?? "Treino",
    });
  }

  // Templates
  const { data: templates } = await supabase
    .from("coaching_workout_templates")
    .select("id, name")
    .eq("group_id", groupId)
    .order("name");

  const { data: blocks } = await supabase
    .from("coaching_workout_blocks")
    .select("template_id")
    .in(
      "template_id",
      (templates ?? []).map((t) => t.id)
    );

  const blockCountMap = new Map<string, number>();
  for (const b of blocks ?? []) {
    const tid = (b as { template_id: string }).template_id;
    blockCountMap.set(tid, (blockCountMap.get(tid) ?? 0) + 1);
  }

  const athletes: Athlete[] = members.map((m) => {
    const linkedProvider = deviceMap.get(m.user_id) ?? null;
    const resolvedWatch = m.watch_type ?? (
      linkedProvider === "garmin" ? "garmin"
      : linkedProvider === "apple" ? "apple_watch"
      : linkedProvider === "polar" ? "polar"
      : linkedProvider === "suunto" ? "suunto"
      : null
    );

    return {
      member_id: m.id,
      user_id: m.user_id,
      display_name: m.display_name,
      watch_type: resolvedWatch,
      linked_provider: linkedProvider,
      recent_assignments: assignmentsByAthlete.get(m.user_id) ?? [],
    };
  });

  const templateList: Template[] = (templates ?? []).map((t) => ({
    id: t.id,
    name: t.name,
    block_count: blockCountMap.get(t.id) ?? 0,
  }));

  return { athletes, templates: templateList };
}

export default async function AssignWorkoutPage() {
  const groupId = cookies().get("portal_group_id")?.value;
  if (!groupId) return <NoGroupSelected />;

  const { athletes, templates } = await getData(groupId);

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-content-primary">
          Atribuir Treinos
        </h1>
        <p className="mt-1 text-sm text-content-secondary">
          Selecione atletas, escolha um template e defina a data
        </p>
      </div>

      <AssignWorkoutClient athletes={athletes} templates={templates} />
    </div>
  );
}
