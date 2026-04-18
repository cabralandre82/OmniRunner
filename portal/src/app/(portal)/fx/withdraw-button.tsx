"use client";

import { useEffect, useState } from "react";

/**
 * L01-02 — O formulário NÃO aceita mais fx_rate do usuário. O rate é buscado
 * server-side em `platform_fx_quotes` via GET /api/custody/fx-quote e exibido
 * apenas como informação (read-only). Previne fraude de admin_master malicioso
 * inflando rate no POST.
 */

interface FxQuoteDisplay {
  rate: number;
  source: string;
  fetched_at: string;
  age_seconds: number;
}

export function WithdrawButton({ available }: { available: number }) {
  const [open, setOpen] = useState(false);
  const [amount, setAmount] = useState("");
  const [currency, setCurrency] = useState<"BRL" | "EUR" | "GBP">("BRL");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState(false);

  const [quote, setQuote] = useState<FxQuoteDisplay | null>(null);
  const [quoteError, setQuoteError] = useState<string | null>(null);
  const [quoteLoading, setQuoteLoading] = useState(false);

  useEffect(() => {
    if (!open) return;
    let active = true;
    async function load() {
      setQuoteLoading(true);
      setQuoteError(null);
      try {
        const res = await fetch(`/api/custody/fx-quote?currency=${currency}`);
        const data = await res.json();
        if (!res.ok) {
          if (active) {
            setQuote(null);
            setQuoteError(data.detail ?? data.error ?? "Cotação indisponível");
          }
          return;
        }
        if (active) setQuote(data as FxQuoteDisplay);
      } catch {
        if (active) setQuoteError("Falha ao buscar cotação");
      } finally {
        if (active) setQuoteLoading(false);
      }
    }
    load();
    return () => {
      active = false;
    };
  }, [open, currency]);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);

    const amountNum = parseFloat(amount);

    if (!amountNum || amountNum <= 0) {
      setError("Valor deve ser positivo");
      return;
    }
    if (amountNum > available) {
      setError(`Valor excede disponivel (${available.toFixed(2)})`);
      return;
    }
    if (!quote) {
      setError("Cotação indisponível. Solicite ao platform_admin refrescar.");
      return;
    }

    setLoading(true);
    try {
      const res = await fetch("/api/custody/withdraw", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          amount_usd: amountNum,
          target_currency: currency,
        }),
      });

      if (!res.ok) {
        const data = await res.json();
        setError(data.detail ?? data.error ?? "Erro ao processar retirada");
        return;
      }

      setSuccess(true);
      setTimeout(() => window.location.reload(), 1500);
    } catch {
      setError("Erro de conexao");
    } finally {
      setLoading(false);
    }
  }

  if (!open) {
    return (
      <button
        onClick={() => setOpen(true)}
        disabled={available <= 0}
        className="rounded-lg bg-orange-600 px-4 py-2 text-sm font-medium text-white hover:bg-orange-700 disabled:opacity-50"
      >
        Solicitar Retirada
      </button>
    );
  }

  if (success) {
    return (
      <div className="rounded-lg border border-success/30 bg-success-soft p-4">
        <p className="font-medium text-success">Retirada processada com sucesso!</p>
      </div>
    );
  }

  const quoteAgeLabel =
    quote && quote.age_seconds != null
      ? quote.age_seconds < 60
        ? `${quote.age_seconds}s atrás`
        : quote.age_seconds < 3600
          ? `${Math.floor(quote.age_seconds / 60)} min atrás`
          : `${Math.floor(quote.age_seconds / 3600)}h atrás`
      : null;

  const estimatedLocal =
    quote && amount
      ? (parseFloat(amount) || 0) * quote.rate
      : null;

  return (
    <form onSubmit={handleSubmit} className="flex flex-wrap items-end gap-3">
      <div>
        <label className="block text-xs font-medium text-content-secondary">Valor (USD)</label>
        <input
          type="number"
          step="0.01"
          min="1"
          max={available}
          value={amount}
          onChange={(e) => setAmount(e.target.value)}
          className="mt-1 w-28 rounded-lg border border-border px-3 py-2 text-sm"
          placeholder="100.00"
        />
      </div>
      <div>
        <label className="block text-xs font-medium text-content-secondary">Moeda</label>
        <select
          value={currency}
          onChange={(e) => setCurrency(e.target.value as "BRL" | "EUR" | "GBP")}
          className="mt-1 rounded-lg border border-border px-3 py-2 text-sm"
        >
          <option value="BRL">BRL</option>
          <option value="EUR">EUR</option>
          <option value="GBP">GBP</option>
        </select>
      </div>
      <div className="min-w-[10rem]">
        <label className="block text-xs font-medium text-content-secondary">
          Cotação oficial ({currency}/USD)
        </label>
        <div className="mt-1 rounded-lg border border-border bg-surface-elevated px-3 py-2 text-sm">
          {quoteLoading && <span className="text-content-muted">Buscando...</span>}
          {quote && (
            <>
              <span className="font-mono text-content-primary">{quote.rate.toFixed(4)}</span>
              <span className="ml-2 text-xs text-content-muted">
                {quote.source}
                {quoteAgeLabel ? ` · ${quoteAgeLabel}` : ""}
              </span>
            </>
          )}
          {quoteError && <span className="text-xs text-error">{quoteError}</span>}
        </div>
      </div>
      {estimatedLocal != null && estimatedLocal > 0 && (
        <div>
          <label className="block text-xs font-medium text-content-secondary">
            Estimativa bruta
          </label>
          <div className="mt-1 rounded-lg border border-border bg-surface-elevated px-3 py-2 text-sm text-content-secondary">
            ~{estimatedLocal.toLocaleString("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 2 })} {currency}
            <span className="ml-1 text-xs text-content-muted">(sem spread)</span>
          </div>
        </div>
      )}
      <button
        type="submit"
        disabled={loading || !quote}
        className="rounded-lg bg-orange-600 px-4 py-2 text-sm font-medium text-white hover:bg-orange-700 disabled:opacity-50"
      >
        {loading ? "..." : "Confirmar"}
      </button>
      <button
        type="button"
        onClick={() => setOpen(false)}
        className="rounded-lg border border-border px-3 py-2 text-sm text-content-secondary hover:bg-surface-elevated"
      >
        Cancelar
      </button>
      {error && <p className="w-full text-sm text-error">{error}</p>}
    </form>
  );
}
