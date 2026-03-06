"use client";

import { useState, useMemo } from "react";
import { useRouter } from "next/navigation";

/* ── Interfaces ─────────────────────────────────────────────── */

interface Athlete {
  member_id: string;
  user_id: string;
  display_name: string;
  watch_type: string | null;
  linked_provider: string | null;
  recent_assignments: {
    id: string;
    scheduled_date: string;
    status: string;
    template_name: string;
  }[];
}

interface TemplateBlock {
  id: string;
  order_index: number;
  block_type: string;
  duration_seconds: number | null;
  distance_meters: number | null;
  target_pace_min_sec_per_km: number | null;
  target_pace_max_sec_per_km: number | null;
  target_hr_zone: number | null;
  target_hr_min: number | null;
  target_hr_max: number | null;
  rpe_target: number | null;
  repeat_count: number | null;
  notes: string | null;
}

interface Template {
  id: string;
  name: string;
  block_count: number;
  blocks?: TemplateBlock[];
}

/* ── Constants ──────────────────────────────────────────────── */

const WATCH_LABELS: Record<string, string> = {
  garmin: "Garmin",
  coros: "COROS",
  suunto: "Suunto",
  apple_watch: "Apple Watch",
  polar: "Polar",
  other: "Outro",
};
const WATCH_COLORS: Record<string, string> = {
  garmin:
    "bg-green-100 text-green-800 dark:bg-green-900/30 dark:text-green-300",
  coros: "bg-green-100 text-green-800 dark:bg-green-900/30 dark:text-green-300",
  suunto:
    "bg-green-100 text-green-800 dark:bg-green-900/30 dark:text-green-300",
  polar:
    "bg-yellow-100 text-yellow-800 dark:bg-yellow-900/30 dark:text-yellow-300",
  apple_watch:
    "bg-orange-100 text-orange-800 dark:bg-orange-900/30 dark:text-orange-300",
  other:
    "bg-gray-100 text-gray-700 dark:bg-gray-700/30 dark:text-gray-300",
};
const FIT_COMPATIBLE = new Set(["garmin", "coros", "suunto"]);

const STATUS_LABELS: Record<string, string> = {
  planned: "Planejado",
  completed: "Concluído",
  missed: "Perdido",
};
const STATUS_COLORS: Record<string, string> = {
  planned:
    "bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-300",
  completed:
    "bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-300",
  missed:
    "bg-red-100 text-red-700 dark:bg-red-900/30 dark:text-red-300",
};

const BLOCK_TYPE_LABELS: Record<string, string> = {
  warmup: "Aquecimento",
  interval: "Intervalo",
  recovery: "Recuperação",
  cooldown: "Desaquecimento",
  steady: "Contínuo",
  rest: "Descanso",
  repeat: "Repetir",
};
const BLOCK_TYPE_COLORS: Record<string, string> = {
  warmup:
    "bg-yellow-100 text-yellow-800 dark:bg-yellow-900/30 dark:text-yellow-300",
  interval:
    "bg-red-100 text-red-800 dark:bg-red-900/30 dark:text-red-300",
  recovery:
    "bg-green-100 text-green-800 dark:bg-green-900/30 dark:text-green-300",
  cooldown:
    "bg-blue-100 text-blue-800 dark:bg-blue-900/30 dark:text-blue-300",
  steady:
    "bg-emerald-100 text-emerald-800 dark:bg-emerald-900/30 dark:text-emerald-300",
  rest: "bg-gray-100 text-gray-800 dark:bg-gray-700/30 dark:text-gray-300",
  repeat:
    "bg-purple-100 text-purple-800 dark:bg-purple-900/30 dark:text-purple-300",
};

const BLOCK_TYPES = [
  { value: "warmup", label: "Aquecimento" },
  { value: "interval", label: "Intervalo" },
  { value: "recovery", label: "Recuperação" },
  { value: "cooldown", label: "Desaquecimento" },
  { value: "steady", label: "Contínuo" },
  { value: "rest", label: "Descanso" },
  { value: "repeat", label: "Repetir" },
];

/* ── Helpers ────────────────────────────────────────────────── */

function fmtPace(s: number) {
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
}
function fmtDist(m: number) {
  return m >= 1000 ? `${(m / 1000).toFixed(1)} km` : `${m} m`;
}
function fmtDur(s: number) {
  const min = Math.floor(s / 60);
  const sec = s % 60;
  return sec > 0 ? `${min}m${sec}s` : `${min} min`;
}

function blockDetails(b: TemplateBlock): string {
  const d: string[] = [];
  if (b.block_type === "repeat" && b.repeat_count) d.push(`${b.repeat_count}x`);
  if (b.duration_seconds) d.push(fmtDur(b.duration_seconds));
  if (b.distance_meters) d.push(fmtDist(b.distance_meters));
  if (!b.duration_seconds && !b.distance_meters && b.block_type !== "repeat")
    d.push("livre");
  if (b.target_pace_min_sec_per_km && b.target_pace_max_sec_per_km) {
    const mn = fmtPace(b.target_pace_min_sec_per_km);
    const mx = fmtPace(b.target_pace_max_sec_per_km);
    d.push(mn === mx ? `${mn}/km` : `${mn}–${mx}/km`);
  }
  if (b.target_hr_zone) d.push(`Z${b.target_hr_zone}`);
  if (b.target_hr_min && b.target_hr_max)
    d.push(`${b.target_hr_min}–${b.target_hr_max} bpm`);
  if (b.rpe_target) d.push(`RPE ${b.rpe_target}`);
  return d.join(" · ");
}

/* ── Main Component ─────────────────────────────────────────── */

export function AssignWorkoutClient({
  athletes,
  templates,
}: {
  athletes: Athlete[];
  templates: Template[];
}) {
  const router = useRouter();

  // Step 1 state
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());
  const [search, setSearch] = useState("");
  const [watchFilter, setWatchFilter] = useState("all");
  const [editingWatch, setEditingWatch] = useState<string | null>(null);

  // Step 2 state
  const [mode, setMode] = useState<"template" | "create" | null>(null);
  const [templateId, setTemplateId] = useState("");
  const [previewBlocks, setPreviewBlocks] = useState<TemplateBlock[]>([]);
  const [loadingPreview, setLoadingPreview] = useState(false);
  const [newBlocks, setNewBlocks] = useState<TemplateBlock[]>([]);
  const [newName, setNewName] = useState("");
  const [newDescription, setNewDescription] = useState("");
  const [showBlockForm, setShowBlockForm] = useState(false);

  // Step 3 state
  const [date, setDate] = useState(() => new Date().toISOString().split("T")[0]);
  const [loading, setLoading] = useState(false);
  const [result, setResult] = useState<{
    ok: boolean;
    success: number;
    total: number;
  } | null>(null);

  const selectedCount = selectedIds.size;
  const hasStep1 = selectedCount > 0;
  const hasStep2 =
    mode === "template" ? !!templateId : mode === "create" ? newBlocks.length > 0 && newName.trim().length >= 2 : false;

  /* ── Filtering ──────────────────────────────────────── */

  const filteredAthletes = useMemo(
    () =>
      athletes.filter((a) => {
        if (search && !a.display_name.toLowerCase().includes(search.toLowerCase()))
          return false;
        if (watchFilter === "fit" && !FIT_COMPATIBLE.has(a.watch_type ?? ""))
          return false;
        if (watchFilter === "no_fit" && FIT_COMPATIBLE.has(a.watch_type ?? ""))
          return false;
        if (watchFilter === "unknown" && a.watch_type != null) return false;
        return true;
      }),
    [athletes, search, watchFilter],
  );

  const allVisibleSelected =
    filteredAthletes.length > 0 &&
    filteredAthletes.every((a) => selectedIds.has(a.user_id));

  /* ── Handlers ───────────────────────────────────────── */

  const toggleSelection = (userId: string) => {
    setSelectedIds((prev) => {
      const next = new Set(prev);
      if (next.has(userId)) next.delete(userId);
      else next.add(userId);
      return next;
    });
  };

  const selectAll = () => {
    const visible = filteredAthletes.map((a) => a.user_id);
    setSelectedIds((prev) => {
      const next = new Set(prev);
      const all = visible.every((id) => next.has(id));
      if (all) visible.forEach((id) => next.delete(id));
      else visible.forEach((id) => next.add(id));
      return next;
    });
  };

  const handleWatchTypeChange = async (memberId: string, newType: string | null) => {
    try {
      await fetch("/api/workouts/watch-type", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ member_id: memberId, watch_type: newType }),
      });
      setEditingWatch(null);
      router.refresh();
    } catch {
      /* silent */
    }
  };

  const handleTemplateSelect = async (tid: string) => {
    setTemplateId(tid);
    if (!tid) {
      setPreviewBlocks([]);
      return;
    }
    setLoadingPreview(true);
    try {
      const res = await fetch(`/api/workouts/templates/blocks?template_id=${tid}`);
      const data = await res.json();
      setPreviewBlocks(data.blocks ?? []);
    } catch {
      setPreviewBlocks([]);
    } finally {
      setLoadingPreview(false);
    }
  };

  const handleAssign = async () => {
    setLoading(true);
    setResult(null);

    try {
      let assignTemplateId = templateId;

      if (mode === "create") {
        const createRes = await fetch("/api/workouts/templates", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            name: newName,
            description: newDescription,
            blocks: newBlocks,
          }),
        });
        const createData = await createRes.json();
        if (!createData.ok) {
          setResult({ ok: false, success: 0, total: selectedCount });
          return;
        }
        assignTemplateId = createData.id;
      }

      const res = await fetch("/api/workouts/assign", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          template_id: assignTemplateId,
          athlete_user_ids: Array.from(selectedIds),
          scheduled_date: date,
        }),
      });
      const data = await res.json();
      setResult({ ok: data.ok, success: data.success, total: data.total });
      if (data.ok) {
        setSelectedIds(new Set());
        setMode(null);
        setTemplateId("");
        setPreviewBlocks([]);
        setNewBlocks([]);
        setNewName("");
        setNewDescription("");
        router.refresh();
      }
    } finally {
      setLoading(false);
    }
  };

  const addNewBlock = (block: TemplateBlock) => {
    setNewBlocks((prev) => [...prev, { ...block, order_index: prev.length }]);
    setShowBlockForm(false);
  };

  const removeNewBlock = (id: string) => {
    setNewBlocks((prev) =>
      prev.filter((b) => b.id !== id).map((b, i) => ({ ...b, order_index: i })),
    );
  };

  /* ── Step indicator ─────────────────────────────────── */

  const currentStep = !hasStep1 ? 1 : !hasStep2 ? 2 : 3;

  const selectedNames = useMemo(() => {
    if (selectedCount === 0) return "";
    const names = athletes
      .filter((a) => selectedIds.has(a.user_id))
      .map((a) => a.display_name);
    if (names.length <= 3) return names.join(", ");
    return `${names.slice(0, 3).join(", ")} e mais ${names.length - 3}`;
  }, [athletes, selectedIds, selectedCount]);

  const chosenTemplateName =
    mode === "template"
      ? templates.find((t) => t.id === templateId)?.name ?? ""
      : mode === "create"
        ? newName
        : "";

  return (
    <div className="space-y-6">
      {/* ── Step Indicator ─────────────────────────────── */}
      <div className="flex items-center gap-2">
        {[1, 2, 3].map((step) => (
          <div key={step} className="flex items-center gap-2">
            <div
              className={`flex h-8 w-8 items-center justify-center rounded-full text-sm font-bold transition-colors ${
                step < currentStep
                  ? "bg-green-500 text-white"
                  : step === currentStep
                    ? "bg-brand text-white"
                    : "bg-surface-elevated text-content-muted"
              }`}
            >
              {step < currentStep ? "✓" : step}
            </div>
            <span
              className={`text-sm font-medium ${
                step === currentStep
                  ? "text-content-primary"
                  : "text-content-muted"
              }`}
            >
              {step === 1
                ? "Selecione os atletas"
                : step === 2
                  ? "Escolha o treino"
                  : "Confirme e atribua"}
            </span>
            {step < 3 && (
              <div className="mx-2 h-px w-8 bg-border" />
            )}
          </div>
        ))}
      </div>

      {/* ── STEP 1: Select athletes ───────────────────── */}
      <div className="rounded-xl border border-border bg-surface shadow-sm">
        <div className="border-b border-border px-6 py-4">
          <div className="flex items-center justify-between">
            <div>
              <h2 className="text-lg font-semibold text-content-primary">
                Passo 1 — Selecione os atletas
              </h2>
              <p className="mt-0.5 text-sm text-content-secondary">
                {selectedCount === 0
                  ? "Clique nos atletas para selecioná-los"
                  : `${selectedCount} atleta${selectedCount !== 1 ? "s" : ""} selecionado${selectedCount !== 1 ? "s" : ""}`}
              </p>
            </div>
            <div className="flex items-center gap-2">
              <input
                type="text"
                placeholder="Buscar..."
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                className="rounded-lg border border-border bg-surface px-3 py-1.5 text-sm focus:border-brand focus:ring-1 focus:ring-brand"
              />
              <select
                value={watchFilter}
                onChange={(e) => setWatchFilter(e.target.value)}
                className="rounded-lg border border-border bg-surface px-3 py-1.5 text-sm focus:border-brand focus:ring-1 focus:ring-brand"
              >
                <option value="all">Todos</option>
                <option value="fit">.FIT</option>
                <option value="no_fit">Manual</option>
                <option value="unknown">Sem relógio</option>
              </select>
            </div>
          </div>
        </div>

        <div className="overflow-x-auto">
          <table className="min-w-full divide-y divide-border text-sm">
            <thead className="bg-bg-secondary">
              <tr>
                <th className="w-10 px-4 py-3">
                  <input
                    type="checkbox"
                    checked={allVisibleSelected}
                    onChange={selectAll}
                    className="rounded border-border text-brand focus:ring-brand"
                  />
                </th>
                <th className="px-4 py-3 text-left font-medium text-content-secondary">
                  Atleta
                </th>
                <th className="px-4 py-3 text-center font-medium text-content-secondary">
                  Relógio
                </th>
                <th className="px-4 py-3 text-center font-medium text-content-secondary">
                  .FIT
                </th>
                <th className="px-4 py-3 text-left font-medium text-content-secondary">
                  Últimos treinos
                </th>
              </tr>
            </thead>
            <tbody className="divide-y divide-border-subtle">
              {filteredAthletes.map((athlete) => {
                const selected = selectedIds.has(athlete.user_id);
                const fitOk = FIT_COMPATIBLE.has(athlete.watch_type ?? "");
                return (
                  <tr
                    key={athlete.member_id}
                    className={`cursor-pointer transition-colors ${
                      selected
                        ? "bg-brand/5 dark:bg-brand/10"
                        : "hover:bg-surface-elevated"
                    }`}
                    onClick={() => toggleSelection(athlete.user_id)}
                  >
                    <td
                      className="px-4 py-3"
                      onClick={(e) => e.stopPropagation()}
                    >
                      <input
                        type="checkbox"
                        checked={selected}
                        onChange={() => toggleSelection(athlete.user_id)}
                        className="rounded border-border text-brand focus:ring-brand"
                      />
                    </td>
                    <td className="whitespace-nowrap px-4 py-3 font-medium text-content-primary">
                      {athlete.display_name}
                    </td>
                    <td
                      className="whitespace-nowrap px-4 py-3 text-center"
                      onClick={(e) => e.stopPropagation()}
                    >
                      {editingWatch === athlete.member_id ? (
                        <select
                          defaultValue={athlete.watch_type ?? ""}
                          onChange={(e) =>
                            handleWatchTypeChange(
                              athlete.member_id,
                              e.target.value || null,
                            )
                          }
                          onBlur={() => setEditingWatch(null)}
                          autoFocus
                          className="rounded border border-border bg-surface px-2 py-1 text-xs focus:border-brand focus:ring-1 focus:ring-brand"
                        >
                          <option value="">Auto-detectar</option>
                          <option value="garmin">Garmin</option>
                          <option value="coros">COROS</option>
                          <option value="suunto">Suunto</option>
                          <option value="apple_watch">Apple Watch</option>
                          <option value="polar">Polar</option>
                          <option value="other">Outro</option>
                        </select>
                      ) : (
                        <button
                          onClick={() => setEditingWatch(athlete.member_id)}
                          className={`inline-block rounded-full px-2.5 py-0.5 text-xs font-medium ${
                            athlete.watch_type
                              ? (WATCH_COLORS[athlete.watch_type] ??
                                WATCH_COLORS.other)
                              : "bg-gray-100 text-gray-500 dark:bg-gray-700/30 dark:text-gray-400"
                          }`}
                          title="Clique para alterar"
                        >
                          {athlete.watch_type
                            ? (WATCH_LABELS[athlete.watch_type] ??
                              athlete.watch_type)
                            : "Definir"}
                        </button>
                      )}
                    </td>
                    <td className="whitespace-nowrap px-4 py-3 text-center">
                      {fitOk ? (
                        <span className="text-green-600 dark:text-green-400" title="Compatível .FIT">✓</span>
                      ) : athlete.watch_type ? (
                        <span className="text-orange-500 dark:text-orange-400" title="Envio manual">⚠</span>
                      ) : (
                        <span className="text-gray-400">—</span>
                      )}
                    </td>
                    <td
                      className="px-4 py-3"
                      onClick={(e) => e.stopPropagation()}
                    >
                      <div className="flex flex-wrap gap-1.5">
                        {athlete.recent_assignments.length === 0 && (
                          <span className="text-xs text-content-secondary">
                            Nenhum treino recente
                          </span>
                        )}
                        {athlete.recent_assignments.slice(0, 3).map((a) => (
                          <span
                            key={a.id}
                            className={`inline-block rounded px-2 py-0.5 text-xs ${
                              STATUS_COLORS[a.status] ?? STATUS_COLORS.planned
                            }`}
                            title={`${a.template_name} — ${a.scheduled_date}`}
                          >
                            {new Date(
                              a.scheduled_date + "T12:00:00",
                            ).toLocaleDateString("pt-BR", {
                              day: "2-digit",
                              month: "2-digit",
                            })}{" "}
                            {STATUS_LABELS[a.status] ?? a.status}
                          </span>
                        ))}
                      </div>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>

        {filteredAthletes.length === 0 && (
          <div className="p-6 text-center text-sm text-content-secondary">
            Nenhum atleta encontrado.
          </div>
        )}
      </div>

      {/* ── STEP 2: Choose workout (only visible when athletes selected) ── */}
      {hasStep1 && (
        <div className="rounded-xl border-2 border-brand/30 bg-surface shadow-sm">
          <div className="border-b border-border px-6 py-4">
            <h2 className="text-lg font-semibold text-content-primary">
              Passo 2 — Escolha o treino
            </h2>
            <p className="mt-0.5 text-sm text-content-secondary">
              Use um template existente ou crie um treino do zero
            </p>
          </div>

          {/* Mode selector */}
          <div className="flex gap-3 px-6 pt-5">
            <button
              onClick={() => {
                setMode("template");
                setNewBlocks([]);
                setNewName("");
              }}
              className={`flex-1 rounded-xl border-2 p-4 text-left transition ${
                mode === "template"
                  ? "border-brand bg-brand/5"
                  : "border-border hover:border-brand/40"
              }`}
            >
              <p className="text-sm font-semibold text-content-primary">
                Usar template existente
              </p>
              <p className="mt-1 text-xs text-content-secondary">
                Escolha um template já criado
              </p>
            </button>
            <button
              onClick={() => {
                setMode("create");
                setTemplateId("");
                setPreviewBlocks([]);
              }}
              className={`flex-1 rounded-xl border-2 p-4 text-left transition ${
                mode === "create"
                  ? "border-brand bg-brand/5"
                  : "border-border hover:border-brand/40"
              }`}
            >
              <p className="text-sm font-semibold text-content-primary">
                Criar treino novo
              </p>
              <p className="mt-1 text-xs text-content-secondary">
                Monte um treino do zero agora
              </p>
            </button>
          </div>

          {/* Template mode */}
          {mode === "template" && (
            <div className="space-y-4 px-6 py-5">
              <select
                value={templateId}
                onChange={(e) => handleTemplateSelect(e.target.value)}
                className="w-full rounded-lg border border-border bg-surface px-3 py-2.5 text-sm focus:border-brand focus:ring-1 focus:ring-brand"
              >
                <option value="">Selecione um template...</option>
                {templates.map((t) => (
                  <option key={t.id} value={t.id}>
                    {t.name} ({t.block_count} blocos)
                  </option>
                ))}
              </select>

              {loadingPreview && (
                <p className="text-sm text-content-secondary">Carregando blocos...</p>
              )}

              {previewBlocks.length > 0 && (
                <div className="rounded-lg border border-border bg-bg-secondary">
                  <div className="px-4 py-2 text-xs font-semibold uppercase tracking-wide text-content-muted">
                    Prévia do treino
                  </div>
                  <div className="divide-y divide-border-subtle">
                    {previewBlocks.map((b) => (
                      <div key={b.id} className="flex items-center gap-3 px-4 py-2">
                        <span
                          className={`inline-block rounded px-2 py-0.5 text-xs font-semibold ${
                            BLOCK_TYPE_COLORS[b.block_type] ?? "bg-gray-100 text-gray-800"
                          }`}
                        >
                          {BLOCK_TYPE_LABELS[b.block_type] ?? b.block_type}
                        </span>
                        <span className="text-xs text-content-primary">
                          {blockDetails(b)}
                        </span>
                      </div>
                    ))}
                  </div>
                </div>
              )}
            </div>
          )}

          {/* Create mode */}
          {mode === "create" && (
            <div className="space-y-4 px-6 py-5">
              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="mb-1 block text-xs font-medium text-content-secondary">
                    Nome do treino *
                  </label>
                  <input
                    type="text"
                    value={newName}
                    onChange={(e) => setNewName(e.target.value)}
                    placeholder="Ex: Intervalado 5x1km"
                    className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm focus:border-brand focus:ring-1 focus:ring-brand"
                  />
                </div>
                <div>
                  <label className="mb-1 block text-xs font-medium text-content-secondary">
                    Descrição
                  </label>
                  <input
                    type="text"
                    value={newDescription}
                    onChange={(e) => setNewDescription(e.target.value)}
                    placeholder="Opcional"
                    className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm focus:border-brand focus:ring-1 focus:ring-brand"
                  />
                </div>
              </div>

              {/* Block list */}
              {newBlocks.length > 0 && (
                <div className="rounded-lg border border-border">
                  <div className="divide-y divide-border-subtle">
                    {newBlocks.map((b) => (
                      <div
                        key={b.id}
                        className="flex items-center gap-3 px-4 py-2"
                      >
                        <span
                          className={`inline-block rounded px-2 py-0.5 text-xs font-semibold ${
                            BLOCK_TYPE_COLORS[b.block_type] ?? "bg-gray-100 text-gray-800"
                          }`}
                        >
                          {BLOCK_TYPE_LABELS[b.block_type] ?? b.block_type}
                        </span>
                        <span className="flex-1 text-xs text-content-primary">
                          {blockDetails(b)}
                        </span>
                        <button
                          onClick={() => removeNewBlock(b.id)}
                          className="text-error/60 hover:text-error"
                        >
                          <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" strokeWidth={2} stroke="currentColor">
                            <path strokeLinecap="round" strokeLinejoin="round" d="M6 18L18 6M6 6l12 12" />
                          </svg>
                        </button>
                      </div>
                    ))}
                  </div>
                </div>
              )}

              {!showBlockForm ? (
                <button
                  onClick={() => setShowBlockForm(true)}
                  className="rounded-lg border border-dashed border-brand/40 px-4 py-2.5 text-sm font-medium text-brand hover:bg-brand/5 w-full"
                >
                  + Adicionar bloco
                </button>
              ) : (
                <InlineBlockForm
                  onAdd={addNewBlock}
                  onCancel={() => setShowBlockForm(false)}
                />
              )}
            </div>
          )}
        </div>
      )}

      {/* ── STEP 3: Confirm and assign (only visible when step 2 done) ── */}
      {hasStep1 && hasStep2 && (
        <div className="rounded-xl border-2 border-green-300 bg-green-50/50 p-6 shadow-sm dark:border-green-800 dark:bg-green-900/10">
          <h2 className="text-lg font-semibold text-content-primary">
            Passo 3 — Confirme e atribua
          </h2>

          <div className="mt-3 rounded-lg bg-surface border border-border p-4 text-sm">
            <div className="flex items-center gap-2">
              <span className="font-medium text-content-secondary">Atletas:</span>
              <span className="text-content-primary">{selectedNames}</span>
            </div>
            <div className="mt-2 flex items-center gap-2">
              <span className="font-medium text-content-secondary">Treino:</span>
              <span className="text-content-primary">{chosenTemplateName}</span>
            </div>
          </div>

          <div className="mt-4 flex items-end gap-4">
            <div>
              <label className="mb-1 block text-xs font-medium text-content-secondary">
                Data do treino
              </label>
              <input
                type="date"
                value={date}
                onChange={(e) => setDate(e.target.value)}
                className="rounded-lg border border-border bg-surface px-3 py-2.5 text-sm focus:border-brand focus:ring-1 focus:ring-brand"
              />
            </div>
            <button
              onClick={handleAssign}
              disabled={loading}
              className="rounded-lg bg-green-600 px-6 py-2.5 text-sm font-semibold text-white hover:bg-green-700 disabled:opacity-50"
            >
              {loading
                ? "Atribuindo..."
                : `Atribuir treino a ${selectedCount} atleta${selectedCount !== 1 ? "s" : ""}`}
            </button>
          </div>

          {result && (
            <div
              className={`mt-3 rounded-lg px-4 py-2 text-sm ${
                result.ok
                  ? "border border-green-200 bg-green-100 text-green-800 dark:border-green-800 dark:bg-green-900/30 dark:text-green-300"
                  : "border border-red-200 bg-red-100 text-red-800 dark:border-red-800 dark:bg-red-900/30 dark:text-red-300"
              }`}
            >
              {result.success}/{result.total} atribuições realizadas com
              sucesso.
            </div>
          )}
        </div>
      )}
    </div>
  );
}

/* ── Inline Block Form ──────────────────────────────────────── */

function InlineBlockForm({
  onAdd,
  onCancel,
}: {
  onAdd: (block: TemplateBlock) => void;
  onCancel: () => void;
}) {
  const [blockType, setBlockType] = useState("steady");
  const [durationMin, setDurationMin] = useState("");
  const [distanceM, setDistanceM] = useState("");
  const [paceMinMin, setPaceMinMin] = useState("");
  const [paceMinSec, setPaceMinSec] = useState("");
  const [paceMaxMin, setPaceMaxMin] = useState("");
  const [paceMaxSec, setPaceMaxSec] = useState("");
  const [hrZone, setHrZone] = useState<number | null>(null);
  const [rpe, setRpe] = useState<number | null>(null);
  const [repeatCount, setRepeatCount] = useState("");
  const [notes, setNotes] = useState("");
  const [err, setErr] = useState<string | null>(null);

  const isRepeat = blockType === "repeat";
  const isRest = blockType === "rest";

  function parsePace(m: string, s: string): number | null {
    const mi = parseInt(m);
    if (isNaN(mi)) return null;
    return mi * 60 + (parseInt(s) || 0);
  }

  function handleAdd() {
    setErr(null);
    if (isRepeat) {
      const rc = parseInt(repeatCount);
      if (isNaN(rc) || rc < 1) {
        setErr("Informe o número de repetições");
        return;
      }
    }
    const pMin = parsePace(paceMinMin, paceMinSec);
    const pMax = parsePace(paceMaxMin, paceMaxSec);
    const dur = parseInt(durationMin);
    const dist = parseInt(distanceM);

    onAdd({
      id: crypto.randomUUID(),
      order_index: 0,
      block_type: blockType,
      duration_seconds: !isNaN(dur) ? dur * 60 : null,
      distance_meters: !isNaN(dist) ? dist : null,
      target_pace_min_sec_per_km: isRest || isRepeat ? null : pMin,
      target_pace_max_sec_per_km: isRest || isRepeat ? null : (pMax ?? pMin),
      target_hr_zone: isRest || isRepeat ? null : hrZone,
      target_hr_min: null,
      target_hr_max: null,
      rpe_target: isRest || isRepeat ? null : rpe,
      repeat_count: isRepeat ? parseInt(repeatCount) || null : null,
      notes: notes.trim() || null,
    });
  }

  return (
    <div className="rounded-lg border border-border bg-bg-secondary p-4">
      {err && (
        <p className="mb-3 text-sm text-error">{err}</p>
      )}
      <div className="grid gap-3">
        <div className="grid grid-cols-3 gap-3">
          <div>
            <label className="mb-1 block text-xs font-medium text-content-secondary">Tipo</label>
            <select
              value={blockType}
              onChange={(e) => setBlockType(e.target.value)}
              className="w-full rounded-lg border border-border bg-surface px-2 py-2 text-sm focus:border-brand focus:ring-1 focus:ring-brand"
            >
              {BLOCK_TYPES.map((bt) => (
                <option key={bt.value} value={bt.value}>{bt.label}</option>
              ))}
            </select>
          </div>
          {isRepeat ? (
            <div>
              <label className="mb-1 block text-xs font-medium text-content-secondary">Repetições *</label>
              <input type="number" min={1} value={repeatCount} onChange={(e) => setRepeatCount(e.target.value)} placeholder="5"
                className="w-full rounded-lg border border-border bg-surface px-2 py-2 text-sm focus:border-brand focus:ring-1 focus:ring-brand" />
            </div>
          ) : (
            <>
              <div>
                <label className="mb-1 block text-xs font-medium text-content-secondary">Duração (min)</label>
                <input type="number" min={0} value={durationMin} onChange={(e) => setDurationMin(e.target.value)}
                  className="w-full rounded-lg border border-border bg-surface px-2 py-2 text-sm focus:border-brand focus:ring-1 focus:ring-brand" />
              </div>
              <div>
                <label className="mb-1 block text-xs font-medium text-content-secondary">Distância (m)</label>
                <input type="number" min={0} value={distanceM} onChange={(e) => setDistanceM(e.target.value)}
                  className="w-full rounded-lg border border-border bg-surface px-2 py-2 text-sm focus:border-brand focus:ring-1 focus:ring-brand" />
              </div>
            </>
          )}
        </div>

        {!isRepeat && !isRest && (
          <div className="grid grid-cols-4 gap-3">
            <div className="col-span-2">
              <label className="mb-1 block text-xs font-medium text-content-secondary">Pace (/km)</label>
              <div className="flex items-center gap-1">
                <input type="number" min={0} value={paceMinMin} onChange={(e) => setPaceMinMin(e.target.value)} placeholder="min"
                  className="w-14 rounded border border-border bg-surface px-1 py-2 text-center text-sm" />
                <span className="text-xs text-content-muted">:</span>
                <input type="number" min={0} max={59} value={paceMinSec} onChange={(e) => setPaceMinSec(e.target.value)} placeholder="s"
                  className="w-14 rounded border border-border bg-surface px-1 py-2 text-center text-sm" />
                <span className="text-xs text-content-muted">a</span>
                <input type="number" min={0} value={paceMaxMin} onChange={(e) => setPaceMaxMin(e.target.value)} placeholder="min"
                  className="w-14 rounded border border-border bg-surface px-1 py-2 text-center text-sm" />
                <span className="text-xs text-content-muted">:</span>
                <input type="number" min={0} max={59} value={paceMaxSec} onChange={(e) => setPaceMaxSec(e.target.value)} placeholder="s"
                  className="w-14 rounded border border-border bg-surface px-1 py-2 text-center text-sm" />
              </div>
            </div>
            <div>
              <label className="mb-1 block text-xs font-medium text-content-secondary">Zona FC</label>
              <select value={hrZone ?? ""} onChange={(e) => setHrZone(e.target.value ? parseInt(e.target.value) : null)}
                className="w-full rounded-lg border border-border bg-surface px-2 py-2 text-sm">
                <option value="">—</option>
                {[1,2,3,4,5].map((z) => <option key={z} value={z}>Z{z}</option>)}
              </select>
            </div>
            <div>
              <label className="mb-1 block text-xs font-medium text-content-secondary">RPE</label>
              <select value={rpe ?? ""} onChange={(e) => setRpe(e.target.value ? parseInt(e.target.value) : null)}
                className="w-full rounded-lg border border-border bg-surface px-2 py-2 text-sm">
                <option value="">—</option>
                {Array.from({length:10},(_,i)=>i+1).map((r) => <option key={r} value={r}>{r}</option>)}
              </select>
            </div>
          </div>
        )}

        {!isRepeat && (
          <div>
            <label className="mb-1 block text-xs font-medium text-content-secondary">Observações</label>
            <input type="text" value={notes} onChange={(e) => setNotes(e.target.value)} placeholder="Opcional"
              className="w-full rounded-lg border border-border bg-surface px-2 py-2 text-sm" />
          </div>
        )}
      </div>

      <div className="mt-4 flex justify-end gap-2">
        <button onClick={onCancel} className="rounded-lg border border-border px-3 py-1.5 text-sm text-content-secondary hover:bg-surface-elevated">
          Cancelar
        </button>
        <button onClick={handleAdd} className="rounded-lg bg-brand px-4 py-1.5 text-sm font-medium text-white hover:bg-brand/90">
          Adicionar bloco
        </button>
      </div>
    </div>
  );
}
