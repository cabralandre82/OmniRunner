"use client";

import { useState } from "react";
import { csrfFetch } from "@/lib/api/csrf-fetch";

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
      const res = await csrfFetch("/api/custody", {
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
        className="rounded-lg bg-brand px-4 py-2 text-sm font-medium text-white hover:brightness-110 transition"
      >
        Depositar Lastro
      </button>
    );
  }

  return (
    <div className="rounded-xl border border-border bg-surface p-4 shadow-lg w-80">
      <h3 className="text-sm font-semibold text-content-primary mb-3">
        Novo Depósito de Lastro
      </h3>

      <label className="block text-xs font-medium text-content-secondary mb-1">
        Valor (USD)
      </label>
      <input
        type="number"
        min={10}
        step={1}
        value={amount}
        onChange={(e) => setAmount(e.target.value)}
        placeholder="1000"
        className="w-full rounded-lg border border-border px-3 py-2 text-sm mb-3 focus:border-brand focus:ring-1 focus:ring-brand"
      />

      <label className="block text-xs font-medium text-content-secondary mb-1">
        Gateway
      </label>
      <select
        value={gateway}
        onChange={(e) => setGateway(e.target.value as "stripe" | "mercadopago")}
        className="w-full rounded-lg border border-border px-3 py-2 text-sm mb-3"
      >
        <option value="stripe">Stripe</option>
        <option value="mercadopago">MercadoPago</option>
      </select>

      {amount && parseFloat(amount) >= 10 && (
        <p className="text-xs text-content-secondary mb-3">
          Equivale a{" "}
          <span className="font-semibold">
            {Math.floor(parseFloat(amount)).toLocaleString()} coins
          </span>
        </p>
      )}

      {message && (
        <p className={`text-xs mb-3 ${message.includes("sucesso") ? "text-success" : "text-error"}`}>
          {message}
        </p>
      )}

      <div className="flex gap-2">
        <button
          onClick={handleSubmit}
          disabled={loading}
          className="flex-1 rounded-lg bg-brand px-3 py-2 text-sm font-medium text-white hover:brightness-110 disabled:opacity-50 transition"
        >
          {loading ? "Processando..." : "Confirmar"}
        </button>
        <button
          onClick={() => {
            setOpen(false);
            setMessage("");
          }}
          className="rounded-lg border border-border px-3 py-2 text-sm text-content-secondary hover:bg-surface-elevated transition"
        >
          Cancelar
        </button>
      </div>
    </div>
  );
}
