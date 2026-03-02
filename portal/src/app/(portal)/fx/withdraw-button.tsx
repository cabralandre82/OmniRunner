"use client";

import { useState } from "react";

export function WithdrawButton({ available }: { available: number }) {
  const [open, setOpen] = useState(false);
  const [amount, setAmount] = useState("");
  const [fxRate, setFxRate] = useState("");
  const [currency, setCurrency] = useState("BRL");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState(false);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);

    const amountNum = parseFloat(amount);
    const rateNum = parseFloat(fxRate);

    if (!amountNum || amountNum <= 0) {
      setError("Valor deve ser positivo");
      return;
    }
    if (amountNum > available) {
      setError(`Valor excede disponivel (${available.toFixed(2)})`);
      return;
    }
    if (!rateNum || rateNum <= 0) {
      setError("Cotacao deve ser positiva");
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
          fx_rate: rateNum,
        }),
      });

      if (!res.ok) {
        const data = await res.json();
        setError(data.error ?? "Erro ao processar retirada");
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
      <div className="rounded-lg border border-green-200 bg-green-50 p-4">
        <p className="font-medium text-green-800">Retirada processada com sucesso!</p>
      </div>
    );
  }

  return (
    <form onSubmit={handleSubmit} className="flex items-end gap-3">
      <div>
        <label className="block text-xs font-medium text-gray-500">Valor (USD)</label>
        <input
          type="number"
          step="0.01"
          min="1"
          max={available}
          value={amount}
          onChange={(e) => setAmount(e.target.value)}
          className="mt-1 w-28 rounded-lg border border-gray-300 px-3 py-2 text-sm"
          placeholder="100.00"
        />
      </div>
      <div>
        <label className="block text-xs font-medium text-gray-500">Cotacao ({currency}/USD)</label>
        <input
          type="number"
          step="0.0001"
          min="0.01"
          value={fxRate}
          onChange={(e) => setFxRate(e.target.value)}
          className="mt-1 w-28 rounded-lg border border-gray-300 px-3 py-2 text-sm"
          placeholder="5.2500"
        />
      </div>
      <div>
        <label className="block text-xs font-medium text-gray-500">Moeda</label>
        <select
          value={currency}
          onChange={(e) => setCurrency(e.target.value)}
          className="mt-1 rounded-lg border border-gray-300 px-3 py-2 text-sm"
        >
          <option value="BRL">BRL</option>
          <option value="EUR">EUR</option>
          <option value="GBP">GBP</option>
        </select>
      </div>
      <button
        type="submit"
        disabled={loading}
        className="rounded-lg bg-orange-600 px-4 py-2 text-sm font-medium text-white hover:bg-orange-700 disabled:opacity-50"
      >
        {loading ? "..." : "Confirmar"}
      </button>
      <button
        type="button"
        onClick={() => setOpen(false)}
        className="rounded-lg border border-gray-300 px-3 py-2 text-sm text-gray-600 hover:bg-gray-50"
      >
        Cancelar
      </button>
      {error && <p className="text-sm text-red-600">{error}</p>}
    </form>
  );
}
