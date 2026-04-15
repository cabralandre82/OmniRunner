"use client";

import { useState } from "react";
import {
  WorkoutRelease,
  ReleaseBlock,
  STATUS_LABEL,
  STATUS_BG,
  WORKOUT_TYPE_LABEL,
  formatDate,
  formatDuration,
  formatDistanceM,
  formatPace,
} from "./types";
import { BlockEditor } from "./block-editor";

interface WorkoutActionDrawerProps {
  workout: WorkoutRelease | null;
  onClose: () => void;
  onRelease: (id: string) => Promise<void>;
  onCancel: (id: string) => Promise<void>;
  onCopyToDay: (id: string, targetDate: string) => Promise<void>;
  onUpdateLabel: (id: string, label: string, notes: string) => Promise<void>;
  onUpdateBlocks: (id: string, blocks: ReleaseBlock[]) => Promise<void>;
  onSchedule: (id: string, scheduledAt: string) => Promise<void>;
}

export function WorkoutActionDrawer({
  workout,
  onClose,
  onRelease,
  onCancel,
  onCopyToDay,
  onUpdateLabel,
  onUpdateBlocks,
  onSchedule,
}: WorkoutActionDrawerProps) {
  const open = workout !== null;
  const [tab, setTab] = useState<"info" | "edit" | "blocks" | "copy" | "schedule">("info");
  const [actionLoading, setActionLoading] = useState<string | null>(null);

  // Edit state
  const [editLabel, setEditLabel] = useState(workout?.workout_label ?? "");
  const [editNotes, setEditNotes] = useState(workout?.coach_notes ?? "");

  // Blocks state — initialised from content_snapshot
  const [editBlocks, setEditBlocks] = useState<ReleaseBlock[]>(
    workout?.content_snapshot?.blocks ?? [],
  );

  // Copy state
  const [copyDate, setCopyDate] = useState("");

  // Schedule state
  const [scheduleDate, setScheduleDate] = useState("");
  const [scheduleTime, setScheduleTime] = useState("06:00");

  // Reset when workout changes
  if (workout && editLabel !== (workout.workout_label ?? "") && tab === "info") {
    setEditLabel(workout.workout_label ?? "");
    setEditNotes(workout.coach_notes ?? "");
    setEditBlocks(workout.content_snapshot?.blocks ?? []);
  }

  if (!workout) return null;

  const completed = workout.completed?.[0];
  const feedback = workout.feedback?.[0];
  const isActionable = ["draft", "scheduled"].includes(workout.release_status);
  const canCancel = !["cancelled", "replaced", "archived"].includes(workout.release_status);

  async function handleAction(key: string, fn: () => Promise<void>) {
    setActionLoading(key);
    try {
      await fn();
      onClose();
    } catch {
      // error handled by parent
    } finally {
      setActionLoading(null);
    }
  }

  const tabClass = (t: typeof tab) =>
    `px-3 py-1.5 text-xs font-medium rounded-md transition-colors ${
      tab === t
        ? "bg-brand text-white"
        : "text-content-secondary hover:bg-surface-elevated"
    }`;

  return (
    <>
      {/* Backdrop */}
      {open && (
        <div
          className="fixed inset-0 z-40 bg-overlay/60"
          onClick={onClose}
          aria-hidden="true"
        />
      )}

      {/* Bottom drawer */}
      <div
        className={`fixed inset-x-0 bottom-0 z-50 flex flex-col rounded-t-2xl bg-surface shadow-xl transition-transform duration-300 ${
          open ? "translate-y-0" : "translate-y-full"
        }`}
        style={{ maxHeight: "85vh" }}
      >
        {/* Drag handle */}
        <div className="flex justify-center pt-3 pb-1">
          <div className="h-1 w-10 rounded-full bg-border" />
        </div>

        {/* Header */}
        <div className="flex items-center justify-between px-5 pb-3 pt-1">
          <div className="min-w-0">
            <h3 className="truncate text-base font-semibold text-content-primary">
              {workout.workout_label || workout.template?.name || "Treino"}
            </h3>
            <div className="mt-0.5 flex items-center gap-2">
              <span className={`rounded-full px-2 py-0.5 text-[11px] font-semibold border ${STATUS_BG[workout.release_status]}`}>
                {STATUS_LABEL[workout.release_status]}
              </span>
              <span className="text-xs text-content-muted">
                {WORKOUT_TYPE_LABEL[workout.workout_type] ?? workout.workout_type}
                {" · "}
                {formatDate(workout.scheduled_date)}
              </span>
            </div>
          </div>
          <button
            onClick={onClose}
            className="ml-3 shrink-0 rounded-lg p-1.5 text-content-muted hover:bg-surface-elevated"
          >
            <svg className="h-5 w-5" fill="none" viewBox="0 0 24 24" strokeWidth={2} stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        {/* Tabs */}
        <div className="flex gap-1 border-b border-border px-5 pb-3">
          <button onClick={() => setTab("info")} className={tabClass("info")}>Detalhes</button>
          <button onClick={() => setTab("edit")} className={tabClass("edit")}>Editar</button>
          <button onClick={() => setTab("blocks")} className={tabClass("blocks")}>🧩 Blocos</button>
          <button onClick={() => setTab("copy")} className={tabClass("copy")}>Copiar</button>
          {isActionable && (
            <button onClick={() => setTab("schedule")} className={tabClass("schedule")}>Agendar</button>
          )}
        </div>

        {/* Tab content */}
        <div className="flex-1 overflow-y-auto px-5 py-4 space-y-4">

          {/* INFO TAB */}
          {tab === "info" && (
            <>
              {/* Coach notes */}
              {workout.coach_notes && (
                <div className="rounded-lg border border-brand/20 bg-brand-soft p-3">
                  <p className="text-[11px] font-semibold uppercase tracking-wide text-brand">Orientações do treinador</p>
                  <p className="mt-1 text-sm text-content-primary">{workout.coach_notes}</p>
                </div>
              )}

              {/* Video link */}
              {workout.video_url && (
                <a
                  href={workout.video_url}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="flex items-center gap-2 rounded-lg border border-border bg-surface-elevated px-3 py-2.5 text-sm text-content-secondary hover:bg-brand-soft hover:text-brand transition-colors"
                >
                  <svg className="h-4 w-4 shrink-0 text-error" fill="currentColor" viewBox="0 0 24 24">
                    <path d="M23.498 6.186a3.016 3.016 0 0 0-2.122-2.136C19.505 3.545 12 3.545 12 3.545s-7.505 0-9.377.505A3.017 3.017 0 0 0 .502 6.186C0 8.07 0 12 0 12s0 3.93.502 5.814a3.016 3.016 0 0 0 2.122 2.136c1.871.505 9.376.505 9.376.505s7.505 0 9.377-.505a3.015 3.015 0 0 0 2.122-2.136C24 15.93 24 12 24 12s0-3.93-.502-5.814zM9.545 15.568V8.432L15.818 12l-6.273 3.568z" />
                  </svg>
                  <span className="truncate">Ver vídeo explicativo</span>
                  <svg className="h-3.5 w-3.5 shrink-0 text-content-muted" fill="none" viewBox="0 0 24 24" strokeWidth={2} stroke="currentColor">
                    <path strokeLinecap="round" strokeLinejoin="round" d="M13.5 6H5.25A2.25 2.25 0 0 0 3 8.25v10.5A2.25 2.25 0 0 0 5.25 21h10.5A2.25 2.25 0 0 0 18 18.75V10.5m-10.5 6L21 3m0 0h-5.25M21 3v5.25" />
                  </svg>
                </a>
              )}

              {/* Template info */}
              {workout.template && (
                <div className="rounded-lg border border-border bg-surface-elevated p-3">
                  <p className="text-[11px] font-semibold uppercase tracking-wide text-content-muted">Template base</p>
                  <p className="mt-1 text-sm font-medium text-content-primary">{workout.template.name}</p>
                  {workout.template.description && (
                    <p className="text-xs text-content-secondary">{workout.template.description}</p>
                  )}
                </div>
              )}

              {/* Blocks preview */}
              {(workout.content_snapshot?.blocks?.length ?? 0) > 0 && (
                <div className="rounded-lg border border-border bg-surface-elevated p-3">
                  <p className="mb-2 text-[11px] font-semibold uppercase tracking-wide text-content-muted">Estrutura do treino</p>
                  <BlockEditor blocks={workout.content_snapshot!.blocks} onChange={() => {}} readOnly />
                </div>
              )}

              {/* Version badge */}
              {workout.content_version > 1 && (
                <div className="rounded-lg border border-warning/30 bg-warning-soft p-3 text-sm text-warning">
                  ⚠️ Treino foi atualizado após liberação (versão {workout.content_version}).
                  O atleta verá a versão mais recente.
                </div>
              )}

              {/* Completed metrics */}
              {completed && (
                <div className="rounded-lg border border-success/20 bg-success-soft p-3">
                  <p className="text-[11px] font-semibold uppercase tracking-wide text-success">Realizado</p>
                  <div className="mt-2 grid grid-cols-3 gap-2">
                    {completed.actual_distance_m != null && (
                      <div className="text-center">
                        <p className="text-base font-bold text-content-primary">
                          {formatDistanceM(completed.actual_distance_m)}
                        </p>
                        <p className="text-[10px] text-content-muted">Distância</p>
                      </div>
                    )}
                    {completed.actual_duration_s != null && (
                      <div className="text-center">
                        <p className="text-base font-bold text-content-primary">
                          {formatDuration(completed.actual_duration_s)}
                        </p>
                        <p className="text-[10px] text-content-muted">Duração</p>
                      </div>
                    )}
                    {completed.perceived_effort != null && (
                      <div className="text-center">
                        <p className="text-base font-bold text-content-primary">
                          RPE {completed.perceived_effort}
                        </p>
                        <p className="text-[10px] text-content-muted">Esforço</p>
                      </div>
                    )}
                  </div>
                </div>
              )}

              {/* Feedback */}
              {feedback?.how_was_it && (
                <div className="rounded-lg border border-border bg-surface-elevated p-3">
                  <p className="text-[11px] font-semibold uppercase tracking-wide text-content-muted">Feedback do atleta</p>
                  {feedback.rating != null && (
                    <p className="mt-1 text-sm text-warning">
                      {"★".repeat(feedback.rating)}{"☆".repeat(5 - feedback.rating)}
                    </p>
                  )}
                  <p className="mt-1 text-sm italic text-content-secondary">{feedback.how_was_it}</p>
                </div>
              )}

              {/* Quick actions */}
              <div className="space-y-2">
                {isActionable && (
                  <button
                    onClick={() => handleAction("release", () => onRelease(workout.id))}
                    disabled={actionLoading !== null}
                    className="flex w-full items-center justify-center gap-2 rounded-lg bg-brand py-2.5 text-sm font-semibold text-white hover:bg-brand/90 disabled:opacity-60"
                  >
                    {actionLoading === "release" ? "Liberando..." : "🚀 Liberar para o atleta"}
                  </button>
                )}
                {canCancel && (
                  <button
                    onClick={() => {
                      if (!confirm("Cancelar este treino?")) return;
                      handleAction("cancel", () => onCancel(workout.id));
                    }}
                    disabled={actionLoading !== null}
                    className="flex w-full items-center justify-center gap-2 rounded-lg border border-error/30 py-2.5 text-sm font-medium text-error hover:bg-error-soft disabled:opacity-60"
                  >
                    {actionLoading === "cancel" ? "Cancelando..." : "Cancelar treino"}
                  </button>
                )}
              </div>
            </>
          )}

          {/* EDIT TAB */}
          {tab === "edit" && (
            <div className="space-y-4">
              <div>
                <label className="mb-1.5 block text-xs font-medium text-content-secondary">
                  Nome do treino (personalizado)
                </label>
                <input
                  type="text"
                  value={editLabel}
                  onChange={(e) => setEditLabel(e.target.value)}
                  placeholder={workout.template?.name ?? "ex: Tiro de 1km × 5"}
                  className="w-full rounded-lg border border-border bg-bg-secondary px-3 py-2 text-sm text-content-primary placeholder:text-content-muted focus:border-brand focus:outline-none"
                />
              </div>
              <div>
                <label className="mb-1.5 block text-xs font-medium text-content-secondary">
                  Observações para o atleta
                </label>
                <textarea
                  value={editNotes}
                  onChange={(e) => setEditNotes(e.target.value)}
                  rows={4}
                  placeholder="ex: Mantenha o cadência alta nos intervalos. Beba água antes."
                  className="w-full resize-none rounded-lg border border-border bg-bg-secondary px-3 py-2 text-sm text-content-primary placeholder:text-content-muted focus:border-brand focus:outline-none"
                />
              </div>
              <button
                onClick={() => handleAction("update", () => onUpdateLabel(workout.id, editLabel, editNotes))}
                disabled={actionLoading !== null}
                className="w-full rounded-lg bg-brand py-2.5 text-sm font-semibold text-white hover:bg-brand/90 disabled:opacity-60"
              >
                {actionLoading === "update" ? "Salvando..." : "Salvar alterações"}
              </button>
            </div>
          )}

          {/* BLOCKS TAB */}
          {tab === "blocks" && (
            <div className="space-y-3">
              <p className="text-xs text-content-muted">
                Personalize os blocos deste treino para este atleta. Não altera o template original.
              </p>
              <BlockEditor blocks={editBlocks} onChange={setEditBlocks} />
              <button
                onClick={() => handleAction("blocks", () => onUpdateBlocks(workout.id, editBlocks))}
                disabled={actionLoading !== null}
                className="w-full rounded-lg bg-brand py-2.5 text-sm font-semibold text-white hover:bg-brand/90 disabled:opacity-60"
              >
                {actionLoading === "blocks" ? "Salvando..." : "Salvar blocos personalizados"}
              </button>
            </div>
          )}

          {/* COPY TAB */}
          {tab === "copy" && (
            <div className="space-y-4">
              <p className="text-sm text-content-secondary">
                Copia este treino para outro dia (do mesmo atleta ou de outro).
              </p>
              <div>
                <label className="mb-1.5 block text-xs font-medium text-content-secondary">
                  Data de destino
                </label>
                <input
                  type="date"
                  value={copyDate}
                  onChange={(e) => setCopyDate(e.target.value)}
                  className="w-full rounded-lg border border-border bg-bg-secondary px-3 py-2 text-sm text-content-primary focus:border-brand focus:outline-none"
                />
              </div>
              <button
                onClick={() => {
                  if (!copyDate) return;
                  handleAction("copy", () => onCopyToDay(workout.id, copyDate));
                }}
                disabled={!copyDate || actionLoading !== null}
                className="w-full rounded-lg bg-brand py-2.5 text-sm font-semibold text-white hover:bg-brand/90 disabled:opacity-60"
              >
                {actionLoading === "copy" ? "Copiando..." : "Copiar para este dia"}
              </button>
            </div>
          )}

          {/* SCHEDULE TAB */}
          {tab === "schedule" && isActionable && (
            <div className="space-y-4">
              <p className="text-sm text-content-secondary">
                O treino ficará oculto até a data/hora agendada, quando será liberado automaticamente.
              </p>
              <div>
                <label className="mb-1.5 block text-xs font-medium text-content-secondary">
                  Data de liberação
                </label>
                <input
                  type="date"
                  value={scheduleDate}
                  onChange={(e) => setScheduleDate(e.target.value)}
                  className="w-full rounded-lg border border-border bg-bg-secondary px-3 py-2 text-sm text-content-primary focus:border-brand focus:outline-none"
                />
              </div>
              <div>
                <label className="mb-1.5 block text-xs font-medium text-content-secondary">
                  Horário (UTC-3 Brasília)
                </label>
                <input
                  type="time"
                  value={scheduleTime}
                  onChange={(e) => setScheduleTime(e.target.value)}
                  className="w-full rounded-lg border border-border bg-bg-secondary px-3 py-2 text-sm text-content-primary focus:border-brand focus:outline-none"
                />
              </div>
              <button
                onClick={() => {
                  if (!scheduleDate) return;
                  // Combine date + time, assume Brasília = UTC-3
                  const iso = `${scheduleDate}T${scheduleTime}:00-03:00`;
                  handleAction("schedule", () => onSchedule(workout.id, iso));
                }}
                disabled={!scheduleDate || actionLoading !== null}
                className="w-full rounded-lg bg-warning py-2.5 text-sm font-semibold text-white hover:brightness-110 disabled:opacity-60"
              >
                {actionLoading === "schedule" ? "Agendando..." : "⏰ Agendar liberação"}
              </button>
            </div>
          )}
        </div>
      </div>
    </>
  );
}
