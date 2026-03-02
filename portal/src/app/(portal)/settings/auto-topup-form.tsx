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
}

interface AutoTopupFormProps {
  currentSettings: TopupSettings | null;
  products: Product[];
  hasStripePaymentMethod?: boolean;
}

export function AutoTopupForm({ currentSettings, products, hasStripePaymentMethod }: AutoTopupFormProps) {
  const router = useRouter();
  const [enabled, setEnabled] = useState(currentSettings?.enabled ?? false);
  const [threshold, setThreshold] = useState(currentSettings?.threshold_tokens ?? 50);
  const [productId, setProductId] = useState(
    currentSettings?.product_id ?? products[0]?.id ?? "",
  );
  const [maxPerMonth, setMaxPerMonth] = useState(currentSettings?.max_per_month ?? 3);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState(false);

  if (products.length === 0) {
    return (
      <p className="mt-4 text-sm text-gray-500">
        Nenhum pacote de créditos disponível para configurar recarga automática.
      </p>
    );
  }

  async function handleSave() {
    setLoading(true);
    setError(null);
    setSuccess(false);

    try {
      const res = await fetch("/api/auto-topup", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          enabled,
          threshold_tokens: threshold,
          product_id: productId,
          max_per_month: maxPerMonth,
        }),
      });

      const data = await res.json();

      if (!res.ok) {
        setError(data.error ?? "Erro ao salvar configurações");
        return;
      }

      setSuccess(true);
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
          <p className="text-sm font-medium text-gray-900">
            {enabled ? "Ativa" : "Desativada"}
          </p>
          <p className="text-xs text-gray-500">
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
          className={`relative inline-flex h-6 w-11 shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 disabled:opacity-50 ${
            enabled ? "bg-blue-600" : "bg-gray-200"
          }`}
        >
          <span
            className={`pointer-events-none inline-block h-5 w-5 transform rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out ${
              enabled ? "translate-x-5" : "translate-x-0"
            }`}
          />
        </button>
      </div>

      {/* Config fields (shown when enabled or when initial setup) */}
      {(enabled || !currentSettings) && (
        <div className="space-y-4 rounded-lg border border-gray-100 bg-gray-50 p-4">
          {/* Threshold */}
          <div>
            <label className="block text-sm font-medium text-gray-700">
              Limite mínimo de créditos
            </label>
            <p className="text-xs text-gray-500 mb-1">
              A recarga dispara quando o saldo cair abaixo deste valor (10–10.000)
            </p>
            <input
              type="number"
              min={10}
              max={10000}
              value={threshold}
              onChange={(e) => setThreshold(Number(e.target.value))}
              className="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm shadow-sm focus:border-blue-500 focus:outline-none focus:ring-1 focus:ring-blue-500 sm:w-40"
            />
          </div>

          {/* Product */}
          <div>
            <label className="block text-sm font-medium text-gray-700">
              Pacote de recarga
            </label>
            <p className="text-xs text-gray-500 mb-1">
              O pacote que será comprado automaticamente
            </p>
            <select
              value={productId}
              onChange={(e) => setProductId(e.target.value)}
              className="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm shadow-sm focus:border-blue-500 focus:outline-none focus:ring-1 focus:ring-blue-500"
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
            <label className="block text-sm font-medium text-gray-700">
              Máximo de recargas por mês
            </label>
            <p className="text-xs text-gray-500 mb-1">
              Limite de segurança: quantas vezes pode recarregar no mês (1–10)
            </p>
            <input
              type="number"
              min={1}
              max={10}
              value={maxPerMonth}
              onChange={(e) => setMaxPerMonth(Number(e.target.value))}
              className="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm shadow-sm focus:border-blue-500 focus:outline-none focus:ring-1 focus:ring-blue-500 sm:w-40"
            />
          </div>

          {/* Summary */}
          {selectedProduct && enabled && (
            <div className={`rounded-lg p-3 text-sm ${hasStripePaymentMethod ? "bg-blue-50 text-blue-800" : "bg-amber-50 text-amber-800"}`}>
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
            className="rounded-lg bg-blue-600 px-5 py-2 text-sm font-medium text-white shadow-sm transition hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 disabled:opacity-50"
          >
            {loading ? "Salvando..." : "Salvar Configurações"}
          </button>

          {error && <p className="text-sm text-red-600">{error}</p>}
          {success && (
            <p className="text-sm text-green-600">Configurações salvas!</p>
          )}
        </div>
      )}
    </div>
  );
}
