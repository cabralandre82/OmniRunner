"use client";

import { useEffect, useState, useCallback } from "react";
import { BlockEditor } from "./block-editor";
import type { ReleaseBlock } from "./types";

// ── Types ─────────────────────────────────────────────────────────────────────

const DAYS_PT = ["Seg", "Ter", "Qua", "Qui", "Sex", "Sáb", "Dom"];

const TYPE_EMOJI: Record<string, string> = {
  continuous: "🏃", interval: "⚡", regenerative: "🌱", long_run: "🛤️",
  strength: "💪", technique: "🎯", test: "⏱️", free: "🆓", race: "🏆", brick: "🔁",
};

const WORKOUT_TYPES = [
  { value: "continuous",   label: "Corrida Contínua" },
  { value: "interval",     label: "Intervalado" },
  { value: "regenerative", label: "Regenerativo" },
  { value: "long_run",     label: "Longão" },
  { value: "strength",     label: "Força" },
  { value: "technique",    label: "Técnica" },
  { value: "test",         label: "Teste" },
  { value: "free",         label: "Livre" },
  { value: "race",         label: "Prova" },
  { value: "brick",        label: "Brick" },
];

interface TemplateWorkout {
  id: string;
  day_of_week: number;
  workout_order: number;
  workout_type: string;
  workout_label: string;
  description: string | null;
  coach_notes: string | null;
  blocks: ReleaseBlock[];
}

interface WeekTemplate {
  id: string;
  name: string;
  description: string | null;
  workout_count: number;
  days_with_workouts: number[];
  workouts: TemplateWorkout[];
}

// ── Apply target (passed from weekly-planner when user picks a week) ──────────

export interface ApplyTarget {
  planWeekId:   string;
  athleteId:    string;
  weekStart:    string;   // YYYY-MM-DD (Monday)
  weekLabel:    string;
  athleteName:  string;
}

// ── Override state for the apply flow ────────────────────────────────────────

interface WorkoutOverride {
  workout_label?: string;
  workout_type?:  string;
  coach_notes?:   string;
  blocks?:        ReleaseBlock[];
  remove?:        boolean;
}

// ── WeekTemplateLibrary (main export) ────────────────────────────────────────

export interface WeekTemplateLibraryProps {
  open:          boolean;
  groupId:       string;
  applyTarget?:  ApplyTarget | null;
  onClose:       () => void;
  onApplied?:    () => void;
}

type View = "library" | "new" | "edit" | "apply";

export function WeekTemplateLibrary({
  open,
  groupId: _groupId,
  applyTarget,
  onClose,
  onApplied,
}: WeekTemplateLibraryProps) {
  const [view, setView]               = useState<View>("library");
  const [templates, setTemplates]     = useState<WeekTemplate[]>([]);
  const [loading, setLoading]         = useState(false);
  const [editTarget, setEditTarget]   = useState<WeekTemplate | null>(null);
  const [applyTemplate, setApplyTemplate] = useState<WeekTemplate | null>(null);

  // ── Load templates ──────────────────────────────────────────────────────────

  const loadTemplates = useCallback(async () => {
    setLoading(true);
    try {
      const res  = await fetch("/api/training-plan/week-templates");
      const json = await res.json();
      if (json.ok) setTemplates(json.data ?? []);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    if (!open) return;
    setView(applyTarget ? "library" : "library");
    loadTemplates();
  }, [open, loadTemplates, applyTarget]);

  // Reset view on close
  useEffect(() => {
    if (!open) { setView("library"); setEditTarget(null); setApplyTemplate(null); }
  }, [open]);

  if (!open) return null;

  // ── Delete ──────────────────────────────────────────────────────────────────

  async function handleDelete(id: string) {
    if (!confirm("Excluir este modelo da biblioteca?")) return;
    await fetch(`/api/training-plan/week-templates/${id}`, { method: "DELETE" });
    setTemplates((prev) => prev.filter((t) => t.id !== id));
  }

  // ── Render ──────────────────────────────────────────────────────────────────

  return (
    <>
      <div className="fixed inset-0 z-50 bg-overlay/60" onClick={onClose} aria-hidden="true" />
      <div
        className="fixed inset-0 z-50 flex items-end justify-center sm:items-center p-4"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex w-full max-w-2xl flex-col rounded-2xl bg-surface shadow-2xl"
          style={{ maxHeight: view === "new" || view === "edit" ? "96vh" : "85vh" }}>

          {/* ── Library view ──────────────────────────────────────────────── */}
          {view === "library" && (
            <LibraryView
              templates={templates}
              loading={loading}
              applyTarget={applyTarget ?? null}
              onNew={() => { setEditTarget(null); setView("new"); }}
              onEdit={(t)  => { setEditTarget(t); setView("edit"); }}
              onDelete={handleDelete}
              onApply={(t) => { setApplyTemplate(t); setView("apply"); }}
              onClose={onClose}
            />
          )}

          {/* ── New/Edit template editor ───────────────────────────────────── */}
          {(view === "new" || view === "edit") && (
            <TemplateEditor
              initial={editTarget}
              onSaved={(updated) => {
                setTemplates((prev) =>
                  editTarget
                    ? prev.map((t) => (t.id === updated.id ? updated : t))
                    : [updated, ...prev],
                );
                setView("library");
              }}
              onBack={() => setView("library")}
            />
          )}

          {/* ── Apply flow ────────────────────────────────────────────────── */}
          {view === "apply" && applyTemplate && applyTarget && (
            <ApplyView
              template={applyTemplate}
              target={applyTarget}
              onBack={() => setView("library")}
              onApplied={() => {
                setView("library");
                onClose();
                onApplied?.();
              }}
            />
          )}
        </div>
      </div>
    </>
  );
}

// ── LibraryView ───────────────────────────────────────────────────────────────

function LibraryView({
  templates, loading, applyTarget,
  onNew, onEdit, onDelete, onApply, onClose,
}: {
  templates:   WeekTemplate[];
  loading:     boolean;
  applyTarget: ApplyTarget | null;
  onNew:       () => void;
  onEdit:      (t: WeekTemplate) => void;
  onDelete:    (id: string) => void;
  onApply:     (t: WeekTemplate) => void;
  onClose:     () => void;
}) {
  const [search, setSearch] = useState("");
  const filtered = templates.filter((t) =>
    !search.trim() || t.name.toLowerCase().includes(search.toLowerCase()),
  );

  return (
    <>
      {/* Header */}
      <div className="flex items-center justify-between border-b border-border px-6 py-4 shrink-0">
        <div>
          <h2 className="text-base font-semibold text-content-primary">📚 Biblioteca de Modelos de Semana</h2>
          <p className="mt-0.5 text-xs text-content-muted">
            {applyTarget
              ? `Escolha um modelo para aplicar na semana de ${applyTarget.athleteName}`
              : "Crie e gerencie modelos de semana reutilizáveis para o seu grupo."}
          </p>
        </div>
        <div className="flex items-center gap-2">
          <button
            onClick={onNew}
            className="flex items-center gap-1.5 rounded-lg bg-brand px-3 py-1.5 text-xs font-semibold text-white hover:bg-brand/90"
          >
            <svg className="h-3.5 w-3.5" fill="none" viewBox="0 0 24 24" strokeWidth={2.5} stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" d="M12 4.5v15m7.5-7.5h-15" />
            </svg>
            Novo modelo
          </button>
          <button onClick={onClose} className="rounded-lg p-1.5 text-content-muted hover:bg-surface-elevated">
            <svg className="h-5 w-5" fill="none" viewBox="0 0 24 24" strokeWidth={2} stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>
      </div>

      {/* Search */}
      <div className="px-6 pt-4 pb-2 shrink-0">
        <input
          type="text"
          placeholder="Buscar modelo..."
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          className="w-full rounded-lg border border-border bg-bg-secondary px-3 py-2 text-sm text-content-primary placeholder:text-content-muted focus:border-brand focus:outline-none"
        />
      </div>

      {/* List */}
      <div className="flex-1 overflow-y-auto px-6 pb-6 space-y-2">
        {loading ? (
          <div className="py-10 text-center text-sm text-content-muted">Carregando modelos...</div>
        ) : filtered.length === 0 ? (
          <div className="py-10 text-center">
            <p className="text-sm text-content-muted">
              {search ? "Nenhum modelo encontrado." : "Nenhum modelo criado ainda."}
            </p>
            {!search && (
              <button onClick={onNew} className="mt-3 rounded-lg bg-brand px-4 py-2 text-xs font-semibold text-white hover:bg-brand/90">
                Criar primeiro modelo
              </button>
            )}
          </div>
        ) : (
          filtered.map((t) => (
            <TemplateCard
              key={t.id}
              template={t}
              showApply={!!applyTarget}
              onEdit={() => onEdit(t)}
              onDelete={() => onDelete(t.id)}
              onApply={() => onApply(t)}
            />
          ))
        )}
      </div>
    </>
  );
}

// ── TemplateCard ──────────────────────────────────────────────────────────────

function TemplateCard({
  template, showApply, onEdit, onDelete, onApply,
}: {
  template:  WeekTemplate;
  showApply: boolean;
  onEdit:    () => void;
  onDelete:  () => void;
  onApply:   () => void;
}) {
  const [expanded, setExpanded] = useState(false);

  return (
    <div className="rounded-xl border border-border bg-surface-elevated overflow-hidden">
      <div className="flex items-center gap-3 px-4 py-3">
        <button onClick={() => setExpanded((e) => !e)} className="flex flex-1 items-start gap-2 text-left min-w-0">
          <div className="flex-1 min-w-0">
            <p className="truncate text-sm font-semibold text-content-primary">{template.name}</p>
            <p className="mt-0.5 text-[11px] text-content-muted">
              {template.workout_count} treino{template.workout_count !== 1 ? "s" : ""}
              {template.days_with_workouts.length > 0 && (
                <> &middot; {template.days_with_workouts.map((d) => DAYS_PT[d]).join(", ")}</>
              )}
            </p>
          </div>
          <svg
            className={`h-4 w-4 shrink-0 text-content-muted mt-0.5 transition-transform ${expanded ? "rotate-180" : ""}`}
            fill="none" viewBox="0 0 24 24" strokeWidth={2} stroke="currentColor"
          >
            <path strokeLinecap="round" strokeLinejoin="round" d="M19 9l-7 7-7-7" />
          </svg>
        </button>

        <div className="flex items-center gap-1 shrink-0">
          <button
            onClick={onEdit}
            className="rounded-lg p-1.5 text-content-muted hover:bg-surface hover:text-brand transition-colors"
            title="Editar modelo"
          >
            <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" strokeWidth={1.5} stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" d="M16.862 4.487l1.687-1.688a1.875 1.875 0 112.652 2.652L10.582 16.07a4.5 4.5 0 01-1.897 1.13L6 18l.8-2.685a4.5 4.5 0 011.13-1.897l8.932-8.931zm0 0L19.5 7.125" />
            </svg>
          </button>
          <button
            onClick={onDelete}
            className="rounded-lg p-1.5 text-content-muted hover:bg-error-soft hover:text-error transition-colors"
            title="Excluir modelo"
          >
            <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" strokeWidth={1.5} stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" d="M14.74 9l-.346 9m-4.788 0L9.26 9m9.968-3.21c.342.052.682.107 1.022.166m-1.022-.165L18.16 19.673a2.25 2.25 0 01-2.244 2.077H8.084a2.25 2.25 0 01-2.244-2.077L4.772 5.79m14.456 0a48.108 48.108 0 00-3.478-.397m-12 .562c.34-.059.68-.114 1.022-.165m0 0a48.11 48.11 0 013.478-.397m7.5 0v-.916c0-1.18-.91-2.164-2.09-2.201a51.964 51.964 0 00-3.32 0c-1.18.037-2.09 1.022-2.09 2.201v.916" />
            </svg>
          </button>
          {showApply && (
            <button
              onClick={onApply}
              className="ml-1 rounded-lg bg-brand px-3 py-1.5 text-xs font-semibold text-white hover:bg-brand/90"
            >
              Aplicar
            </button>
          )}
        </div>
      </div>

      {/* Day grid preview */}
      {expanded && (
        <div className="border-t border-border px-4 pb-3 pt-2">
          <div className="grid grid-cols-7 gap-1">
            {DAYS_PT.map((day, i) => {
              const dayWorkouts = template.workouts.filter((w) => w.day_of_week === i);
              return (
                <div key={day} className="text-center">
                  <p className="text-[10px] text-content-muted mb-0.5">{day}</p>
                  {dayWorkouts.length === 0 ? (
                    <div className="h-6 rounded-sm bg-surface flex items-center justify-center text-[10px] text-content-muted">—</div>
                  ) : (
                    dayWorkouts.map((w) => (
                      <div
                        key={w.id}
                        className="mb-0.5 rounded-sm bg-brand px-0.5 py-0.5 text-[9px] leading-tight text-white truncate"
                        title={w.workout_label}
                      >
                        {TYPE_EMOJI[w.workout_type] ?? "🏃"} {w.workout_label}
                      </div>
                    ))
                  )}
                </div>
              );
            })}
          </div>
        </div>
      )}
    </div>
  );
}

// ── TemplateEditor ────────────────────────────────────────────────────────────

function TemplateEditor({
  initial,
  onSaved,
  onBack,
}: {
  initial:  WeekTemplate | null;
  onSaved:  (t: WeekTemplate) => void;
  onBack:   () => void;
}) {
  const [name, setName]               = useState(initial?.name ?? "");
  const [description, setDescription] = useState(initial?.description ?? "");
  const [workouts, setWorkouts]       = useState<TemplateWorkout[]>(initial?.workouts ?? []);
  const [saving, setSaving]           = useState(false);
  const [error, setError]             = useState("");
  const [editingWorkout, setEditingWorkout] = useState<{
    id: string | null;   // null = new
    dayOfWeek: number;
    data: Partial<TemplateWorkout>;
  } | null>(null);

  const isNew = !initial;

  // ── Save template header ────────────────────────────────────────────────────

  async function handleSave() {
    if (!name.trim()) { setError("Nome obrigatório"); return; }
    setSaving(true);
    setError("");
    try {
      let templateId = initial?.id;

      if (isNew) {
        const res  = await fetch("/api/training-plan/week-templates", {
          method:  "POST",
          headers: { "Content-Type": "application/json" },
          body:    JSON.stringify({ name: name.trim(), description: description.trim() || null }),
        });
        const json = await res.json();
        if (!json.ok) throw new Error(json.error?.message ?? "Erro ao criar modelo");
        templateId = json.data.id;

        // Create all workouts
        for (const w of workouts) {
          await fetch(`/api/training-plan/week-templates/${templateId}/workouts`, {
            method:  "POST",
            headers: { "Content-Type": "application/json" },
            body:    JSON.stringify({
              day_of_week:   w.day_of_week,
              workout_order: w.workout_order,
              workout_type:  w.workout_type,
              workout_label: w.workout_label,
              description:   w.description,
              coach_notes:   w.coach_notes,
              blocks:        w.blocks,
            }),
          });
        }
      } else {
        // Update name/description
        await fetch(`/api/training-plan/week-templates/${templateId}`, {
          method:  "PATCH",
          headers: { "Content-Type": "application/json" },
          body:    JSON.stringify({ name: name.trim(), description: description.trim() || null }),
        });
        // Workout changes are saved inline as they happen
      }

      onSaved({
        id:                 templateId!,
        name:               name.trim(),
        description:        description.trim() || null,
        workout_count:      workouts.length,
        days_with_workouts: Array.from(new Set(workouts.map((w) => w.day_of_week))).sort((a, b) => a - b),
        workouts,
      });
    } catch (e) {
      setError(e instanceof Error ? e.message : "Erro ao salvar");
    } finally {
      setSaving(false);
    }
  }

  // ── Add / update workout in state (and DB if editing existing template) ─────

  async function saveWorkout(data: Omit<TemplateWorkout, "id">, existingId?: string) {
    if (!isNew && initial?.id) {
      if (existingId) {
        await fetch(`/api/training-plan/week-templates/${initial.id}/workouts/${existingId}`, {
          method:  "PATCH",
          headers: { "Content-Type": "application/json" },
          body:    JSON.stringify(data),
        });
        setWorkouts((prev) => prev.map((w) => w.id === existingId ? { ...w, ...data } : w));
      } else {
        const res  = await fetch(`/api/training-plan/week-templates/${initial.id}/workouts`, {
          method:  "POST",
          headers: { "Content-Type": "application/json" },
          body:    JSON.stringify(data),
        });
        const json = await res.json();
        if (json.ok) setWorkouts((prev) => [...prev, json.data]);
      }
    } else {
      if (existingId) {
        setWorkouts((prev) => prev.map((w) => w.id === existingId ? { ...w, ...data } : w));
      } else {
        setWorkouts((prev) => [...prev, { ...data, id: `local-${Date.now()}` }]);
      }
    }
  }

  async function deleteWorkout(id: string) {
    if (!isNew && initial?.id) {
      await fetch(`/api/training-plan/week-templates/${initial.id}/workouts/${id}`, { method: "DELETE" });
    }
    setWorkouts((prev) => prev.filter((w) => w.id !== id));
  }

  // ── Render ──────────────────────────────────────────────────────────────────

  return (
    <>
      {/* Header */}
      <div className="flex items-center gap-3 border-b border-border px-6 py-4 shrink-0">
        <button onClick={onBack} className="rounded-lg p-1 text-content-muted hover:bg-surface-elevated">
          <svg className="h-5 w-5" fill="none" viewBox="0 0 24 24" strokeWidth={2} stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" d="M15 19l-7-7 7-7" />
          </svg>
        </button>
        <div className="flex-1 min-w-0">
          <h2 className="text-base font-semibold text-content-primary">
            {isNew ? "Novo Modelo de Semana" : `Editando: ${initial?.name}`}
          </h2>
          <p className="text-xs text-content-muted">Configure os treinos por dia da semana</p>
        </div>
        <button
          onClick={handleSave}
          disabled={!name.trim() || saving}
          className="rounded-lg bg-brand px-4 py-2 text-sm font-semibold text-white hover:bg-brand/90 disabled:opacity-60"
        >
          {saving ? "Salvando..." : isNew ? "Criar modelo" : "Salvar"}
        </button>
      </div>

      <div className="flex-1 overflow-y-auto px-6 py-4 space-y-5">
        {/* Name & description */}
        <div className="space-y-3">
          <div>
            <label className="block text-xs font-medium text-content-secondary mb-1">Nome do modelo *</label>
            <input
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="Ex: Semana Base Intermediário"
              maxLength={80}
              className="w-full rounded-lg border border-border bg-bg-secondary px-3 py-2 text-sm text-content-primary focus:border-brand focus:outline-none"
            />
          </div>
          <div>
            <label className="block text-xs font-medium text-content-secondary mb-1">Descrição (opcional)</label>
            <input
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              placeholder="Ex: Semana com foco em volume aeróbio, indicada para iniciantes"
              maxLength={200}
              className="w-full rounded-lg border border-border bg-bg-secondary px-3 py-2 text-sm text-content-primary focus:border-brand focus:outline-none"
            />
          </div>
          {error && <p className="text-xs text-error">{error}</p>}
        </div>

        {/* Day grid */}
        <div>
          <p className="text-xs font-medium text-content-secondary mb-3">Treinos por dia da semana</p>
          <div className="space-y-2">
            {DAYS_PT.map((day, dayIdx) => {
              const dayWorkouts = workouts
                .filter((w) => w.day_of_week === dayIdx)
                .sort((a, b) => a.workout_order - b.workout_order);
              return (
                <div key={day} className="rounded-xl border border-border bg-surface-elevated overflow-hidden">
                  {/* Day header */}
                  <div className="flex items-center justify-between px-4 py-2 bg-surface">
                    <span className="text-xs font-semibold text-content-secondary">{day}</span>
                    <button
                      onClick={() => setEditingWorkout({
                        id: null,
                        dayOfWeek: dayIdx,
                        data: { day_of_week: dayIdx, workout_type: "continuous", workout_label: "", blocks: [], workout_order: dayWorkouts.length + 1 },
                      })}
                      className="flex items-center gap-1 text-[11px] text-brand hover:underline"
                    >
                      <svg className="h-3 w-3" fill="none" viewBox="0 0 24 24" strokeWidth={2.5} stroke="currentColor">
                        <path strokeLinecap="round" strokeLinejoin="round" d="M12 4.5v15m7.5-7.5h-15" />
                      </svg>
                      Adicionar treino
                    </button>
                  </div>

                  {/* Workout chips */}
                  {dayWorkouts.length > 0 && (
                    <div className="px-4 py-2 space-y-1.5">
                      {dayWorkouts.map((w) => (
                        <div key={w.id} className="flex items-center gap-2 rounded-lg border border-border bg-surface px-3 py-2">
                          <span className="text-sm">{TYPE_EMOJI[w.workout_type] ?? "🏃"}</span>
                          <div className="flex-1 min-w-0">
                            <p className="truncate text-xs font-medium text-content-primary">{w.workout_label}</p>
                            {w.blocks.length > 0 && (
                              <p className="text-[10px] text-content-muted">{w.blocks.length} bloco{w.blocks.length !== 1 ? "s" : ""}</p>
                            )}
                          </div>
                          <button
                            onClick={() => setEditingWorkout({ id: w.id, dayOfWeek: dayIdx, data: { ...w } })}
                            className="rounded p-1 text-content-muted hover:text-brand"
                          >
                            <svg className="h-3.5 w-3.5" fill="none" viewBox="0 0 24 24" strokeWidth={1.5} stroke="currentColor">
                              <path strokeLinecap="round" strokeLinejoin="round" d="M16.862 4.487l1.687-1.688a1.875 1.875 0 112.652 2.652L10.582 16.07a4.5 4.5 0 01-1.897 1.13L6 18l.8-2.685a4.5 4.5 0 011.13-1.897l8.932-8.931z" />
                            </svg>
                          </button>
                          <button
                            onClick={() => deleteWorkout(w.id)}
                            className="rounded p-1 text-content-muted hover:text-error"
                          >
                            <svg className="h-3.5 w-3.5" fill="none" viewBox="0 0 24 24" strokeWidth={1.5} stroke="currentColor">
                              <path strokeLinecap="round" strokeLinejoin="round" d="M6 18L18 6M6 6l12 12" />
                            </svg>
                          </button>
                        </div>
                      ))}
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        </div>
      </div>

      {/* Workout edit modal */}
      {editingWorkout && (
        <WorkoutEditModal
          dayOfWeek={editingWorkout.dayOfWeek}
          initial={editingWorkout.data as TemplateWorkout}
          onSave={async (data) => {
            await saveWorkout(data, editingWorkout.id ?? undefined);
            setEditingWorkout(null);
          }}
          onClose={() => setEditingWorkout(null)}
        />
      )}
    </>
  );
}

// ── WorkoutEditModal ──────────────────────────────────────────────────────────

function WorkoutEditModal({
  dayOfWeek,
  initial,
  onSave,
  onClose,
}: {
  dayOfWeek: number;
  initial:   Partial<TemplateWorkout>;
  onSave:    (data: Omit<TemplateWorkout, "id">) => Promise<void>;
  onClose:   () => void;
}) {
  const [label, setLabel]     = useState(initial.workout_label ?? "");
  const [type, setType]       = useState(initial.workout_type  ?? "continuous");
  const [notes, setNotes]     = useState(initial.coach_notes   ?? "");
  const [desc, setDesc]       = useState(initial.description   ?? "");
  const [blocks, setBlocks]   = useState<ReleaseBlock[]>(initial.blocks ?? []);
  const [showBlocks, setShowBlocks] = useState(false);
  const [saving, setSaving]   = useState(false);

  async function handleSave() {
    if (!label.trim()) return;
    setSaving(true);
    await onSave({
      day_of_week:   dayOfWeek,
      workout_order: initial.workout_order ?? 1,
      workout_type:  type,
      workout_label: label.trim(),
      description:   desc.trim() || null,
      coach_notes:   notes.trim() || null,
      blocks,
    });
    setSaving(false);
  }

  return (
    <>
      <div className="fixed inset-0 z-[60] bg-overlay/60" onClick={onClose} aria-hidden="true" />
      <div className="fixed inset-0 z-[60] flex items-end justify-center sm:items-center p-4"
        onClick={(e) => e.stopPropagation()}>
        <div className="flex w-full max-w-lg flex-col rounded-2xl bg-surface shadow-2xl"
          style={{ maxHeight: showBlocks ? "96vh" : "75vh" }}>

          {/* Header */}
          <div className="flex items-center justify-between border-b border-border px-5 py-4 shrink-0">
            <h3 className="text-sm font-semibold text-content-primary">
              {initial.workout_label ? "Editar treino" : "Adicionar treino"} — {DAYS_PT[dayOfWeek]}
            </h3>
            <button onClick={onClose} className="rounded-lg p-1 text-content-muted hover:bg-surface-elevated">
              <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" strokeWidth={2} stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </div>

          <div className="flex-1 overflow-y-auto px-5 py-4 space-y-3">
            {/* Label */}
            <div>
              <label className="block text-xs font-medium text-content-secondary mb-1">Nome do treino *</label>
              <input
                value={label}
                onChange={(e) => setLabel(e.target.value)}
                placeholder="Ex: Rodagem 45min"
                maxLength={120}
                className="w-full rounded-lg border border-border bg-bg-secondary px-3 py-2 text-sm focus:border-brand focus:outline-none"
              />
            </div>

            {/* Type */}
            <div>
              <label className="block text-xs font-medium text-content-secondary mb-1">Tipo</label>
              <select
                value={type}
                onChange={(e) => setType(e.target.value)}
                className="w-full rounded-lg border border-border bg-bg-secondary px-3 py-2 text-sm focus:border-brand focus:outline-none"
              >
                {WORKOUT_TYPES.map((t) => (
                  <option key={t.value} value={t.value}>{t.label}</option>
                ))}
              </select>
            </div>

            {/* Description */}
            <div>
              <label className="block text-xs font-medium text-content-secondary mb-1">Descrição</label>
              <textarea
                value={desc}
                onChange={(e) => setDesc(e.target.value)}
                placeholder="Detalhes do treino..."
                rows={2}
                maxLength={500}
                className="w-full rounded-lg border border-border bg-bg-secondary px-3 py-2 text-sm focus:border-brand focus:outline-none resize-none"
              />
            </div>

            {/* Coach notes */}
            <div>
              <label className="block text-xs font-medium text-content-secondary mb-1">Observações para o atleta</label>
              <input
                value={notes}
                onChange={(e) => setNotes(e.target.value)}
                placeholder="Ex: Aquecer 10min antes de começar"
                maxLength={500}
                className="w-full rounded-lg border border-border bg-bg-secondary px-3 py-2 text-sm focus:border-brand focus:outline-none"
              />
            </div>

            {/* Block editor toggle */}
            <div>
              <button
                onClick={() => setShowBlocks((v) => !v)}
                className="flex items-center gap-2 text-xs font-medium text-brand hover:underline"
              >
                ✏️ {showBlocks ? "Ocultar" : "Editar"} blocos
                {blocks.length > 0 && (
                  <span className="rounded-full bg-brand/10 px-2 py-0.5 text-brand text-[10px]">
                    {blocks.length}
                  </span>
                )}
              </button>

              {showBlocks && (
                <div className="mt-3 rounded-xl border border-border bg-bg-secondary p-3">
                  <BlockEditor
                    blocks={blocks}
                    onChange={setBlocks}
                  />
                </div>
              )}
            </div>
          </div>

          {/* Footer */}
          <div className="border-t border-border px-5 py-3 shrink-0 flex gap-2">
            <button onClick={onClose} className="flex-1 rounded-lg border border-border py-2 text-sm text-content-secondary hover:bg-surface-elevated">
              Cancelar
            </button>
            <button
              onClick={handleSave}
              disabled={!label.trim() || saving}
              className="flex-1 rounded-lg bg-brand py-2 text-sm font-semibold text-white hover:bg-brand/90 disabled:opacity-60"
            >
              {saving ? "Salvando..." : "Salvar treino"}
            </button>
          </div>
        </div>
      </div>
    </>
  );
}

// ── ApplyView ─────────────────────────────────────────────────────────────────

function ApplyView({
  template,
  target,
  onBack,
  onApplied,
}: {
  template:  WeekTemplate;
  target:    ApplyTarget;
  onBack:    () => void;
  onApplied: () => void;
}) {
  const [overrides, setOverrides] = useState<Record<string, WorkoutOverride>>({});
  const [autoRelease, setAutoRelease] = useState(false);
  const [applying, setApplying]   = useState(false);
  const [error, setError]         = useState("");
  const [editingId, setEditingId] = useState<string | null>(null);

  const workouts = template.workouts.sort(
    (a, b) => a.day_of_week !== b.day_of_week ? a.day_of_week - b.day_of_week : a.workout_order - b.workout_order,
  );

  function patchOverride(id: string, patch: Partial<WorkoutOverride>) {
    setOverrides((prev) => ({ ...prev, [id]: { ...prev[id], ...patch } }));
  }

  // Compute the actual dates for each day_of_week
  function dateForDay(dow: number): string {
    const base = new Date(target.weekStart + "T00:00:00");
    base.setDate(base.getDate() + dow);
    return base.toLocaleDateString("pt-BR", { weekday: "short", day: "2-digit", month: "2-digit" });
  }

  async function handleApply() {
    setApplying(true);
    setError("");
    try {
      const overrideList = Object.entries(overrides).map(([id, ov]) => ({
        template_workout_id: id,
        ...ov,
      }));

      const res  = await fetch(`/api/training-plan/week-templates/${template.id}/apply`, {
        method:  "POST",
        headers: { "Content-Type": "application/json" },
        body:    JSON.stringify({
          plan_week_id:    target.planWeekId,
          athlete_id:      target.athleteId,
          week_start_date: target.weekStart,
          auto_release:    autoRelease,
          overrides:       overrideList,
        }),
      });
      const json = await res.json();
      if (!json.ok) throw new Error(json.error?.message ?? "Erro ao aplicar");
      onApplied();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Erro");
    } finally {
      setApplying(false);
    }
  }

  const editingWorkout = workouts.find((w) => w.id === editingId);

  return (
    <>
      {/* Header */}
      <div className="flex items-center gap-3 border-b border-border px-6 py-4 shrink-0">
        <button onClick={onBack} className="rounded-lg p-1 text-content-muted hover:bg-surface-elevated">
          <svg className="h-5 w-5" fill="none" viewBox="0 0 24 24" strokeWidth={2} stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" d="M15 19l-7-7 7-7" />
          </svg>
        </button>
        <div className="flex-1 min-w-0">
          <h2 className="text-sm font-semibold text-content-primary truncate">
            Aplicar &ldquo;{template.name}&rdquo; → {target.athleteName}
          </h2>
          <p className="text-xs text-content-muted">{target.weekLabel} &middot; Personalize antes de confirmar</p>
        </div>
      </div>

      {/* Workout list with inline overrides */}
      <div className="flex-1 overflow-y-auto px-6 py-4 space-y-2">
        {workouts.map((w) => {
          const ov = overrides[w.id] ?? {};
          const removed = ov.remove === true;
          return (
            <div
              key={w.id}
              className={`rounded-xl border transition-all ${removed ? "border-border opacity-40 grayscale" : "border-border bg-surface-elevated"}`}
            >
              <div className="flex items-center gap-3 px-4 py-3">
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-1.5">
                    <span className="text-xs text-content-muted">{dateForDay(w.day_of_week)}</span>
                    <span className="text-sm">{TYPE_EMOJI[ov.workout_type ?? w.workout_type] ?? "🏃"}</span>
                  </div>
                  <p className={`text-sm font-medium text-content-primary truncate ${removed ? "line-through" : ""}`}>
                    {ov.workout_label ?? w.workout_label}
                  </p>
                  {(ov.blocks ?? w.blocks).length > 0 && (
                    <p className="text-[10px] text-content-muted">{(ov.blocks ?? w.blocks).length} blocos</p>
                  )}
                </div>
                <div className="flex items-center gap-1 shrink-0">
                  {!removed && (
                    <button
                      onClick={() => setEditingId(w.id)}
                      className="rounded-lg p-1.5 text-content-muted hover:text-brand hover:bg-surface"
                      title="Personalizar"
                    >
                      <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" strokeWidth={1.5} stroke="currentColor">
                        <path strokeLinecap="round" strokeLinejoin="round" d="M16.862 4.487l1.687-1.688a1.875 1.875 0 112.652 2.652L10.582 16.07a4.5 4.5 0 01-1.897 1.13L6 18l.8-2.685a4.5 4.5 0 011.13-1.897l8.932-8.931z" />
                      </svg>
                    </button>
                  )}
                  <button
                    onClick={() => patchOverride(w.id, { remove: !removed })}
                    className={`rounded-lg p-1.5 transition-colors ${removed ? "text-brand hover:text-brand/70" : "text-content-muted hover:text-error"}`}
                    title={removed ? "Restaurar" : "Remover da aplicação"}
                  >
                    {removed ? (
                      <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" strokeWidth={1.5} stroke="currentColor">
                        <path strokeLinecap="round" strokeLinejoin="round" d="M9 15L3 9m0 0l6-6M3 9h12a6 6 0 010 12h-3" />
                      </svg>
                    ) : (
                      <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" strokeWidth={1.5} stroke="currentColor">
                        <path strokeLinecap="round" strokeLinejoin="round" d="M6 18L18 6M6 6l12 12" />
                      </svg>
                    )}
                  </button>
                </div>
              </div>
            </div>
          );
        })}

        {workouts.length === 0 && (
          <p className="py-8 text-center text-sm text-content-muted">
            Este modelo não tem treinos configurados ainda.
          </p>
        )}
      </div>

      {/* Footer */}
      <div className="border-t border-border px-6 py-4 shrink-0 space-y-3">
        <label className="flex items-center gap-2.5 cursor-pointer">
          <div
            onClick={() => setAutoRelease((v) => !v)}
            className={`relative h-5 w-9 rounded-full transition-colors ${autoRelease ? "bg-brand" : "bg-border"}`}
          >
            <div className={`absolute top-0.5 h-4 w-4 rounded-full bg-white shadow transition-transform ${autoRelease ? "translate-x-4" : "translate-x-0.5"}`} />
          </div>
          <span className="text-xs text-content-secondary">Liberar treinos imediatamente para o atleta</span>
        </label>

        {error && <p className="text-xs text-error">{error}</p>}

        <div className="flex gap-2">
          <button onClick={onBack} className="flex-1 rounded-lg border border-border py-2.5 text-sm text-content-secondary hover:bg-surface-elevated">
            Voltar
          </button>
          <button
            onClick={handleApply}
            disabled={applying || workouts.filter((w) => !overrides[w.id]?.remove).length === 0}
            className="flex-1 rounded-lg bg-brand py-2.5 text-sm font-semibold text-white hover:bg-brand/90 disabled:opacity-60"
          >
            {applying ? "Aplicando..." : `Aplicar ${workouts.filter((w) => !overrides[w.id]?.remove).length} treino(s)`}
          </button>
        </div>
      </div>

      {/* Inline workout customization modal */}
      {editingWorkout && (
        <WorkoutEditModal
          dayOfWeek={editingWorkout.day_of_week}
          initial={{
            ...editingWorkout,
            ...(overrides[editingWorkout.id] ?? {}),
            blocks: overrides[editingWorkout.id]?.blocks ?? editingWorkout.blocks,
          }}
          onSave={async (data) => {
            patchOverride(editingWorkout.id, {
              workout_label: data.workout_label,
              workout_type:  data.workout_type,
              coach_notes:   data.coach_notes ?? undefined,
              blocks:        data.blocks,
            });
            setEditingId(null);
          }}
          onClose={() => setEditingId(null)}
        />
      )}
    </>
  );
}
