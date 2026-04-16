"use client";

import { useState, useCallback } from "react";
import {
  PlanWeek,
  WorkoutRelease,
  WorkoutPickResult,
  ReleaseBlock,
  STATUS_LABEL,
  STATUS_BG,
  WORKOUT_TYPE_LABEL,
  CYCLE_LABEL,
  CYCLE_BG,
  formatDate,
  formatDuration,
  weekDates,
  ReleaseStatus,
} from "./types";
import { WorkoutPickerDrawer } from "./workout-picker-drawer";
import { WorkoutActionDrawer } from "./workout-action-drawer";
import { BatchAssignModal } from "./batch-assign-modal";

const DAYS_PT = ["Seg", "Ter", "Qua", "Qui", "Sex", "Sáb", "Dom"];

const TYPE_EMOJI: Record<string, string> = {
  continuous:   "🏃",
  interval:     "⚡",
  regenerative: "🌱",
  long_run:     "🛤️",
  strength:     "💪",
  technique:    "🎯",
  test:         "⏱️",
  free:         "🆓",
  race:         "🏆",
  brick:        "🔁",
};

interface WeeklyPlannerProps {
  planId: string;
  weeks: PlanWeek[];
  athleteId: string;
  groupId: string;
  onWeeksChange: (weeks: PlanWeek[]) => void;
}

interface ActivePicker {
  weekId: string;
  date: string;
  dayLabel: string;
}

export function WeeklyPlanner({
  planId,
  weeks,
  athleteId,
  groupId,
  onWeeksChange,
}: WeeklyPlannerProps) {
  const [activePicker, setActivePicker] = useState<ActivePicker | null>(null);
  const [activeWorkout, setActiveWorkout] = useState<WorkoutRelease | null>(null);
  const [batchWeek, setBatchWeek] = useState<PlanWeek | null>(null);
  const [actionLoading, setActionLoading] = useState<string | null>(null);
  const [pickerLoading, setPickerLoading] = useState(false);
  const [toast, setToast] = useState<{ type: "success" | "error"; text: string } | null>(null);

  const showToast = useCallback((type: "success" | "error", text: string) => {
    setToast({ type, text });
    setTimeout(() => setToast(null), 3500);
  }, []);

  // ── Reload weeks ───────────────────────────────────────────────────────────

  const reloadWeeks = useCallback(async () => {
    const res = await fetch(`/api/training-plan/${planId}/weeks`);
    const json = await res.json();
    if (json.ok) onWeeksChange(json.data ?? []);
  }, [planId, onWeeksChange]);

  // ── Add workout (template or descriptive) ──────────────────────────────────

  const handlePick = useCallback(
    async (result: WorkoutPickResult) => {
      if (!activePicker) return;
      setPickerLoading(true);
      try {
        let body: Record<string, unknown>;
        let toastName: string;

        if (result.mode === "template") {
          body = {
            athlete_id:     athleteId,
            template_id:    result.template.id,
            scheduled_date: activePicker.date,
            workout_type:   result.template.workout_type,
          };
          toastName = result.template.name;
        } else {
          body = {
            athlete_id:     athleteId,
            scheduled_date: activePicker.date,
            workout_type:   result.workout_type,
            workout_label:  result.label,
            description:    result.description,
            coach_notes:    result.coach_notes,
            video_url:      result.video_url,
            blocks:         result.blocks,
          };
          toastName = result.label;
        }

        const res = await fetch(`/api/training-plan/weeks/${activePicker.weekId}/workouts`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(body),
        });
        const json = await res.json();
        if (!json.ok) throw new Error(json.error?.message ?? "Erro");
        setActivePicker(null);
        await reloadWeeks();
        showToast("success", `"${toastName}" adicionado para ${activePicker.dayLabel}`);
      } catch (e) {
        showToast("error", e instanceof Error ? e.message : "Erro ao adicionar");
      } finally {
        setPickerLoading(false);
      }
    },
    [activePicker, athleteId, reloadWeeks, showToast],
  );

  // ── Release workout ────────────────────────────────────────────────────────

  const handleRelease = useCallback(
    async (workoutId: string) => {
      const res = await fetch(`/api/training-plan/workouts/${workoutId}/release`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({}),
      });
      const json = await res.json();
      if (!json.ok) throw new Error(json.error?.message ?? "Erro ao liberar");
      await reloadWeeks();
      showToast("success", "Treino liberado!");
    },
    [reloadWeeks, showToast],
  );

  // ── Cancel workout ─────────────────────────────────────────────────────────

  const handleCancel = useCallback(
    async (workoutId: string) => {
      const res = await fetch(`/api/training-plan/workouts/${workoutId}/cancel`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({}),
      });
      const json = await res.json();
      if (!json.ok) throw new Error(json.error?.message ?? "Erro ao cancelar");
      await reloadWeeks();
      showToast("success", "Treino cancelado.");
    },
    [reloadWeeks, showToast],
  );

  // ── Copy workout ───────────────────────────────────────────────────────────

  const handleCopyToDay = useCallback(
    async (workoutId: string, targetDate: string) => {
      const res = await fetch(`/api/training-plan/workouts/${workoutId}/copy`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ target_date: targetDate }),
      });
      const json = await res.json();
      if (!json.ok) throw new Error(json.error?.message ?? "Erro ao copiar");
      await reloadWeeks();
      showToast("success", "Treino copiado!");
    },
    [reloadWeeks, showToast],
  );

  // ── Update label/notes ─────────────────────────────────────────────────────

  const handleUpdateLabel = useCallback(
    async (workoutId: string, label: string, notes: string) => {
      const res = await fetch(`/api/training-plan/workouts/${workoutId}/update`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ workout_label: label || null, coach_notes: notes || null }),
      });
      const json = await res.json();
      if (!json.ok) throw new Error(json.error?.message ?? "Erro ao atualizar");
      await reloadWeeks();
      showToast("success", "Treino atualizado!");
    },
    [reloadWeeks, showToast],
  );

  // ── Update blocks (per-athlete customization) ─────────────────────────────

  const handleUpdateBlocks = useCallback(
    async (workoutId: string, blocks: ReleaseBlock[]) => {
      const res = await fetch(`/api/training-plan/workouts/${workoutId}/update`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ blocks }),
      });
      const json = await res.json();
      if (!json.ok) throw new Error(json.error?.message ?? "Erro ao salvar blocos");
      await reloadWeeks();
      showToast("success", "Blocos personalizados salvos!");
    },
    [reloadWeeks, showToast],
  );

  // ── Schedule ───────────────────────────────────────────────────────────────

  const handleSchedule = useCallback(
    async (workoutId: string, scheduledAt: string) => {
      const res = await fetch(`/api/training-plan/workouts/${workoutId}/schedule`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ scheduled_release_at: scheduledAt }),
      });
      const json = await res.json();
      if (!json.ok) throw new Error(json.error?.message ?? "Erro ao agendar");
      await reloadWeeks();
      showToast("success", "Liberação agendada!");
    },
    [reloadWeeks, showToast],
  );

  // ── Bulk release week ──────────────────────────────────────────────────────

  const handleBulkRelease = useCallback(
    async (weekId: string, weekLabel: string) => {
      if (!confirm(`Liberar todos os treinos rascunho da "${weekLabel}" agora?`)) return;
      setActionLoading(`bulk-release-${weekId}`);
      try {
        const res = await fetch(`/api/training-plan/weeks/${weekId}/release`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ reason: "Liberação em lote pelo portal" }),
        });
        const json = await res.json();
        if (!json.ok) throw new Error(json.error?.message ?? "Erro");
        await reloadWeeks();
        showToast("success", `${json.data?.released_count ?? "?"} treino(s) liberado(s)!`);
      } catch (e) {
        showToast("error", e instanceof Error ? e.message : "Erro ao liberar");
      } finally {
        setActionLoading(null);
      }
    },
    [reloadWeeks, showToast],
  );

  // ── Duplicate week ─────────────────────────────────────────────────────────

  const handleDuplicateWeek = useCallback(
    async (weekId: string, targetStartsOn?: string) => {
      setActionLoading(`dup-${weekId}`);
      try {
        const body = targetStartsOn ? { target_starts_on: targetStartsOn } : {};
        const res = await fetch(`/api/training-plan/weeks/${weekId}/duplicate`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(body),
        });
        const json = await res.json();
        if (!json.ok) throw new Error(json.error?.message ?? "Erro");
        await reloadWeeks();
        showToast("success", targetStartsOn ? "Semana replicada como próxima!" : "Semana duplicada!");
      } catch (e) {
        showToast("error", e instanceof Error ? e.message : "Erro ao duplicar");
      } finally {
        setActionLoading(null);
      }
    },
    [reloadWeeks, showToast],
  );

  // ── Replicate week as next week ─────────────────────────────────────────────

  const handleReplicateAsNext = useCallback(
    async (weekId: string, weekEndsOn: string) => {
      // Monday after week.ends_on (which is Sunday)
      const sunday = new Date(weekEndsOn + "T00:00:00");
      sunday.setDate(sunday.getDate() + 1);
      const nextMonday = sunday.toISOString().split("T")[0];
      await handleDuplicateWeek(weekId, nextMonday);
    },
    [handleDuplicateWeek],
  );

  // ── Batch assign success ───────────────────────────────────────────────────

  const handleBatchSuccess = useCallback(
    (count: number) => {
      showToast("success", `Semana distribuída para ${count} atleta${count !== 1 ? "s" : ""}!`);
    },
    [showToast],
  );

  // ── Render ─────────────────────────────────────────────────────────────────

  return (
    <>
      {/* Toast */}
      {toast && (
        <div
          className={`fixed bottom-6 left-1/2 z-[100] -translate-x-1/2 rounded-xl border px-5 py-3 text-sm font-medium shadow-lg transition-all ${
            toast.type === "success"
              ? "border-success/30 bg-success-soft text-success"
              : "border-error/30 bg-error-soft text-error"
          }`}
        >
          {toast.text}
        </div>
      )}

      {/* Weeks */}
      <div className="space-y-5">
        {weeks.map((week) => (
          <WeekBlock
            key={week.id}
            week={week}
            onCellClick={(date, label) =>
              setActivePicker({ weekId: week.id, date, dayLabel: label })
            }
            onWorkoutClick={(w) => setActiveWorkout(w)}
            onBulkRelease={handleBulkRelease}
            onDuplicate={handleDuplicateWeek}
            onReplicateAsNext={(weekId) => handleReplicateAsNext(weekId, week.ends_on)}
            onBatchAssign={(w) => setBatchWeek(w)}
            actionLoading={actionLoading}
            activePicker={activePicker}
          />
        ))}
      </div>

      {/* Workout Picker Drawer */}
      <WorkoutPickerDrawer
        open={activePicker !== null}
        targetDate={activePicker?.date ?? null}
        targetDayLabel={activePicker?.dayLabel ?? ""}
        groupId={groupId}
        onPick={handlePick}
        onClose={() => setActivePicker(null)}
        loading={pickerLoading}
      />

      {/* Workout Action Drawer */}
      <WorkoutActionDrawer
        key={activeWorkout?.id ?? "closed"}
        workout={activeWorkout}
        onClose={() => setActiveWorkout(null)}
        onRelease={handleRelease}
        onCancel={handleCancel}
        onCopyToDay={handleCopyToDay}
        onUpdateLabel={handleUpdateLabel}
        onUpdateBlocks={handleUpdateBlocks}
        onSchedule={handleSchedule}
      />

      {/* Batch Assign Modal */}
      <BatchAssignModal
        open={batchWeek !== null}
        sourceWeek={batchWeek}
        groupId={groupId}
        currentAthleteId={athleteId}
        onClose={() => setBatchWeek(null)}
        onSuccess={handleBatchSuccess}
      />
    </>
  );
}

// ─── WeekBlock ────────────────────────────────────────────────────────────────

interface WeekBlockProps {
  week: PlanWeek;
  onCellClick: (date: string, label: string) => void;
  onWorkoutClick: (w: WorkoutRelease) => void;
  onBulkRelease: (weekId: string, label: string) => void;
  onDuplicate: (weekId: string) => void;
  onReplicateAsNext: (weekId: string) => void;
  onBatchAssign: (week: PlanWeek) => void;
  actionLoading: string | null;
  activePicker: ActivePicker | null;
}

function WeekBlock({
  week,
  onCellClick,
  onWorkoutClick,
  onBulkRelease,
  onDuplicate,
  onReplicateAsNext,
  onBatchAssign,
  actionLoading,
  activePicker,
}: WeekBlockProps) {
  const [showMenu, setShowMenu] = useState(false);

  // Exclude cancelled / replaced / archived workouts from all counts
  const activeWorkouts = week.workouts?.filter(
    (w) => !["cancelled", "replaced", "archived"].includes(w.release_status)
  ) ?? [];
  const totalWorkouts = activeWorkouts.length;
  const completedCount = activeWorkouts.filter((w) => w.release_status === "completed").length;
  const releasedCount = activeWorkouts.filter((w) =>
    ["released", "in_progress"].includes(w.release_status)
  ).length;
  const draftCount = activeWorkouts.filter((w) => w.release_status === "draft").length;
  const hasUnreleased = draftCount > 0;
  const isReleasing = actionLoading === `bulk-release-${week.id}`;
  const isDuplicating = actionLoading === `dup-${week.id}`;
  const weekLabel = week.label ? `Semana ${week.week_number} — ${week.label}` : `Semana ${week.week_number}`;
  const dates = weekDates(week.starts_on);
  const today = new Date().toISOString().split("T")[0];

  const workoutsByDate = new Map<string, WorkoutRelease[]>();
  for (const d of dates) workoutsByDate.set(d, []);
  for (const w of week.workouts ?? []) {
    if (["cancelled", "replaced", "archived"].includes(w.release_status)) continue;
    const list = workoutsByDate.get(w.scheduled_date) ?? [];
    list.push(w);
    workoutsByDate.set(w.scheduled_date, list);
  }

  return (
    <div className="overflow-hidden rounded-xl border border-border bg-surface shadow-sm">
      {/* Week header */}
      <div className="flex items-center justify-between border-b border-border bg-bg-secondary px-5 py-3">
        <div className="flex items-center gap-3 min-w-0">
          <span className={`shrink-0 rounded-full px-2.5 py-0.5 text-xs font-semibold ${CYCLE_BG[week.cycle_type] ?? "bg-surface-elevated text-content-muted"}`}>
            {CYCLE_LABEL[week.cycle_type] ?? week.cycle_type}
          </span>
          <div className="min-w-0">
            <h3 className="text-sm font-semibold text-content-primary truncate">{weekLabel}</h3>
            <p className="text-xs text-content-muted">
              {formatDate(week.starts_on)} a {formatDate(week.ends_on)}
              {" · "}
              {totalWorkouts} treino{totalWorkouts !== 1 ? "s" : ""}
              {totalWorkouts > 0 && ` · ${completedCount}/${totalWorkouts} ✓`}
              {releasedCount > 0 && ` · ${releasedCount} liberado${releasedCount !== 1 ? "s" : ""}`}
              {draftCount > 0 && ` · ${draftCount} rascunho${draftCount !== 1 ? "s" : ""}`}
            </p>
          </div>
        </div>

        {/* Week actions */}
        <div className="flex shrink-0 items-center gap-2">
          {hasUnreleased && (
            <button
              onClick={() => onBulkRelease(week.id, weekLabel)}
              disabled={isReleasing}
              className="flex items-center gap-1.5 rounded-lg bg-brand px-3 py-1.5 text-xs font-semibold text-white hover:bg-brand/90 disabled:opacity-60 transition-all"
            >
              {isReleasing ? (
                <svg className="h-3.5 w-3.5 animate-spin" fill="none" viewBox="0 0 24 24">
                  <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4"/>
                  <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"/>
                </svg>
              ) : (
                <svg className="h-3.5 w-3.5" fill="none" viewBox="0 0 24 24" strokeWidth={2.5} stroke="currentColor">
                  <path strokeLinecap="round" strokeLinejoin="round" d="M6 12L3.269 3.126A59.768 59.768 0 0121.485 12 59.77 59.77 0 013.27 20.876L5.999 12zm0 0h7.5" />
                </svg>
              )}
              Liberar semana
            </button>
          )}

          {/* More menu */}
          <div className="relative">
            <button
              onClick={() => setShowMenu((v) => !v)}
              className="rounded-lg border border-border p-1.5 text-content-muted hover:bg-surface-elevated"
            >
              <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" strokeWidth={1.5} stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" d="M12 6.75a.75.75 0 110-1.5.75.75 0 010 1.5zM12 12.75a.75.75 0 110-1.5.75.75 0 010 1.5zM12 18.75a.75.75 0 110-1.5.75.75 0 010 1.5z" />
              </svg>
            </button>

            {showMenu && (
              <>
                <div className="fixed inset-0 z-10" onClick={() => setShowMenu(false)} aria-hidden="true" />
                <div className="absolute right-0 top-full z-20 mt-1 w-52 rounded-xl border border-border bg-surface shadow-lg">
                  <button
                    onClick={() => { setShowMenu(false); onReplicateAsNext(week.id); }}
                    disabled={isDuplicating}
                    className="flex w-full items-center gap-2.5 px-4 py-2.5 text-sm text-content-secondary hover:bg-surface-elevated disabled:opacity-60"
                  >
                    <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" strokeWidth={1.5} stroke="currentColor">
                      <path strokeLinecap="round" strokeLinejoin="round" d="M16.023 9.348h4.992v-.001M2.985 19.644v-4.992m0 0h4.992m-4.993 0 3.181 3.183a8.25 8.25 0 0 0 13.803-3.7M4.031 9.865a8.25 8.25 0 0 1 13.803-3.7l3.181 3.182m0-4.991v4.99" />
                    </svg>
                    Replicar como próxima semana
                  </button>
                  <button
                    onClick={() => { setShowMenu(false); onDuplicate(week.id); }}
                    disabled={isDuplicating}
                    className="flex w-full items-center gap-2.5 px-4 py-2.5 text-sm text-content-secondary hover:bg-surface-elevated disabled:opacity-60"
                  >
                    <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" strokeWidth={1.5} stroke="currentColor">
                      <path strokeLinecap="round" strokeLinejoin="round" d="M15.75 17.25v3.375c0 .621-.504 1.125-1.125 1.125h-9.75a1.125 1.125 0 01-1.125-1.125V7.875c0-.621.504-1.125 1.125-1.125H6.75a9.06 9.06 0 011.5.124m7.5 10.376h3.375c.621 0 1.125-.504 1.125-1.125V11.25c0-4.46-3.243-8.161-7.5-8.876a9.06 9.06 0 00-1.5-.124H9.375c-.621 0-1.125.504-1.125 1.125v3.5m7.5 10.375H9.375a1.125 1.125 0 01-1.125-1.125v-9.25m12 6.625v-1.875a3.375 3.375 0 00-3.375-3.375h-1.5a1.125 1.125 0 01-1.125-1.125v-1.5a3.375 3.375 0 00-3.375-3.375H9.75" />
                    </svg>
                    Duplicar semana (escolher data)
                  </button>
                  <button
                    onClick={() => { setShowMenu(false); onBatchAssign(week); }}
                    className="flex w-full items-center gap-2.5 px-4 py-2.5 text-sm text-content-secondary hover:bg-surface-elevated"
                  >
                    <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" strokeWidth={1.5} stroke="currentColor">
                      <path strokeLinecap="round" strokeLinejoin="round" d="M18 18.72a9.094 9.094 0 003.741-.479 3 3 0 00-4.682-2.72m.94 3.198l.001.031c0 .225-.012.447-.037.666A11.944 11.944 0 0112 21c-2.17 0-4.207-.576-5.963-1.584A6.062 6.062 0 016 18.719m12 0a5.971 5.971 0 00-.941-3.197m0 0A5.995 5.995 0 0012 12.75a5.995 5.995 0 00-5.058 2.772m0 0a3 3 0 00-4.681 2.72 8.986 8.986 0 003.74.477m.94-3.197a5.971 5.971 0 00-.94 3.197M15 6.75a3 3 0 11-6 0 3 3 0 016 0zm6 3a2.25 2.25 0 11-4.5 0 2.25 2.25 0 014.5 0zm-13.5 0a2.25 2.25 0 11-4.5 0 2.25 2.25 0 014.5 0z" />
                    </svg>
                    Distribuir para outros atletas
                  </button>
                </div>
              </>
            )}
          </div>
        </div>
      </div>

      {/* Progress bar */}
      {totalWorkouts > 0 && (
        <div className="h-1 bg-border">
          <div
            className="h-full bg-success transition-all duration-700"
            style={{ width: `${Math.round((completedCount / totalWorkouts) * 100)}%` }}
          />
        </div>
      )}

      {/* 7-column grid */}
      <div className="grid grid-cols-7 divide-x divide-border overflow-x-auto">
        {dates.map((date, i) => {
          const dayWorkouts = (workoutsByDate.get(date) ?? []).sort(
            (a, b) => a.workout_order - b.workout_order,
          );
          const isToday = date === today;
          const isPast = date < today;
          const isPickerTarget = activePicker?.date === date && activePicker?.weekId === week.id;
          const dayLabel = `${DAYS_PT[i]}, ${formatDate(date)}`;

          return (
            <div
              key={date}
              className={`min-h-[160px] p-2 ${isToday ? "bg-brand-soft/20" : ""} ${isPickerTarget ? "ring-2 ring-inset ring-brand" : ""}`}
            >
              {/* Day header */}
              <div className={`mb-2 text-center text-[11px] leading-tight ${isToday ? "font-bold text-brand" : isPast ? "text-content-muted" : "text-content-secondary"}`}>
                <p>{DAYS_PT[i]}</p>
                <p>{formatDate(date)}</p>
              </div>

              {/* Workouts */}
              <div className="space-y-1.5">
                {dayWorkouts.map((workout) => (
                  <WorkoutChip
                    key={workout.id}
                    workout={workout}
                    onClick={() => onWorkoutClick(workout)}
                  />
                ))}

                {/* Add button */}
                <button
                  onClick={() => onCellClick(date, dayLabel)}
                  className={`flex w-full items-center justify-center rounded-lg border border-dashed py-1.5 text-[11px] transition-all ${
                    isPickerTarget
                      ? "border-brand bg-brand-soft text-brand"
                      : "border-border text-content-muted opacity-0 hover:opacity-100 hover:border-brand hover:text-brand hover:bg-brand-soft"
                  } ${dayWorkouts.length === 0 ? "opacity-50 hover:opacity-100" : ""}`}
                >
                  + treino
                </button>
              </div>
            </div>
          );
        })}
      </div>

      {/* Week notes */}
      {week.coach_notes && (
        <div className="border-t border-border px-5 py-2 text-xs text-content-secondary">
          <span className="font-medium">📝 Notas:</span> {week.coach_notes}
        </div>
      )}
    </div>
  );
}

// ─── WorkoutChip ──────────────────────────────────────────────────────────────

function WorkoutChip({ workout, onClick }: { workout: WorkoutRelease; onClick: () => void }) {
  const completed = workout.completed?.[0];
  const isCompleted = workout.release_status === "completed";
  const emoji = TYPE_EMOJI[workout.workout_type] ?? "🏃";
  const name = workout.workout_label || workout.template?.name || "Treino";

  return (
    <button
      onClick={onClick}
      className={`group relative w-full rounded-lg border px-2 py-1.5 text-left text-[11px] transition-all hover:shadow-sm hover:scale-[1.02] active:scale-100 ${STATUS_BG[workout.release_status]}`}
    >
      {/* Updated badge */}
      {workout.content_version > 1 && workout.release_status === "released" && (
        <span className="absolute -right-1 -top-1 flex h-4 w-4 items-center justify-center rounded-full bg-warning text-[9px] font-bold text-white shadow-sm">
          !
        </span>
      )}

      <div className="flex items-start gap-1.5">
        <span className="text-[13px] leading-none mt-0.5">{emoji}</span>
        <div className="min-w-0">
          <p className="truncate font-medium leading-tight">{name}</p>
          <p className="opacity-70 leading-tight mt-0.5">
            {STATUS_LABEL[workout.release_status as ReleaseStatus]}
          </p>
          {isCompleted && completed?.actual_distance_m != null && (
            <p className="font-semibold leading-tight mt-0.5">
              ✓ {(completed.actual_distance_m / 1000).toFixed(1)} km
            </p>
          )}
          {isCompleted && completed?.actual_duration_s != null && !completed?.actual_distance_m && (
            <p className="font-semibold leading-tight mt-0.5">
              ✓ {formatDuration(completed.actual_duration_s)}
            </p>
          )}
        </div>
      </div>
    </button>
  );
}
