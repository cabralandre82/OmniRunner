"use client";

import { useEffect, useState, useMemo } from "react";
import {
  WorkoutTemplate,
  WORKOUT_TYPE_LABEL,
  WorkoutType,
  formatDistanceM,
} from "./types";

interface WorkoutPickerDrawerProps {
  open: boolean;
  targetDate: string | null;
  targetDayLabel: string;
  groupId: string;
  onPick: (template: WorkoutTemplate) => void;
  onClose: () => void;
  loading?: boolean;
}

const TYPE_ICONS: Record<string, string> = {
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

export function WorkoutPickerDrawer({
  open,
  targetDate,
  targetDayLabel,
  groupId,
  onPick,
  onClose,
  loading = false,
}: WorkoutPickerDrawerProps) {
  const [templates, setTemplates] = useState<WorkoutTemplate[]>([]);
  const [fetching, setFetching] = useState(false);
  const [search, setSearch] = useState("");
  const [filterType, setFilterType] = useState<WorkoutType | "all">("all");

  useEffect(() => {
    if (!open || !groupId) return;
    setFetching(true);
    fetch(`/api/training-plan/templates?groupId=${groupId}`)
      .then((r) => r.json())
      .then((j) => {
        if (j.ok) setTemplates(j.data ?? []);
      })
      .catch(() => {})
      .finally(() => setFetching(false));
  }, [open, groupId]);

  const filtered = useMemo(() => {
    let list = templates;
    if (filterType !== "all") list = list.filter((t) => t.workout_type === filterType);
    if (search.trim()) {
      const q = search.toLowerCase();
      list = list.filter((t) => t.name.toLowerCase().includes(q));
    }
    return list;
  }, [templates, search, filterType]);

  // Group by workout type
  const grouped = useMemo(() => {
    const map = new Map<string, WorkoutTemplate[]>();
    for (const t of filtered) {
      if (!map.has(t.workout_type)) map.set(t.workout_type, []);
      map.get(t.workout_type)!.push(t);
    }
    return map;
  }, [filtered]);

  const allTypes = Array.from(new Set(templates.map((t) => t.workout_type))) as WorkoutType[];

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

      {/* Drawer */}
      <aside
        className={`fixed inset-y-0 right-0 z-50 flex w-full max-w-sm flex-col bg-surface shadow-xl transition-transform duration-300 ${
          open ? "translate-x-0" : "translate-x-full"
        }`}
      >
        {/* Header */}
        <div className="flex items-center justify-between border-b border-border px-5 py-4">
          <div>
            <h2 className="text-base font-semibold text-content-primary">
              Adicionar treino
            </h2>
            {targetDate && (
              <p className="text-xs text-content-muted">{targetDayLabel}</p>
            )}
          </div>
          <button
            onClick={onClose}
            className="rounded-lg p-1.5 text-content-muted hover:bg-surface-elevated"
          >
            <svg className="h-5 w-5" fill="none" viewBox="0 0 24 24" strokeWidth={2} stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        {/* Search + filter */}
        <div className="border-b border-border px-4 py-3 space-y-2">
          <div className="relative">
            <svg className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-content-muted" fill="none" viewBox="0 0 24 24" strokeWidth={1.5} stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" d="M21 21l-5.197-5.197m0 0A7.5 7.5 0 105.196 5.196a7.5 7.5 0 0010.607 10.607z" />
            </svg>
            <input
              type="text"
              placeholder="Buscar treino..."
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              className="w-full rounded-lg border border-border bg-bg-secondary pl-9 pr-4 py-2 text-sm text-content-primary placeholder:text-content-muted focus:border-brand focus:outline-none"
            />
          </div>

          {/* Type filter chips */}
          <div className="flex flex-wrap gap-1.5">
            <button
              onClick={() => setFilterType("all")}
              className={`rounded-full px-2.5 py-0.5 text-xs font-medium transition-colors ${
                filterType === "all"
                  ? "bg-brand text-white"
                  : "bg-surface-elevated text-content-secondary hover:bg-brand-soft hover:text-brand"
              }`}
            >
              Todos
            </button>
            {allTypes.map((t) => (
              <button
                key={t}
                onClick={() => setFilterType(t === filterType ? "all" : t)}
                className={`rounded-full px-2.5 py-0.5 text-xs font-medium transition-colors ${
                  filterType === t
                    ? "bg-brand text-white"
                    : "bg-surface-elevated text-content-secondary hover:bg-brand-soft hover:text-brand"
                }`}
              >
                {TYPE_ICONS[t]} {WORKOUT_TYPE_LABEL[t as WorkoutType] ?? t}
              </button>
            ))}
          </div>
        </div>

        {/* Template list */}
        <div className="flex-1 overflow-y-auto">
          {fetching ? (
            <div className="space-y-2 p-4">
              {[1, 2, 3, 4, 5].map((i) => (
                <div key={i} className="h-16 animate-pulse rounded-lg bg-surface-elevated" />
              ))}
            </div>
          ) : filtered.length === 0 ? (
            <div className="flex flex-col items-center justify-center p-10 text-center">
              <span className="text-3xl">📭</span>
              <p className="mt-2 text-sm text-content-secondary">
                {search ? "Nenhum treino encontrado." : "Sem templates cadastrados."}
              </p>
              <a
                href="/workouts"
                target="_blank"
                className="mt-2 text-xs text-brand underline"
              >
                Criar templates na biblioteca →
              </a>
            </div>
          ) : (
            <div className="divide-y divide-border">
              {Array.from(grouped.entries()).map(([type, items]) => (
                <div key={type}>
                  <div className="sticky top-0 bg-surface px-4 py-2">
                    <p className="text-xs font-semibold uppercase tracking-wide text-content-muted">
                      {TYPE_ICONS[type]} {WORKOUT_TYPE_LABEL[type as WorkoutType] ?? type} ({items.length})
                    </p>
                  </div>
                  {items.map((template: WorkoutTemplate) => (
                    <button
                      key={template.id}
                      onClick={() => onPick(template)}
                      disabled={loading}
                      className="group w-full px-4 py-3 text-left transition-colors hover:bg-brand-soft disabled:opacity-60"
                    >
                      <div className="flex items-start justify-between gap-3">
                        <div className="min-w-0">
                          <p className="truncate text-sm font-medium text-content-primary group-hover:text-brand">
                            {template.name}
                          </p>
                          {template.description && (
                            <p className="mt-0.5 truncate text-xs text-content-muted">
                              {template.description}
                            </p>
                          )}
                          <div className="mt-1 flex items-center gap-3 text-[11px] text-content-muted">
                            {template.estimated_distance_m != null && template.estimated_distance_m > 0 && (
                              <span>📏 {formatDistanceM(template.estimated_distance_m)}</span>
                            )}
                            {template.block_count > 0 && (
                              <span>🧩 {template.block_count} bloco{template.block_count !== 1 ? "s" : ""}</span>
                            )}
                          </div>
                        </div>
                        <div className="mt-0.5 flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-surface-elevated text-brand opacity-0 transition-opacity group-hover:opacity-100">
                          <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" strokeWidth={2.5} stroke="currentColor">
                            <path strokeLinecap="round" strokeLinejoin="round" d="M12 4.5v15m7.5-7.5h-15" />
                          </svg>
                        </div>
                      </div>
                    </button>
                  ))}
                </div>
              ))}
            </div>
          )}
        </div>

        {/* Footer */}
        <div className="border-t border-border px-4 py-3">
          <a
            href="/workouts"
            target="_blank"
            className="flex items-center justify-center gap-2 rounded-lg border border-border py-2 text-sm text-content-secondary hover:bg-surface-elevated"
          >
            <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" strokeWidth={1.5} stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" d="M12 4.5v15m7.5-7.5h-15" />
            </svg>
            Gerenciar biblioteca de treinos
          </a>
        </div>
      </aside>
    </>
  );
}
