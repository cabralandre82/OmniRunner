"use client";

import { useState } from "react";

interface BuyButtonProps {
  productId: string;
  productName: string;
}

export function BuyButton({ productId }: BuyButtonProps) {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleBuy(gateway: "mercadopago" | "stripe" = "mercadopago") {
    setLoading(true);
    setError(null);

    try {
      const res = await fetch("/api/checkout", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ product_id: productId, gateway }),
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
    <div className="mt-4 space-y-2">
      <button
        onClick={() => handleBuy("mercadopago")}
        disabled={loading}
        className="w-full rounded-lg bg-[#009ee3] px-4 py-2.5 text-sm font-medium text-white shadow-sm transition hover:bg-[#0080c0] focus:outline-none focus:ring-2 focus:ring-[#009ee3] focus:ring-offset-2 disabled:opacity-50"
      >
        {loading ? "Processando..." : `Pagar com Pix, Cartão ou Boleto`}
      </button>
      {error && <p className="mt-1 text-xs text-red-600">{error}</p>}
    </div>
  );
}
