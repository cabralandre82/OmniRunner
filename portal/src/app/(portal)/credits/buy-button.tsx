"use client";

import { useState } from "react";

interface BuyButtonProps {
  productId: string;
  productName: string;
}

export function BuyButton({ productId, productName }: BuyButtonProps) {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleBuy() {
    setLoading(true);
    setError(null);

    try {
      const res = await fetch("/api/checkout", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ product_id: productId }),
      });

      const data = await res.json();

      if (!res.ok || !data.checkout_url) {
        setError(data.error ?? "Erro ao iniciar pagamento");
        setLoading(false);
        return;
      }

      window.location.href = data.checkout_url;
    } catch {
      setError("Erro de conexão");
      setLoading(false);
    }
  }

  return (
    <div className="mt-4">
      <button
        onClick={handleBuy}
        disabled={loading}
        className="w-full rounded-lg bg-blue-600 px-4 py-2.5 text-sm font-medium text-white shadow-sm transition hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 disabled:opacity-50"
      >
        {loading ? "Processando..." : `Comprar ${productName}`}
      </button>
      {error && (
        <p className="mt-2 text-xs text-red-600">{error}</p>
      )}
    </div>
  );
}
