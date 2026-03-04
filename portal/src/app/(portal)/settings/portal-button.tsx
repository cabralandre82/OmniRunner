"use client";

import { useState } from "react";

export function PortalButton() {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleOpen() {
    setLoading(true);
    setError(null);

    try {
      const res = await fetch("/api/billing-portal", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
      });

      const data = await res.json();

      if (!res.ok || !data.portal_url) {
        setError(data.error ?? "Erro ao abrir portal de pagamento");
        setLoading(false);
        return;
      }

      window.location.href = data.portal_url;
    } catch {
      setError("Erro de conexão");
      setLoading(false);
    }
  }

  return (
    <div className="mt-4">
      <button
        onClick={handleOpen}
        disabled={loading}
        className="rounded-lg bg-surface-elevated px-5 py-2.5 text-sm font-medium text-white shadow-sm transition hover:bg-bg-secondary focus:outline-none focus:ring-2 focus:ring-brand disabled:opacity-50"
      >
        {loading ? "Abrindo..." : "Gerenciar Cobrança"}
      </button>
      {error && <p className="mt-2 text-xs text-error">{error}</p>}
    </div>
  );
}
