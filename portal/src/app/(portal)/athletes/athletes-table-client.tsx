"use client";

import { useState } from "react";
import Link from "next/link";
import { formatKm, formatDateISO, formatDateMs } from "@/lib/format";
import { notifyAthleteLink } from "@/lib/deep-links";
import { DistributeButton } from "./distribute-button";

const formatDate = formatDateISO;
const formatJoinDate = formatDateMs;

const STATUS_LABELS: Record<string, { label: string; color: string }> = {
  VERIFIED: { label: "Verificado", color: "bg-success-soft text-success" },
  CALIBRATING: { label: "Calibrando", color: "bg-info-soft text-info" },
  MONITORED: { label: "Observação", color: "bg-warning-soft text-warning" },
  DOWNGRADED: { label: "Rebaixado", color: "bg-error-soft text-error" },
  UNVERIFIED: { label: "Sem status", color: "bg-neutral-soft text-content-muted" },
};

interface Athlete {
  user_id: string;
  display_name: string;
  joined_at_ms: number;
  verification_status: string;
  trust_score: number;
  total_sessions: number;
  total_distance_m: number;
  last_session_at: string | null;
}

export function AthletesTableClient({
  athletes,
  isAdmin,
}: {
  athletes: Athlete[];
  isAdmin: boolean;
}) {
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [bulkOpen, setBulkOpen] = useState(false);

  const toggleOne = (id: string) => {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  };

  const toggleAll = () => {
    if (selected.size === athletes.length) setSelected(new Set());
    else setSelected(new Set(athletes.map((a) => a.user_id)));
  };

  const clearSelection = () => {
    setSelected(new Set());
    setBulkOpen(false);
  };

  const selectedCount = selected.size;

  return (
    <div className="space-y-3">
      {selectedCount > 0 && (
        <div className="flex items-center justify-between rounded-lg border border-border bg-surface-elevated px-4 py-2">
          <span className="text-sm font-medium text-content-primary">
            {selectedCount} atleta{selectedCount > 1 ? "s" : ""} selecionado{selectedCount > 1 ? "s" : ""}
          </span>
          <div className="relative">
            <button
              onClick={() => setBulkOpen(!bulkOpen)}
              className="rounded-lg border border-border bg-surface px-3 py-1.5 text-sm font-medium text-content-secondary hover:bg-surface-elevated hover:text-content-primary"
            >
              Ações em lote ▾
            </button>
            {bulkOpen && (
              <>
                <div
                  className="fixed inset-0 z-10"
                  onClick={() => setBulkOpen(false)}
                  aria-hidden
                />
                <div className="absolute right-0 top-full z-20 mt-1 min-w-[180px] rounded-lg border border-border bg-surface py-1 shadow-lg">
                  <button
                    onClick={() => {
                      setBulkOpen(false);
                      // Placeholder — sem integração backend
                      // alert("Enviar notificação em breve");
                    }}
                    className="block w-full px-4 py-2 text-left text-sm text-content-secondary hover:bg-surface-elevated hover:text-content-primary"
                  >
                    Enviar notificação
                  </button>
                  <button
                    onClick={clearSelection}
                    className="block w-full px-4 py-2 text-left text-sm text-content-muted hover:bg-surface-elevated"
                  >
                    Limpar seleção
                  </button>
                </div>
              </>
            )}
          </div>
        </div>
      )}

      <div className="overflow-hidden rounded-xl border border-border bg-surface shadow-sm">
        <div className="overflow-x-auto">
          <table className="min-w-full divide-y divide-border text-sm">
            <thead className="bg-bg-secondary">
              <tr>
                <th className="w-10 px-2 py-3">
                  <input
                    type="checkbox"
                    checked={athletes.length > 0 && selected.size === athletes.length}
                    onChange={toggleAll}
                    className="h-4 w-4 rounded border-border text-brand focus:ring-brand"
                    aria-label="Selecionar todos"
                  />
                </th>
                <th className="px-4 py-3 text-left text-xs font-medium uppercase tracking-wide text-content-muted">
                  Atleta
                </th>
                <th className="px-4 py-3 text-left text-xs font-medium uppercase tracking-wide text-content-muted">
                  Status
                </th>
                <th className="px-4 py-3 text-center text-xs font-medium uppercase tracking-wide text-content-muted">
                  Trust
                </th>
                <th className="px-4 py-3 text-center text-xs font-medium uppercase tracking-wide text-content-muted">
                  Corridas
                </th>
                <th className="px-4 py-3 text-right text-xs font-medium uppercase tracking-wide text-content-muted">
                  Distância
                </th>
                <th className="px-4 py-3 text-left text-xs font-medium uppercase tracking-wide text-content-muted">
                  Última Corrida
                </th>
                <th className="px-4 py-3 text-left text-xs font-medium uppercase tracking-wide text-content-muted">
                  Membro Desde
                </th>
                {isAdmin && (
                  <th className="px-4 py-3 text-center text-xs font-medium uppercase tracking-wide text-content-muted">
                    OmniCoins
                  </th>
                )}
                <th className="px-4 py-3 text-center text-xs font-medium uppercase tracking-wide text-content-muted">
                  Ações
                </th>
              </tr>
            </thead>
            <tbody className="divide-y divide-border-subtle">
              {athletes.map((a) => {
                const s = STATUS_LABELS[a.verification_status] ?? STATUS_LABELS.UNVERIFIED;
                return (
                  <tr key={a.user_id} className="hover:bg-surface-elevated transition-colors">
                    <td className="whitespace-nowrap px-2 py-3">
                      <input
                        type="checkbox"
                        checked={selected.has(a.user_id)}
                        onChange={() => toggleOne(a.user_id)}
                        className="h-4 w-4 rounded border-border text-brand focus:ring-brand"
                        aria-label={`Selecionar ${a.display_name}`}
                      />
                    </td>
                    <td className="whitespace-nowrap px-4 py-3">
                      <p className="font-medium text-content-primary">
                        {a.display_name}
                      </p>
                    </td>
                    <td className="whitespace-nowrap px-4 py-3">
                      <span
                        className={`inline-flex rounded-full px-2.5 py-0.5 text-xs font-medium ${s.color}`}
                      >
                        {s.label}
                      </span>
                    </td>
                    <td className="whitespace-nowrap px-4 py-3 text-center">
                      <span className="font-semibold text-content-primary">
                        {a.trust_score}
                      </span>
                      <span className="text-xs text-content-muted">/100</span>
                    </td>
                    <td className="whitespace-nowrap px-4 py-3 text-center text-content-secondary">
                      {a.total_sessions}
                    </td>
                    <td className="whitespace-nowrap px-4 py-3 text-right text-content-secondary">
                      {formatKm(a.total_distance_m)} km
                    </td>
                    <td className="whitespace-nowrap px-4 py-3 text-content-muted">
                      {formatDate(a.last_session_at)}
                    </td>
                    <td className="whitespace-nowrap px-4 py-3 text-content-muted">
                      {formatJoinDate(a.joined_at_ms)}
                    </td>
                    {isAdmin && (
                      <td className="whitespace-nowrap px-4 py-3 text-center">
                        <DistributeButton
                          athleteId={a.user_id}
                          athleteName={a.display_name}
                        />
                      </td>
                    )}
                    <td className="whitespace-nowrap px-4 py-3 text-center">
                      <div className="flex items-center justify-center gap-1">
                        <Link
                          href={`/athletes/${a.user_id}`}
                          className="rounded-lg p-1.5 text-content-muted hover:bg-surface-elevated hover:text-content-primary transition-colors"
                          title="Ver perfil"
                        >
                          <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" strokeWidth={1.5} stroke="currentColor">
                            <path strokeLinecap="round" strokeLinejoin="round" d="M2.036 12.322a1.012 1.012 0 010-.639C3.423 7.51 7.36 4.5 12 4.5c4.64 0 8.577 3.007 9.963 7.178.07.207.07.431 0 .639C20.577 16.49 16.64 19.5 12 19.5c-4.64 0-8.577-3.007-9.963-7.178z" />
                            <path strokeLinecap="round" strokeLinejoin="round" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
                          </svg>
                        </Link>
                        <CopyDeepLinkButton userId={a.user_id} displayName={a.display_name} />
                      </div>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}

function CopyDeepLinkButton({ userId, displayName }: { userId: string; displayName: string }) {
  const [copied, setCopied] = useState(false);

  const handleCopy = async () => {
    const link = notifyAthleteLink(userId);
    try {
      await navigator.clipboard.writeText(link);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      // fallback: ignore
    }
  };

  return (
    <button
      onClick={handleCopy}
      className="relative rounded-lg p-1.5 text-content-muted hover:bg-surface-elevated hover:text-content-primary transition-colors"
      title={`Copiar deep link — ${displayName}`}
    >
      {copied ? (
        <svg className="h-4 w-4 text-success" fill="none" viewBox="0 0 24 24" strokeWidth={2} stroke="currentColor">
          <path strokeLinecap="round" strokeLinejoin="round" d="M4.5 12.75l6 6 9-13.5" />
        </svg>
      ) : (
        <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" strokeWidth={1.5} stroke="currentColor">
          <path strokeLinecap="round" strokeLinejoin="round" d="M13.19 8.688a4.5 4.5 0 011.242 7.244l-4.5 4.5a4.5 4.5 0 01-6.364-6.364l1.757-1.757m13.35-.622l1.757-1.757a4.5 4.5 0 00-6.364-6.364l-4.5 4.5a4.5 4.5 0 001.242 7.244" />
        </svg>
      )}
      {copied && (
        <span className="absolute -top-8 left-1/2 -translate-x-1/2 whitespace-nowrap rounded bg-success px-2 py-0.5 text-xs font-medium text-white shadow">
          Copiado!
        </span>
      )}
    </button>
  );
}
