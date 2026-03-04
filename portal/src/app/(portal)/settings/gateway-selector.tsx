"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

type Gateway = "mercadopago" | "stripe";

interface GatewaySelectorProps {
  currentGateway: Gateway;
}

const GATEWAYS: {
  id: Gateway;
  name: string;
  tagline: string;
  color: string;
  selectedBorder: string;
  selectedBg: string;
  pros: string[];
  cons: string[];
}[] = [
  {
    id: "mercadopago",
    name: "MercadoPago",
    tagline: "Pagamento nacional",
    color: "text-[#009ee3]",
    selectedBorder: "border-[#009ee3]",
    selectedBg: "bg-[#009ee3]/5",
    pros: [
      "Pix instantâneo (aprovação em segundos)",
      "Boleto bancário (para quem prefere)",
      "Cartão de crédito/débito nacional",
      "Taxas competitivas no Brasil",
      "Sem necessidade de cartão internacional",
    ],
    cons: [
      "Não suporta cobrança automática recorrente",
      "Recarga automática envia apenas notificação push",
    ],
  },
  {
    id: "stripe",
    name: "Stripe",
    tagline: "Pagamento internacional",
    color: "text-[#635bff]",
    selectedBorder: "border-[#635bff]",
    selectedBg: "bg-[#635bff]/5",
    pros: [
      "Cobrança automática com cartão salvo",
      "Recarga automática debita sem intervenção",
      "Portal de faturas e recibos integrado",
      "Aceita cartões internacionais",
    ],
    cons: [
      "Não aceita Pix nem Boleto",
      "Apenas cartão de crédito/débito",
      "Requer configuração do cartão no portal Stripe",
    ],
  },
];

export function GatewaySelector({ currentGateway }: GatewaySelectorProps) {
  const router = useRouter();
  const [selected, setSelected] = useState<Gateway>(currentGateway);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState(false);

  const hasChanged = selected !== currentGateway;

  async function handleSave() {
    setSaving(true);
    setError(null);
    setSuccess(false);

    try {
      const res = await fetch("/api/gateway-preference", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ preferred_gateway: selected }),
      });

      const data = await res.json();

      if (!res.ok) {
        setError(data.error ?? "Erro ao salvar");
        return;
      }

      setSuccess(true);
      router.refresh();
      setTimeout(() => setSuccess(false), 3000);
    } catch {
      setError("Erro de conexão");
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="space-y-4">
      <div className="grid gap-4 sm:grid-cols-2">
        {GATEWAYS.map((gw) => {
          const isSelected = selected === gw.id;

          return (
            <button
              key={gw.id}
              type="button"
              onClick={() => { setSelected(gw.id); setSuccess(false); }}
              className={`relative rounded-xl border-2 p-5 text-left transition-all ${
                isSelected
                  ? `${gw.selectedBorder} ${gw.selectedBg} shadow-md`
                  : "border-border bg-surface hover:border-border hover:shadow-sm"
              }`}
            >
              {isSelected && (
                <span className="absolute right-3 top-3 flex h-5 w-5 items-center justify-center rounded-full bg-current text-white">
                  <svg className="h-3 w-3" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={3}>
                    <path strokeLinecap="round" strokeLinejoin="round" d="M5 13l4 4L19 7" />
                  </svg>
                </span>
              )}

              <h3 className={`text-lg font-bold ${isSelected ? gw.color : "text-content-primary"}`}>
                {gw.name}
              </h3>
              <p className="mt-0.5 text-xs text-content-secondary">{gw.tagline}</p>

              <div className="mt-4 space-y-2">
                <p className="text-xs font-semibold uppercase tracking-wide text-success">
                  Vantagens
                </p>
                <ul className="space-y-1">
                  {gw.pros.map((pro, i) => (
                    <li key={i} className="flex items-start gap-1.5 text-xs text-content-secondary">
                      <span className="mt-0.5 text-green-500 shrink-0">+</span>
                      {pro}
                    </li>
                  ))}
                </ul>
              </div>

              <div className="mt-3 space-y-2">
                <p className="text-xs font-semibold uppercase tracking-wide text-amber-700">
                  Limitações
                </p>
                <ul className="space-y-1">
                  {gw.cons.map((con, i) => (
                    <li key={i} className="flex items-start gap-1.5 text-xs text-content-secondary">
                      <span className="mt-0.5 text-amber-500 shrink-0">-</span>
                      {con}
                    </li>
                  ))}
                </ul>
              </div>
            </button>
          );
        })}
      </div>

      {hasChanged && (
        <div className="flex items-center gap-3">
          <button
            onClick={handleSave}
            disabled={saving}
            className="rounded-lg bg-brand px-5 py-2 text-sm font-medium text-white shadow-sm transition hover:brightness-110 focus:outline-none focus:ring-2 focus:ring-brand focus:ring-offset-2 disabled:opacity-50"
          >
            {saving ? "Salvando..." : "Salvar Preferência"}
          </button>
          <button
            onClick={() => { setSelected(currentGateway); setError(null); }}
            className="text-sm text-content-secondary hover:text-content-secondary"
          >
            Cancelar
          </button>
        </div>
      )}

      {error && <p className="text-sm text-error">{error}</p>}
      {success && <p className="text-sm text-success">Preferência salva com sucesso!</p>}
    </div>
  );
}
