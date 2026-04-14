"use client";

import { useEffect, useState, useCallback } from "react";
import { useParams } from "next/navigation";
import Link from "next/link";
import Image from "next/image";
import { WeeklyPlanner } from "@/components/training-plan/weekly-planner";
import { PlanWeek, CYCLE_LABEL, CycleType } from "@/components/training-plan/types";

// ─── Types ────────────────────────────────────────────────────────────────────

interface PlanHeader {
  id: string;
  name: string;
  sport_type: string;
  status: string;
  starts_on: string | null;
  ends_on: string | null;
  athlete_user_id: string | null;
  athlete_name: string | null;
  athlete_avatar: string | null;
  group_id: string;
  description: string | null;
}

const SPORT_ICON: Record<string, string> = {
  running:   "🏃",
  cycling:   "🚴",
  triathlon: "🏅",
  swimming:  "🏊",
  strength:  "💪",
  multi:     "🔁",
};

const PLAN_STATUS_STYLE: Record<string, string> = {
  active:    "bg-success-soft text-success",
  paused:    "bg-warning-soft text-warning",
  completed: "bg-surface-elevated text-content-secondary",
  archived:  "bg-error-soft text-error",
};

const PLAN_STATUS_LABEL: Record<string, string> = {
  active:    "Ativa",
  paused:    "Pausada",
  completed: "Concluída",
  archived:  "Arquivada",
};

const CYCLE_OPTIONS: CycleType[] = [
  "base", "build", "peak", "recovery", "taper", "test", "free", "transition",
];

// ─── Add Week Modal ───────────────────────────────────────────────────────────

function AddWeekModal({
  open,
  planId,
  lastWeekEnd,
  onClose,
  onSuccess,
}: {
  open: boolean;
  planId: string;
  lastWeekEnd: string | null;
  onClose: () => void;
  onSuccess: () => void;
}) {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Auto-suggest next Monday after last week
  function suggestStartDate(): string {
    if (!lastWeekEnd) {
      const now = new Date();
      const day = now.getDay();
      const diffToMonday = day === 0 ? 1 : 8 - day;
      now.setDate(now.getDate() + (day === 1 ? 0 : diffToMonday));
      return now.toISOString().split("T")[0];
    }
    const after = new Date(lastWeekEnd + "T00:00:00");
    after.setDate(after.getDate() + 1);
    return after.toISOString().split("T")[0];
  }

  const [startsOn, setStartsOn] = useState(suggestStartDate());
  const [cycleType, setCycleType] = useState<CycleType>("base");
  const [label, setLabel] = useState("");
  const [coachNotes, setCoachNotes] = useState("");

  useEffect(() => {
    if (open) {
      setStartsOn(suggestStartDate());
      setError(null);
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, lastWeekEnd]);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setLoading(true);
    setError(null);
    try {
      const res = await fetch(`/api/training-plan/${planId}/weeks`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          starts_on: startsOn,
          cycle_type: cycleType,
          label: label || undefined,
          coach_notes: coachNotes || undefined,
        }),
      });
      const json = await res.json();
      if (!json.ok) {
        const msg = json.error?.code === "WEEK_MUST_START_ON_MONDAY"
          ? "A semana deve começar numa segunda-feira."
          : json.error?.message ?? "Erro ao criar semana";
        throw new Error(msg);
      }
      onSuccess();
      onClose();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Erro desconhecido");
    } finally {
      setLoading(false);
    }
  }

  if (!open) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
      <div className="absolute inset-0 bg-overlay/70" onClick={onClose} aria-hidden="true" />
      <form
        onSubmit={handleSubmit}
        className="relative z-10 w-full max-w-md rounded-2xl bg-surface p-6 shadow-2xl"
      >
        <h2 className="mb-5 text-base font-semibold text-content-primary">Adicionar semana</h2>

        <div className="space-y-4">
          <div>
            <label className="mb-1.5 block text-xs font-medium text-content-secondary">
              Início da semana (deve ser segunda-feira)
            </label>
            <input
              type="date"
              value={startsOn}
              onChange={(e) => setStartsOn(e.target.value)}
              required
              className="w-full rounded-lg border border-border bg-bg-secondary px-3 py-2 text-sm text-content-primary focus:border-brand focus:outline-none"
            />
          </div>

          <div>
            <label className="mb-1.5 block text-xs font-medium text-content-secondary">
              Tipo de ciclo
            </label>
            <select
              value={cycleType}
              onChange={(e) => setCycleType(e.target.value as CycleType)}
              className="w-full rounded-lg border border-border bg-bg-secondary px-3 py-2 text-sm text-content-primary focus:border-brand focus:outline-none"
            >
              {CYCLE_OPTIONS.map((c) => (
                <option key={c} value={c}>{CYCLE_LABEL[c]}</option>
              ))}
            </select>
          </div>

          <div>
            <label className="mb-1.5 block text-xs font-medium text-content-secondary">
              Rótulo da semana (opcional)
            </label>
            <input
              type="text"
              value={label}
              onChange={(e) => setLabel(e.target.value)}
              placeholder="ex: Semana de pico antes da prova"
              maxLength={80}
              className="w-full rounded-lg border border-border bg-bg-secondary px-3 py-2 text-sm text-content-primary placeholder:text-content-muted focus:border-brand focus:outline-none"
            />
          </div>

          <div>
            <label className="mb-1.5 block text-xs font-medium text-content-secondary">
              Notas do treinador (opcional)
            </label>
            <textarea
              value={coachNotes}
              onChange={(e) => setCoachNotes(e.target.value)}
              rows={2}
              placeholder="Orientações gerais para a semana..."
              maxLength={500}
              className="w-full resize-none rounded-lg border border-border bg-bg-secondary px-3 py-2 text-sm text-content-primary placeholder:text-content-muted focus:border-brand focus:outline-none"
            />
          </div>

          {error && (
            <p className="text-sm text-error">{error}</p>
          )}
        </div>

        <div className="mt-6 flex justify-end gap-3">
          <button
            type="button"
            onClick={onClose}
            disabled={loading}
            className="rounded-lg border border-border px-4 py-2 text-sm text-content-secondary hover:bg-surface-elevated disabled:opacity-50"
          >
            Cancelar
          </button>
          <button
            type="submit"
            disabled={loading}
            className="rounded-lg bg-brand px-5 py-2 text-sm font-semibold text-white hover:bg-brand/90 disabled:opacity-60"
          >
            {loading ? "Criando..." : "Criar semana"}
          </button>
        </div>
      </form>
    </div>
  );
}

// ─── Page ─────────────────────────────────────────────────────────────────────

export default function TrainingPlanDetailPage() {
  const { planId } = useParams<{ planId: string }>();
  const [plan, setPlan] = useState<PlanHeader | null>(null);
  const [weeks, setWeeks] = useState<PlanWeek[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [showAddWeek, setShowAddWeek] = useState(false);

  const loadData = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const [planRes, weeksRes] = await Promise.all([
        fetch(`/api/training-plan/${planId}`),
        fetch(`/api/training-plan/${planId}/weeks`),
      ]);
      const [planJson, weeksJson] = await Promise.all([planRes.json(), weeksRes.json()]);

      if (!planJson.ok) throw new Error(planJson.error?.message ?? "Plano não encontrado");
      if (!weeksJson.ok) throw new Error(weeksJson.error?.message ?? "Erro ao carregar semanas");

      setPlan(planJson.data);
      setWeeks(weeksJson.data ?? []);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Erro desconhecido");
    } finally {
      setLoading(false);
    }
  }, [planId]);

  useEffect(() => { loadData(); }, [loadData]);

  const lastWeekEnd = weeks.length > 0 ? weeks[weeks.length - 1].ends_on : null;

  // ── Stats ──────────────────────────────────────────────────────────────────

  const totalWorkouts = weeks.reduce((s, w) => s + (w.workouts?.length ?? 0), 0);
  const releasedCount = weeks.reduce(
    (s, w) => s + (w.workouts?.filter((x) => ["released", "in_progress", "completed"].includes(x.release_status)).length ?? 0),
    0,
  );
  const completedCount = weeks.reduce(
    (s, w) => s + (w.workouts?.filter((x) => x.release_status === "completed").length ?? 0),
    0,
  );

  // ── Render ─────────────────────────────────────────────────────────────────

  if (loading) {
    return (
      <div className="space-y-4 animate-pulse">
        <div className="h-24 rounded-xl bg-surface-elevated" />
        {[1, 2].map((i) => (
          <div key={i} className="h-52 rounded-xl bg-surface-elevated" />
        ))}
      </div>
    );
  }

  if (error || !plan) {
    return (
      <div className="rounded-xl border border-error/30 bg-error-soft p-8 text-center">
        <p className="text-sm text-error">{error ?? "Plano não encontrado"}</p>
        <button onClick={loadData} className="mt-3 rounded-lg bg-brand px-4 py-2 text-sm font-medium text-white">
          Tentar novamente
        </button>
      </div>
    );
  }

  return (
    <div className="space-y-5">
      {/* Plan header card */}
      <div className="rounded-xl border border-border bg-surface p-5 shadow-sm">
        <div className="flex items-start justify-between gap-4">
          <div className="flex items-start gap-4 min-w-0">
            {/* Athlete avatar */}
            <div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-full bg-surface-elevated text-lg font-semibold text-brand">
              {plan.athlete_avatar ? (
                <Image
                  src={plan.athlete_avatar}
                  alt={plan.athlete_name ?? ""}
                  width={48}
                  height={48}
                  unoptimized
                  className="h-full w-full rounded-full object-cover"
                />
              ) : (
                (plan.athlete_name?.[0] ?? "A").toUpperCase()
              )}
            </div>

            <div className="min-w-0">
              <div className="flex flex-wrap items-center gap-2">
                <h1 className="text-lg font-bold text-content-primary truncate">{plan.name}</h1>
                <span className={`shrink-0 rounded-full px-2 py-0.5 text-xs font-medium ${PLAN_STATUS_STYLE[plan.status] ?? "bg-surface-elevated text-content-secondary"}`}>
                  {PLAN_STATUS_LABEL[plan.status] ?? plan.status}
                </span>
              </div>

              {plan.athlete_name && (
                <p className="mt-0.5 text-sm text-content-secondary">
                  {SPORT_ICON[plan.sport_type] ?? "🏅"} {plan.athlete_name}
                </p>
              )}

              {/* Stats row */}
              <div className="mt-2 flex flex-wrap gap-4 text-xs text-content-muted">
                <span>{weeks.length} semana{weeks.length !== 1 ? "s" : ""}</span>
                <span>{totalWorkouts} treino{totalWorkouts !== 1 ? "s" : ""}</span>
                {totalWorkouts > 0 && (
                  <span className="text-success font-medium">
                    {completedCount}/{totalWorkouts} concluídos
                  </span>
                )}
                {releasedCount > 0 && (
                  <span className="text-info font-medium">
                    {releasedCount} liberado{releasedCount !== 1 ? "s" : ""}
                  </span>
                )}
              </div>
            </div>
          </div>

          {/* Header actions */}
          <div className="flex shrink-0 items-center gap-2">
            <Link
              href="/training-plan"
              className="rounded-lg border border-border px-3 py-2 text-xs text-content-secondary hover:bg-surface-elevated"
            >
              ← Planilhas
            </Link>
            <button
              onClick={loadData}
              className="rounded-lg border border-border p-2 text-content-muted hover:bg-surface-elevated"
              title="Atualizar"
            >
              <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" strokeWidth={1.5} stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" d="M16.023 9.348h4.992v-.001M2.985 19.644v-4.992m0 0h4.992m-4.993 0l3.181 3.183a8.25 8.25 0 0013.803-3.7M4.031 9.865a8.25 8.25 0 0113.803-3.7l3.181 3.182m0-4.991v4.99" />
              </svg>
            </button>
          </div>
        </div>

        {/* Progress bar */}
        {totalWorkouts > 0 && (
          <div className="mt-4">
            <div className="mb-1 flex justify-between text-[11px] text-content-muted">
              <span>Progresso geral</span>
              <span>{Math.round((completedCount / totalWorkouts) * 100)}%</span>
            </div>
            <div className="h-2 overflow-hidden rounded-full bg-surface-elevated">
              <div
                className="h-full bg-success transition-all duration-700"
                style={{ width: `${(completedCount / totalWorkouts) * 100}%` }}
              />
            </div>
          </div>
        )}
      </div>

      {/* Quick guide (only if no weeks) */}
      {weeks.length === 0 && (
        <div className="rounded-xl border border-border bg-surface p-8 text-center shadow-sm">
          <div className="mx-auto mb-3 flex h-12 w-12 items-center justify-center rounded-full bg-brand-soft text-2xl">
            📅
          </div>
          <h3 className="text-base font-semibold text-content-primary">Nenhuma semana criada</h3>
          <p className="mt-1 text-sm text-content-secondary">
            Crie a primeira semana para começar a prescrever treinos.
          </p>
          <button
            onClick={() => setShowAddWeek(true)}
            className="mt-4 rounded-lg bg-brand px-5 py-2 text-sm font-semibold text-white hover:bg-brand/90"
          >
            + Criar primeira semana
          </button>
        </div>
      )}

      {/* Weekly planner */}
      {weeks.length > 0 && plan.athlete_user_id && (
        <WeeklyPlanner
          planId={planId}
          weeks={weeks}
          athleteId={plan.athlete_user_id}
          groupId={plan.group_id}
          onWeeksChange={setWeeks}
        />
      )}

      {/* Add week button (shown below all weeks) */}
      {weeks.length > 0 && (
        <button
          onClick={() => setShowAddWeek(true)}
          className="flex w-full items-center justify-center gap-2 rounded-xl border-2 border-dashed border-border py-4 text-sm text-content-muted transition-colors hover:border-brand hover:text-brand hover:bg-brand-soft/30"
        >
          <svg className="h-5 w-5" fill="none" viewBox="0 0 24 24" strokeWidth={2} stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" d="M12 4.5v15m7.5-7.5h-15" />
          </svg>
          Adicionar próxima semana
        </button>
      )}

      {/* Add Week Modal */}
      <AddWeekModal
        open={showAddWeek}
        planId={planId}
        lastWeekEnd={lastWeekEnd}
        onClose={() => setShowAddWeek(false)}
        onSuccess={loadData}
      />
    </div>
  );
}
