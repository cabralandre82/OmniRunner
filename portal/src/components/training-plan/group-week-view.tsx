"use client";

import { useEffect, useState, useCallback } from "react";
import Link from "next/link";
import Image from "next/image";

const DAYS_PT = ["Seg", "Ter", "Qua", "Qui", "Sex", "Sáb", "Dom"];

const STATUS_COLOR: Record<string, string> = {
  draft:       "bg-surface-elevated text-content-muted border-border",
  scheduled:   "bg-warning-soft text-warning border-warning/20",
  released:    "bg-brand-soft text-brand border-brand/20",
  in_progress: "bg-brand text-white border-brand",
  completed:   "bg-success-soft text-success border-success/20",
};

const TYPE_EMOJI: Record<string, string> = {
  continuous:   "🏃",
  interval:     "⚡",
  regenerative: "🧘",
  long_run:     "🛣️",
  strength:     "💪",
  technique:    "🎯",
  test:         "📊",
  free:         "🆓",
  race:         "🏆",
  brick:        "🔥",
};

interface WorkoutChip {
  id: string;
  scheduled_date: string;
  workout_type: string;
  workout_label: string | null;
  release_status: string;
  template_name: string | null;
}

interface AthleteRow {
  user_id: string;
  display_name: string;
  avatar_url: string | null;
  plan_id: string | null;
  workouts: WorkoutChip[];
}

interface GroupWeekData {
  week_start: string;
  week_end:   string;
  athletes:   AthleteRow[];
}

function getMonday(date: Date): string {
  const dow = date.getDay();
  const offset = dow === 0 ? -6 : 1 - dow;
  const mon = new Date(date);
  mon.setDate(date.getDate() + offset);
  return mon.toISOString().split("T")[0];
}

function addDays(dateStr: string, days: number): string {
  const d = new Date(dateStr + "T00:00:00");
  d.setDate(d.getDate() + days);
  return d.toISOString().split("T")[0];
}

function formatShortDate(dateStr: string): string {
  const d = new Date(dateStr + "T00:00:00");
  return `${String(d.getDate()).padStart(2, "0")}/${String(d.getMonth() + 1).padStart(2, "0")}`;
}

export function GroupWeekView() {
  const [weekStart, setWeekStart] = useState(() => getMonday(new Date()));
  const [data, setData] = useState<GroupWeekData | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");

  const load = useCallback(async (start: string) => {
    setLoading(true);
    setError("");
    try {
      const res = await fetch(`/api/training-plan/group-week-view?weekStart=${start}`);
      const json = await res.json();
      if (json.ok) setData(json.data);
      else setError(json.error?.message ?? "Erro ao carregar");
    } catch {
      setError("Erro de rede");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { load(weekStart); }, [weekStart, load]);

  function prevWeek() { setWeekStart((s) => addDays(s, -7)); }
  function nextWeek() { setWeekStart((s) => addDays(s, 7)); }
  function goToday() { setWeekStart(getMonday(new Date())); }

  const weekDates = data
    ? Array.from({ length: 7 }, (_, i) => addDays(data.week_start, i))
    : Array.from({ length: 7 }, (_, i) => addDays(weekStart, i));

  const today = new Date().toISOString().split("T")[0];

  return (
    <div className="space-y-4">
      {/* Week navigator */}
      <div className="flex items-center justify-between rounded-xl border border-border bg-surface px-5 py-3">
        <div className="flex items-center gap-2">
          <button
            onClick={prevWeek}
            className="rounded-lg border border-border p-1.5 text-content-muted hover:bg-surface-elevated"
          >
            <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" strokeWidth={2} stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" d="M15.75 19.5L8.25 12l7.5-7.5" />
            </svg>
          </button>
          <button
            onClick={nextWeek}
            className="rounded-lg border border-border p-1.5 text-content-muted hover:bg-surface-elevated"
          >
            <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" strokeWidth={2} stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" d="M8.25 4.5l7.5 7.5-7.5 7.5" />
            </svg>
          </button>
          <span className="text-sm font-semibold text-content-primary">
            {formatShortDate(weekStart)} – {formatShortDate(addDays(weekStart, 6))}
          </span>
        </div>
        <button
          onClick={goToday}
          className="rounded-lg border border-border px-3 py-1.5 text-xs font-medium text-content-secondary hover:bg-surface-elevated"
        >
          Hoje
        </button>
      </div>

      {/* Grid */}
      {loading ? (
        <div className="animate-pulse rounded-xl border border-border bg-surface p-8 text-center text-sm text-content-muted">
          Carregando...
        </div>
      ) : error ? (
        <div className="rounded-xl border border-error/20 bg-error-soft p-6 text-center text-sm text-error">
          {error}
          <button onClick={() => load(weekStart)} className="ml-3 underline">Tentar novamente</button>
        </div>
      ) : !data || data.athletes.length === 0 ? (
        <div className="rounded-xl border border-border bg-surface p-8 text-center text-sm text-content-muted">
          Nenhum atleta no grupo ainda.
        </div>
      ) : (
        <div className="overflow-x-auto rounded-xl border border-border bg-surface">
          <table className="w-full min-w-[640px] border-collapse text-xs">
            {/* Header: days */}
            <thead>
              <tr className="border-b border-border bg-bg-secondary">
                <th className="w-36 px-4 py-2.5 text-left text-[11px] font-semibold uppercase tracking-wide text-content-muted">
                  Atleta
                </th>
                {weekDates.map((date, i) => (
                  <th
                    key={date}
                    className={`px-2 py-2.5 text-center text-[11px] font-semibold uppercase tracking-wide ${
                      date === today ? "text-brand" : "text-content-muted"
                    }`}
                  >
                    <div>{DAYS_PT[i]}</div>
                    <div className={`font-normal normal-case ${date === today ? "font-bold" : ""}`}>
                      {formatShortDate(date)}
                    </div>
                  </th>
                ))}
                <th className="w-16 px-2 py-2.5 text-center text-[11px] font-semibold uppercase tracking-wide text-content-muted">
                  Plano
                </th>
              </tr>
            </thead>

            <tbody className="divide-y divide-border">
              {data.athletes.map((athlete) => {
                const workoutsByDate = new Map<string, WorkoutChip[]>();
                for (const d of weekDates) workoutsByDate.set(d, []);
                for (const w of athlete.workouts) {
                  const list = workoutsByDate.get(w.scheduled_date) ?? [];
                  list.push(w);
                  workoutsByDate.set(w.scheduled_date, list);
                }

                const completedCount = athlete.workouts.filter((w) => w.release_status === "completed").length;
                const totalCount = athlete.workouts.length;

                return (
                  <tr key={athlete.user_id} className="hover:bg-surface-elevated/50 transition-colors">
                    {/* Athlete cell */}
                    <td className="px-4 py-2">
                      <div className="flex items-center gap-2">
                        {athlete.avatar_url ? (
                          <Image
                            src={athlete.avatar_url}
                            alt={athlete.display_name}
                            width={28}
                            height={28}
                            unoptimized
                            className="h-7 w-7 rounded-full object-cover shrink-0"
                          />
                        ) : (
                          <div className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-brand-soft text-xs font-semibold text-brand">
                            {athlete.display_name.charAt(0).toUpperCase()}
                          </div>
                        )}
                        <div className="min-w-0">
                          <p className="truncate font-medium text-content-primary leading-tight">
                            {athlete.display_name}
                          </p>
                          {totalCount > 0 && (
                            <p className="text-[10px] text-content-muted leading-tight">
                              {completedCount}/{totalCount} ✓
                            </p>
                          )}
                        </div>
                      </div>
                    </td>

                    {/* Day cells */}
                    {weekDates.map((date) => {
                      const chips = workoutsByDate.get(date) ?? [];
                      return (
                        <td
                          key={date}
                          className={`px-1.5 py-1.5 align-top ${date === today ? "bg-brand-soft/10" : ""}`}
                        >
                          <div className="flex flex-col gap-0.5 min-h-[28px]">
                            {chips.map((chip) => (
                              <div
                                key={chip.id}
                                className={`rounded border px-1 py-0.5 text-[10px] leading-tight ${
                                  STATUS_COLOR[chip.release_status] ?? "bg-surface-elevated text-content-muted border-border"
                                }`}
                                title={chip.workout_label || chip.template_name || chip.workout_type}
                              >
                                <span className="mr-0.5">{TYPE_EMOJI[chip.workout_type] ?? "🏃"}</span>
                                <span className="truncate">
                                  {chip.workout_label || chip.template_name || "Treino"}
                                </span>
                              </div>
                            ))}
                          </div>
                        </td>
                      );
                    })}

                    {/* Link to plan */}
                    <td className="px-2 py-2 text-center">
                      {athlete.plan_id ? (
                        <Link
                          href={`/training-plan/${athlete.plan_id}`}
                          className="inline-flex items-center justify-center rounded-lg border border-border p-1.5 text-content-muted hover:bg-brand-soft hover:text-brand hover:border-brand/20 transition-colors"
                          title="Abrir planilha"
                        >
                          <svg className="h-3.5 w-3.5" fill="none" viewBox="0 0 24 24" strokeWidth={2} stroke="currentColor">
                            <path strokeLinecap="round" strokeLinejoin="round" d="M13.5 6H5.25A2.25 2.25 0 003 8.25v10.5A2.25 2.25 0 005.25 21h10.5A2.25 2.25 0 0018 18.75V10.5m-10.5 6L21 3m0 0h-5.25M21 3v5.25" />
                          </svg>
                        </Link>
                      ) : (
                        <span className="text-[10px] text-content-muted">—</span>
                      )}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}

      {/* Legend */}
      <div className="flex flex-wrap items-center gap-3 text-[11px] text-content-muted">
        <span className="font-medium">Status:</span>
        {[
          ["draft", "Rascunho"],
          ["released", "Liberado"],
          ["in_progress", "Em andamento"],
          ["completed", "Concluído"],
        ].map(([key, label]) => (
          <span key={key} className={`inline-flex items-center gap-1 rounded border px-1.5 py-0.5 ${STATUS_COLOR[key]}`}>
            {label}
          </span>
        ))}
      </div>
    </div>
  );
}
