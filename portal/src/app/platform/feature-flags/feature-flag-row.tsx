"use client";

import { useState } from "react";

interface Flag {
  id: string;
  key: string;
  enabled: boolean;
  rollout_pct: number;
  updated_at: string;
}

export function FeatureFlagRow({ flag }: { flag: Flag }) {
  const [enabled, setEnabled] = useState(flag.enabled);
  const [rollout, setRollout] = useState(flag.rollout_pct);
  const [saving, setSaving] = useState(false);

  const dirty = enabled !== flag.enabled || rollout !== flag.rollout_pct;

  async function handleSave() {
    setSaving(true);
    try {
      await fetch("/api/platform/feature-flags", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          id: flag.id,
          enabled,
          rollout_pct: rollout,
        }),
      });
      flag.enabled = enabled;
      flag.rollout_pct = rollout;
    } finally {
      setSaving(false);
    }
  }

  return (
    <tr className="hover:bg-gray-50 transition-colors">
      <td className="px-5 py-3">
        <code className="rounded bg-gray-100 px-2 py-0.5 text-sm font-medium text-gray-800">
          {flag.key}
        </code>
      </td>
      <td className="px-5 py-3 text-center">
        <button
          onClick={() => setEnabled(!enabled)}
          className={`inline-flex h-6 w-11 items-center rounded-full transition-colors ${
            enabled ? "bg-green-500" : "bg-gray-300"
          }`}
          aria-label={`Toggle ${flag.key}`}
        >
          <span
            className={`inline-block h-4 w-4 rounded-full bg-white shadow transform transition-transform ${
              enabled ? "translate-x-6" : "translate-x-1"
            }`}
          />
        </button>
      </td>
      <td className="px-5 py-3">
        <div className="flex items-center justify-center gap-2">
          <input
            type="range"
            min={0}
            max={100}
            value={rollout}
            onChange={(e) => setRollout(Number(e.target.value))}
            className="h-1.5 w-20 accent-blue-600"
            aria-label={`Rollout percentage for ${flag.key}`}
          />
          <span className="w-10 text-right text-sm font-medium text-gray-700">
            {rollout}%
          </span>
        </div>
      </td>
      <td className="px-5 py-3 text-right">
        <div className="flex items-center justify-end gap-2">
          <span className="text-xs text-gray-400">
            {new Date(flag.updated_at).toLocaleDateString("pt-BR")}
          </span>
          {dirty && (
            <button
              onClick={handleSave}
              disabled={saving}
              className="rounded-lg bg-blue-600 px-3 py-1 text-xs font-medium text-white hover:bg-blue-700 disabled:opacity-50"
            >
              {saving ? "..." : "Salvar"}
            </button>
          )}
        </div>
      </td>
    </tr>
  );
}
