"use client";

import { useState } from "react";

type Gateway = "mercadopago" | "stripe";

interface BuyButtonProps {
  productId: string;
  productName: string;
  preferredGateway: Gateway;
}

const GATEWAY_STYLES: Record<Gateway, { bg: string; hover: string; ring: string; label: string }> = {
  mercadopago: {
    bg: "bg-[#009ee3]",
    hover: "hover:bg-[#0080c0]",
    ring: "focus:ring-[#009ee3]",
    label: "Pagar com Pix, Cartão ou Boleto",
  },
  stripe: {
    bg: "bg-[#635bff]",
    hover: "hover:bg-[#4b44d4]",
    ring: "focus:ring-[#635bff]",
    label: "Pagar com Cartão (Stripe)",
  },
};

export function BuyButton({ productId, preferredGateway }: BuyButtonProps) {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const style = GATEWAY_STYLES[preferredGateway];
  const altGateway: Gateway = preferredGateway === "mercadopago" ? "stripe" : "mercadopago";
  const altStyle = GATEWAY_STYLES[altGateway];

  async function handleBuy(gateway: Gateway) {
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
        onClick={() => handleBuy(preferredGateway)}
        disabled={loading}
        className={`w-full rounded-lg ${style.bg} px-4 py-2.5 text-sm font-medium text-white shadow-sm transition ${style.hover} focus:outline-none focus:ring-2 ${style.ring} focus:ring-offset-2 disabled:opacity-50`}
      >
        {loading ? "Processando..." : style.label}
      </button>
      <button
        onClick={() => handleBuy(altGateway)}
        disabled={loading}
        className="w-full rounded-lg border border-gray-200 bg-white px-4 py-1.5 text-xs font-medium text-gray-500 transition hover:bg-gray-50 hover:text-gray-700 disabled:opacity-50"
      >
        ou {altStyle.label.toLowerCase()}
      </button>
      {error && <p className="mt-1 text-xs text-red-600">{error}</p>}
    </div>
  );
}
