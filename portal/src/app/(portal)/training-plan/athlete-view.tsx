"use client";

import { useEffect, useState, useMemo } from "react";
import Link from "next/link";
import Image from "next/image";
import { formatDate } from "@/components/training-plan/types";

interface CurrentWeek {
  id: string;
  week_number: number;
  starts_on: string;
  ends_on: string;
  status: string;
  total: number;
  draft: number;
  released: number;
  completed: number;
}

interface AthleteOverview {
  user_id: string;
  display_name: string;
  avatar_url: string | null;
  plan: { id: string; name: string; status: string } | null;
  current_week: CurrentWeek | null;
  avg_rpe_last5: number | null;
  fatigue_alert: boolean;
}

function getWeekStatusBadge(week: CurrentWeek | null): {
  label: string;
  style: string;
  dot: string;
} | null {
  if (!week) return null;
  if (week.total === 0) return {
    label: "Semana vazia",
    style: "bg-surface-elevated text-content-muted",
    dot: "bg-content-muted",
  };
  if (week.completed === week.total && week.total > 0) return {
    label: `${week.total} concluídos ✓`,
    style: "bg-success-soft text-success",
    dot: "bg-success",
  };
  if (week.released > 0 && week.draft === 0) return {
    label: `${week.released} liberado${week.released !== 1 ? "s" : ""}`,
    style: "bg-info-soft text-info",
    dot: "bg-info",
  };
  if (week.released > 0 && week.draft > 0) return {
    label: `${week.released} lib · ${week.draft} rascunho${week.draft !== 1 ? "s" : ""}`,
    style: "bg-warning-soft text-warning",
    dot: "bg-warning",
  };
  if (week.draft > 0) return {
    label: `${week.draft} rascunho${week.draft !== 1 ? "s" : ""}`,
    style: "bg-warning-soft text-warning",
    dot: "bg-warning",
  };
  return null;
}

function AthleteCard({ athlete }: { athlete: AthleteOverview }) {
  const badge = getWeekStatusBadge(athlete.current_week);
  const initials = (athlete.display_name || "A").slice(0, 2).toUpperCase();

  return (
    <div className="flex items-center gap-4 rounded-xl border border-border bg-surface px-5 py-4 shadow-sm transition-all hover:border-brand/30 hover:shadow-md">
      {/* Avatar */}
      <div className="flex h-11 w-11 shrink-0 items-center justify-center rounded-full bg-brand-soft text-sm font-bold text-brand">
        {athlete.avatar_url ? (
          <Image
            src={athlete.avatar_url}
            alt={athlete.display_name}
            width={44}
            height={44}
            unoptimized
            className="h-full w-full rounded-full object-cover"
          />
        ) : (
          initials
        )}
      </div>

      {/* Name + week info */}
      <div className="min-w-0 flex-1">
        <div className="flex flex-wrap items-center gap-2">
          <p className="font-semibold text-content-primary truncate">{athlete.display_name}</p>
          {athlete.fatigue_alert && (
            <span
              className="flex items-center gap-1 rounded-full border border-error/30 bg-error-soft px-2 py-0.5 text-[11px] font-semibold text-error"
              title={`Fadiga detectada — RPE médio: ${athlete.avg_rpe_last5?.toFixed(1)}`}
            >
              ⚠️ RPE alto {athlete.avg_rpe_last5 != null ? `(${athlete.avg_rpe_last5.toFixed(1)})` : ""}
            </span>
          )}
        </div>

        {athlete.plan ? (
          <div className="mt-0.5 flex flex-wrap items-center gap-2 text-xs text-content-secondary">
            {athlete.current_week ? (
              <>
                <span>Sem. {athlete.current_week.week_number}</span>
                <span className="text-content-muted">
                  {formatDate(athlete.current_week.starts_on)} – {formatDate(athlete.current_week.ends_on)}
                </span>
                {badge && (
                  <span className={`flex items-center gap-1 rounded-full px-2 py-0.5 font-medium ${badge.style}`}>
                    <span className={`inline-block h-1.5 w-1.5 rounded-full ${badge.dot}`} />
                    {badge.label}
                  </span>
                )}
              </>
            ) : (
              <span className="text-content-muted">Nenhuma semana cadastrada</span>
            )}
          </div>
        ) : (
          <p className="mt-0.5 text-xs text-content-muted italic">Sem planilha ativa</p>
        )}
      </div>

      {/* Action */}
      <div className="shrink-0">
        {athlete.plan ? (
          <Link
            href={`/training-plan/${athlete.plan.id}`}
            className="rounded-lg border border-border px-3 py-1.5 text-xs font-medium text-content-secondary hover:border-brand hover:bg-brand-soft hover:text-brand transition-colors"
          >
            Ver planilha →
          </Link>
        ) : (
          <Link
            href={`/training-plan/new?athleteId=${athlete.user_id}`}
            className="rounded-lg bg-brand px-3 py-1.5 text-xs font-semibold text-white hover:bg-brand/90 transition-colors"
          >
            + Criar planilha
          </Link>
        )}
      </div>
    </div>
  );
}

export function AthleteTrainingView({ groupId }: { groupId: string }) {
  const [athletes, setAthletes] = useState<AthleteOverview[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [search, setSearch] = useState("");

  useEffect(() => {
    setLoading(true);
    fetch("/api/training-plan/athletes-overview")
      .then((r) => r.json())
      .then((json) => {
        if (json.ok) setAthletes(json.data ?? []);
        else setError(json.error?.message ?? "Erro ao carregar");
      })
      .catch(() => setError("Erro ao carregar atletas"))
      .finally(() => setLoading(false));
  }, [groupId]);

  const filtered = useMemo(() => {
    if (!search.trim()) return athletes;
    const q = search.toLowerCase();
    return athletes.filter((a) => a.display_name.toLowerCase().includes(q));
  }, [athletes, search]);

  const withPlan    = filtered.filter((a) => a.plan);
  const withoutPlan = filtered.filter((a) => !a.plan);
  const fatigueCount = filtered.filter((a) => a.fatigue_alert).length;

  if (loading) {
    return (
      <div className="space-y-3">
        {[1, 2, 3].map((i) => (
          <div key={i} className="h-20 animate-pulse rounded-xl bg-surface-elevated" />
        ))}
      </div>
    );
  }

  if (error) {
    return (
      <div className="rounded-xl border border-error/30 bg-error-soft p-6 text-center text-sm text-error">
        {error}
      </div>
    );
  }

  if (athletes.length === 0) {
    return (
      <div className="rounded-xl border border-border bg-surface p-12 text-center shadow-sm">
        <div className="mx-auto mb-4 flex h-14 w-14 items-center justify-center rounded-full bg-brand-soft text-2xl">👤</div>
        <h3 className="text-base font-semibold text-content-primary">Nenhum atleta no grupo</h3>
        <p className="mt-1 text-sm text-content-secondary">
          Adicione atletas ao grupo para gerenciar os treinos.
        </p>
      </div>
    );
  }

  return (
    <div className="space-y-4">
      {/* Summary bar */}
      <div className="flex flex-wrap items-center gap-4 text-sm text-content-secondary">
        <span><strong className="text-content-primary">{athletes.length}</strong> atleta{athletes.length !== 1 ? "s" : ""}</span>
        <span><strong className="text-content-primary">{withPlan.length}</strong> com planilha</span>
        {fatigueCount > 0 && (
          <span className="flex items-center gap-1 font-medium text-error">
            ⚠️ {fatigueCount} alerta{fatigueCount !== 1 ? "s" : ""} de fadiga
          </span>
        )}
      </div>

      {/* Search */}
      <div className="relative">
        <svg className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-content-muted" fill="none" viewBox="0 0 24 24" strokeWidth={1.5} stroke="currentColor">
          <path strokeLinecap="round" strokeLinejoin="round" d="M21 21l-5.197-5.197m0 0A7.5 7.5 0 105.196 5.196a7.5 7.5 0 0010.607 10.607z" />
        </svg>
        <input
          type="text"
          placeholder="Buscar atleta..."
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          className="w-full rounded-lg border border-border bg-surface pl-9 pr-4 py-2 text-sm text-content-primary placeholder:text-content-muted focus:border-brand focus:outline-none"
        />
      </div>

      {/* Athletes with plans */}
      {withPlan.length > 0 && (
        <div className="space-y-2">
          {withPlan.map((a) => <AthleteCard key={a.user_id} athlete={a} />)}
        </div>
      )}

      {/* Athletes without plans */}
      {withoutPlan.length > 0 && (
        <details className="group" open={withPlan.length === 0}>
          <summary className="cursor-pointer list-none">
            <div className="flex items-center gap-2 py-1 text-sm text-content-muted hover:text-content-secondary">
              <svg className="h-4 w-4 transition-transform group-open:rotate-90" fill="none" viewBox="0 0 24 24" strokeWidth={1.5} stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" d="M8.25 4.5l7.5 7.5-7.5 7.5" />
              </svg>
              {withoutPlan.length} atleta{withoutPlan.length !== 1 ? "s" : ""} sem planilha
            </div>
          </summary>
          <div className="mt-2 space-y-2">
            {withoutPlan.map((a) => <AthleteCard key={a.user_id} athlete={a} />)}
          </div>
        </details>
      )}

      {filtered.length === 0 && search && (
        <p className="text-center text-sm text-content-muted py-8">
          Nenhum atleta encontrado para &quot;{search}&quot;
        </p>
      )}
    </div>
  );
}
