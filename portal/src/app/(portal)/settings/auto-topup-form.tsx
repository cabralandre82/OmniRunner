"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { formatBRL } from "@/lib/format";

interface Product {
  id: string;
  name: string;
  credits_amount: number;
  price_cents: number;
}

interface TopupSettings {
  enabled: boolean;
  threshold_tokens: number;
  product_id: string;
  max_per_month: number;
  // L12-05 — daily cap antifraude
  daily_charge_cap_brl?: number | null;
  daily_max_charges?: number | null;
  daily_limit_timezone?: string | null;
}

interface AutoTopupFormProps {
  currentSettings: TopupSettings | null;
  products: Product[];
  hasStripePaymentMethod?: boolean;
}

// L12-05 — defaults coerentes com a migration (DEFAULT 500.00 / 3 / SP)
const DEFAULT_DAILY_CAP_BRL = 500;
const DEFAULT_DAILY_MAX_CHARGES = 3;
const DEFAULT_DAILY_TZ = "America/Sao_Paulo";

export function AutoTopupForm({ currentSettings, products, hasStripePaymentMethod }: AutoTopupFormProps) {
  const router = useRouter();
  const [enabled, setEnabled] = useState(currentSettings?.enabled ?? false);
  const [threshold, setThreshold] = useState(currentSettings?.threshold_tokens ?? 50);
  const [productId, setProductId] = useState(
    currentSettings?.product_id ?? products[0]?.id ?? "",
  );
  const [maxPerMonth, setMaxPerMonth] = useState(currentSettings?.max_per_month ?? 3);
  // L12-05 — daily cap state
  const initialDailyCap =
    currentSettings?.daily_charge_cap_brl ?? DEFAULT_DAILY_CAP_BRL;
  const initialDailyMax =
    currentSettings?.daily_max_charges ?? DEFAULT_DAILY_MAX_CHARGES;
  const initialDailyTz =
    currentSettings?.daily_limit_timezone ?? DEFAULT_DAILY_TZ;
  const [dailyCapBrl, setDailyCapBrl] = useState<number>(initialDailyCap);
  const [dailyMaxCharges, setDailyMaxCharges] =
    useState<number>(initialDailyMax);
  const [dailyTz, setDailyTz] = useState<string>(initialDailyTz);
  const [dailyCapReason, setDailyCapReason] = useState<string>("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState(false);

  // L12-05 — true se algum dos 3 campos daily_* foi alterado em relação ao
  // valor atual carregado do banco. Quando true, a textarea de "motivo"
  // fica obrigatória (audit trail).
  const dailyCapDirty =
    dailyCapBrl !== initialDailyCap
    || dailyMaxCharges !== initialDailyMax
    || dailyTz !== initialDailyTz;

  if (products.length === 0) {
    return (
      <p className="mt-4 text-sm text-content-secondary">
        Nenhum pacote de créditos disponível para configurar recarga automática.
      </p>
    );
  }

  async function handleSave() {
    // L12-05 — client-side gate antes de POST: poupa um round-trip e dá
    // feedback instantâneo. Server-side superRefine no Zod re-valida.
    if (dailyCapDirty && dailyCapReason.trim().length < 10) {
      setError(
        "Informe o motivo (>= 10 caracteres) para alterar os limites " +
        "diários de antifraude.",
      );
      return;
    }

    setLoading(true);
    setError(null);
    setSuccess(false);

    try {
      const body: Record<string, unknown> = {
        enabled,
        threshold_tokens: threshold,
        product_id: productId,
        max_per_month: maxPerMonth,
      };

      if (dailyCapDirty) {
        body.daily_charge_cap_brl = dailyCapBrl;
        body.daily_max_charges = dailyMaxCharges;
        body.daily_limit_timezone = dailyTz;
        body.daily_cap_change_reason = dailyCapReason.trim();
      }

      const res = await fetch("/api/auto-topup", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
      });

      const data = await res.json();

      if (!res.ok) {
        setError(data.error ?? "Erro ao salvar configurações");
        return;
      }

      setSuccess(true);
      setDailyCapReason("");
      router.refresh();
      setTimeout(() => setSuccess(false), 3000);
    } catch {
      setError("Erro de conexão");
    } finally {
      setLoading(false);
    }
  }

  async function handleToggle() {
    const newEnabled = !enabled;
    setEnabled(newEnabled);

    if (currentSettings) {
      setLoading(true);
      setError(null);
      try {
        const res = await fetch("/api/auto-topup", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ enabled: newEnabled }),
        });
        const data = await res.json();
        if (!res.ok) {
          setError(data.error ?? "Erro ao alterar");
          setEnabled(!newEnabled);
        }
        router.refresh();
      } catch {
        setError("Erro de conexão");
        setEnabled(!newEnabled);
      } finally {
        setLoading(false);
      }
    }
  }

  const selectedProduct = products.find((p) => p.id === productId);

  return (
    <div className="mt-5 space-y-5">
      {/* Toggle */}
      <div className="flex items-center justify-between">
        <div>
          <p className="text-sm font-medium text-content-primary">
            {enabled ? "Ativa" : "Desativada"}
          </p>
          <p className="text-xs text-content-secondary">
            {enabled
              ? hasStripePaymentMethod
                ? "O sistema recarregará automaticamente quando os créditos estiverem baixos"
                : "Você receberá notificações push quando os créditos estiverem baixos"
              : "Ative para monitorar o saldo e recarregar ou ser notificado automaticamente"}
          </p>
        </div>
        <button
          type="button"
          role="switch"
          aria-checked={enabled}
          onClick={handleToggle}
          disabled={loading}
          className={`relative inline-flex h-6 w-11 shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none focus:ring-2 focus:ring-brand disabled:opacity-50 ${
            enabled ? "bg-brand" : "bg-surface-elevated"
          }`}
        >
          <span
            className={`pointer-events-none inline-block h-5 w-5 transform rounded-full bg-surface shadow ring-0 transition duration-200 ease-in-out ${
              enabled ? "translate-x-5" : "translate-x-0"
            }`}
          />
        </button>
      </div>

      {/* Config fields (shown when enabled or when initial setup) */}
      {(enabled || !currentSettings) && (
        <div className="space-y-4 rounded-lg border border-border-subtle bg-bg-secondary p-4">
          {/* Threshold */}
          <div>
            <label className="block text-sm font-medium text-content-secondary">
              Limite mínimo de créditos
            </label>
            <p className="text-xs text-content-secondary mb-1">
              A recarga dispara quando o saldo cair abaixo deste valor (10–10.000)
            </p>
            <input
              type="number"
              min={10}
              max={10000}
              value={threshold}
              onChange={(e) => setThreshold(Number(e.target.value))}
              className="w-full rounded-lg border border-border px-3 py-2 text-sm shadow-sm focus:border-brand focus:outline-none focus:ring-1 focus:ring-brand sm:w-40"
            />
          </div>

          {/* Product */}
          <div>
            <label className="block text-sm font-medium text-content-secondary">
              Pacote de recarga
            </label>
            <p className="text-xs text-content-secondary mb-1">
              O pacote que será comprado automaticamente
            </p>
            <select
              value={productId}
              onChange={(e) => setProductId(e.target.value)}
              className="w-full rounded-lg border border-border px-3 py-2 text-sm shadow-sm focus:border-brand focus:outline-none focus:ring-1 focus:ring-brand"
            >
              {products.map((p) => (
                <option key={p.id} value={p.id}>
                  {p.name} — {p.credits_amount.toLocaleString("pt-BR")} créditos ({formatBRL(p.price_cents)})
                </option>
              ))}
            </select>
          </div>

          {/* Max per month */}
          <div>
            <label className="block text-sm font-medium text-content-secondary">
              Máximo de recargas por mês
            </label>
            <p className="text-xs text-content-secondary mb-1">
              Limite de segurança: quantas vezes pode recarregar no mês (1–10)
            </p>
            <input
              type="number"
              min={1}
              max={10}
              value={maxPerMonth}
              onChange={(e) => setMaxPerMonth(Number(e.target.value))}
              className="w-full rounded-lg border border-border px-3 py-2 text-sm shadow-sm focus:border-brand focus:outline-none focus:ring-1 focus:ring-brand sm:w-40"
            />
          </div>

          {/* L12-05 — Limites diários antifraude (defesa em profundidade) */}
          {hasStripePaymentMethod && (
            <details
              data-testid="daily-cap-section"
              className="rounded-lg border border-border-subtle bg-surface p-3"
            >
              <summary className="cursor-pointer text-sm font-medium text-content-primary">
                Limites diários de antifraude (avançado)
              </summary>
              <div className="mt-3 space-y-3">
                <p className="text-xs text-content-secondary">
                  Defesa em profundidade contra cobranças indevidas em rajada
                  (ex.: bug em settings, conta comprometida ou erro do cron).
                  Atual: até{" "}
                  <strong>{dailyMaxCharges}x</strong> e{" "}
                  <strong>{formatBRL(Math.round(dailyCapBrl * 100))}</strong>{" "}
                  por dia (janela {dailyTz}).
                </p>

                <div>
                  <label
                    htmlFor="daily-cap-brl"
                    className="block text-xs font-medium text-content-secondary"
                  >
                    Teto diário em R$ (0–100.000)
                  </label>
                  <input
                    id="daily-cap-brl"
                    type="number"
                    min={0}
                    max={100000}
                    step={10}
                    value={dailyCapBrl}
                    onChange={(e) => setDailyCapBrl(Number(e.target.value))}
                    className="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm shadow-sm focus:border-brand focus:outline-none focus:ring-1 focus:ring-brand sm:w-40"
                  />
                </div>

                <div>
                  <label
                    htmlFor="daily-max-charges"
                    className="block text-xs font-medium text-content-secondary"
                  >
                    Máximo de cobranças por dia (1–24)
                  </label>
                  <input
                    id="daily-max-charges"
                    type="number"
                    min={1}
                    max={24}
                    value={dailyMaxCharges}
                    onChange={(e) => setDailyMaxCharges(Number(e.target.value))}
                    className="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm shadow-sm focus:border-brand focus:outline-none focus:ring-1 focus:ring-brand sm:w-32"
                  />
                </div>

                <div>
                  <label
                    htmlFor="daily-tz"
                    className="block text-xs font-medium text-content-secondary"
                  >
                    Fuso horário da janela diária
                  </label>
                  <select
                    id="daily-tz"
                    value={dailyTz}
                    onChange={(e) => setDailyTz(e.target.value)}
                    className="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm shadow-sm focus:border-brand focus:outline-none focus:ring-1 focus:ring-brand"
                  >
                    <option value="America/Sao_Paulo">America/Sao_Paulo (BRT/BRST)</option>
                    <option value="America/Manaus">America/Manaus (AMT)</option>
                    <option value="America/Belem">America/Belem (BRT)</option>
                    <option value="America/Recife">America/Recife (BRT)</option>
                    <option value="UTC">UTC</option>
                  </select>
                </div>

                {dailyCapDirty && (
                  <div>
                    <label
                      htmlFor="daily-cap-reason"
                      className="block text-xs font-medium text-content-secondary"
                    >
                      Motivo da alteração (obrigatório, mín. 10 caracteres)
                    </label>
                    <textarea
                      id="daily-cap-reason"
                      value={dailyCapReason}
                      onChange={(e) => setDailyCapReason(e.target.value)}
                      rows={2}
                      placeholder="Ex: ajuste após acordo com CFO em ticket SUP-1234"
                      className="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm shadow-sm focus:border-brand focus:outline-none focus:ring-1 focus:ring-brand"
                    />
                    <p className="mt-1 text-xs text-content-secondary">
                      {dailyCapReason.trim().length}/10 caracteres
                      {dailyCapReason.trim().length >= 10 ? " ✓" : ""}
                    </p>
                  </div>
                )}
              </div>
            </details>
          )}

          {/* Summary */}
          {selectedProduct && enabled && (
            <div className={`rounded-lg p-3 text-sm ${hasStripePaymentMethod ? "bg-brand-soft text-info" : "bg-amber-50 text-amber-800"}`}>
              Quando o saldo cair abaixo de{" "}
              <strong>{threshold.toLocaleString("pt-BR")}</strong> créditos:
              {hasStripePaymentMethod ? (
                <> o pacote <strong>{selectedProduct.name}</strong> ({formatBRL(selectedProduct.price_cents)}) será cobrado automaticamente no cartão salvo. Máximo de <strong>{maxPerMonth}x</strong> por mês.</>
              ) : (
                <> você receberá uma <strong>notificação push</strong> avisando que os créditos estão baixos. Compre manualmente pelo portal com Pix, Cartão ou Boleto via MercadoPago. Para cobrança automática, configure um cartão pelo Stripe.</>
              )}
            </div>
          )}

          {/* Save button */}
          <button
            onClick={handleSave}
            disabled={loading || !productId}
            className="rounded-lg bg-brand px-5 py-2 text-sm font-medium text-white shadow-sm transition hover:brightness-110 focus:outline-none focus:ring-2 focus:ring-brand disabled:opacity-50"
          >
            {loading ? "Salvando..." : "Salvar Configurações"}
          </button>

          {error && <p className="text-sm text-error">{error}</p>}
          {success && (
            <p className="text-sm text-success">Configurações salvas!</p>
          )}
        </div>
      )}
    </div>
  );
}
