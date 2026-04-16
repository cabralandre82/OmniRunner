import { cookies } from "next/headers";
import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { NoGroupSelected } from "@/components/no-group-selected";
import { formatDateISO } from "@/lib/format";
import { UnarchiveButton } from "./unarchive-button";
import { AthleteTrainingView } from "./athlete-view";
import { GroupWeekView } from "@/components/training-plan/group-week-view";

export const dynamic = "force-dynamic";

const SPORT_LABELS: Record<string, string> = {
  running:   "Corrida",
  cycling:   "Ciclismo",
  triathlon: "Triathlon",
  swimming:  "Natação",
  strength:  "Força",
  multi:     "Multi-esporte",
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

async function getPlans(groupId: string, includeArchived = false): Promise<Plan[]> {
  const supabase = createClient();
  let query = supabase
    .from("training_plans")
    .select("id, name, sport_type, status, starts_on, ends_on, created_at, athlete_user_id")
    .eq("group_id", groupId)
    .order("created_at", { ascending: false })
    .range(0, 99);

  if (!includeArchived) query = query.neq("status", "archived");
  const { data, error } = await query;

  if (error || !data) return [];

  const athleteIds = Array.from(new Set(data.map((p) => p.athlete_user_id).filter(Boolean)));
  const weekCounts = new Map<string, number>();

  if (data.length > 0) {
    const { data: weeks } = await supabase
      .from("training_plan_weeks")
      .select("plan_id")
      .in("plan_id", data.map((p) => p.id));
    for (const w of weeks ?? []) {
      weekCounts.set(w.plan_id, (weekCounts.get(w.plan_id) ?? 0) + 1);
    }
  }

  const athleteNames = new Map<string, string>();
  if (athleteIds.length > 0) {
    const { data: profiles } = await supabase
      .from("profiles")
      .select("id, display_name")
      .in("id", athleteIds);
    for (const p of profiles ?? []) {
      athleteNames.set(p.id, p.display_name || "Atleta");
    }
  }

  return data.map((p) => ({
    id:           p.id,
    name:         p.name,
    sport_type:   p.sport_type,
    status:       p.status,
    starts_on:    p.starts_on,
    ends_on:      p.ends_on,
    created_at:   p.created_at,
    athlete_name: p.athlete_user_id ? (athleteNames.get(p.athlete_user_id) ?? null) : null,
    week_count:   weekCounts.get(p.id) ?? 0,
  }));
}

export default async function TrainingPlanListPage({
  searchParams,
}: {
  searchParams?: { view?: string };
}) {
  const cookieStore = cookies();
  const groupId = cookieStore.get("portal_group_id")?.value;
  if (!groupId) return <NoGroupSelected />;

  const view = searchParams?.view === "plans" ? "plans"
    : searchParams?.view === "group" ? "group"
    : "athletes";

  let plans: Plan[] = [];
  let archivedPlans: Plan[] = [];
  let fetchError: string | null = null;

  if (view === "plans") {
    try {
      const all = await getPlans(groupId, true);
      plans = all.filter((p) => p.status !== "archived");
      archivedPlans = all.filter((p) => p.status === "archived");
    } catch (e) {
      fetchError = String(e);
    }
  }

  const tabClass = (t: string) =>
    `flex items-center gap-1.5 rounded-lg px-4 py-2 text-sm font-medium transition-colors ${
      view === t
        ? "bg-brand text-white"
        : "border border-border text-content-secondary hover:bg-surface-elevated"
    }`;


  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-content-primary">Passagem de Treino</h1>
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

      {/* View toggle */}
      <div className="flex gap-2">
        <Link href="/training-plan" className={tabClass("athletes")}>
          <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" strokeWidth={1.5} stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" d="M15 19.128a9.38 9.38 0 002.625.372 9.337 9.337 0 004.121-.952 4.125 4.125 0 00-7.533-2.493M15 19.128v-.003c0-1.113-.285-2.16-.786-3.07M15 19.128v.106A12.318 12.318 0 018.624 21c-2.331 0-4.512-.645-6.374-1.766l-.001-.109a6.375 6.375 0 0111.964-3.07M12 6.375a3.375 3.375 0 11-6.75 0 3.375 3.375 0 016.75 0zm8.25 2.25a2.625 2.625 0 11-5.25 0 2.625 2.625 0 015.25 0z" />
          </svg>
          Por atleta
        </Link>
        <Link href="/training-plan?view=plans" className={tabClass("plans")}>
          <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" strokeWidth={1.5} stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" d="M6.75 3v2.25M17.25 3v2.25M3 18.75V7.5a2.25 2.25 0 012.25-2.25h13.5A2.25 2.25 0 0121 7.5v11.25m-18 0A2.25 2.25 0 005.25 21h13.5A2.25 2.25 0 0021 18.75m-18 0v-7.5A2.25 2.25 0 015.25 9h13.5A2.25 2.25 0 0121 11.25v7.5" />
          </svg>
          Por planilha
        </Link>
        <Link href="/training-plan?view=group" className={tabClass("group")}>
          <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" strokeWidth={1.5} stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" d="M3.375 19.5h17.25m-17.25 0a1.125 1.125 0 01-1.125-1.125M3.375 19.5h1.5C5.496 19.5 6 18.996 6 18.375m-3.75 0V5.625m0 12.75v-1.5c0-.621.504-1.125 1.125-1.125m18.375 2.625V5.625m0 12.75c0 .621-.504 1.125-1.125 1.125m1.125-1.125v-1.5c0-.621-.504-1.125-1.125-1.125m0 3.75h-1.5A1.125 1.125 0 0118 18.375M20.625 4.5H3.375m17.25 0c.621 0 1.125.504 1.125 1.125M20.625 4.5h-1.5A1.125 1.125 0 0118 5.625m3.75 0v1.5c0 .621-.504 1.125-1.125 1.125M3.375 4.5c-.621 0-1.125.504-1.125 1.125M3.375 4.5h1.5C5.496 4.5 6 5.004 6 5.625m-3.75 0v1.5c0 .621.504 1.125 1.125 1.125m0 0h1.5m-1.5 0c-.621 0-1.125.504-1.125 1.125v1.5c0 .621.504 1.125 1.125 1.125m1.5-3.75C5.496 8.25 6 7.746 6 7.125v-1.5M4.875 8.25C5.496 8.25 6 8.754 6 9.375v1.5m0-5.25v5.25m0-5.25C6 5.004 6.504 4.5 7.125 4.5h9.75c.621 0 1.125.504 1.125 1.125m1.125 2.625h1.5m-1.5 0A1.125 1.125 0 0118 7.125v-1.5m1.125 2.625c-.621 0-1.125.504-1.125 1.125v1.5m2.625-2.625c.621 0 1.125.504 1.125 1.125v1.5c0 .621-.504 1.125-1.125 1.125M18 5.625v5.25M7.125 12h9.75m-9.75 0A1.125 1.125 0 016 10.875M7.125 12C6.504 12 6 12.504 6 13.125m0-2.25C6 11.496 5.496 12 4.875 12M18 10.875c0 .621-.504 1.125-1.125 1.125M18 10.875c.621 0 1.125.504 1.125 1.125v1.5c0 .621-.504 1.125-1.125 1.125m-9.75 0h9.75" />
          </svg>
          Visão Grupo
        </Link>
      </div>

      {/* ── ATHLETE VIEW ─────────────────────────────────────────────────────── */}
      {view === "athletes" && <AthleteTrainingView groupId={groupId} />}

      {/* ── GROUP WEEK VIEW ───────────────────────────────────────────────────── */}
      {view === "group" && <GroupWeekView />}

      {/* ── PLANS VIEW ───────────────────────────────────────────────────────── */}
      {view === "plans" && (
        <>
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

          {/* Archived plans */}
          {archivedPlans.length > 0 && (
            <details className="group">
              <summary className="cursor-pointer list-none">
                <div className="flex items-center gap-2 text-sm text-content-muted hover:text-content-secondary">
                  <svg className="h-4 w-4 transition-transform group-open:rotate-90" fill="none" viewBox="0 0 24 24" strokeWidth={1.5} stroke="currentColor">
                    <path strokeLinecap="round" strokeLinejoin="round" d="M8.25 4.5l7.5 7.5-7.5 7.5" />
                  </svg>
                  {archivedPlans.length} planilha{archivedPlans.length !== 1 ? "s" : ""} arquivada{archivedPlans.length !== 1 ? "s" : ""}
                </div>
              </summary>
              <div className="mt-3 space-y-2">
                {archivedPlans.map((plan) => (
                  <div key={plan.id} className="flex items-center justify-between rounded-lg border border-border bg-surface px-4 py-3 opacity-60">
                    <div className="min-w-0">
                      <p className="truncate text-sm font-medium text-content-secondary line-through">{plan.name}</p>
                      {plan.athlete_name && (
                        <p className="text-xs text-content-muted">{plan.athlete_name}</p>
                      )}
                    </div>
                    <UnarchiveButton planId={plan.id} planName={plan.name} />
                  </div>
                ))}
              </div>
            </details>
          )}
        </>
      )}
    </div>
  );
}
