"use client";

import { useState, useEffect } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";

interface Athlete {
  id: string;
  name: string;
}

export default function NewTrainingPlanPage() {
  const router = useRouter();
  const [athletes, setAthletes] = useState<Athlete[]>([]);
  const [loadingAthletes, setLoadingAthletes] = useState(true);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const [form, setForm] = useState({
    name: "",
    description: "",
    sport_type: "running",
    athlete_user_id: "",
    starts_on: "",
    ends_on: "",
  });

  useEffect(() => {
    fetch("/api/athletes")
      .then((r) => r.json())
      .then((json) => {
        if (json.ok) {
          setAthletes(
            (json.data ?? []).map((a: Record<string, unknown>) => ({
              id: a.user_id ?? a.id,
              name: (a.full_name ?? a.username ?? "Atleta") as string,
            }))
          );
        }
      })
      .catch(() => {})
      .finally(() => setLoadingAthletes(false));
  }, []);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);
    setSubmitting(true);

    try {
      const res = await fetch("/api/training-plan", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          name: form.name.trim(),
          description: form.description.trim() || undefined,
          sport_type: form.sport_type,
          athlete_user_id: form.athlete_user_id || undefined,
          starts_on: form.starts_on || undefined,
          ends_on: form.ends_on || undefined,
        }),
      });
      const json = await res.json();
      if (!json.ok) throw new Error(json.error?.message ?? "Erro ao criar planilha");
      router.push(`/training-plan/${json.data.id}`);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Erro desconhecido");
      setSubmitting(false);
    }
  };

  return (
    <div className="mx-auto max-w-xl space-y-6">
      <div className="flex items-center gap-3">
        <Link href="/training-plan" className="text-sm text-content-muted hover:text-content-primary">
          ← Planilhas
        </Link>
        <h1 className="text-xl font-bold text-content-primary">Nova Planilha</h1>
      </div>

      <div className="rounded-xl border border-border bg-surface p-6 shadow-sm">
        <form onSubmit={handleSubmit} className="space-y-4">
          {error && (
            <div className="rounded-lg border border-error/30 bg-error-soft px-4 py-3 text-sm text-error">
              {error}
            </div>
          )}

          <div>
            <label className="block text-sm font-medium text-content-primary">Nome da planilha *</label>
            <input
              type="text"
              required
              minLength={2}
              maxLength={120}
              value={form.name}
              onChange={(e) => setForm((f) => ({ ...f, name: e.target.value }))}
              placeholder="Ex: Preparação Maratona SP 2026"
              className="mt-1 block w-full rounded-lg border border-border bg-bg-secondary px-3 py-2 text-sm text-content-primary placeholder-content-muted focus:border-brand focus:outline-none focus:ring-1 focus:ring-brand"
            />
          </div>

          <div>
            <label className="block text-sm font-medium text-content-primary">Descrição</label>
            <textarea
              rows={2}
              maxLength={500}
              value={form.description}
              onChange={(e) => setForm((f) => ({ ...f, description: e.target.value }))}
              placeholder="Objetivo da planilha (opcional)"
              className="mt-1 block w-full rounded-lg border border-border bg-bg-secondary px-3 py-2 text-sm text-content-primary placeholder-content-muted focus:border-brand focus:outline-none focus:ring-1 focus:ring-brand"
            />
          </div>

          <div>
            <label className="block text-sm font-medium text-content-primary">Modalidade</label>
            <select
              value={form.sport_type}
              onChange={(e) => setForm((f) => ({ ...f, sport_type: e.target.value }))}
              className="mt-1 block w-full rounded-lg border border-border bg-bg-secondary px-3 py-2 text-sm text-content-primary focus:border-brand focus:outline-none focus:ring-1 focus:ring-brand"
            >
              <option value="running">Corrida</option>
              <option value="cycling">Ciclismo</option>
              <option value="triathlon">Triathlon</option>
              <option value="swimming">Natação</option>
              <option value="strength">Força</option>
              <option value="multi">Multi-esporte</option>
            </select>
          </div>

          <div>
            <label className="block text-sm font-medium text-content-primary">Atleta</label>
            {loadingAthletes ? (
              <div className="mt-1 h-9 rounded-lg bg-surface-elevated animate-pulse" />
            ) : (
              <select
                value={form.athlete_user_id}
                onChange={(e) => setForm((f) => ({ ...f, athlete_user_id: e.target.value }))}
                className="mt-1 block w-full rounded-lg border border-border bg-bg-secondary px-3 py-2 text-sm text-content-primary focus:border-brand focus:outline-none focus:ring-1 focus:ring-brand"
              >
                <option value="">— Modelo de grupo (sem atleta específico) —</option>
                {athletes.map((a) => (
                  <option key={a.id} value={a.id}>{a.name}</option>
                ))}
              </select>
            )}
          </div>

          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className="block text-sm font-medium text-content-primary">Início</label>
              <input
                type="date"
                value={form.starts_on}
                onChange={(e) => setForm((f) => ({ ...f, starts_on: e.target.value }))}
                className="mt-1 block w-full rounded-lg border border-border bg-bg-secondary px-3 py-2 text-sm text-content-primary focus:border-brand focus:outline-none focus:ring-1 focus:ring-brand"
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-content-primary">Fim</label>
              <input
                type="date"
                value={form.ends_on}
                min={form.starts_on || undefined}
                onChange={(e) => setForm((f) => ({ ...f, ends_on: e.target.value }))}
                className="mt-1 block w-full rounded-lg border border-border bg-bg-secondary px-3 py-2 text-sm text-content-primary focus:border-brand focus:outline-none focus:ring-1 focus:ring-brand"
              />
            </div>
          </div>

          <div className="flex gap-3 pt-2">
            <Link
              href="/training-plan"
              className="flex-1 rounded-lg border border-border px-4 py-2.5 text-center text-sm font-medium text-content-secondary hover:bg-surface-elevated"
            >
              Cancelar
            </Link>
            <button
              type="submit"
              disabled={submitting || !form.name.trim()}
              className="flex-1 rounded-lg bg-brand px-4 py-2.5 text-sm font-medium text-white hover:bg-brand/90 disabled:opacity-60"
            >
              {submitting ? "Criando..." : "Criar Planilha"}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
