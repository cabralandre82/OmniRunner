"use client";

import { useState } from "react";

export function DistributeButton({
  athleteId,
  athleteName,
}: {
  athleteId: string;
  athleteName: string;
}) {
  const [open, setOpen] = useState(false);
  const [amount, setAmount] = useState("");
  const [loading, setLoading] = useState(false);
  const [result, setResult] = useState<{ ok?: boolean; error?: string } | null>(
    null,
  );

  async function handleSubmit() {
    const num = parseInt(amount, 10);
    if (!num || num < 1 || num > 1000) {
      setResult({ error: "Valor deve ser entre 1 e 1000" });
      return;
    }

    setLoading(true);
    setResult(null);

    try {
      const res = await fetch("/api/distribute-coins", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ athlete_user_id: athleteId, amount: num }),
      });
      const data = await res.json();

      if (res.ok) {
        setResult({ ok: true });
        setAmount("");
        setTimeout(() => {
          setOpen(false);
          setResult(null);
        }, 1500);
      } else {
        setResult({ error: data.error ?? "Erro desconhecido" });
      }
    } catch {
      setResult({ error: "Erro de conexão" });
    } finally {
      setLoading(false);
    }
  }

  if (!open) {
    return (
      <button
        onClick={() => setOpen(true)}
        className="rounded-lg bg-indigo-50 px-2.5 py-1 text-xs font-medium text-indigo-700 hover:bg-indigo-100"
      >
        Distribuir
      </button>
    );
  }

  return (
    <div className="flex items-center gap-2">
      <input
        type="number"
        min={1}
        max={1000}
        value={amount}
        onChange={(e) => setAmount(e.target.value)}
        placeholder="Qtd"
        className="w-20 rounded-lg border border-gray-300 px-2 py-1 text-xs focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
        disabled={loading}
      />
      <button
        onClick={handleSubmit}
        disabled={loading}
        className="rounded-lg bg-indigo-600 px-2.5 py-1 text-xs font-medium text-white hover:bg-indigo-700 disabled:opacity-50"
      >
        {loading ? "..." : "Enviar"}
      </button>
      <button
        onClick={() => {
          setOpen(false);
          setResult(null);
        }}
        className="text-xs text-gray-400 hover:text-gray-600"
      >
        Cancelar
      </button>
      {result?.ok && (
        <span className="text-xs font-medium text-green-600">
          {amount} OmniCoins enviadas para {athleteName}
        </span>
      )}
      {result?.error && (
        <span className="text-xs font-medium text-red-600">{result.error}</span>
      )}
    </div>
  );
}
