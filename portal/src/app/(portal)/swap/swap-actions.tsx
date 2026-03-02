"use client";

import { useState } from "react";

export function SwapActions({
  acceptOrderId,
}: {
  acceptOrderId?: string;
}) {
  const [loading, setLoading] = useState(false);
  const [showCreate, setShowCreate] = useState(false);
  const [amount, setAmount] = useState("");
  const [message, setMessage] = useState("");

  async function handleAccept() {
    if (!acceptOrderId) return;
    setLoading(true);

    try {
      const res = await fetch("/api/swap", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "accept", order_id: acceptOrderId }),
      });

      const data = await res.json();
      if (!res.ok) {
        alert(data.error ?? "Erro ao aceitar oferta");
        return;
      }

      window.location.reload();
    } catch {
      alert("Erro de conexão");
    } finally {
      setLoading(false);
    }
  }

  async function handleCreate() {
    const val = parseFloat(amount);
    if (!val || val < 100) {
      setMessage("Valor mínimo: US$ 100.00");
      return;
    }

    setLoading(true);
    setMessage("");

    try {
      const res = await fetch("/api/swap", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "create", amount_usd: val }),
      });

      const data = await res.json();
      if (!res.ok) {
        setMessage(data.error ?? "Erro ao criar oferta");
        return;
      }

      setShowCreate(false);
      setAmount("");
      window.location.reload();
    } catch {
      setMessage("Erro de conexão");
    } finally {
      setLoading(false);
    }
  }

  if (acceptOrderId) {
    return (
      <button
        onClick={handleAccept}
        disabled={loading}
        className="rounded-lg bg-green-600 px-3 py-1.5 text-xs font-medium text-white hover:bg-green-700 disabled:opacity-50 transition"
      >
        {loading ? "..." : "Comprar"}
      </button>
    );
  }

  if (!showCreate) {
    return (
      <button
        onClick={() => setShowCreate(true)}
        className="rounded-lg bg-blue-600 px-4 py-2 text-sm font-medium text-white hover:bg-blue-700 transition"
      >
        Criar Oferta de Venda
      </button>
    );
  }

  return (
    <div className="rounded-xl border border-gray-200 bg-white p-4 shadow-lg w-72">
      <h3 className="text-sm font-semibold text-gray-900 mb-3">
        Vender Lastro
      </h3>

      <input
        type="number"
        min={100}
        step={1}
        value={amount}
        onChange={(e) => setAmount(e.target.value)}
        placeholder="5000"
        className="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm mb-3"
      />

      {message && (
        <p className="text-xs text-red-600 mb-2">{message}</p>
      )}

      <div className="flex gap-2">
        <button
          onClick={handleCreate}
          disabled={loading}
          className="flex-1 rounded-lg bg-blue-600 px-3 py-2 text-sm font-medium text-white hover:bg-blue-700 disabled:opacity-50 transition"
        >
          {loading ? "..." : "Publicar"}
        </button>
        <button
          onClick={() => setShowCreate(false)}
          className="rounded-lg border border-gray-300 px-3 py-2 text-sm text-gray-600 hover:bg-gray-50 transition"
        >
          Cancelar
        </button>
      </div>
    </div>
  );
}
