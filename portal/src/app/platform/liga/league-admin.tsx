"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

interface Props {
  seasons: Record<string, unknown>[];
  activeSeason: Record<string, unknown> | null;
  enrollments: Record<string, unknown>[];
  snapshots: Record<string, unknown>[];
}

export function LeagueAdmin({
  seasons,
  activeSeason,
  enrollments,
  snapshots,
}: Props) {
  const router = useRouter();
  const [loading, setLoading] = useState(false);
  const [showCreate, setShowCreate] = useState(false);
  const [name, setName] = useState("");
  const [startDate, setStartDate] = useState("");
  const [endDate, setEndDate] = useState("");
  const [message, setMessage] = useState<string | null>(null);

  async function apiCall(body: Record<string, unknown>) {
    setLoading(true);
    setMessage(null);
    try {
      const res = await fetch("/api/platform/liga", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
      });
      const data = await res.json();
      if (!res.ok) {
        setMessage(`Erro: ${data.error ?? res.statusText}`);
      } else {
        setMessage(
          data.status === "activated"
            ? `Temporada ativada. ${data.enrolled} assessorias inscritas automaticamente.`
            : data.status === "completed"
              ? "Temporada encerrada."
              : data.status === "created"
                ? "Temporada criada."
                : data.snapshots != null
                  ? `Snapshot gerado: ${data.snapshots} assessorias processadas, ${data.auto_enrolled ?? 0} novas inscritas.`
                  : JSON.stringify(data),
        );
        router.refresh();
      }
    } catch (err) {
      setMessage(`Erro de rede: ${err}`);
    } finally {
      setLoading(false);
    }
  }

  async function handleCreate() {
    if (!name || !startDate || !endDate) return;
    await apiCall({
      action: "create_season",
      name,
      start_at_ms: new Date(startDate).getTime(),
      end_at_ms: new Date(endDate).getTime(),
    });
    setShowCreate(false);
    setName("");
    setStartDate("");
    setEndDate("");
  }

  return (
    <>
      {message && (
        <div
          className={`rounded-lg px-4 py-3 text-sm ${
            message.startsWith("Erro")
              ? "bg-red-50 text-red-700"
              : "bg-green-50 text-green-700"
          }`}
        >
          {message}
        </div>
      )}

      {/* Active season card */}
      <div className="rounded-xl border border-gray-200 bg-white p-6">
        <div className="flex items-center justify-between">
          <h2 className="text-lg font-semibold text-gray-900">
            Temporada Ativa
          </h2>
          <div className="flex gap-2">
            {activeSeason && (
              <>
                <button
                  onClick={() => apiCall({ action: "trigger_snapshot" })}
                  disabled={loading}
                  className="rounded-lg bg-blue-600 px-3 py-1.5 text-xs font-medium text-white hover:bg-blue-700 disabled:opacity-50"
                >
                  Gerar Snapshot Agora
                </button>
                <button
                  onClick={() =>
                    apiCall({
                      action: "complete_season",
                      season_id: activeSeason.id,
                    })
                  }
                  disabled={loading}
                  className="rounded-lg bg-gray-600 px-3 py-1.5 text-xs font-medium text-white hover:bg-gray-700 disabled:opacity-50"
                >
                  Encerrar
                </button>
              </>
            )}
          </div>
        </div>

        {activeSeason ? (
          <div className="mt-4 grid grid-cols-3 gap-4">
            <Stat
              label="Nome"
              value={activeSeason.name as string}
            />
            <Stat
              label="Início"
              value={new Date(
                activeSeason.start_at_ms as number,
              ).toLocaleDateString("pt-BR")}
            />
            <Stat
              label="Fim"
              value={new Date(
                activeSeason.end_at_ms as number,
              ).toLocaleDateString("pt-BR")}
            />
            <Stat
              label="Assessorias inscritas"
              value={String(enrollments.length)}
            />
            <Stat
              label="Última semana"
              value={
                snapshots.length > 0
                  ? (snapshots[0].week_key as string)
                  : "—"
              }
            />
            <Stat
              label="Dias restantes"
              value={String(
                Math.max(
                  0,
                  Math.ceil(
                    ((activeSeason.end_at_ms as number) - Date.now()) /
                      86400000,
                  ),
                ),
              )}
            />
          </div>
        ) : (
          <p className="mt-4 text-sm text-gray-400">
            Nenhuma temporada ativa. Crie ou ative uma temporada abaixo.
          </p>
        )}
      </div>

      {/* Ranking */}
      {snapshots.length > 0 && (
        <div className="rounded-xl border border-gray-200 bg-white p-6">
          <h2 className="text-lg font-semibold text-gray-900 mb-4">
            Ranking — {snapshots[0].week_key as string}
          </h2>
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-gray-100 text-left text-xs text-gray-500">
                <th className="pb-2 pr-4">#</th>
                <th className="pb-2 pr-4">Assessoria</th>
                <th className="pb-2 pr-4">Local</th>
                <th className="pb-2 pr-4 text-right">Score</th>
                <th className="pb-2 pr-4 text-right">Semana</th>
                <th className="pb-2 pr-4 text-right">Km</th>
                <th className="pb-2 pr-4 text-right">Sessões</th>
                <th className="pb-2 text-right">Ativos</th>
              </tr>
            </thead>
            <tbody>
              {snapshots.map((s, i) => {
                const rank = s.rank as number;
                const prevRank = s.prev_rank as number | null;
                let delta = "";
                if (prevRank != null && prevRank !== rank) {
                  const diff = prevRank - rank;
                  delta = diff > 0 ? ` ↑${diff}` : ` ↓${Math.abs(diff)}`;
                }

                return (
                  <tr
                    key={i}
                    className="border-b border-gray-50 hover:bg-gray-50"
                  >
                    <td className="py-2.5 pr-4 font-semibold">
                      {rank <= 3
                        ? ["🥇", "🥈", "🥉"][rank - 1]
                        : `#${rank}`}
                      {delta && (
                        <span
                          className={`ml-1 text-xs ${
                            delta.includes("↑")
                              ? "text-green-600"
                              : "text-red-500"
                          }`}
                        >
                          {delta}
                        </span>
                      )}
                    </td>
                    <td className="py-2.5 pr-4 font-medium text-gray-900">
                      {s.group_name as string}
                    </td>
                    <td className="py-2.5 pr-4 text-gray-500">
                      {[s.city, s.state]
                        .filter((v) => v && v !== "")
                        .join(", ") || "—"}
                    </td>
                    <td className="py-2.5 pr-4 text-right font-semibold text-blue-600">
                      {(s.cumulative_score as number).toFixed(0)}
                    </td>
                    <td className="py-2.5 pr-4 text-right text-gray-500">
                      {(s.week_score as number).toFixed(1)}
                    </td>
                    <td className="py-2.5 pr-4 text-right">
                      {(s.total_km as number).toFixed(0)}
                    </td>
                    <td className="py-2.5 pr-4 text-right">
                      {s.total_sessions as number}
                    </td>
                    <td className="py-2.5 text-right">
                      {s.active_members as number}/{s.total_members as number}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}

      {/* All seasons */}
      <div className="rounded-xl border border-gray-200 bg-white p-6">
        <div className="flex items-center justify-between mb-4">
          <h2 className="text-lg font-semibold text-gray-900">
            Todas as Temporadas
          </h2>
          <button
            onClick={() => setShowCreate(!showCreate)}
            className="rounded-lg bg-green-600 px-3 py-1.5 text-xs font-medium text-white hover:bg-green-700"
          >
            + Nova Temporada
          </button>
        </div>

        {showCreate && (
          <div className="mb-6 rounded-lg border border-gray-200 bg-gray-50 p-4 space-y-3">
            <div>
              <label className="block text-xs font-medium text-gray-600 mb-1">
                Nome
              </label>
              <input
                type="text"
                value={name}
                onChange={(e) => setName(e.target.value)}
                placeholder="Liga Q1 2026"
                className="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm"
              />
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className="block text-xs font-medium text-gray-600 mb-1">
                  Início
                </label>
                <input
                  type="date"
                  value={startDate}
                  onChange={(e) => setStartDate(e.target.value)}
                  className="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm"
                />
              </div>
              <div>
                <label className="block text-xs font-medium text-gray-600 mb-1">
                  Fim
                </label>
                <input
                  type="date"
                  value={endDate}
                  onChange={(e) => setEndDate(e.target.value)}
                  className="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm"
                />
              </div>
            </div>
            <div className="flex gap-2 pt-1">
              <button
                onClick={handleCreate}
                disabled={loading || !name || !startDate || !endDate}
                className="rounded-lg bg-green-600 px-4 py-2 text-sm font-medium text-white hover:bg-green-700 disabled:opacity-50"
              >
                Criar
              </button>
              <button
                onClick={() => setShowCreate(false)}
                className="rounded-lg px-4 py-2 text-sm font-medium text-gray-600 hover:bg-gray-100"
              >
                Cancelar
              </button>
            </div>
          </div>
        )}

        {seasons.length === 0 ? (
          <p className="text-sm text-gray-400">Nenhuma temporada criada.</p>
        ) : (
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-gray-100 text-left text-xs text-gray-500">
                <th className="pb-2 pr-4">Nome</th>
                <th className="pb-2 pr-4">Início</th>
                <th className="pb-2 pr-4">Fim</th>
                <th className="pb-2 pr-4">Status</th>
                <th className="pb-2 text-right">Ações</th>
              </tr>
            </thead>
            <tbody>
              {seasons.map((s) => (
                <tr
                  key={s.id as string}
                  className="border-b border-gray-50 hover:bg-gray-50"
                >
                  <td className="py-2.5 pr-4 font-medium text-gray-900">
                    {s.name as string}
                  </td>
                  <td className="py-2.5 pr-4 text-gray-500">
                    {new Date(s.start_at_ms as number).toLocaleDateString(
                      "pt-BR",
                    )}
                  </td>
                  <td className="py-2.5 pr-4 text-gray-500">
                    {new Date(s.end_at_ms as number).toLocaleDateString(
                      "pt-BR",
                    )}
                  </td>
                  <td className="py-2.5 pr-4">
                    <StatusBadge status={s.status as string} />
                  </td>
                  <td className="py-2.5 text-right">
                    {s.status === "upcoming" && (
                      <button
                        onClick={() =>
                          apiCall({
                            action: "activate_season",
                            season_id: s.id,
                          })
                        }
                        disabled={loading}
                        className="rounded bg-blue-600 px-2.5 py-1 text-xs font-medium text-white hover:bg-blue-700 disabled:opacity-50"
                      >
                        Ativar
                      </button>
                    )}
                    {s.status === "active" && (
                      <button
                        onClick={() =>
                          apiCall({
                            action: "complete_season",
                            season_id: s.id,
                          })
                        }
                        disabled={loading}
                        className="rounded bg-gray-600 px-2.5 py-1 text-xs font-medium text-white hover:bg-gray-700 disabled:opacity-50"
                      >
                        Encerrar
                      </button>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </>
  );
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <p className="text-xs text-gray-500">{label}</p>
      <p className="text-lg font-semibold text-gray-900">{value}</p>
    </div>
  );
}

function StatusBadge({ status }: { status: string }) {
  const styles: Record<string, string> = {
    upcoming: "bg-yellow-50 text-yellow-700",
    active: "bg-green-50 text-green-700",
    completed: "bg-gray-100 text-gray-500",
  };
  const labels: Record<string, string> = {
    upcoming: "Programada",
    active: "Ativa",
    completed: "Encerrada",
  };

  return (
    <span
      className={`inline-block rounded-full px-2.5 py-0.5 text-xs font-medium ${
        styles[status] ?? "bg-gray-100 text-gray-500"
      }`}
    >
      {labels[status] ?? status}
    </span>
  );
}
