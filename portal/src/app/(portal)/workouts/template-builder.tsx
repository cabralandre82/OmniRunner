"use client";

import { useState, useCallback } from "react";
import { useRouter } from "next/navigation";

interface Block {
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

interface TemplateBuilderProps {
  templateId?: string;
  initialName?: string;
  initialDescription?: string;
  initialBlocks?: Block[];
}

const BLOCK_TYPES = [
  { value: "warmup", label: "Aquecimento" },
  { value: "interval", label: "Intervalo" },
  { value: "recovery", label: "Recuperação" },
  { value: "cooldown", label: "Desaquecimento" },
  { value: "steady", label: "Contínuo" },
  { value: "rest", label: "Descanso" },
  { value: "repeat", label: "Repetir" },
];

const BLOCK_TYPE_LABELS: Record<string, string> = Object.fromEntries(
  BLOCK_TYPES.map((bt) => [bt.value, bt.label]),
);

const BLOCK_TYPE_COLORS: Record<string, string> = {
  warmup:
    "bg-yellow-100 text-yellow-800 dark:bg-yellow-900/30 dark:text-yellow-300",
  interval: "bg-red-100 text-red-800 dark:bg-red-900/30 dark:text-red-300",
  recovery:
    "bg-green-100 text-green-800 dark:bg-green-900/30 dark:text-green-300",
  cooldown: "bg-blue-100 text-blue-800 dark:bg-blue-900/30 dark:text-blue-300",
  steady:
    "bg-emerald-100 text-emerald-800 dark:bg-emerald-900/30 dark:text-emerald-300",
  rest: "bg-gray-100 text-gray-800 dark:bg-gray-700/30 dark:text-gray-300",
  repeat:
    "bg-purple-100 text-purple-800 dark:bg-purple-900/30 dark:text-purple-300",
};

function fmtPace(secPerKm: number): string {
  const m = Math.floor(secPerKm / 60);
  const s = secPerKm % 60;
  return `${m}:${String(s).padStart(2, "0")}`;
}

function fmtDistance(meters: number): string {
  return meters >= 1000
    ? `${(meters / 1000).toFixed(1)} km`
    : `${meters} m`;
}

function fmtDuration(seconds: number): string {
  const m = Math.floor(seconds / 60);
  const s = seconds % 60;
  return s > 0 ? `${m}m${s}s` : `${m} min`;
}

function generateId(): string {
  return crypto.randomUUID();
}

export function TemplateBuilder({
  templateId,
  initialName = "",
  initialDescription = "",
  initialBlocks = [],
}: TemplateBuilderProps) {
  const router = useRouter();
  const isEdit = !!templateId;

  const [name, setName] = useState(initialName);
  const [description, setDescription] = useState(initialDescription);
  const [blocks, setBlocks] = useState<Block[]>(initialBlocks);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [showBlockForm, setShowBlockForm] = useState(false);

  const addBlock = useCallback((block: Block) => {
    setBlocks((prev) => [...prev, { ...block, order_index: prev.length }]);
    setShowBlockForm(false);
  }, []);

  const removeBlock = useCallback((id: string) => {
    setBlocks((prev) =>
      prev
        .filter((b) => b.id !== id)
        .map((b, i) => ({ ...b, order_index: i })),
    );
  }, []);

  const moveBlock = useCallback((fromIdx: number, direction: "up" | "down") => {
    setBlocks((prev) => {
      const toIdx = direction === "up" ? fromIdx - 1 : fromIdx + 1;
      if (toIdx < 0 || toIdx >= prev.length) return prev;
      const next = [...prev];
      [next[fromIdx], next[toIdx]] = [next[toIdx], next[fromIdx]];
      return next.map((b, i) => ({ ...b, order_index: i }));
    });
  }, []);

  const handleSave = async () => {
    if (!name || name.trim().length < 2) {
      setError("Nome deve ter pelo menos 2 caracteres");
      return;
    }
    setSaving(true);
    setError(null);

    try {
      const res = await fetch("/api/workouts/templates", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          id: templateId,
          name,
          description,
          blocks,
        }),
      });
      const data = await res.json();
      if (!res.ok || !data.ok) {
        setError(data.error || "Erro ao salvar template");
        return;
      }
      router.push(`/workouts/${data.id}`);
      router.refresh();
    } catch {
      setError("Erro de conexão");
    } finally {
      setSaving(false);
    }
  };

  let inRepeat = false;

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-content-primary">
            {isEdit ? "Editar Template" : "Novo Template"}
          </h1>
          <p className="mt-1 text-sm text-content-secondary">
            {isEdit
              ? "Modifique o template e seus blocos"
              : "Crie um template de treino com blocos estruturados"}
          </p>
        </div>
        <button
          onClick={handleSave}
          disabled={saving || !name.trim()}
          className="rounded-lg bg-brand px-5 py-2.5 text-sm font-medium text-white hover:bg-brand/90 disabled:opacity-50"
        >
          {saving ? "Salvando..." : "Salvar Template"}
        </button>
      </div>

      {error && (
        <div className="rounded-lg border border-error/30 bg-error-soft px-4 py-3 text-sm text-error">
          {error}
        </div>
      )}

      {/* Template info */}
      <div className="rounded-xl border border-border bg-surface p-6 shadow-sm">
        <div className="space-y-4">
          <div>
            <label className="mb-1 block text-sm font-medium text-content-secondary">
              Nome do template *
            </label>
            <input
              type="text"
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="Ex: Treino intervalado 5x1km"
              className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm focus:border-brand focus:ring-1 focus:ring-brand"
            />
          </div>
          <div>
            <label className="mb-1 block text-sm font-medium text-content-secondary">
              Descrição
            </label>
            <textarea
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              placeholder="Opcional"
              rows={2}
              className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm focus:border-brand focus:ring-1 focus:ring-brand"
            />
          </div>
        </div>
      </div>

      {/* Blocks */}
      <div className="rounded-xl border border-border bg-surface shadow-sm">
        <div className="flex items-center justify-between border-b border-border px-6 py-4">
          <h2 className="text-lg font-semibold text-content-primary">
            Blocos ({blocks.length})
          </h2>
          <button
            onClick={() => setShowBlockForm(true)}
            className="rounded-lg border border-brand bg-transparent px-4 py-1.5 text-sm font-medium text-brand hover:bg-brand/5"
          >
            + Adicionar Bloco
          </button>
        </div>

        {blocks.length === 0 && !showBlockForm && (
          <div className="p-8 text-center text-sm text-content-secondary">
            Nenhum bloco adicionado. Clique em &quot;Adicionar Bloco&quot; para
            começar.
          </div>
        )}

        <div className="divide-y divide-border-subtle">
          {blocks.map((block, idx) => {
            const isRepeat = block.block_type === "repeat";
            if (isRepeat) inRepeat = true;
            if (
              !isRepeat &&
              !["interval", "recovery"].includes(block.block_type)
            ) {
              inRepeat = false;
            }

            const details: string[] = [];
            if (isRepeat && block.repeat_count) {
              details.push(`${block.repeat_count}x`);
            }
            if (block.duration_seconds) {
              details.push(fmtDuration(block.duration_seconds));
            }
            if (block.distance_meters) {
              details.push(fmtDistance(block.distance_meters));
            }
            if (
              !block.duration_seconds &&
              !block.distance_meters &&
              !isRepeat
            ) {
              details.push("livre");
            }
            if (
              block.target_pace_min_sec_per_km &&
              block.target_pace_max_sec_per_km
            ) {
              const min = fmtPace(block.target_pace_min_sec_per_km);
              const max = fmtPace(block.target_pace_max_sec_per_km);
              details.push(min === max ? `${min}/km` : `${min}–${max}/km`);
            }
            if (block.target_hr_zone) {
              details.push(`Z${block.target_hr_zone}`);
            }
            if (block.target_hr_min && block.target_hr_max) {
              details.push(
                `${block.target_hr_min}–${block.target_hr_max} bpm`,
              );
            }
            if (block.rpe_target) {
              details.push(`RPE ${block.rpe_target}`);
            }

            const indent = inRepeat && !isRepeat ? "ml-8" : "";

            return (
              <div
                key={block.id}
                className={`flex items-center gap-3 px-6 py-3 ${indent}`}
              >
                <div
                  className={`w-2 self-stretch rounded-full ${
                    BLOCK_TYPE_COLORS[block.block_type]?.split(" ")[0] ??
                    "bg-gray-300"
                  }`}
                />
                <span
                  className={`inline-block rounded px-2 py-0.5 text-xs font-semibold ${
                    BLOCK_TYPE_COLORS[block.block_type] ??
                    "bg-gray-100 text-gray-800"
                  }`}
                >
                  {BLOCK_TYPE_LABELS[block.block_type] ?? block.block_type}
                </span>
                <span className="flex-1 text-sm text-content-primary">
                  {details.join(" · ")}
                </span>
                {block.notes && (
                  <span className="text-xs italic text-content-secondary">
                    {block.notes}
                  </span>
                )}
                <div className="flex items-center gap-1">
                  <button
                    onClick={() => moveBlock(idx, "up")}
                    disabled={idx === 0}
                    className="rounded p-1 text-content-muted hover:bg-surface-elevated hover:text-content-primary disabled:opacity-30"
                    title="Mover para cima"
                  >
                    <svg
                      className="h-4 w-4"
                      fill="none"
                      viewBox="0 0 24 24"
                      strokeWidth={2}
                      stroke="currentColor"
                    >
                      <path
                        strokeLinecap="round"
                        strokeLinejoin="round"
                        d="M4.5 15.75l7.5-7.5 7.5 7.5"
                      />
                    </svg>
                  </button>
                  <button
                    onClick={() => moveBlock(idx, "down")}
                    disabled={idx === blocks.length - 1}
                    className="rounded p-1 text-content-muted hover:bg-surface-elevated hover:text-content-primary disabled:opacity-30"
                    title="Mover para baixo"
                  >
                    <svg
                      className="h-4 w-4"
                      fill="none"
                      viewBox="0 0 24 24"
                      strokeWidth={2}
                      stroke="currentColor"
                    >
                      <path
                        strokeLinecap="round"
                        strokeLinejoin="round"
                        d="M19.5 8.25l-7.5 7.5-7.5-7.5"
                      />
                    </svg>
                  </button>
                  <button
                    onClick={() => removeBlock(block.id)}
                    className="rounded p-1 text-error/70 hover:bg-error-soft hover:text-error"
                    title="Remover bloco"
                  >
                    <svg
                      className="h-4 w-4"
                      fill="none"
                      viewBox="0 0 24 24"
                      strokeWidth={2}
                      stroke="currentColor"
                    >
                      <path
                        strokeLinecap="round"
                        strokeLinejoin="round"
                        d="M6 18L18 6M6 6l12 12"
                      />
                    </svg>
                  </button>
                </div>
              </div>
            );
          })}
        </div>

        {showBlockForm && (
          <div className="border-t border-border">
            <AddBlockForm
              onAdd={addBlock}
              onCancel={() => setShowBlockForm(false)}
            />
          </div>
        )}
      </div>
    </div>
  );
}

function AddBlockForm({
  onAdd,
  onCancel,
}: {
  onAdd: (block: Block) => void;
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
  const [hrMin, setHrMin] = useState("");
  const [hrMax, setHrMax] = useState("");
  const [rpe, setRpe] = useState<number | null>(null);
  const [repeatCount, setRepeatCount] = useState("");
  const [notes, setNotes] = useState("");
  const [formError, setFormError] = useState<string | null>(null);

  const isRepeat = blockType === "repeat";
  const isRest = blockType === "rest";

  function parsePace(minStr: string, secStr: string): number | null {
    const m = parseInt(minStr);
    if (isNaN(m)) return null;
    const s = parseInt(secStr) || 0;
    return m * 60 + s;
  }

  function handleAdd() {
    setFormError(null);

    if (isRepeat) {
      const rc = parseInt(repeatCount);
      if (isNaN(rc) || rc < 1) {
        setFormError("Informe o número de repetições");
        return;
      }
    }

    const pMin = parsePace(paceMinMin, paceMinSec);
    const pMax = parsePace(paceMaxMin, paceMaxSec);
    const dur = parseInt(durationMin);
    const dist = parseInt(distanceM);

    onAdd({
      id: generateId(),
      order_index: 0,
      block_type: blockType,
      duration_seconds: !isNaN(dur) ? dur * 60 : null,
      distance_meters: !isNaN(dist) ? dist : null,
      target_pace_min_sec_per_km: isRest || isRepeat ? null : pMin,
      target_pace_max_sec_per_km:
        isRest || isRepeat ? null : (pMax ?? pMin),
      target_hr_zone: isRest || isRepeat ? null : hrZone,
      target_hr_min: isRest || isRepeat ? null : (parseInt(hrMin) || null),
      target_hr_max: isRest || isRepeat ? null : (parseInt(hrMax) || null),
      rpe_target: isRest || isRepeat ? null : rpe,
      repeat_count: isRepeat ? parseInt(repeatCount) || null : null,
      notes: notes.trim() || null,
    });
  }

  return (
    <div className="p-6">
      <h3 className="mb-4 text-base font-semibold text-content-primary">
        Adicionar Bloco
      </h3>

      {formError && (
        <div className="mb-4 rounded-lg border border-error/30 bg-error-soft px-3 py-2 text-sm text-error">
          {formError}
        </div>
      )}

      <div className="grid gap-4">
        {/* Block type */}
        <div>
          <label className="mb-1 block text-xs font-medium text-content-secondary">
            Tipo
          </label>
          <select
            value={blockType}
            onChange={(e) => setBlockType(e.target.value)}
            className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm focus:border-brand focus:ring-1 focus:ring-brand"
          >
            {BLOCK_TYPES.map((bt) => (
              <option key={bt.value} value={bt.value}>
                {bt.label}
              </option>
            ))}
          </select>
        </div>

        {isRepeat && (
          <>
            <div>
              <label className="mb-1 block text-xs font-medium text-content-secondary">
                Repetições *
              </label>
              <input
                type="number"
                min={1}
                value={repeatCount}
                onChange={(e) => setRepeatCount(e.target.value)}
                placeholder="Ex: 5"
                className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm focus:border-brand focus:ring-1 focus:ring-brand"
              />
            </div>
            <p className="text-xs text-content-secondary">
              Os próximos blocos adicionados serão repetidos este número de
              vezes.
            </p>
          </>
        )}

        {!isRepeat && (
          <>
            {/* Duration and Distance */}
            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className="mb-1 block text-xs font-medium text-content-secondary">
                  Duração (min)
                </label>
                <input
                  type="number"
                  min={0}
                  value={durationMin}
                  onChange={(e) => setDurationMin(e.target.value)}
                  className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm focus:border-brand focus:ring-1 focus:ring-brand"
                />
              </div>
              <div>
                <label className="mb-1 block text-xs font-medium text-content-secondary">
                  Distância (metros)
                </label>
                <input
                  type="number"
                  min={0}
                  value={distanceM}
                  onChange={(e) => setDistanceM(e.target.value)}
                  className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm focus:border-brand focus:ring-1 focus:ring-brand"
                />
              </div>
            </div>

            {!isRest && (
              <>
                {/* Pace */}
                <div>
                  <label className="mb-2 block text-xs font-medium text-content-secondary">
                    Pace alvo (/km)
                  </label>
                  <div className="flex items-center gap-2">
                    <input
                      type="number"
                      min={0}
                      value={paceMinMin}
                      onChange={(e) => setPaceMinMin(e.target.value)}
                      placeholder="min"
                      className="w-16 rounded-lg border border-border bg-surface px-2 py-2 text-center text-sm focus:border-brand focus:ring-1 focus:ring-brand"
                    />
                    <span className="text-content-secondary">:</span>
                    <input
                      type="number"
                      min={0}
                      max={59}
                      value={paceMinSec}
                      onChange={(e) => setPaceMinSec(e.target.value)}
                      placeholder="seg"
                      className="w-16 rounded-lg border border-border bg-surface px-2 py-2 text-center text-sm focus:border-brand focus:ring-1 focus:ring-brand"
                    />
                    <span className="text-sm text-content-secondary">a</span>
                    <input
                      type="number"
                      min={0}
                      value={paceMaxMin}
                      onChange={(e) => setPaceMaxMin(e.target.value)}
                      placeholder="min"
                      className="w-16 rounded-lg border border-border bg-surface px-2 py-2 text-center text-sm focus:border-brand focus:ring-1 focus:ring-brand"
                    />
                    <span className="text-content-secondary">:</span>
                    <input
                      type="number"
                      min={0}
                      max={59}
                      value={paceMaxSec}
                      onChange={(e) => setPaceMaxSec(e.target.value)}
                      placeholder="seg"
                      className="w-16 rounded-lg border border-border bg-surface px-2 py-2 text-center text-sm focus:border-brand focus:ring-1 focus:ring-brand"
                    />
                    <span className="text-sm text-content-secondary">/km</span>
                  </div>
                </div>

                {/* HR Zone + RPE */}
                <div className="grid grid-cols-2 gap-3">
                  <div>
                    <label className="mb-1 block text-xs font-medium text-content-secondary">
                      Zona FC
                    </label>
                    <select
                      value={hrZone ?? ""}
                      onChange={(e) =>
                        setHrZone(
                          e.target.value ? parseInt(e.target.value) : null,
                        )
                      }
                      className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm focus:border-brand focus:ring-1 focus:ring-brand"
                    >
                      <option value="">—</option>
                      {[1, 2, 3, 4, 5].map((z) => (
                        <option key={z} value={z}>
                          Z{z}
                        </option>
                      ))}
                    </select>
                  </div>
                  <div>
                    <label className="mb-1 block text-xs font-medium text-content-secondary">
                      RPE
                    </label>
                    <select
                      value={rpe ?? ""}
                      onChange={(e) =>
                        setRpe(
                          e.target.value ? parseInt(e.target.value) : null,
                        )
                      }
                      className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm focus:border-brand focus:ring-1 focus:ring-brand"
                    >
                      <option value="">—</option>
                      {Array.from({ length: 10 }, (_, i) => i + 1).map((r) => (
                        <option key={r} value={r}>
                          {r}
                        </option>
                      ))}
                    </select>
                  </div>
                </div>

                {/* HR Range */}
                <div className="grid grid-cols-2 gap-3">
                  <div>
                    <label className="mb-1 block text-xs font-medium text-content-secondary">
                      FC mín. (bpm)
                    </label>
                    <input
                      type="number"
                      min={0}
                      value={hrMin}
                      onChange={(e) => setHrMin(e.target.value)}
                      className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm focus:border-brand focus:ring-1 focus:ring-brand"
                    />
                  </div>
                  <div>
                    <label className="mb-1 block text-xs font-medium text-content-secondary">
                      FC máx. (bpm)
                    </label>
                    <input
                      type="number"
                      min={0}
                      value={hrMax}
                      onChange={(e) => setHrMax(e.target.value)}
                      className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm focus:border-brand focus:ring-1 focus:ring-brand"
                    />
                  </div>
                </div>
              </>
            )}

            {/* Notes */}
            <div>
              <label className="mb-1 block text-xs font-medium text-content-secondary">
                Observações
              </label>
              <input
                type="text"
                value={notes}
                onChange={(e) => setNotes(e.target.value)}
                placeholder="Opcional"
                className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm focus:border-brand focus:ring-1 focus:ring-brand"
              />
            </div>
          </>
        )}
      </div>

      <div className="mt-5 flex justify-end gap-3">
        <button
          onClick={onCancel}
          className="rounded-lg border border-border px-4 py-2 text-sm font-medium text-content-secondary hover:bg-surface-elevated"
        >
          Cancelar
        </button>
        <button
          onClick={handleAdd}
          className="rounded-lg bg-brand px-4 py-2 text-sm font-medium text-white hover:bg-brand/90"
        >
          Adicionar
        </button>
      </div>
    </div>
  );
}
