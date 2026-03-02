"use client";

import { useState } from "react";

export function DepositButton() {
  const [open, setOpen] = useState(false);
  const [amount, setAmount] = useState("");
  const [gateway, setGateway] = useState<"stripe" | "mercadopago">("stripe");
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState("");

  async function handleSubmit() {
    const val = parseFloat(amount);
    if (!val || val < 10) {
      setMessage("Valor mínimo: US$ 10.00");
      return;
    }

    setLoading(true);
    setMessage("");

    try {
      const res = await fetch("/api/custody", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ amount_usd: val, gateway }),
      });

      const data = await res.json();
      if (!res.ok) {
        setMessage(data.error ?? "Erro ao criar depósito");
        return;
      }

      setMessage("Depósito criado com sucesso!");
      setOpen(false);
      setAmount("");
      window.location.reload();
    } catch {
      setMessage("Erro de conexão");
    } finally {
      setLoading(false);
    }
  }

  if (!open) {
    return (
      <button
        onClick={() => setOpen(true)}
        className="rounded-lg bg-blue-600 px-4 py-2 text-sm font-medium text-white hover:bg-blue-700 transition"
      >
        Depositar Lastro
      </button>
    );
  }

  return (
    <div className="rounded-xl border border-gray-200 bg-white p-4 shadow-lg w-80">
      <h3 className="text-sm font-semibold text-gray-900 mb-3">
        Novo Depósito de Lastro
      </h3>

      <label className="block text-xs font-medium text-gray-600 mb-1">
        Valor (USD)
      </label>
      <input
        type="number"
        min={10}
        step={1}
        value={amount}
        onChange={(e) => setAmount(e.target.value)}
        placeholder="1000"
        className="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm mb-3 focus:border-blue-500 focus:ring-1 focus:ring-blue-500"
      />

      <label className="block text-xs font-medium text-gray-600 mb-1">
        Gateway
      </label>
      <select
        value={gateway}
        onChange={(e) => setGateway(e.target.value as "stripe" | "mercadopago")}
        className="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm mb-3"
      >
        <option value="stripe">Stripe</option>
        <option value="mercadopago">MercadoPago</option>
      </select>

      {amount && parseFloat(amount) >= 10 && (
        <p className="text-xs text-gray-500 mb-3">
          Equivale a{" "}
          <span className="font-semibold">
            {Math.floor(parseFloat(amount)).toLocaleString()} coins
          </span>
        </p>
      )}

      {message && (
        <p className={`text-xs mb-3 ${message.includes("sucesso") ? "text-green-600" : "text-red-600"}`}>
          {message}
        </p>
      )}

      <div className="flex gap-2">
        <button
          onClick={handleSubmit}
          disabled={loading}
          className="flex-1 rounded-lg bg-blue-600 px-3 py-2 text-sm font-medium text-white hover:bg-blue-700 disabled:opacity-50 transition"
        >
          {loading ? "Processando..." : "Confirmar"}
        </button>
        <button
          onClick={() => {
            setOpen(false);
            setMessage("");
          }}
          className="rounded-lg border border-gray-300 px-3 py-2 text-sm text-gray-600 hover:bg-gray-50 transition"
        >
          Cancelar
        </button>
      </div>
    </div>
  );
}
