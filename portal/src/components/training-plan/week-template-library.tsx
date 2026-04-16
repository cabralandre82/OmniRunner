"use client";

import { useEffect, useState, useMemo } from "react";

const DAYS_PT_SHORT = ["Seg", "Ter", "Qua", "Qui", "Sex", "Sáb", "Dom"];

interface WeekTemplate {
  id: string;
  template_name: string;
  workout_count: number;
  days_with_workouts: number[];
  workouts: {
    scheduled_date: string;
    workout_type: string;
    workout_label: string | null;
    template_name: string | null;
  }[];
}

// ── Save-as-template modal ───────────────────────────────────────────────────

interface SaveTemplateModalProps {
  open: boolean;
  weekId: string | null;
  weekLabel: string;
  onClose: () => void;
  onSaved: () => void;
}

export function SaveWeekTemplateModal({ open, weekId, weekLabel, onClose, onSaved }: SaveTemplateModalProps) {
  const [name, setName] = useState(weekLabel);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");

  useEffect(() => {
    if (open) { setName(weekLabel); setError(""); }
  }, [open, weekLabel]);

  async function handleSave() {
    if (!weekId || !name.trim()) return;
    setSaving(true);
    setError("");
    try {
      const res = await fetch("/api/training-plan/week-templates", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ week_id: weekId, template_name: name.trim() }),
      });
      const json = await res.json();
      if (json.ok) { onSaved(); onClose(); }
      else setError(json.error?.message ?? "Erro ao salvar");
    } catch {
      setError("Erro de rede");
    } finally {
      setSaving(false);
    }
  }

  if (!open) return null;

  return (
    <>
      <div className="fixed inset-0 z-50 bg-overlay/60" onClick={onClose} aria-hidden="true" />
      <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
        <div className="w-full max-w-sm rounded-2xl bg-surface p-6 shadow-2xl">
          <h3 className="mb-1 text-base font-semibold text-content-primary">📚 Salvar como modelo de semana</h3>
          <p className="mb-4 text-xs text-content-muted">
            O modelo fica salvo na biblioteca e pode ser aplicado para qualquer atleta do grupo.
          </p>
          <label className="mb-1.5 block text-xs font-medium text-content-secondary">Nome do modelo</label>
          <input
            type="text"
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="Ex: Semana Base Intermediário"
            maxLength={80}
            className="w-full rounded-lg border border-border bg-bg-secondary px-3 py-2 text-sm text-content-primary focus:border-brand focus:outline-none"
          />
          {error && <p className="mt-1.5 text-xs text-error">{error}</p>}
          <div className="mt-4 flex gap-2">
            <button onClick={onClose} className="flex-1 rounded-lg border border-border py-2 text-sm text-content-secondary hover:bg-surface-elevated">
              Cancelar
            </button>
            <button
              onClick={handleSave}
              disabled={!name.trim() || saving}
              className="flex-1 rounded-lg bg-brand py-2 text-sm font-semibold text-white hover:bg-brand/90 disabled:opacity-60"
            >
              {saving ? "Salvando..." : "Salvar modelo"}
            </button>
          </div>
        </div>
      </div>
    </>
  );
}

// ── Library picker modal ─────────────────────────────────────────────────────

interface WeekTemplateLibraryProps {
  open: boolean;
  groupId: string;
  currentAthleteId: string;
  onClose: () => void;
  onApply: (templateWeekId: string, templateName: string) => void;
}

export function WeekTemplateLibrary({
  open,
  groupId,
  currentAthleteId: _,
  onClose,
  onApply,
}: WeekTemplateLibraryProps) {
  const [templates, setTemplates] = useState<WeekTemplate[]>([]);
  const [loading, setLoading] = useState(false);
  const [search, setSearch] = useState("");
  const [expanded, setExpanded] = useState<string | null>(null);
  const [deleting, setDeleting] = useState<string | null>(null);

  useEffect(() => {
    if (!open) return;
    setLoading(true);
    fetch(`/api/training-plan/week-templates?groupId=${groupId}`)
      .then((r) => r.json())
      .then((j) => { if (j.ok) setTemplates(j.data ?? []); })
      .catch(() => {})
      .finally(() => setLoading(false));
  }, [open, groupId]);

  const filtered = useMemo(() => {
    if (!search.trim()) return templates;
    const q = search.toLowerCase();
    return templates.filter((t) => t.template_name.toLowerCase().includes(q));
  }, [templates, search]);

  async function handleRemove(id: string) {
    setDeleting(id);
    await fetch(`/api/training-plan/week-templates?weekId=${id}`, { method: "DELETE" });
    setTemplates((prev) => prev.filter((t) => t.id !== id));
    setDeleting(null);
  }

  if (!open) return null;

  return (
    <>
      <div className="fixed inset-0 z-50 bg-overlay/60" onClick={onClose} aria-hidden="true" />
      <div className="fixed inset-0 z-50 flex items-end justify-center sm:items-center p-4">
        <div className="flex max-h-[85vh] w-full max-w-xl flex-col rounded-2xl bg-surface shadow-2xl">
          {/* Header */}
          <div className="flex items-center justify-between border-b border-border px-6 py-4">
            <div>
              <h2 className="text-base font-semibold text-content-primary">📚 Biblioteca de Modelos de Semana</h2>
              <p className="mt-0.5 text-xs text-content-muted">Aplique um modelo para compor a semana de qualquer atleta.</p>
            </div>
            <button onClick={onClose} className="rounded-lg p-1.5 text-content-muted hover:bg-surface-elevated">
              <svg className="h-5 w-5" fill="none" viewBox="0 0 24 24" strokeWidth={2} stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </div>

          {/* Search */}
          <div className="px-6 pt-4 pb-2">
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
              <div className="py-8 text-center text-sm text-content-muted">Carregando modelos...</div>
            ) : filtered.length === 0 ? (
              <div className="py-8 text-center">
                <p className="text-sm text-content-muted">
                  {search ? "Nenhum modelo encontrado." : "Nenhum modelo salvo ainda."}
                </p>
                {!search && (
                  <p className="mt-1 text-xs text-content-muted">
                    Para criar um modelo, abra o menu (⋮) de qualquer semana e escolha &ldquo;Salvar como modelo&rdquo;.
                  </p>
                )}
              </div>
            ) : (
              filtered.map((t) => (
                <div key={t.id} className="rounded-xl border border-border bg-surface-elevated">
                  {/* Template header */}
                  <div className="flex items-center justify-between gap-3 px-4 py-3">
                    <button
                      onClick={() => setExpanded(expanded === t.id ? null : t.id)}
                      className="flex flex-1 items-start gap-3 text-left"
                    >
                      <div className="flex-1 min-w-0">
                        <p className="truncate text-sm font-semibold text-content-primary">{t.template_name}</p>
                        <p className="mt-0.5 text-[11px] text-content-muted">
                          {t.workout_count} treino{t.workout_count !== 1 ? "s" : ""}
                          {" · dias: "}
                          {t.days_with_workouts.map((d) => DAYS_PT_SHORT[d]).join(", ")}
                        </p>
                      </div>
                      <svg className={`h-4 w-4 shrink-0 text-content-muted transition-transform ${expanded === t.id ? "rotate-180" : ""}`} fill="none" viewBox="0 0 24 24" strokeWidth={2} stroke="currentColor">
                        <path strokeLinecap="round" strokeLinejoin="round" d="M19 9l-7 7-7-7" />
                      </svg>
                    </button>

                    <div className="flex items-center gap-1.5 shrink-0">
                      <button
                        onClick={() => handleRemove(t.id)}
                        disabled={deleting === t.id}
                        className="rounded-lg p-1.5 text-content-muted hover:bg-error-soft hover:text-error transition-colors disabled:opacity-50"
                        title="Remover da biblioteca"
                      >
                        <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" strokeWidth={1.5} stroke="currentColor">
                          <path strokeLinecap="round" strokeLinejoin="round" d="M14.74 9l-.346 9m-4.788 0L9.26 9m9.968-3.21c.342.052.682.107 1.022.166m-1.022-.165L18.16 19.673a2.25 2.25 0 01-2.244 2.077H8.084a2.25 2.25 0 01-2.244-2.077L4.772 5.79m14.456 0a48.108 48.108 0 00-3.478-.397m-12 .562c.34-.059.68-.114 1.022-.165m0 0a48.11 48.11 0 013.478-.397m7.5 0v-.916c0-1.18-.91-2.164-2.09-2.201a51.964 51.964 0 00-3.32 0c-1.18.037-2.09 1.022-2.09 2.201v.916" />
                        </svg>
                      </button>
                      <button
                        onClick={() => onApply(t.id, t.template_name)}
                        className="rounded-lg bg-brand px-3 py-1.5 text-xs font-semibold text-white hover:bg-brand/90"
                      >
                        Aplicar
                      </button>
                    </div>
                  </div>

                  {/* Expanded: day preview */}
                  {expanded === t.id && (
                    <div className="border-t border-border px-4 pb-3 pt-2">
                      <div className="grid grid-cols-7 gap-1">
                        {DAYS_PT_SHORT.map((day, i) => {
                          const dayWorkouts = t.workouts.filter((w) => {
                            const d = new Date(w.scheduled_date + "T00:00:00");
                            return ((d.getDay() + 6) % 7) === i;
                          });
                          return (
                            <div key={day} className="text-center">
                              <p className="text-[10px] text-content-muted">{day}</p>
                              {dayWorkouts.length === 0 ? (
                                <div className="mt-0.5 h-6 rounded-sm bg-surface text-[10px] leading-6 text-content-muted">—</div>
                              ) : (
                                dayWorkouts.map((w, wi) => (
                                  <div key={wi} className="mt-0.5 rounded-sm bg-brand px-0.5 py-0.5 text-[9px] leading-tight text-white truncate" title={w.workout_label || w.template_name || ""}>
                                    {w.workout_label || w.template_name || "T"}
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
              ))
            )}
          </div>
        </div>
      </div>
    </>
  );
}
