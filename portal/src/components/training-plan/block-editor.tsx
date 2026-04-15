"use client";

import { useState, useCallback } from "react";
import { ReleaseBlock } from "./types";

// ── Constants ─────────────────────────────────────────────────────────────────

export const BLOCK_TYPE_OPTIONS: { value: ReleaseBlock["block_type"]; label: string; color: string }[] = [
  { value: "warmup",   label: "Aquecimento", color: "bg-yellow-100 text-yellow-800" },
  { value: "steady",   label: "Contínuo",    color: "bg-emerald-100 text-emerald-800" },
  { value: "interval", label: "Intervalo",   color: "bg-red-100 text-red-800" },
  { value: "recovery", label: "Recuperação", color: "bg-green-100 text-green-800" },
  { value: "repeat",   label: "Repetir",     color: "bg-purple-100 text-purple-800" },
  { value: "rest",     label: "Descanso",    color: "bg-gray-100 text-gray-600" },
  { value: "cooldown", label: "Volta Calma", color: "bg-blue-100 text-blue-800" },
];

const BLOCK_COLOR: Record<string, string> = Object.fromEntries(
  BLOCK_TYPE_OPTIONS.map((b) => [b.value, b.color]),
);
const BLOCK_LABEL: Record<string, string> = Object.fromEntries(
  BLOCK_TYPE_OPTIONS.map((b) => [b.value, b.label]),
);

function emptyBlock(orderIndex: number): ReleaseBlock {
  return {
    order_index: orderIndex,
    block_type: "interval",
    duration_seconds: null,
    distance_meters: null,
    target_pace_min_sec_per_km: null,
    target_pace_max_sec_per_km: null,
    target_hr_zone: null,
    target_hr_min: null,
    target_hr_max: null,
    rpe_target: null,
    repeat_count: null,
    notes: null,
  };
}

function parsePace(val: string): number | null {
  const m = val.match(/^(\d+):(\d{2})$/);
  if (!m) return null;
  const mins = parseInt(m[1], 10);
  const secs = parseInt(m[2], 10);
  if (secs >= 60) return null;
  return mins * 60 + secs;
}

function fmtPace(secs: number | null): string {
  if (secs == null) return "";
  const m = Math.floor(secs / 60);
  const s = secs % 60;
  return `${m}:${String(s).padStart(2, "0")}`;
}

// ── Sub-component: single block row ───────────────────────────────────────────

interface BlockRowProps {
  block: ReleaseBlock;
  index: number;
  total: number;
  onChange: (b: ReleaseBlock) => void;
  onRemove: () => void;
  onMove: (dir: "up" | "down") => void;
}

function BlockRow({ block, index, total, onChange, onRemove, onMove }: BlockRowProps) {
  const [expanded, setExpanded] = useState(false);

  function set<K extends keyof ReleaseBlock>(key: K, value: ReleaseBlock[K]) {
    onChange({ ...block, [key]: value });
  }

  const isRepeat = block.block_type === "repeat";

  const summary = [
    block.distance_meters != null ? `${block.distance_meters}m` : null,
    block.duration_seconds != null
      ? block.duration_seconds >= 60
        ? `${Math.floor(block.duration_seconds / 60)}min`
        : `${block.duration_seconds}s`
      : null,
    block.target_pace_min_sec_per_km != null
      ? `${fmtPace(block.target_pace_min_sec_per_km)}–${fmtPace(block.target_pace_max_sec_per_km ?? block.target_pace_min_sec_per_km)}/km`
      : null,
    block.target_hr_zone != null ? `Z${block.target_hr_zone}` : null,
    block.rpe_target != null ? `RPE ${block.rpe_target}` : null,
    isRepeat && block.repeat_count != null ? `×${block.repeat_count}` : null,
  ].filter(Boolean).join(" · ");

  return (
    <div className="rounded-lg border border-border bg-surface">
      {/* Row header */}
      <div className="flex items-center gap-2 px-3 py-2">
        {/* Reorder */}
        <div className="flex flex-col gap-0.5">
          <button
            type="button"
            disabled={index === 0}
            onClick={() => onMove("up")}
            className="text-content-muted hover:text-content-primary disabled:opacity-20"
          >
            <svg className="h-3 w-3" fill="none" viewBox="0 0 24 24" strokeWidth={3} stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" d="M4.5 15.75l7.5-7.5 7.5 7.5" />
            </svg>
          </button>
          <button
            type="button"
            disabled={index === total - 1}
            onClick={() => onMove("down")}
            className="text-content-muted hover:text-content-primary disabled:opacity-20"
          >
            <svg className="h-3 w-3" fill="none" viewBox="0 0 24 24" strokeWidth={3} stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" d="M19.5 8.25l-7.5 7.5-7.5-7.5" />
            </svg>
          </button>
        </div>

        {/* Type chip */}
        <span className={`shrink-0 rounded-full px-2 py-0.5 text-[11px] font-semibold ${BLOCK_COLOR[block.block_type] ?? "bg-surface-elevated text-content-secondary"}`}>
          {BLOCK_LABEL[block.block_type] ?? block.block_type}
        </span>

        {/* Summary */}
        <span className="flex-1 truncate text-xs text-content-muted">{summary || "—"}</span>

        {/* Actions */}
        <button
          type="button"
          onClick={() => setExpanded((v) => !v)}
          className="shrink-0 rounded p-1 text-content-muted hover:bg-surface-elevated hover:text-content-primary"
        >
          <svg className={`h-4 w-4 transition-transform ${expanded ? "rotate-180" : ""}`} fill="none" viewBox="0 0 24 24" strokeWidth={2} stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" d="M19.5 8.25l-7.5 7.5-7.5-7.5" />
          </svg>
        </button>
        <button
          type="button"
          onClick={onRemove}
          className="shrink-0 rounded p-1 text-error/50 hover:bg-error-soft hover:text-error"
        >
          <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" strokeWidth={2} stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" d="M6 18L18 6M6 6l12 12" />
          </svg>
        </button>
      </div>

      {/* Expanded editor */}
      {expanded && (
        <div className="border-t border-border px-3 pb-3 pt-2 space-y-3">
          {/* Type selector */}
          <div>
            <label className="mb-1 block text-[11px] font-medium text-content-muted">Tipo de bloco</label>
            <select
              value={block.block_type}
              onChange={(e) => set("block_type", e.target.value as ReleaseBlock["block_type"])}
              className="w-full rounded border border-border bg-bg-secondary px-2 py-1.5 text-xs text-content-primary focus:border-brand focus:outline-none"
            >
              {BLOCK_TYPE_OPTIONS.map((opt) => (
                <option key={opt.value} value={opt.value}>{opt.label}</option>
              ))}
            </select>
          </div>

          {isRepeat ? (
            <div>
              <label className="mb-1 block text-[11px] font-medium text-content-muted">Repetições</label>
              <input
                type="number"
                min={1}
                max={100}
                value={block.repeat_count ?? ""}
                onChange={(e) => set("repeat_count", e.target.value ? parseInt(e.target.value, 10) : null)}
                placeholder="ex: 4"
                className="w-full rounded border border-border bg-bg-secondary px-2 py-1.5 text-xs text-content-primary focus:border-brand focus:outline-none"
              />
              <p className="mt-1 text-[10px] text-content-muted">Os blocos seguintes serão repetidos N vezes.</p>
            </div>
          ) : (
            <>
              {/* Distance / Duration */}
              <div className="grid grid-cols-2 gap-2">
                <div>
                  <label className="mb-1 block text-[11px] font-medium text-content-muted">Distância (m)</label>
                  <input
                    type="number"
                    min={0}
                    value={block.distance_meters ?? ""}
                    onChange={(e) => set("distance_meters", e.target.value ? parseInt(e.target.value, 10) : null)}
                    placeholder="ex: 1000"
                    className="w-full rounded border border-border bg-bg-secondary px-2 py-1.5 text-xs text-content-primary focus:border-brand focus:outline-none"
                  />
                </div>
                <div>
                  <label className="mb-1 block text-[11px] font-medium text-content-muted">Duração (s)</label>
                  <input
                    type="number"
                    min={0}
                    value={block.duration_seconds ?? ""}
                    onChange={(e) => set("duration_seconds", e.target.value ? parseInt(e.target.value, 10) : null)}
                    placeholder="ex: 300"
                    className="w-full rounded border border-border bg-bg-secondary px-2 py-1.5 text-xs text-content-primary focus:border-brand focus:outline-none"
                  />
                </div>
              </div>

              {/* Pace range */}
              <div className="grid grid-cols-2 gap-2">
                <div>
                  <label className="mb-1 block text-[11px] font-medium text-content-muted">Pace mín (mm:ss/km)</label>
                  <input
                    type="text"
                    value={fmtPace(block.target_pace_min_sec_per_km)}
                    onChange={(e) => set("target_pace_min_sec_per_km", parsePace(e.target.value))}
                    placeholder="4:30"
                    className="w-full rounded border border-border bg-bg-secondary px-2 py-1.5 text-xs text-content-primary focus:border-brand focus:outline-none"
                  />
                </div>
                <div>
                  <label className="mb-1 block text-[11px] font-medium text-content-muted">Pace máx (mm:ss/km)</label>
                  <input
                    type="text"
                    value={fmtPace(block.target_pace_max_sec_per_km)}
                    onChange={(e) => set("target_pace_max_sec_per_km", parsePace(e.target.value))}
                    placeholder="4:50"
                    className="w-full rounded border border-border bg-bg-secondary px-2 py-1.5 text-xs text-content-primary focus:border-brand focus:outline-none"
                  />
                </div>
              </div>

              {/* HR zone + RPE */}
              <div className="grid grid-cols-2 gap-2">
                <div>
                  <label className="mb-1 block text-[11px] font-medium text-content-muted">Zona FC (1–5)</label>
                  <input
                    type="number"
                    min={1}
                    max={5}
                    value={block.target_hr_zone ?? ""}
                    onChange={(e) => set("target_hr_zone", e.target.value ? parseInt(e.target.value, 10) : null)}
                    placeholder="3"
                    className="w-full rounded border border-border bg-bg-secondary px-2 py-1.5 text-xs text-content-primary focus:border-brand focus:outline-none"
                  />
                </div>
                <div>
                  <label className="mb-1 block text-[11px] font-medium text-content-muted">RPE (1–10)</label>
                  <input
                    type="number"
                    min={1}
                    max={10}
                    value={block.rpe_target ?? ""}
                    onChange={(e) => set("rpe_target", e.target.value ? parseInt(e.target.value, 10) : null)}
                    placeholder="7"
                    className="w-full rounded border border-border bg-bg-secondary px-2 py-1.5 text-xs text-content-primary focus:border-brand focus:outline-none"
                  />
                </div>
              </div>

              {/* Notes */}
              <div>
                <label className="mb-1 block text-[11px] font-medium text-content-muted">Nota do bloco</label>
                <input
                  type="text"
                  value={block.notes ?? ""}
                  onChange={(e) => set("notes", e.target.value || null)}
                  placeholder="ex: Foco no cadência"
                  className="w-full rounded border border-border bg-bg-secondary px-2 py-1.5 text-xs text-content-primary focus:border-brand focus:outline-none"
                />
              </div>
            </>
          )}
        </div>
      )}
    </div>
  );
}

// ── Main BlockEditor ───────────────────────────────────────────────────────────

interface BlockEditorProps {
  blocks: ReleaseBlock[];
  onChange: (blocks: ReleaseBlock[]) => void;
  /** When true shows a compact read-only summary (no editing) */
  readOnly?: boolean;
}

export function BlockEditor({ blocks, onChange, readOnly = false }: BlockEditorProps) {
  const reindex = useCallback((list: ReleaseBlock[]) =>
    list.map((b, i) => ({ ...b, order_index: i })),
  []);

  function handleChange(index: number, updated: ReleaseBlock) {
    const next = [...blocks];
    next[index] = updated;
    onChange(reindex(next));
  }

  function handleRemove(index: number) {
    onChange(reindex(blocks.filter((_, i) => i !== index)));
  }

  function handleMove(index: number, dir: "up" | "down") {
    const next = [...blocks];
    const to = dir === "up" ? index - 1 : index + 1;
    if (to < 0 || to >= next.length) return;
    [next[index], next[to]] = [next[to], next[index]];
    onChange(reindex(next));
  }

  function handleAdd() {
    onChange(reindex([...blocks, emptyBlock(blocks.length)]));
  }

  if (readOnly) {
    if (blocks.length === 0) {
      return (
        <p className="text-xs text-content-muted italic">
          Sem blocos estruturados — treino livre.
        </p>
      );
    }
    return (
      <div className="space-y-1">
        {blocks.map((b, i) => {
          const paceStr = b.target_pace_min_sec_per_km != null
            ? ` · ${fmtPace(b.target_pace_min_sec_per_km)}–${fmtPace(b.target_pace_max_sec_per_km ?? b.target_pace_min_sec_per_km)}/km`
            : "";
          const distStr = b.distance_meters != null ? ` · ${b.distance_meters}m` : "";
          const durStr = b.duration_seconds != null
            ? ` · ${b.duration_seconds >= 60 ? `${Math.floor(b.duration_seconds / 60)}min` : `${b.duration_seconds}s`}`
            : "";
          const hrStr = b.target_hr_zone != null ? ` · Z${b.target_hr_zone}` : "";
          const rpeStr = b.rpe_target != null ? ` · RPE${b.rpe_target}` : "";
          const repStr = b.block_type === "repeat" && b.repeat_count ? ` ×${b.repeat_count}` : "";
          return (
            <div key={i} className="flex items-center gap-2 text-xs">
              <span className={`shrink-0 rounded-full px-1.5 py-0.5 text-[10px] font-semibold ${BLOCK_COLOR[b.block_type] ?? ""}`}>
                {BLOCK_LABEL[b.block_type]}
              </span>
              <span className="text-content-muted">{`${distStr}${durStr}${paceStr}${hrStr}${rpeStr}${repStr}`.replace(/^ · /, "") || "—"}</span>
            </div>
          );
        })}
      </div>
    );
  }

  return (
    <div className="space-y-2">
      {blocks.map((b, i) => (
        <BlockRow
          key={i}
          block={b}
          index={i}
          total={blocks.length}
          onChange={(updated) => handleChange(i, updated)}
          onRemove={() => handleRemove(i)}
          onMove={(dir) => handleMove(i, dir)}
        />
      ))}
      <button
        type="button"
        onClick={handleAdd}
        className="flex w-full items-center justify-center gap-1.5 rounded-lg border border-dashed border-border py-2 text-xs text-content-secondary hover:border-brand hover:text-brand transition-colors"
      >
        <svg className="h-3.5 w-3.5" fill="none" viewBox="0 0 24 24" strokeWidth={2.5} stroke="currentColor">
          <path strokeLinecap="round" strokeLinejoin="round" d="M12 4.5v15m7.5-7.5h-15" />
        </svg>
        Adicionar bloco
      </button>
    </div>
  );
}
