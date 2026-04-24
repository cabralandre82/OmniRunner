"use client";

import { useState } from "react";
import { useTranslations } from "next-intl";
import { csrfFetch } from "@/lib/api/csrf-fetch";

export function DistributeButton({
  athleteId,
  athleteName,
}: {
  athleteId: string;
  athleteName: string;
}) {
  const tc = useTranslations("common");
  const ta = useTranslations("athletes");
  const te = useTranslations("error");
  const [open, setOpen] = useState(false);
  const [amount, setAmount] = useState("");
  const [loading, setLoading] = useState(false);
  const [result, setResult] = useState<{ ok?: boolean; error?: string } | null>(
    null,
  );

  async function handleSubmit() {
    const num = parseInt(amount, 10);
    if (!num || num < 1 || num > 1000) {
        setResult({ error: te("generic") });
      return;
    }

    // L05-11 — fat-finger guard. Anything ≥ 500 OmniCoins (~ R$ 500
    // at default 1:1 issuance rate, half of the per-call cap) needs
    // a typed-confirmation. Browser-native `confirm()` is enough here
    // because the single-athlete distribute is low-frequency and we
    // don't want to ship a heavyweight modal for a non-batch path.
    // Batch distribute (`/api/distribute-coins/batch`) gets its own
    // dedicated TYPE-CONFIRMAR modal when the UI ships.
    if (num >= 500) {
      const confirmed = window.confirm(
        ta("distribute_confirm_high_value", {
          amount: String(num),
          athlete: athleteName,
        }),
      );
      if (!confirmed) return;
    }

    setLoading(true);
    setResult(null);

    try {
      const res = await csrfFetch("/api/distribute-coins", {
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
        setResult({ error: data.error ?? te("generic") });
      }
    } catch {
      setResult({ error: te("generic") });
    } finally {
      setLoading(false);
    }
  }

  if (!open) {
    return (
      <button
        onClick={() => setOpen(true)}
        className="rounded-lg bg-indigo-50 px-2.5 py-1 text-xs font-medium text-brand hover:bg-indigo-100"
      >
        {ta("distribute")}
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
        className="w-20 rounded-lg border border-border px-2 py-1 text-xs focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
        disabled={loading}
      />
      <button
        onClick={handleSubmit}
        disabled={loading}
        className="rounded-lg bg-brand px-2.5 py-1 text-xs font-medium text-white hover:bg-indigo-700 disabled:opacity-50"
      >
        {loading ? "..." : tc("confirm")}
      </button>
      <button
        onClick={() => {
          setOpen(false);
          setResult(null);
        }}
        className="text-xs text-content-muted hover:text-content-secondary"
      >
        {tc("cancel")}
      </button>
      {result?.ok && (
        <span className="text-xs font-medium text-success">
          {amount} OmniCoins enviadas para {athleteName}
        </span>
      )}
      {result?.error && (
        <span className="text-xs font-medium text-error">{result.error}</span>
      )}
    </div>
  );
}
