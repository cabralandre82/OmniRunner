"use client";

import Image from "next/image";
import { useState, useEffect } from "react";

interface BrandingData {
  logo_url: string | null;
  primary_color: string;
  sidebar_bg: string;
  sidebar_text: string;
  accent_color: string;
}

const PRESETS = [
  { name: "Padrão", primary: "#2563eb", sidebar_bg: "#ffffff", sidebar_text: "#111827", accent: "#2563eb" },
  { name: "Escuro", primary: "#6366f1", sidebar_bg: "#1e1b4b", sidebar_text: "#e0e7ff", accent: "#818cf8" },
  { name: "Verde", primary: "#059669", sidebar_bg: "#064e3b", sidebar_text: "#d1fae5", accent: "#34d399" },
  { name: "Laranja", primary: "#ea580c", sidebar_bg: "#431407", sidebar_text: "#fed7aa", accent: "#fb923c" },
  { name: "Rosa", primary: "#db2777", sidebar_bg: "#500724", sidebar_text: "#fce7f3", accent: "#f472b6" },
];

export function BrandingForm() {
  const [data, setData] = useState<BrandingData>({
    logo_url: null,
    primary_color: "#2563eb",
    sidebar_bg: "#ffffff",
    sidebar_text: "#111827",
    accent_color: "#2563eb",
  });
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [result, setResult] = useState<{ ok?: boolean; error?: string } | null>(null);

  useEffect(() => {
    fetch("/api/branding")
      .then((r) => r.json())
      .then((d) => {
        setData(d);
        setLoading(false);
      })
      .catch(() => setLoading(false));
  }, []);

  async function handleSave() {
    setSaving(true);
    setResult(null);

    try {
      const res = await fetch("/api/branding", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(data),
      });
      const json = await res.json();

      if (res.ok) {
        setResult({ ok: true });
        setTimeout(() => window.location.reload(), 800);
      } else {
        setResult({ error: json.error ?? "Erro desconhecido" });
      }
    } catch {
      setResult({ error: "Erro de conexão" });
    } finally {
      setSaving(false);
    }
  }

  function applyPreset(preset: typeof PRESETS[0]) {
    setData((prev) => ({
      ...prev,
      primary_color: preset.primary,
      sidebar_bg: preset.sidebar_bg,
      sidebar_text: preset.sidebar_text,
      accent_color: preset.accent,
    }));
  }

  if (loading) {
    return (
      <div className="py-6 text-center text-sm text-content-muted">
        Carregando...
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Presets */}
      <div>
        <label className="mb-2 block text-xs font-medium text-content-secondary">
          Temas Prontos
        </label>
        <div className="flex flex-wrap gap-2">
          {PRESETS.map((p) => (
            <button
              key={p.name}
              onClick={() => applyPreset(p)}
              className="flex items-center gap-2 rounded-lg border border-border px-3 py-2 text-xs font-medium text-content-secondary hover:bg-surface-elevated"
            >
              <span
                className="inline-block h-4 w-4 rounded-full border border-border"
                style={{ backgroundColor: p.primary }}
              />
              {p.name}
            </button>
          ))}
        </div>
      </div>

      {/* Logo URL */}
      <div>
        <label className="mb-1 block text-xs font-medium text-content-secondary">
          Logo URL
        </label>
        <input
          type="url"
          value={data.logo_url ?? ""}
          onChange={(e) => setData({ ...data, logo_url: e.target.value || null })}
          placeholder="https://exemplo.com/logo.png"
          className="w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-brand focus:outline-none focus:ring-1 focus:ring-brand"
        />
        <p className="mt-1 text-xs text-content-muted">
          Use uma imagem quadrada PNG ou SVG. Recomendado: 128x128px.
        </p>
      </div>

      {/* Color pickers */}
      <div className="grid gap-4 sm:grid-cols-2">
        <ColorPicker
          label="Cor Principal"
          value={data.primary_color}
          onChange={(v) => setData({ ...data, primary_color: v })}
        />
        <ColorPicker
          label="Cor de Destaque"
          value={data.accent_color}
          onChange={(v) => setData({ ...data, accent_color: v })}
        />
        <ColorPicker
          label="Fundo da Sidebar"
          value={data.sidebar_bg}
          onChange={(v) => setData({ ...data, sidebar_bg: v })}
        />
        <ColorPicker
          label="Texto da Sidebar"
          value={data.sidebar_text}
          onChange={(v) => setData({ ...data, sidebar_text: v })}
        />
      </div>

      {/* Preview */}
      <div>
        <label className="mb-2 block text-xs font-medium text-content-secondary">
          Preview
        </label>
        <div className="flex overflow-hidden rounded-lg border border-border" style={{ height: 160 }}>
          <div
            className="flex w-40 flex-col p-3"
            style={{ backgroundColor: data.sidebar_bg, color: data.sidebar_text }}
          >
            <div className="flex items-center gap-2">
              {data.logo_url ? (
                <Image src={data.logo_url} alt="Logo" width={24} height={24} className="rounded" />
              ) : (
                <span
                  className="flex h-6 w-6 items-center justify-center rounded text-xs font-bold text-white"
                  style={{ backgroundColor: data.primary_color }}
                >
                  O
                </span>
              )}
              <span className="text-sm font-bold">Assessoria</span>
            </div>
            <div className="mt-3 space-y-1">
              <div
                className="rounded px-2 py-1 text-xs font-medium"
                style={{ backgroundColor: data.accent_color + "22", color: data.accent_color }}
              >
                Dashboard
              </div>
              <div className="rounded px-2 py-1 text-xs opacity-70">Atletas</div>
              <div className="rounded px-2 py-1 text-xs opacity-70">Créditos</div>
            </div>
          </div>
          <div className="flex-1 bg-bg-secondary p-3">
            <div
              className="h-2 w-20 rounded"
              style={{ backgroundColor: data.primary_color }}
            />
            <div className="mt-2 h-2 w-32 rounded bg-surface-elevated" />
            <div className="mt-4 flex gap-2">
              <div
                className="rounded px-3 py-1 text-xs font-medium text-white"
                style={{ backgroundColor: data.primary_color }}
              >
                Botão
              </div>
              <div
                className="rounded border px-3 py-1 text-xs font-medium"
                style={{ borderColor: data.accent_color, color: data.accent_color }}
              >
                Secundário
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* Save */}
      <div className="flex items-center gap-3">
        <button
          onClick={handleSave}
          disabled={saving}
          className="rounded-lg bg-brand px-4 py-2 text-sm font-medium text-white hover:brightness-110 disabled:opacity-50"
        >
          {saving ? "Salvando..." : "Salvar Branding"}
        </button>
        {result?.ok && (
          <span className="text-sm font-medium text-success">
            Salvo! Recarregando...
          </span>
        )}
        {result?.error && (
          <span className="text-sm font-medium text-error">
            {result.error}
          </span>
        )}
      </div>
    </div>
  );
}

function ColorPicker({
  label,
  value,
  onChange,
}: {
  label: string;
  value: string;
  onChange: (v: string) => void;
}) {
  return (
    <div>
      <label className="mb-1 block text-xs font-medium text-content-secondary">
        {label}
      </label>
      <div className="flex items-center gap-2">
        <input
          type="color"
          value={value}
          onChange={(e) => onChange(e.target.value)}
          className="h-9 w-9 cursor-pointer rounded border border-border"
        />
        <input
          type="text"
          value={value}
          onChange={(e) => {
            const v = e.target.value;
            if (/^#[0-9a-fA-F]{0,6}$/.test(v)) onChange(v);
          }}
          className="w-24 rounded-lg border border-border px-2 py-1.5 text-sm font-mono focus:border-brand focus:outline-none focus:ring-1 focus:ring-brand"
        />
      </div>
    </div>
  );
}
