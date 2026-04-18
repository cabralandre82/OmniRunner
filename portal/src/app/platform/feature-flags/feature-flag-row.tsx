"use client";

import { useState } from "react";

interface Flag {
  id: string;
  key: string;
  enabled: boolean;
  rollout_pct: number;
  category: string;
  scope: string;
  reason: string | null;
  updated_at: string;
}

const CATEGORY_BADGE: Record<
  string,
  { label: string; className: string }
> = {
  kill_switch: {
    label: "Kill switch",
    className: "bg-danger/10 text-danger border border-danger/30",
  },
  banner: {
    label: "Banner",
    className: "bg-warning/10 text-warning border border-warning/30",
  },
  operational: {
    label: "Operacional",
    className: "bg-info/10 text-info border border-info/30",
  },
  product: {
    label: "Produto",
    className: "bg-brand/10 text-brand border border-brand/30",
  },
  experimental: {
    label: "Experimental",
    className: "bg-content-muted/10 text-content-secondary border border-border",
  },
};

export function FeatureFlagRow({ flag }: { flag: Flag }) {
  const [enabled, setEnabled] = useState(flag.enabled);
  const [rollout, setRollout] = useState(flag.rollout_pct);
  const [reason, setReason] = useState("");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const dirty = enabled !== flag.enabled || rollout !== flag.rollout_pct;
  const badge = CATEGORY_BADGE[flag.category] ?? CATEGORY_BADGE.product;

  async function handleSave() {
    setError(null);
    if (reason.trim().length < 3) {
      setError("Motivo é obrigatório (mín 3 chars)");
      return;
    }
    setSaving(true);
    try {
      const res = await fetch("/api/platform/feature-flags", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          id: flag.id,
          key: flag.key,
          scope: flag.scope,
          enabled,
          rollout_pct: rollout,
          reason: reason.trim(),
        }),
      });
      if (!res.ok) {
        const body = await res.json().catch(() => ({}));
        setError(body?.error ?? `HTTP ${res.status}`);
        return;
      }
      flag.enabled = enabled;
      flag.rollout_pct = rollout;
      flag.reason = reason.trim();
      setReason("");
    } finally {
      setSaving(false);
    }
  }

  return (
    <tr className="hover:bg-surface-elevated transition-colors">
      <td className="px-5 py-3 align-top">
        <code className="rounded bg-surface-elevated px-2 py-0.5 text-sm font-medium text-content-primary">
          {flag.key}
        </code>
        {flag.scope !== "global" && (
          <span className="ml-2 text-xs text-content-muted">
            scope={flag.scope}
          </span>
        )}
        {flag.reason && (
          <p className="mt-1 text-xs text-content-muted italic">
            {flag.reason}
          </p>
        )}
      </td>
      <td className="px-5 py-3 align-top">
        <span
          className={`inline-block rounded-full px-2.5 py-0.5 text-[11px] font-semibold ${badge.className}`}
        >
          {badge.label}
        </span>
      </td>
      <td className="px-5 py-3 text-center align-top">
        <button
          onClick={() => setEnabled(!enabled)}
          className={`inline-flex h-6 w-11 items-center rounded-full transition-colors ${
            enabled ? "bg-success" : "bg-surface-elevated"
          }`}
          aria-label={`Toggle ${flag.key}`}
        >
          <span
            className={`inline-block h-4 w-4 rounded-full bg-surface shadow transform transition-transform ${
              enabled ? "translate-x-6" : "translate-x-1"
            }`}
          />
        </button>
      </td>
      <td className="px-5 py-3 align-top">
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
          <span className="w-10 text-right text-sm font-medium text-content-secondary">
            {rollout}%
          </span>
        </div>
      </td>
      <td className="px-5 py-3 text-right align-top">
        <div className="flex flex-col items-end gap-2">
          <span className="text-xs text-content-muted">
            {new Date(flag.updated_at).toLocaleDateString("pt-BR")}
          </span>
          {dirty && (
            <div className="flex flex-col items-end gap-1">
              <input
                type="text"
                value={reason}
                onChange={(e) => setReason(e.target.value)}
                placeholder="Motivo (obrigatório)"
                className="w-48 rounded-md border border-border bg-surface px-2 py-1 text-xs text-content-primary"
                aria-label={`Motivo da mudança em ${flag.key}`}
              />
              {error && (
                <span className="text-xs text-danger">{error}</span>
              )}
              <button
                onClick={handleSave}
                disabled={saving}
                className="rounded-lg bg-brand px-3 py-1 text-xs font-medium text-white hover:brightness-110 disabled:opacity-50"
              >
                {saving ? "..." : "Salvar"}
              </button>
            </div>
          )}
        </div>
      </td>
    </tr>
  );
}
