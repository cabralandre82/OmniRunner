import { cookies } from "next/headers";
import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { NoGroupSelected } from "@/components/no-group-selected";
import { formatDateISO } from "@/lib/format";

export const dynamic = "force-dynamic";

const SPORT_LABELS: Record<string, string> = {
  running: "Corrida",
  cycling: "Ciclismo",
  triathlon: "Triathlon",
  swimming: "Natação",
  strength: "Força",
  multi: "Multi-esporte",
};

const STATUS_STYLES: Record<string, string> = {
  active:    "bg-success-soft text-success",
  paused:    "bg-warning-soft text-warning",
  completed: "bg-surface-elevated text-content-secondary",
  archived:  "bg-error-soft text-error",
};

const STATUS_LABELS: Record<string, string> = {
  active:    "Ativa",
  paused:    "Pausada",
  completed: "Concluída",
  archived:  "Arquivada",
};

interface Plan {
  id: string;
  name: string;
  sport_type: string;
  status: string;
  starts_on: string | null;
  ends_on: string | null;
  created_at: string;
  athlete_name: string | null;
  week_count: number;
}

async function getPlans(groupId: string): Promise<Plan[]> {
  const supabase = createClient();
  const { data, error } = await supabase
    .from("training_plans")
    .select("id, name, sport_type, status, starts_on, ends_on, created_at, athlete_user_id")
    .eq("group_id", groupId)
    .neq("status", "archived")
    .order("created_at", { ascending: false })
    .range(0, 99);

  if (error || !data) return [];

  const athleteIds = [...new Set(data.map((p) => p.athlete_user_id).filter(Boolean))];
  const weekCounts = new Map<string, number>();

  // Fetch week counts
  if (data.length > 0) {
    const { data: weeks } = await supabase
      .from("training_plan_weeks")
      .select("plan_id")
      .in("plan_id", data.map((p) => p.id));
    for (const w of weeks ?? []) {
      weekCounts.set(w.plan_id, (weekCounts.get(w.plan_id) ?? 0) + 1);
    }
  }

  // Fetch athlete names from profiles
  const athleteNames = new Map<string, string>();
  if (athleteIds.length > 0) {
    const { data: profiles } = await supabase
      .from("profiles")
      .select("id, full_name, username")
      .in("id", athleteIds);
    for (const p of profiles ?? []) {
      athleteNames.set(p.id, p.full_name || p.username || "Atleta");
    }
  }

  return data.map((p) => ({
    id: p.id,
    name: p.name,
    sport_type: p.sport_type,
    status: p.status,
    starts_on: p.starts_on,
    ends_on: p.ends_on,
    created_at: p.created_at,
    athlete_name: p.athlete_user_id ? (athleteNames.get(p.athlete_user_id) ?? null) : null,
    week_count: weekCounts.get(p.id) ?? 0,
  }));
}

export default async function TrainingPlanListPage() {
  const cookieStore = cookies();
  const groupId = cookieStore.get("portal_group_id")?.value;
  if (!groupId) return <NoGroupSelected />;

  let plans: Plan[] = [];
  let fetchError: string | null = null;

  try {
    plans = await getPlans(groupId);
  } catch (e) {
    fetchError = String(e);
  }

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-content-primary">Planilhas de Treino</h1>
          <p className="mt-1 text-sm text-content-secondary">
            Prescreva, organize e libere treinos para seus atletas
          </p>
        </div>
        <Link
          href="/training-plan/new"
          className="rounded-lg bg-brand px-5 py-2.5 text-sm font-medium text-white hover:bg-brand/90 transition-colors"
        >
          + Nova Planilha
        </Link>
      </div>

      {fetchError && (
        <div className="rounded-lg border border-error/30 bg-error-soft p-4 text-sm text-error">
          Erro ao carregar planilhas. Tente recarregar a página.
        </div>
      )}

      {plans.length === 0 && !fetchError ? (
        <div className="rounded-xl border border-border bg-surface p-12 text-center shadow-sm">
          <div className="mx-auto mb-4 flex h-14 w-14 items-center justify-center rounded-full bg-brand-soft">
            <svg className="h-7 w-7 text-brand" fill="none" viewBox="0 0 24 24" strokeWidth={1.5} stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" d="M6.75 3v2.25M17.25 3v2.25M3 18.75V7.5a2.25 2.25 0 012.25-2.25h13.5A2.25 2.25 0 0121 7.5v11.25m-18 0A2.25 2.25 0 005.25 21h13.5A2.25 2.25 0 0021 18.75m-18 0v-7.5A2.25 2.25 0 015.25 9h13.5A2.25 2.25 0 0121 11.25v7.5" />
            </svg>
          </div>
          <h3 className="text-base font-semibold text-content-primary">Nenhuma planilha criada</h3>
          <p className="mt-1 text-sm text-content-secondary">
            Crie sua primeira planilha para prescrever e distribuir treinos.
          </p>
          <Link
            href="/training-plan/new"
            className="mt-4 inline-block rounded-lg bg-brand px-5 py-2 text-sm font-medium text-white hover:bg-brand/90"
          >
            Criar primeira planilha
          </Link>
        </div>
      ) : (
        <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
          {plans.map((plan) => (
            <Link
              key={plan.id}
              href={`/training-plan/${plan.id}`}
              className="group block rounded-xl border border-border bg-surface p-5 shadow-sm transition-all hover:border-brand/40 hover:shadow-md"
            >
              <div className="flex items-start justify-between gap-3">
                <div className="min-w-0">
                  <h3 className="truncate font-semibold text-content-primary group-hover:text-brand">
                    {plan.name}
                  </h3>
                  {plan.athlete_name && (
                    <p className="mt-0.5 text-xs text-content-secondary">{plan.athlete_name}</p>
                  )}
                </div>
                <span className={`shrink-0 rounded-full px-2 py-0.5 text-xs font-medium ${STATUS_STYLES[plan.status] ?? "bg-surface-elevated text-content-secondary"}`}>
                  {STATUS_LABELS[plan.status] ?? plan.status}
                </span>
              </div>

              <div className="mt-3 flex flex-wrap items-center gap-x-4 gap-y-1 text-xs text-content-secondary">
                <span className="flex items-center gap-1">
                  <svg className="h-3.5 w-3.5" fill="none" viewBox="0 0 24 24" strokeWidth={1.5} stroke="currentColor">
                    <path strokeLinecap="round" strokeLinejoin="round" d="M15.362 5.214A8.252 8.252 0 0112 21 8.25 8.25 0 016.038 7.048 8.287 8.287 0 009 9.6a8.983 8.983 0 013.361-6.867 8.21 8.21 0 003 2.48z" />
                  </svg>
                  {SPORT_LABELS[plan.sport_type] ?? plan.sport_type}
                </span>
                <span className="flex items-center gap-1">
                  <svg className="h-3.5 w-3.5" fill="none" viewBox="0 0 24 24" strokeWidth={1.5} stroke="currentColor">
                    <path strokeLinecap="round" strokeLinejoin="round" d="M6.75 3v2.25M17.25 3v2.25M3 18.75V7.5a2.25 2.25 0 012.25-2.25h13.5A2.25 2.25 0 0121 7.5v11.25m-18 0A2.25 2.25 0 005.25 21h13.5A2.25 2.25 0 0021 18.75m-18 0v-7.5" />
                  </svg>
                  {plan.week_count} {plan.week_count === 1 ? "semana" : "semanas"}
                </span>
              </div>

              {(plan.starts_on || plan.ends_on) && (
                <p className="mt-2 text-xs text-content-muted">
                  {plan.starts_on && formatDateISO(plan.starts_on)}
                  {plan.starts_on && plan.ends_on && " → "}
                  {plan.ends_on && formatDateISO(plan.ends_on)}
                </p>
              )}
            </Link>
          ))}
        </div>
      )}
    </div>
  );
}
