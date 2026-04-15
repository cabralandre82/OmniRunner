"use client";

import { useEffect, useState, useMemo } from "react";
import {
  WorkoutTemplate,
  WorkoutPickResult,
  ReleaseBlock,
  WORKOUT_TYPE_LABEL,
  WorkoutType,
  formatDistanceM,
} from "./types";
import { BlockEditor } from "./block-editor";

interface WorkoutPickerDrawerProps {
  open: boolean;
  targetDate: string | null;
  targetDayLabel: string;
  groupId: string;
  onPick: (result: WorkoutPickResult) => void;
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

const WORKOUT_TYPES = Object.keys(WORKOUT_TYPE_LABEL) as WorkoutType[];

type DrawerTab = "templates" | "describe" | "ai";

export function WorkoutPickerDrawer({
  open,
  targetDate,
  targetDayLabel,
  groupId,
  onPick,
  onClose,
  loading = false,
}: WorkoutPickerDrawerProps) {
  const [tab, setTab] = useState<DrawerTab>("templates");

  // ── Templates tab state ───────────────────────────────────────────────────
  const [templates, setTemplates] = useState<WorkoutTemplate[]>([]);
  const [fetching, setFetching] = useState(false);
  const [search, setSearch] = useState("");
  const [filterType, setFilterType] = useState<WorkoutType | "all">("all");

  // ── Describe tab state ────────────────────────────────────────────────────
  const [descLabel, setDescLabel] = useState("");
  const [descDescription, setDescDescription] = useState("");
  const [descType, setDescType] = useState<WorkoutType>("continuous");
  const [descNotes, setDescNotes] = useState("");
  const [descVideo, setDescVideo] = useState("");
  const [descBlocks, setDescBlocks] = useState<ReleaseBlock[]>([]);

  // ── AI tab state ──────────────────────────────────────────────────────────
  const [aiText, setAiText] = useState("");
  const [aiLoading, setAiLoading] = useState(false);
  const [aiResult, setAiResult] = useState<{
    workout_type: WorkoutType;
    workout_label: string;
    description: string | null;
    coach_notes: string | null;
    estimated_distance_km: number | null;
    estimated_duration_minutes: number | null;
    blocks: ReleaseBlock[];
  } | null>(null);
  const [aiError, setAiError] = useState<string | null>(null);

  useEffect(() => {
    if (!open) {
      setTab("templates");
      setSearch("");
      setFilterType("all");
      setDescLabel("");
      setDescDescription("");
      setDescType("continuous");
      setDescNotes("");
      setDescVideo("");
      setDescBlocks([]);
      setAiText("");
      setAiResult(null);
      setAiError(null);
    }
  }, [open]);

  useEffect(() => {
    if (!open || !groupId || tab !== "templates") return;
    setFetching(true);
    fetch(`/api/training-plan/templates?groupId=${groupId}`)
      .then((r) => r.json())
      .then((j) => { if (j.ok) setTemplates(j.data ?? []); })
      .catch(() => {})
      .finally(() => setFetching(false));
  }, [open, groupId, tab]);

  const filtered = useMemo(() => {
    let list = templates;
    if (filterType !== "all") list = list.filter((t) => t.workout_type === filterType);
    if (search.trim()) {
      const q = search.toLowerCase();
      list = list.filter((t) => t.name.toLowerCase().includes(q));
    }
    return list;
  }, [templates, search, filterType]);

  const grouped = useMemo(() => {
    const map = new Map<string, WorkoutTemplate[]>();
    for (const t of filtered) {
      if (!map.has(t.workout_type)) map.set(t.workout_type, []);
      map.get(t.workout_type)!.push(t);
    }
    return map;
  }, [filtered]);

  const allTypes = Array.from(new Set(templates.map((t) => t.workout_type))) as WorkoutType[];

  // ── Handlers ──────────────────────────────────────────────────────────────

  function handleDescribeSubmit() {
    if (!descLabel.trim()) return;
    onPick({
      mode: "descriptive",
      label: descLabel.trim(),
      description: descDescription.trim() || undefined,
      workout_type: descType,
      coach_notes: descNotes.trim() || undefined,
      video_url: descVideo.trim() || undefined,
      blocks: descBlocks.length > 0 ? descBlocks : undefined,
    });
  }

  async function handleAiParse() {
    if (!aiText.trim()) return;
    setAiLoading(true);
    setAiResult(null);
    setAiError(null);
    try {
      const res = await fetch("/api/training-plan/ai/parse-workout", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ text: aiText }),
      });
      const json = await res.json();
      if (!json.ok) throw new Error(json.error?.message ?? "Erro da IA");
      setAiResult(json.data);
    } catch (e) {
      setAiError(e instanceof Error ? e.message : "Erro ao interpretar");
    } finally {
      setAiLoading(false);
    }
  }

  function handleUseAiResult() {
    if (!aiResult) return;
    onPick({
      mode: "descriptive",
      label: aiResult.workout_label,
      description: aiResult.description ?? undefined,
      workout_type: aiResult.workout_type,
      coach_notes: aiResult.coach_notes ?? undefined,
      blocks: aiResult.blocks.length > 0 ? aiResult.blocks : undefined,
    });
  }

  const tabClass = (t: DrawerTab) =>
    `flex-1 py-2 text-xs font-semibold rounded-lg transition-colors ${
      tab === t
        ? "bg-brand text-white"
        : "text-content-secondary hover:bg-surface-elevated"
    }`;

  return (
    <>
      {open && (
        <div className="fixed inset-0 z-40 bg-overlay/60" onClick={onClose} aria-hidden="true" />
      )}

      <aside
        className={`fixed inset-y-0 right-0 z-50 flex w-full max-w-sm flex-col bg-surface shadow-xl transition-transform duration-300 ${
          open ? "translate-x-0" : "translate-x-full"
        }`}
      >
        {/* Header */}
        <div className="flex items-center justify-between border-b border-border px-5 py-4">
          <div>
            <h2 className="text-base font-semibold text-content-primary">Adicionar treino</h2>
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

        {/* Tab selector */}
        <div className="flex gap-1 border-b border-border px-4 py-3">
          <button onClick={() => setTab("templates")} className={tabClass("templates")}>
            📋 Templates
          </button>
          <button onClick={() => setTab("describe")} className={tabClass("describe")}>
            ✍️ Descrever
          </button>
          <button onClick={() => setTab("ai")} className={tabClass("ai")}>
            ✨ IA
          </button>
        </div>

        {/* ── TEMPLATES TAB ───────────────────────────────────────────────── */}
        {tab === "templates" && (
          <>
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
              <div className="flex flex-wrap gap-1.5">
                <button
                  onClick={() => setFilterType("all")}
                  className={`rounded-full px-2.5 py-0.5 text-xs font-medium transition-colors ${
                    filterType === "all" ? "bg-brand text-white" : "bg-surface-elevated text-content-secondary hover:bg-brand-soft hover:text-brand"
                  }`}
                >
                  Todos
                </button>
                {allTypes.map((t) => (
                  <button
                    key={t}
                    onClick={() => setFilterType(t === filterType ? "all" : t)}
                    className={`rounded-full px-2.5 py-0.5 text-xs font-medium transition-colors ${
                      filterType === t ? "bg-brand text-white" : "bg-surface-elevated text-content-secondary hover:bg-brand-soft hover:text-brand"
                    }`}
                  >
                    {TYPE_ICONS[t]} {WORKOUT_TYPE_LABEL[t as WorkoutType] ?? t}
                  </button>
                ))}
              </div>
            </div>

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
                  <p className="mt-1 text-xs text-content-muted">
                    Use a aba <strong>✍️ Descrever</strong> para prescrever sem template.
                  </p>
                  <a href="/workouts" target="_blank" className="mt-2 text-xs text-brand underline">
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
                          onClick={() => onPick({ mode: "template", template })}
                          disabled={loading}
                          className="group w-full px-4 py-3 text-left transition-colors hover:bg-brand-soft disabled:opacity-60"
                        >
                          <div className="flex items-start justify-between gap-3">
                            <div className="min-w-0">
                              <p className="truncate text-sm font-medium text-content-primary group-hover:text-brand">
                                {template.name}
                              </p>
                              {template.description && (
                                <p className="mt-0.5 truncate text-xs text-content-muted">{template.description}</p>
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
          </>
        )}

        {/* ── DESCRIBE TAB ────────────────────────────────────────────────── */}
        {tab === "describe" && (
          <div className="flex flex-1 flex-col overflow-y-auto">
            <div className="flex-1 space-y-4 px-5 py-4">
              <p className="text-xs text-content-muted">
                Prescreva um treino escrevendo diretamente. Ideal para treinos específicos
                que não precisam de um template reutilizável.
              </p>

              <div>
                <label className="mb-1.5 block text-xs font-medium text-content-secondary">
                  Nome do treino *
                </label>
                <input
                  type="text"
                  value={descLabel}
                  onChange={(e) => setDescLabel(e.target.value)}
                  placeholder="ex: Longão progressivo 18km"
                  maxLength={60}
                  className="w-full rounded-lg border border-border bg-bg-secondary px-3 py-2 text-sm text-content-primary placeholder:text-content-muted focus:border-brand focus:outline-none"
                />
              </div>

              <div>
                <label className="mb-1.5 block text-xs font-medium text-content-secondary">
                  Tipo de treino
                </label>
                <select
                  value={descType}
                  onChange={(e) => setDescType(e.target.value as WorkoutType)}
                  className="w-full rounded-lg border border-border bg-bg-secondary px-3 py-2 text-sm text-content-primary focus:border-brand focus:outline-none"
                >
                  {WORKOUT_TYPES.map((t) => (
                    <option key={t} value={t}>
                      {TYPE_ICONS[t]} {WORKOUT_TYPE_LABEL[t]}
                    </option>
                  ))}
                </select>
              </div>

              <div>
                <label className="mb-1.5 block text-xs font-medium text-content-secondary">
                  Descrição do treino
                </label>
                <textarea
                  value={descDescription}
                  onChange={(e) => setDescDescription(e.target.value)}
                  rows={4}
                  placeholder="ex: 5km aquecimento leve + 10km progressivo (6:00 → 5:15/km) + 3km cooldown"
                  maxLength={2000}
                  className="w-full resize-none rounded-lg border border-border bg-bg-secondary px-3 py-2 text-sm text-content-primary placeholder:text-content-muted focus:border-brand focus:outline-none"
                />
              </div>

              <div>
                <label className="mb-1.5 block text-xs font-medium text-content-secondary">
                  Observações para o atleta (opcional)
                </label>
                <textarea
                  value={descNotes}
                  onChange={(e) => setDescNotes(e.target.value)}
                  rows={2}
                  placeholder="ex: Beba 500ml antes. Não acelere nos primeiros 3km."
                  maxLength={500}
                  className="w-full resize-none rounded-lg border border-border bg-bg-secondary px-3 py-2 text-sm text-content-primary placeholder:text-content-muted focus:border-brand focus:outline-none"
                />
              </div>

              <div>
                <label className="mb-1.5 block text-xs font-medium text-content-secondary">
                  Link de vídeo explicativo (opcional)
                </label>
                <input
                  type="url"
                  value={descVideo}
                  onChange={(e) => setDescVideo(e.target.value)}
                  placeholder="https://youtube.com/watch?v=..."
                  className="w-full rounded-lg border border-border bg-bg-secondary px-3 py-2 text-sm text-content-primary placeholder:text-content-muted focus:border-brand focus:outline-none"
                />
              </div>

              <div>
                <label className="mb-1.5 block text-xs font-semibold text-content-secondary">
                  🧩 Blocos estruturados{" "}
                  <span className="font-normal text-content-muted">(para relógio GPS)</span>
                </label>
                <p className="mb-2 text-[11px] text-content-muted">
                  Opcional. Adicione blocos com pace/FC/distância para que o relógio guie o atleta fase a fase.
                </p>
                <BlockEditor blocks={descBlocks} onChange={setDescBlocks} />
              </div>
            </div>

            <div className="border-t border-border px-4 py-3">
              <button
                onClick={handleDescribeSubmit}
                disabled={loading || !descLabel.trim()}
                className="w-full rounded-lg bg-brand py-2.5 text-sm font-semibold text-white hover:bg-brand/90 disabled:opacity-60"
              >
                {loading ? "Adicionando..." : "Adicionar treino"}
              </button>
            </div>
          </div>
        )}

        {/* ── AI TAB ──────────────────────────────────────────────────────── */}
        {tab === "ai" && (
          <div className="flex flex-1 flex-col overflow-y-auto">
            <div className="flex-1 space-y-4 px-5 py-4">
              <div className="rounded-lg border border-brand/20 bg-brand-soft p-3 text-xs text-brand">
                <p className="font-semibold">✨ Criação com IA</p>
                <p className="mt-1 text-brand/80">
                  Descreva o treino em linguagem natural. A IA interpreta e estrutura
                  automaticamente. Requer OPENAI_API_KEY configurada.
                </p>
              </div>

              <div>
                <label className="mb-1.5 block text-xs font-medium text-content-secondary">
                  Descreva o treino
                </label>
                <textarea
                  value={aiText}
                  onChange={(e) => setAiText(e.target.value)}
                  rows={5}
                  placeholder="ex: 30min leve, 4x1km em 4:30 com 2min de descanso, ou longão de 25km no domingo"
                  maxLength={1000}
                  className="w-full resize-none rounded-lg border border-border bg-bg-secondary px-3 py-2 text-sm text-content-primary placeholder:text-content-muted focus:border-brand focus:outline-none"
                />
              </div>

              <button
                onClick={handleAiParse}
                disabled={aiLoading || !aiText.trim()}
                className="flex w-full items-center justify-center gap-2 rounded-lg bg-brand py-2.5 text-sm font-semibold text-white hover:bg-brand/90 disabled:opacity-60"
              >
                {aiLoading ? (
                  <>
                    <svg className="h-4 w-4 animate-spin" fill="none" viewBox="0 0 24 24">
                      <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
                      <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
                    </svg>
                    Interpretando...
                  </>
                ) : (
                  "✨ Interpretar com IA"
                )}
              </button>

              {aiError && (
                <div className="rounded-lg border border-error/30 bg-error-soft p-3 text-sm text-error">
                  {aiError}
                </div>
              )}

              {aiResult && (
                <div className="rounded-xl border border-brand/30 bg-brand-soft/30 p-4 space-y-2">
                  <p className="text-xs font-semibold uppercase tracking-wide text-brand">Resultado interpretado</p>
                  <p className="text-sm font-semibold text-content-primary">
                    {TYPE_ICONS[aiResult.workout_type]} {aiResult.workout_label}
                  </p>
                  <p className="text-xs text-content-secondary">
                    {WORKOUT_TYPE_LABEL[aiResult.workout_type] ?? aiResult.workout_type}
                    {aiResult.estimated_distance_km != null && ` · 📏 ${aiResult.estimated_distance_km} km`}
                    {aiResult.estimated_duration_minutes != null && ` · ⏱ ${aiResult.estimated_duration_minutes} min`}
                  </p>
                  {aiResult.description && (
                    <p className="text-xs text-content-secondary italic">{aiResult.description}</p>
                  )}
                  {aiResult.coach_notes && (
                    <p className="text-xs text-brand">📌 {aiResult.coach_notes}</p>
                  )}
                  {aiResult.blocks.length > 0 && (
                    <div className="mt-1">
                      <p className="mb-1 text-[11px] font-semibold uppercase tracking-wide text-content-muted">
                        🧩 {aiResult.blocks.length} blocos gerados
                      </p>
                      <BlockEditor blocks={aiResult.blocks} onChange={() => {}} readOnly />
                    </div>
                  )}
                  <button
                    onClick={handleUseAiResult}
                    disabled={loading}
                    className="mt-1 w-full rounded-lg bg-brand py-2 text-sm font-semibold text-white hover:bg-brand/90 disabled:opacity-60"
                  >
                    {loading ? "Adicionando..." : "Usar este treino"}
                  </button>
                </div>
              )}
            </div>
          </div>
        )}
      </aside>
    </>
  );
}
