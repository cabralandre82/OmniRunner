"use client";

import { useEffect, useState, useMemo } from "react";
import { PlanWeek, GroupMember } from "./types";

interface BatchAssignModalProps {
  open: boolean;
  sourceWeek: PlanWeek | null;
  groupId: string;
  currentAthleteId: string;
  onClose: () => void;
  onSuccess: (count: number) => void;
}

interface AssignResult {
  athleteId: string;
  name: string;
  status: "pending" | "success" | "error";
  error?: string;
}

const DAYS_PT = ["Seg", "Ter", "Qua", "Qui", "Sex", "Sáb", "Dom"];

export function BatchAssignModal({
  open,
  sourceWeek,
  groupId,
  currentAthleteId,
  onClose,
  onSuccess,
}: BatchAssignModalProps) {
  const [members, setMembers] = useState<GroupMember[]>([]);
  const [fetchingMembers, setFetchingMembers] = useState(false);
  const [search, setSearch] = useState("");
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());
  const [targetStartDate, setTargetStartDate] = useState("");
  const [autoRelease, setAutoRelease] = useState(false);
  const [assigning, setAssigning] = useState(false);
  const [results, setResults] = useState<AssignResult[]>([]);
  const [done, setDone] = useState(false);

  // Fetch group members when modal opens
  useEffect(() => {
    if (!open || !groupId) return;
    setFetchingMembers(true);
    setSelectedIds(new Set());
    setResults([]);
    setDone(false);
    setAutoRelease(false);

    // Calculate default target start (same week next cycle)
    if (sourceWeek) {
      const nextMonday = getNextMonday(sourceWeek.starts_on);
      setTargetStartDate(nextMonday);
    }

    fetch(`/api/groups/${groupId}/members`)
      .then((r) => r.json())
      .then((j) => {
        if (j.ok) {
          // Exclude the current athlete (already has the week)
          setMembers((j.data ?? []).filter((m: GroupMember) => m.user_id !== currentAthleteId));
        }
      })
      .catch(() => {})
      .finally(() => setFetchingMembers(false));
  }, [open, groupId, currentAthleteId, sourceWeek]);

  const filteredMembers = useMemo(() => {
    if (!search.trim()) return members;
    const q = search.toLowerCase();
    return members.filter((m) => m.display_name.toLowerCase().includes(q));
  }, [members, search]);

  function toggleMember(id: string) {
    setSelectedIds((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }

  function selectAll() {
    setSelectedIds(new Set(filteredMembers.map((m) => m.user_id)));
  }

  function clearAll() {
    setSelectedIds(new Set());
  }

  async function handleAssign() {
    if (selectedIds.size === 0 || !targetStartDate || !sourceWeek) return;

    const athleteIds = Array.from(selectedIds);
    const initialResults: AssignResult[] = athleteIds.map((id) => ({
      athleteId: id,
      name: members.find((m) => m.user_id === id)?.display_name ?? id,
      status: "pending",
    }));
    setResults(initialResults);
    setAssigning(true);

    // Call bulk assign API
    try {
      const res = await fetch("/api/training-plan/bulk-assign", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          source_week_id: sourceWeek.id,
          target_athlete_ids: athleteIds,
          target_start_date: targetStartDate,
          group_id: groupId,
          auto_release: autoRelease,
        }),
      });
      const json = await res.json();

      if (json.ok && json.data?.results) {
        const updatedResults: AssignResult[] = initialResults.map((r) => {
          const result = json.data.results.find(
            (res: { athlete_id: string; success: boolean; error?: string }) =>
              res.athlete_id === r.athleteId,
          );
          return {
            ...r,
            status: result?.success ? "success" : "error",
            error: result?.error,
          };
        });
        setResults(updatedResults);
        const successCount = updatedResults.filter((r) => r.status === "success").length;
        setDone(true);
        onSuccess(successCount);
      } else {
        // Mark all as error
        setResults(initialResults.map((r) => ({ ...r, status: "error", error: json.error?.message ?? "Erro" })));
      }
    } catch (err) {
      setResults(initialResults.map((r) => ({ ...r, status: "error", error: "Erro de rede" })));
    } finally {
      setAssigning(false);
    }
  }

  if (!open) return null;

  const workoutCount = sourceWeek?.workouts?.length ?? 0;
  const workoutDates = sourceWeek?.workouts?.map((w) => w.scheduled_date) ?? [];

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
      {/* Backdrop */}
      <div
        className="absolute inset-0 bg-overlay/70"
        onClick={done ? onClose : undefined}
        aria-hidden="true"
      />

      {/* Modal */}
      <div className="relative z-10 flex max-h-[90vh] w-full max-w-lg flex-col rounded-2xl bg-surface shadow-2xl">
        {/* Header */}
        <div className="flex items-center justify-between border-b border-border px-6 py-4">
          <div>
            <h2 className="text-base font-semibold text-content-primary">
              📤 Distribuir semana para atletas
            </h2>
            <p className="mt-0.5 text-xs text-content-muted">
              Semana {sourceWeek?.week_number} · {workoutCount} treino{workoutCount !== 1 ? "s" : ""}
            </p>
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

        <div className="flex-1 overflow-y-auto px-6 py-4 space-y-5">

          {/* Results screen (after assigning) */}
          {done && (
            <div className="space-y-2">
              <p className="text-sm font-semibold text-content-primary">
                ✅ Resultado da distribuição
              </p>
              <div className="space-y-1.5">
                {results.map((r) => (
                  <div
                    key={r.athleteId}
                    className={`flex items-center justify-between rounded-lg px-3 py-2 text-sm ${
                      r.status === "success"
                        ? "bg-success-soft text-success"
                        : r.status === "error"
                        ? "bg-error-soft text-error"
                        : "bg-surface-elevated text-content-muted"
                    }`}
                  >
                    <span>{r.name}</span>
                    <span>
                      {r.status === "success" ? "✓ Copiado" : r.status === "error" ? `✗ ${r.error ?? "Erro"}` : "…"}
                    </span>
                  </div>
                ))}
              </div>
            </div>
          )}

          {!done && (
            <>
              {/* Source week preview */}
              <div className="rounded-lg border border-border bg-surface-elevated p-3">
                <p className="mb-2 text-[11px] font-semibold uppercase tracking-wide text-content-muted">
                  Semana origem
                </p>
                <div className="grid grid-cols-7 gap-1">
                  {DAYS_PT.map((day, i) => {
                    const start = new Date((sourceWeek?.starts_on ?? "") + "T00:00:00");
                    start.setDate(start.getDate() + i);
                    const dateKey = start.toISOString().split("T")[0];
                    const hasWorkout = workoutDates.includes(dateKey);
                    return (
                      <div key={day} className="text-center">
                        <p className="text-[10px] text-content-muted">{day}</p>
                        <div
                          className={`mt-0.5 h-6 rounded-sm text-[10px] leading-6 font-medium ${
                            hasWorkout
                              ? "bg-brand text-white"
                              : "bg-surface text-content-muted"
                          }`}
                        >
                          {hasWorkout ? "T" : "—"}
                        </div>
                      </div>
                    );
                  })}
                </div>
              </div>

              {/* Target start date */}
              <div>
                <label className="mb-1.5 block text-xs font-medium text-content-secondary">
                  Data de início na agenda dos atletas
                </label>
                <input
                  type="date"
                  value={targetStartDate}
                  onChange={(e) => setTargetStartDate(e.target.value)}
                  className="w-full rounded-lg border border-border bg-bg-secondary px-3 py-2 text-sm text-content-primary focus:border-brand focus:outline-none"
                />
                <p className="mt-1 text-[11px] text-content-muted">
                  Os treinos serão copiados mantendo o dia da semana relativo.
                </p>
              </div>

              {/* Auto-release toggle */}
              <button
                type="button"
                onClick={() => setAutoRelease((v) => !v)}
                className={`flex w-full items-center gap-3 rounded-lg border px-4 py-3 text-left transition-colors ${
                  autoRelease
                    ? "border-brand bg-brand-soft"
                    : "border-border hover:bg-surface-elevated"
                }`}
              >
                <div
                  className={`relative flex h-5 w-9 shrink-0 items-center rounded-full transition-colors ${
                    autoRelease ? "bg-brand" : "bg-border"
                  }`}
                >
                  <span
                    className={`absolute h-4 w-4 rounded-full bg-white shadow transition-transform ${
                      autoRelease ? "translate-x-4" : "translate-x-0.5"
                    }`}
                  />
                </div>
                <div>
                  <p className={`text-sm font-medium ${autoRelease ? "text-brand" : "text-content-primary"}`}>
                    Liberar treinos imediatamente
                  </p>
                  <p className="text-[11px] text-content-muted">
                    {autoRelease
                      ? "Os atletas já receberão os treinos liberados no app."
                      : "Os treinos ficarão como rascunho — você libera depois."}
                  </p>
                </div>
              </button>

              {/* Athlete selector */}
              <div>
                <div className="mb-2 flex items-center justify-between">
                  <label className="text-xs font-medium text-content-secondary">
                    Atletas ({selectedIds.size} selecionado{selectedIds.size !== 1 ? "s" : ""})
                  </label>
                  <div className="flex gap-2 text-xs">
                    <button onClick={selectAll} className="text-brand hover:underline">Todos</button>
                    <span className="text-border">|</span>
                    <button onClick={clearAll} className="text-content-muted hover:underline">Limpar</button>
                  </div>
                </div>

                <div className="relative mb-2">
                  <svg className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-content-muted" fill="none" viewBox="0 0 24 24" strokeWidth={1.5} stroke="currentColor">
                    <path strokeLinecap="round" strokeLinejoin="round" d="M21 21l-5.197-5.197m0 0A7.5 7.5 0 105.196 5.196a7.5 7.5 0 0010.607 10.607z" />
                  </svg>
                  <input
                    type="text"
                    placeholder="Buscar atleta..."
                    value={search}
                    onChange={(e) => setSearch(e.target.value)}
                    className="w-full rounded-lg border border-border bg-bg-secondary pl-9 pr-4 py-2 text-sm text-content-primary placeholder:text-content-muted focus:border-brand focus:outline-none"
                  />
                </div>

                <div className="max-h-52 overflow-y-auto rounded-lg border border-border divide-y divide-border">
                  {fetchingMembers ? (
                    <div className="p-4 text-center text-sm text-content-muted">Carregando atletas...</div>
                  ) : filteredMembers.length === 0 ? (
                    <div className="p-4 text-center text-sm text-content-muted">
                      {search ? "Nenhum atleta encontrado." : "Nenhum outro atleta no grupo."}
                    </div>
                  ) : (
                    filteredMembers.map((member) => {
                      const selected = selectedIds.has(member.user_id);
                      return (
                        <button
                          key={member.user_id}
                          onClick={() => toggleMember(member.user_id)}
                          className={`flex w-full items-center gap-3 px-4 py-2.5 text-left transition-colors ${
                            selected ? "bg-brand-soft" : "hover:bg-surface-elevated"
                          }`}
                        >
                          <div
                            className={`flex h-5 w-5 shrink-0 items-center justify-center rounded border-2 transition-colors ${
                              selected
                                ? "border-brand bg-brand text-white"
                                : "border-border"
                            }`}
                          >
                            {selected && (
                              <svg className="h-3 w-3" fill="none" viewBox="0 0 24 24" strokeWidth={3} stroke="currentColor">
                                <path strokeLinecap="round" strokeLinejoin="round" d="M4.5 12.75l6 6 9-13.5" />
                              </svg>
                            )}
                          </div>
                          <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-surface-elevated text-sm font-semibold text-content-secondary">
                            {member.display_name.charAt(0).toUpperCase()}
                          </div>
                          <span className={`text-sm ${selected ? "font-medium text-brand" : "text-content-primary"}`}>
                            {member.display_name}
                          </span>
                        </button>
                      );
                    })
                  )}
                </div>
              </div>
            </>
          )}
        </div>

        {/* Footer */}
        <div className="flex items-center justify-between border-t border-border px-6 py-4">
          <button
            onClick={onClose}
            className="rounded-lg border border-border px-4 py-2 text-sm text-content-secondary hover:bg-surface-elevated"
          >
            {done ? "Fechar" : "Cancelar"}
          </button>

          {!done && (
            <button
              onClick={handleAssign}
              disabled={selectedIds.size === 0 || !targetStartDate || assigning}
              className="flex items-center gap-2 rounded-lg bg-brand px-5 py-2 text-sm font-semibold text-white hover:bg-brand/90 disabled:opacity-60"
            >
              {assigning ? (
                <>
                  <svg className="h-4 w-4 animate-spin" fill="none" viewBox="0 0 24 24">
                    <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4"/>
                    <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"/>
                  </svg>
                  Distribuindo...
                </>
              ) : (
                <>
                  📤 Distribuir para {selectedIds.size || "..."} atleta{selectedIds.size !== 1 ? "s" : ""}
                </>
              )}
            </button>
          )}
        </div>
      </div>
    </div>
  );
}

// ── Helper ────────────────────────────────────────────────────────────────────

function getNextMonday(dateStr: string): string {
  const d = new Date(dateStr + "T00:00:00");
  d.setDate(d.getDate() + 7);
  // Adjust to the nearest Monday
  const day = d.getDay();
  if (day !== 1) {
    const diff = day === 0 ? 1 : 8 - day;
    d.setDate(d.getDate() + diff);
  }
  return d.toISOString().split("T")[0];
}
