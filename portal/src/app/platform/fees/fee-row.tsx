"use client";

import { useState } from "react";

interface Fee {
  id: string;
  fee_type: string;
  rate_pct: number;
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
  const [rate, setRate] = useState(fee.rate_pct);
  const [active, setActive] = useState(fee.is_active);
  const [saving, setSaving] = useState(false);

  const dirty = rate !== fee.rate_pct || active !== fee.is_active;

  async function handleSave() {
    setSaving(true);
    try {
      const res = await fetch("/api/platform/fees", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          fee_type: fee.fee_type,
          rate_pct: rate,
          is_active: active,
        }),
      });

      if (!res.ok) {
        const data = await res.json();
        alert(data.error ?? "Erro ao salvar");
      } else {
        window.location.reload();
      }
    } finally {
      setSaving(false);
    }
  }

  return (
    <tr>
      <td className="px-6 py-4">
        <div className="text-sm font-medium text-gray-900">{label}</div>
        <div className="text-xs text-gray-500">{description}</div>
      </td>
      <td className="px-6 py-4">
        <div className="flex items-center gap-2">
          <input
            type="range"
            min={0}
            max={20}
            step={0.5}
            value={rate}
            onChange={(e) => setRate(Number(e.target.value))}
            className="w-24"
          />
          <span className="text-sm font-mono font-medium text-gray-900 w-12">
            {rate}%
          </span>
        </div>
      </td>
      <td className="px-6 py-4 text-center">
        <button
          onClick={() => setActive(!active)}
          className={`relative inline-flex h-6 w-11 items-center rounded-full transition ${
            active ? "bg-green-500" : "bg-gray-300"
          }`}
          aria-label={`Toggle ${fee.fee_type}`}
        >
          <span
            className={`inline-block h-4 w-4 transform rounded-full bg-white transition ${
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
            className="rounded-lg bg-blue-600 px-3 py-1.5 text-xs font-medium text-white hover:bg-blue-700 disabled:opacity-50 transition"
          >
            {saving ? "..." : "Salvar"}
          </button>
        )}
      </td>
    </tr>
  );
}
