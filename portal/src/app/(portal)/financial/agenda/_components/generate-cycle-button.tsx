"use client";

/**
 * L09-15 · Botão admin-only para forçar geração do ciclo de invoices.
 *
 * Chama POST /api/financial/generate-cycle e, em caso de sucesso,
 * recarrega a página para que o server-component re-fetche a agenda.
 */

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";

interface GenerateCycleResponse {
  ok: boolean;
  data?: {
    ok: boolean;
    period_month: string;
    total_active_subs: number;
    inserted: number;
    skipped: number;
  };
  error?: { code: string; message: string };
}

export function GenerateCycleButton({
  periodMonth,
  label = "Forçar geração do ciclo",
  variant = "secondary",
}: {
  /** YYYY-MM-01 — se omitido, a API usa o mês corrente. */
  periodMonth?: string;
  label?: string;
  variant?: "primary" | "secondary";
}) {
  const router = useRouter();
  const [isPending, startTransition] = useTransition();
  const [msg, setMsg] = useState<string | null>(null);

  const handleClick = async () => {
    setMsg(null);
    const body: Record<string, string> = {};
    if (periodMonth) body.period_month = periodMonth;

    try {
      const res = await fetch("/api/financial/generate-cycle", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
      });
      const json = (await res.json()) as GenerateCycleResponse;

      if (!res.ok || !json.ok) {
        const errMsg = json.error?.message ?? "Falha ao gerar ciclo.";
        setMsg(`Erro: ${errMsg}`);
        return;
      }

      const d = json.data!;
      setMsg(
        `Geração concluída · ${d.inserted} criada(s) · ${d.skipped} já existia(m) · ${d.total_active_subs} ativa(s)`,
      );

      // Refresh do server-component pra popular a lista.
      startTransition(() => router.refresh());
    } catch (e) {
      setMsg(`Erro: ${String(e)}`);
    }
  };

  const baseCls =
    "inline-flex items-center gap-2 rounded-lg px-3 py-1.5 text-xs font-medium transition disabled:cursor-not-allowed disabled:opacity-60";
  const variantCls =
    variant === "primary"
      ? "bg-brand text-white hover:bg-brand-strong"
      : "border border-border bg-surface text-content-secondary hover:bg-surface-elevated";

  return (
    <div className="flex flex-col items-end gap-1">
      <button
        type="button"
        onClick={handleClick}
        disabled={isPending}
        className={`${baseCls} ${variantCls}`}
      >
        {isPending ? "Gerando..." : label}
      </button>
      {msg && (
        <p
          className={`text-xs ${
            msg.startsWith("Erro") ? "text-error" : "text-content-secondary"
          }`}
        >
          {msg}
        </p>
      )}
    </div>
  );
}
