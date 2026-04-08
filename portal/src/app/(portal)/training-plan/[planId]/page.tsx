"use client";

import { useEffect, useState, useCallback } from "react";
import { useParams } from "next/navigation";
import Link from "next/link";

// ─── Types ────────────────────────────────────────────────────────────────────

interface WorkoutRelease {
  id: string;
  scheduled_date: string;
  workout_order: number;
  release_status: string;
  workout_type: string;
  workout_label: string | null;
  coach_notes: string | null;
  content_version: number;
  template: { id: string; name: string; description: string | null } | null;
  completed: Array<{
    id: string;
    actual_distance_m: number | null;
    actual_duration_s: number | null;
    actual_avg_hr: number | null;
    perceived_effort: number | null;
    finished_at: string | null;
  }>;
  feedback: Array<{ rating: number | null; mood: number | null; how_was_it: string | null }>;
}

interface PlanWeek {
  id: string;
  week_number: number;
  starts_on: string;
  ends_on: string;
  label: string | null;
  coach_notes: string | null;
  cycle_type: string;
  status: string;
  workouts: WorkoutRelease[];
}

// ─── Constants ────────────────────────────────────────────────────────────────

const DAYS_OF_WEEK = ["Seg", "Ter", "Qua", "Qui", "Sex", "Sáb", "Dom"];

const STATUS_COLORS: Record<string, string> = {
  draft:       "bg-surface-elevated border-border text-content-secondary",
  scheduled:   "bg-warning-soft border-warning/30 text-warning",
  released:    "bg-info-soft border-info/30 text-info",
  in_progress: "bg-brand-soft border-brand/30 text-brand",
  completed:   "bg-success-soft border-success/30 text-success",
  cancelled:   "bg-error-soft border-error/30 text-error line-through opacity-60",
  replaced:    "bg-surface-elevated border-border text-content-muted line-through opacity-60",
};

const STATUS_LABELS: Record<string, string> = {
  draft:       "Rascunho",
  scheduled:   "Agendado",
  released:    "Liberado",
  in_progress: "Em andamento",
  completed:   "Concluído",
  cancelled:   "Cancelado",
  replaced:    "Substituído",
};

const CYCLE_LABELS: Record<string, string> = {
  base:       "Base",
  build:      "Construção",
  peak:       "Pico",
  recovery:   "Recuperação",
  test:       "Teste",
  free:       "Livre",
  taper:      "Taper",
  transition: "Transição",
};

const CYCLE_COLORS: Record<string, string> = {
  base:       "bg-blue-100 text-blue-800 dark:bg-blue-900/40 dark:text-blue-300",
  build:      "bg-orange-100 text-orange-800 dark:bg-orange-900/40 dark:text-orange-300",
  peak:       "bg-red-100 text-red-800 dark:bg-red-900/40 dark:text-red-300",
  recovery:   "bg-green-100 text-green-800 dark:bg-green-900/40 dark:text-green-300",
  test:       "bg-purple-100 text-purple-800 dark:bg-purple-900/40 dark:text-purple-300",
  free:       "bg-surface-elevated text-content-secondary",
  taper:      "bg-yellow-100 text-yellow-800 dark:bg-yellow-900/40 dark:text-yellow-300",
  transition: "bg-surface-elevated text-content-muted",
};

// ─── Helpers ──────────────────────────────────────────────────────────────────

function formatDate(d: string) {
  const [year, month, day] = d.split("-");
  return `${day}/${month}`;
}

function formatDuration(seconds: number) {
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  if (h > 0) return `${h}h${m.toString().padStart(2, "0")}`;
  return `${m}min`;
}

function getWorkoutsByDay(workouts: WorkoutRelease[], weekStart: string): Map<string, WorkoutRelease[]> {
  const map = new Map<string, WorkoutRelease[]>();
  const start = new Date(weekStart + "T00:00:00");
  for (let i = 0; i < 7; i++) {
    const d = new Date(start);
    d.setDate(d.getDate() + i);
    const key = d.toISOString().split("T")[0];
    map.set(key, workouts.filter((w) => w.scheduled_date === key));
  }
  return map;
}

// ─── Component ────────────────────────────────────────────────────────────────

export default function TrainingPlanDetailPage() {
  const { planId } = useParams<{ planId: string }>();
  const [weeks, setWeeks] = useState<PlanWeek[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [releasingWeek, setReleasingWeek] = useState<string | null>(null);
  const [actionMessage, setActionMessage] = useState<{ type: "success" | "error"; text: string } | null>(null);

  const loadWeeks = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await fetch(`/api/training-plan/${planId}/weeks`);
      const json = await res.json();
      if (!json.ok) throw new Error(json.error?.message ?? "Erro ao carregar");
      setWeeks(json.data ?? []);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Erro desconhecido");
    } finally {
      setLoading(false);
    }
  }, [planId]);

  useEffect(() => { loadWeeks(); }, [loadWeeks]);

  const handleBulkRelease = async (weekId: string, weekLabel: string) => {
    if (!confirm(`Liberar todos os treinos da semana "${weekLabel}"?`)) return;
    setReleasingWeek(weekId);
    setActionMessage(null);
    try {
      const res = await fetch(`/api/training-plan/weeks/${weekId}/release`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ reason: "Liberação manual pelo portal" }),
      });
      const json = await res.json();
      if (!json.ok) throw new Error(json.error?.message ?? "Erro");
      setActionMessage({ type: "success", text: `${json.data.released_count} treino(s) liberado(s) com sucesso!` });
      loadWeeks();
    } catch (e) {
      setActionMessage({ type: "error", text: e instanceof Error ? e.message : "Erro ao liberar" });
    } finally {
      setReleasingWeek(null);
    }
  };

  const handleReleaseWorkout = async (workoutId: string) => {
    setActionMessage(null);
    try {
      const res = await fetch(`/api/training-plan/workouts/${workoutId}/release`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({}),
      });
      const json = await res.json();
      if (!json.ok) throw new Error(json.error?.message ?? "Erro");
      setActionMessage({ type: "success", text: "Treino liberado!" });
      loadWeeks();
    } catch (e) {
      setActionMessage({ type: "error", text: e instanceof Error ? e.message : "Erro ao liberar" });
    }
  };

  const handleCancelWorkout = async (workoutId: string) => {
    if (!confirm("Cancelar este treino?")) return;
    setActionMessage(null);
    try {
      const res = await fetch(`/api/training-plan/workouts/${workoutId}/cancel`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({}),
      });
      const json = await res.json();
      if (!json.ok) throw new Error(json.error?.message ?? "Erro");
      setActionMessage({ type: "success", text: "Treino cancelado." });
      loadWeeks();
    } catch (e) {
      setActionMessage({ type: "error", text: e instanceof Error ? e.message : "Erro ao cancelar" });
    }
  };

  if (loading) {
    return (
      <div className="space-y-4 animate-pulse">
        {[1, 2, 3].map((i) => (
          <div key={i} className="h-48 rounded-xl bg-surface-elevated" />
        ))}
      </div>
    );
  }

  if (error) {
    return (
      <div className="rounded-xl border border-error/30 bg-error-soft p-6 text-center">
        <p className="text-sm text-error">{error}</p>
        <button onClick={loadWeeks} className="mt-3 rounded-lg bg-brand px-4 py-2 text-sm font-medium text-white">
          Tentar novamente
        </button>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-3">
          <Link href="/training-plan" className="text-content-muted hover:text-content-primary">
            ← Planilhas
          </Link>
          <h1 className="text-xl font-bold text-content-primary">Visão Semanal</h1>
        </div>
        <div className="flex gap-2">
          <button
            onClick={loadWeeks}
            className="rounded-lg border border-border px-3 py-2 text-sm font-medium text-content-secondary hover:bg-surface-elevated"
          >
            Atualizar
          </button>
          <button className="rounded-lg bg-brand px-4 py-2 text-sm font-medium text-white hover:bg-brand/90">
            + Adicionar Semana
          </button>
        </div>
      </div>

      {/* Action message */}
      {actionMessage && (
        <div className={`rounded-lg border px-4 py-3 text-sm ${
          actionMessage.type === "success"
            ? "border-success/30 bg-success-soft text-success"
            : "border-error/30 bg-error-soft text-error"
        }`}>
          {actionMessage.text}
        </div>
      )}

      {/* Empty state */}
      {weeks.length === 0 && (
        <div className="rounded-xl border border-border bg-surface p-12 text-center shadow-sm">
          <p className="text-sm text-content-secondary">Nenhuma semana criada nesta planilha ainda.</p>
          <button className="mt-3 rounded-lg bg-brand px-4 py-2 text-sm font-medium text-white hover:bg-brand/90">
            Adicionar primeira semana
          </button>
        </div>
      )}

      {/* Weeks */}
      {weeks.map((week) => {
        const workoutsByDay = getWorkoutsByDay(week.workouts ?? [], week.starts_on);
        const totalWorkouts = week.workouts?.length ?? 0;
        const releasedCount = week.workouts?.filter((w) =>
          ["released", "in_progress", "completed"].includes(w.release_status)
        ).length ?? 0;
        const completedCount = week.workouts?.filter((w) => w.release_status === "completed").length ?? 0;
        const isReleasing = releasingWeek === week.id;
        const hasUnreleased = week.workouts?.some((w) =>
          ["draft", "scheduled"].includes(w.release_status)
        );

        return (
          <div key={week.id} className="overflow-hidden rounded-xl border border-border bg-surface shadow-sm">
            {/* Week header */}
            <div className="flex items-center justify-between border-b border-border bg-bg-secondary px-5 py-3">
              <div className="flex items-center gap-3">
                <span className={`rounded-full px-2.5 py-0.5 text-xs font-semibold ${CYCLE_COLORS[week.cycle_type] ?? "bg-surface-elevated text-content-muted"}`}>
                  {CYCLE_LABELS[week.cycle_type] ?? week.cycle_type}
                </span>
                <div>
                  <h3 className="text-sm font-semibold text-content-primary">
                    Semana {week.week_number}
                    {week.label ? ` — ${week.label}` : ""}
                  </h3>
                  <p className="text-xs text-content-muted">
                    {formatDate(week.starts_on)} a {formatDate(week.ends_on)}
                    {" · "}
                    {totalWorkouts} treino{totalWorkouts !== 1 ? "s" : ""}
                    {totalWorkouts > 0 && (
                      <> · {completedCount}/{totalWorkouts} concluídos</>
                    )}
                  </p>
                </div>
              </div>

              <div className="flex items-center gap-2">
                {hasUnreleased && (
                  <button
                    onClick={() => handleBulkRelease(week.id, `Semana ${week.week_number}`)}
                    disabled={isReleasing}
                    className="flex items-center gap-1.5 rounded-lg bg-brand px-3 py-1.5 text-xs font-medium text-white hover:bg-brand/90 disabled:opacity-60"
                  >
                    {isReleasing ? (
                      <svg className="h-3.5 w-3.5 animate-spin" fill="none" viewBox="0 0 24 24">
                        <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4"/>
                        <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"/>
                      </svg>
                    ) : (
                      <svg className="h-3.5 w-3.5" fill="none" viewBox="0 0 24 24" strokeWidth={2} stroke="currentColor">
                        <path strokeLinecap="round" strokeLinejoin="round" d="M12 16.5V9.75m0 0l3 3m-3-3l-3 3M6.75 19.5a4.5 4.5 0 01-1.41-8.775 5.25 5.25 0 0110.338-2.32 5.75 5.75 0 011.846 1.087"/>
                      </svg>
                    )}
                    Liberar Semana
                  </button>
                )}
                <button className="rounded-lg border border-border px-3 py-1.5 text-xs text-content-secondary hover:bg-surface-elevated">
                  Duplicar
                </button>
              </div>
            </div>

            {/* Progress bar */}
            {totalWorkouts > 0 && (
              <div className="h-1 bg-border">
                <div
                  className="h-full bg-success transition-all"
                  style={{ width: `${(completedCount / totalWorkouts) * 100}%` }}
                />
              </div>
            )}

            {/* 7-column grid */}
            <div className="grid grid-cols-7 divide-x divide-border">
              {DAYS_OF_WEEK.map((dayLabel, i) => {
                const start = new Date(week.starts_on + "T00:00:00");
                start.setDate(start.getDate() + i);
                const dateKey = start.toISOString().split("T")[0];
                const dayWorkouts = workoutsByDay.get(dateKey) ?? [];
                const isToday = dateKey === new Date().toISOString().split("T")[0];

                return (
                  <div key={dateKey} className={`min-h-[140px] p-2 ${isToday ? "bg-brand-soft/30" : ""}`}>
                    {/* Day header */}
                    <div className={`mb-2 text-center ${isToday ? "text-brand font-semibold" : "text-content-muted"} text-xs`}>
                      {dayLabel}
                      <br />
                      <span className={`text-[11px] ${isToday ? "text-brand" : "text-content-muted"}`}>
                        {formatDate(dateKey)}
                      </span>
                    </div>

                    {/* Workouts */}
                    <div className="space-y-1.5">
                      {dayWorkouts
                        .sort((a, b) => a.workout_order - b.workout_order)
                        .map((workout) => {
                          const completed = workout.completed?.[0];
                          const feedback = workout.feedback?.[0];
                          const isCompleted = workout.release_status === "completed";
                          const isReleased = workout.release_status === "released";
                          const isDraft = workout.release_status === "draft";

                          return (
                            <div
                              key={workout.id}
                              className={`group relative rounded-lg border p-2 text-xs transition-all hover:shadow-sm ${STATUS_COLORS[workout.release_status] ?? "bg-surface-elevated border-border"}`}
                            >
                              {/* Template name */}
                              <p className="font-medium leading-tight truncate">
                                {workout.workout_label || workout.template?.name || "Treino"}
                              </p>

                              {/* Status */}
                              <p className="mt-0.5 opacity-75">
                                {STATUS_LABELS[workout.release_status] ?? workout.release_status}
                              </p>

                              {/* Completed metrics */}
                              {isCompleted && completed && (
                                <div className="mt-1 space-y-0.5 text-[10px] opacity-80">
                                  {completed.actual_distance_m && (
                                    <p>{(completed.actual_distance_m / 1000).toFixed(1)} km</p>
                                  )}
                                  {completed.actual_duration_s && (
                                    <p>{formatDuration(completed.actual_duration_s)}</p>
                                  )}
                                  {feedback?.rating && (
                                    <p>{"★".repeat(feedback.rating)}{"☆".repeat(5 - feedback.rating)}</p>
                                  )}
                                </div>
                              )}

                              {/* Updated badge */}
                              {workout.content_version > 1 && isReleased && (
                                <span className="absolute -top-1 -right-1 flex h-3.5 w-3.5 items-center justify-center rounded-full bg-warning text-[8px] text-white font-bold">
                                  !
                                </span>
                              )}

                              {/* Hover actions */}
                              <div className="absolute inset-x-0 -bottom-px hidden flex-col gap-0.5 rounded-b-lg border-t border-border bg-surface p-1 shadow-md group-hover:flex">
                                {isDraft && (
                                  <button
                                    onClick={() => handleReleaseWorkout(workout.id)}
                                    className="w-full rounded px-1 py-0.5 text-[10px] font-medium text-brand hover:bg-brand-soft"
                                  >
                                    Liberar
                                  </button>
                                )}
                                {!["completed", "cancelled", "replaced"].includes(workout.release_status) && (
                                  <button
                                    onClick={() => handleCancelWorkout(workout.id)}
                                    className="w-full rounded px-1 py-0.5 text-[10px] font-medium text-error hover:bg-error-soft"
                                  >
                                    Cancelar
                                  </button>
                                )}
                              </div>
                            </div>
                          );
                        })}

                      {/* Empty day drop target */}
                      {dayWorkouts.length === 0 && (
                        <div className="flex h-12 items-center justify-center rounded-lg border border-dashed border-border text-[10px] text-content-muted opacity-0 hover:opacity-100 transition-opacity cursor-pointer">
                          + treino
                        </div>
                      )}
                    </div>
                  </div>
                );
              })}
            </div>

            {/* Week notes */}
            {week.coach_notes && (
              <div className="border-t border-border px-5 py-2 text-xs text-content-secondary">
                <span className="font-medium">Notas:</span> {week.coach_notes}
              </div>
            )}
          </div>
        );
      })}
    </div>
  );
}
