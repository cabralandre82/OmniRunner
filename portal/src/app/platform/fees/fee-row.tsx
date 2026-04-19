"use client";

import { useState } from "react";
import { toast } from "sonner";
import { csrfFetch } from "@/lib/api/csrf-fetch";

interface Fee {
  id: string;
  fee_type: string;
  rate_pct: number;
  rate_usd: number | null;
  is_active: boolean;
}

export function FeeRow({
  fee,
  label,
  description,
}: {
  fee: Fee;
  label: string;
  description: string;
}) {
  const isMaintenance = fee.fee_type === "maintenance";

  const [ratePct, setRatePct] = useState(fee.rate_pct);
  const [rateUsd, setRateUsd] = useState(fee.rate_usd ?? 1.0);
  const [active, setActive] = useState(fee.is_active);
  const [saving, setSaving] = useState(false);

  const dirty = isMaintenance
    ? rateUsd !== (fee.rate_usd ?? 1.0) || active !== fee.is_active
    : ratePct !== fee.rate_pct || active !== fee.is_active;

  async function handleSave() {
    setSaving(true);
    try {
      const payload: Record<string, unknown> = {
        fee_type: fee.fee_type,
        is_active: active,
      };

      if (isMaintenance) {
        payload.rate_usd = rateUsd;
      } else {
        payload.rate_pct = ratePct;
      }

      const res = await csrfFetch("/api/platform/fees", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      });

      if (!res.ok) {
        const data = await res.json();
        toast.error(data.error ?? "Erro ao salvar");
      } else {
        toast.success("Taxa atualizada");
        window.location.reload();
      }
    } finally {
      setSaving(false);
    }
  }

  return (
    <tr>
      <td className="px-6 py-4">
        <div className="text-sm font-medium text-content-primary">{label}</div>
        <div className="text-xs text-content-secondary">{description}</div>
      </td>
      <td className="px-6 py-4">
        {isMaintenance ? (
          <div className="flex items-center gap-2">
            <input
              type="range"
              min={0}
              max={10}
              step={0.5}
              value={rateUsd}
              onChange={(e) => setRateUsd(Number(e.target.value))}
              className="w-24"
            />
            <span className="text-sm font-mono font-medium text-content-primary w-20">
              ${rateUsd.toFixed(2)}/atleta
            </span>
          </div>
        ) : (
          <div className="flex items-center gap-2">
            <input
              type="range"
              min={0}
              max={20}
              step={0.5}
              value={ratePct}
              onChange={(e) => setRatePct(Number(e.target.value))}
              className="w-24"
            />
            <span className="text-sm font-mono font-medium text-content-primary w-12">
              {ratePct}%
            </span>
          </div>
        )}
      </td>
      <td className="px-6 py-4 text-center">
        <button
          onClick={() => setActive(!active)}
          className={`relative inline-flex h-6 w-11 items-center rounded-full transition ${
            active ? "bg-success" : "bg-surface-elevated"
          }`}
          aria-label={`Toggle ${fee.fee_type}`}
        >
          <span
            className={`inline-block h-4 w-4 transform rounded-full bg-surface transition ${
              active ? "translate-x-6" : "translate-x-1"
            }`}
          />
        </button>
      </td>
      <td className="px-6 py-4 text-right">
        {dirty && (
          <button
            onClick={handleSave}
            disabled={saving}
            className="rounded-lg bg-brand px-3 py-1.5 text-xs font-medium text-white hover:brightness-110 disabled:opacity-50 transition"
          >
            {saving ? "..." : "Salvar"}
          </button>
        )}
      </td>
    </tr>
  );
}
