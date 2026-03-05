"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

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

interface Template {
  id: string;
  name: string;
  block_count: number;
}

const WATCH_LABELS: Record<string, string> = {
  garmin: "Garmin",
  coros: "COROS",
  suunto: "Suunto",
  apple_watch: "Apple Watch",
  polar: "Polar",
  other: "Outro",
};

const WATCH_COLORS: Record<string, string> = {
  garmin: "bg-green-100 text-green-800 dark:bg-green-900/30 dark:text-green-300",
  coros: "bg-green-100 text-green-800 dark:bg-green-900/30 dark:text-green-300",
  suunto: "bg-green-100 text-green-800 dark:bg-green-900/30 dark:text-green-300",
  polar: "bg-yellow-100 text-yellow-800 dark:bg-yellow-900/30 dark:text-yellow-300",
  apple_watch: "bg-orange-100 text-orange-800 dark:bg-orange-900/30 dark:text-orange-300",
  other: "bg-gray-100 text-gray-700 dark:bg-gray-700/30 dark:text-gray-300",
};

const FIT_COMPATIBLE = new Set(["garmin", "coros", "suunto"]);

const STATUS_LABELS: Record<string, string> = {
  planned: "Planejado",
  completed: "Concluído",
  missed: "Perdido",
};

const STATUS_COLORS: Record<string, string> = {
  planned: "bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-300",
  completed: "bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-300",
  missed: "bg-red-100 text-red-700 dark:bg-red-900/30 dark:text-red-300",
};

export function AssignWorkoutClient({
  athletes,
  templates,
}: {
  athletes: Athlete[];
  templates: Template[];
}) {
  const router = useRouter();
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());
  const [templateId, setTemplateId] = useState("");
  const [date, setDate] = useState(() => {
    const d = new Date();
    return d.toISOString().split("T")[0];
  });
  const [loading, setLoading] = useState(false);
  const [result, setResult] = useState<{
    ok: boolean;
    success: number;
    total: number;
  } | null>(null);
  const [search, setSearch] = useState("");
  const [watchFilter, setWatchFilter] = useState<string>("all");
  const [editingWatch, setEditingWatch] = useState<string | null>(null);

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
      const allSelected = visible.every((id) => next.has(id));
      if (allSelected) {
        visible.forEach((id) => next.delete(id));
      } else {
        visible.forEach((id) => next.add(id));
      }
      return next;
    });
  };

  const handleAssign = async () => {
    if (!templateId || selectedIds.size === 0) return;
    setLoading(true);
    setResult(null);
    try {
      const res = await fetch("/api/workouts/assign", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          template_id: templateId,
          athlete_user_ids: Array.from(selectedIds),
          scheduled_date: date,
        }),
      });
      const data = await res.json();
      setResult({ ok: data.ok, success: data.success, total: data.total });
      if (data.ok) {
        setSelectedIds(new Set());
        router.refresh();
      }
    } finally {
      setLoading(false);
    }
  };

  const handleWatchTypeChange = async (
    memberId: string,
    newType: string | null
  ) => {
    try {
      await fetch("/api/workouts/watch-type", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ member_id: memberId, watch_type: newType }),
      });
      setEditingWatch(null);
      router.refresh();
    } catch {
      // silent
    }
  };

  const filteredAthletes = athletes.filter((a) => {
    if (search && !a.display_name.toLowerCase().includes(search.toLowerCase()))
      return false;
    if (watchFilter === "fit" && !FIT_COMPATIBLE.has(a.watch_type ?? ""))
      return false;
    if (watchFilter === "no_fit" && FIT_COMPATIBLE.has(a.watch_type ?? ""))
      return false;
    if (watchFilter === "unknown" && a.watch_type != null) return false;
    return true;
  });

  const allVisibleSelected =
    filteredAthletes.length > 0 &&
    filteredAthletes.every((a) => selectedIds.has(a.user_id));

  const fitCount = athletes.filter((a) =>
    FIT_COMPATIBLE.has(a.watch_type ?? "")
  ).length;
  const noFitCount = athletes.filter(
    (a) => a.watch_type && !FIT_COMPATIBLE.has(a.watch_type)
  ).length;
  const unknownCount = athletes.filter((a) => !a.watch_type).length;

  return (
    <>
      {/* KPI badges */}
      <div className="flex flex-wrap gap-3">
        <div className="rounded-lg border border-border bg-surface px-4 py-2 text-sm">
          <span className="font-semibold text-content-primary">
            {athletes.length}
          </span>{" "}
          <span className="text-content-secondary">atletas</span>
        </div>
        <div className="rounded-lg border border-green-200 bg-green-50 px-4 py-2 text-sm dark:border-green-800 dark:bg-green-900/20">
          <span className="font-semibold text-green-800 dark:text-green-300">
            {fitCount}
          </span>{" "}
          <span className="text-green-700 dark:text-green-400">
            compatíveis .FIT
          </span>
        </div>
        {noFitCount > 0 && (
          <div className="rounded-lg border border-orange-200 bg-orange-50 px-4 py-2 text-sm dark:border-orange-800 dark:bg-orange-900/20">
            <span className="font-semibold text-orange-800 dark:text-orange-300">
              {noFitCount}
            </span>{" "}
            <span className="text-orange-700 dark:text-orange-400">
              envio manual
            </span>
          </div>
        )}
        {unknownCount > 0 && (
          <div className="rounded-lg border border-gray-200 bg-gray-50 px-4 py-2 text-sm dark:border-gray-700 dark:bg-gray-800/30">
            <span className="font-semibold text-gray-700 dark:text-gray-300">
              {unknownCount}
            </span>{" "}
            <span className="text-gray-500 dark:text-gray-400">
              sem relógio definido
            </span>
          </div>
        )}
      </div>

      {/* Assignment form */}
      <div className="rounded-xl border border-border bg-surface p-4 shadow-sm">
        <div className="flex flex-wrap items-end gap-4">
          <div className="min-w-[200px] flex-1">
            <label className="mb-1 block text-xs font-medium text-content-secondary">
              Template
            </label>
            <select
              value={templateId}
              onChange={(e) => setTemplateId(e.target.value)}
              className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm focus:border-brand focus:ring-1 focus:ring-brand"
            >
              <option value="">Selecione um template...</option>
              {templates.map((t) => (
                <option key={t.id} value={t.id}>
                  {t.name} ({t.block_count} blocos)
                </option>
              ))}
            </select>
          </div>
          <div className="w-44">
            <label className="mb-1 block text-xs font-medium text-content-secondary">
              Data
            </label>
            <input
              type="date"
              value={date}
              onChange={(e) => setDate(e.target.value)}
              className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm focus:border-brand focus:ring-1 focus:ring-brand"
            />
          </div>
          <button
            onClick={handleAssign}
            disabled={loading || !templateId || selectedIds.size === 0}
            className="rounded-lg bg-brand px-5 py-2 text-sm font-medium text-white hover:bg-brand/90 disabled:opacity-50"
          >
            {loading
              ? "Atribuindo..."
              : `Atribuir a ${selectedIds.size} atleta${selectedIds.size !== 1 ? "s" : ""}`}
          </button>
        </div>

        {result && (
          <div
            className={`mt-3 rounded-lg px-4 py-2 text-sm ${
              result.ok
                ? "border border-green-200 bg-green-50 text-green-800 dark:border-green-800 dark:bg-green-900/20 dark:text-green-300"
                : "border border-red-200 bg-red-50 text-red-800 dark:border-red-800 dark:bg-red-900/20 dark:text-red-300"
            }`}
          >
            {result.success}/{result.total} atribuições realizadas com sucesso.
          </div>
        )}
      </div>

      {/* Filters */}
      <div className="flex flex-wrap items-center gap-3">
        <input
          type="text"
          placeholder="Buscar atleta..."
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          className="rounded-lg border border-border bg-surface px-3 py-1.5 text-sm focus:border-brand focus:ring-1 focus:ring-brand"
        />
        <select
          value={watchFilter}
          onChange={(e) => setWatchFilter(e.target.value)}
          className="rounded-lg border border-border bg-surface px-3 py-1.5 text-sm focus:border-brand focus:ring-1 focus:ring-brand"
        >
          <option value="all">Todos os relógios</option>
          <option value="fit">Compatível .FIT</option>
          <option value="no_fit">Envio manual</option>
          <option value="unknown">Sem relógio</option>
        </select>
      </div>

      {/* Athletes table */}
      <div className="overflow-hidden rounded-xl border border-border bg-surface shadow-sm">
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
                    <td className="px-4 py-3" onClick={(e) => e.stopPropagation()}>
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
                              e.target.value || null
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
                              ? WATCH_COLORS[athlete.watch_type] ??
                                WATCH_COLORS.other
                              : "bg-gray-100 text-gray-500 dark:bg-gray-700/30 dark:text-gray-400"
                          }`}
                          title="Clique para alterar"
                        >
                          {athlete.watch_type
                            ? WATCH_LABELS[athlete.watch_type] ??
                              athlete.watch_type
                            : "Definir"}
                        </button>
                      )}
                    </td>
                    <td className="whitespace-nowrap px-4 py-3 text-center">
                      {fitOk ? (
                        <span
                          className="text-green-600 dark:text-green-400"
                          title="Compatível com .FIT — treino enviado direto ao relógio"
                        >
                          ✓
                        </span>
                      ) : athlete.watch_type ? (
                        <span
                          className="text-orange-500 dark:text-orange-400"
                          title="Enviar treino por outro meio (WhatsApp, app do relógio)"
                        >
                          ⚠
                        </span>
                      ) : (
                        <span className="text-gray-400">—</span>
                      )}
                    </td>
                    <td className="px-4 py-3" onClick={(e) => e.stopPropagation()}>
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
                            {new Date(a.scheduled_date + "T12:00:00").toLocaleDateString(
                              "pt-BR",
                              { day: "2-digit", month: "2-digit" }
                            )}{" "}
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
      </div>

      {filteredAthletes.length === 0 && (
        <div className="rounded-xl border border-border bg-surface p-8 text-center shadow-sm">
          <p className="text-sm text-content-secondary">
            {search || watchFilter !== "all"
              ? "Nenhum atleta encontrado com os filtros aplicados."
              : "Nenhum atleta vinculado ao grupo."}
          </p>
        </div>
      )}
    </>
  );
}
