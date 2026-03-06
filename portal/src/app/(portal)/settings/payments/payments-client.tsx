"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

export interface PaymentsConfig {
  id: string;
  api_key: string;
  environment: string;
  is_active: boolean;
  connected_at: string | null;
  webhook_id: string | null;
}

interface PaymentsClientProps {
  config: PaymentsConfig | null;
}

export function PaymentsClient({ config }: PaymentsClientProps) {
  const router = useRouter();
  const [apiKey, setApiKey] = useState("");
  const [environment, setEnvironment] = useState<"sandbox" | "production">(
    config?.environment === "production" ? "production" : "sandbox",
  );
  const [loading, setLoading] = useState(false);
  const [testResult, setTestResult] = useState<"success" | "fail" | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);
  const [showApiKey, setShowApiKey] = useState(false);
  const [disconnectConfirm, setDisconnectConfirm] = useState(false);

  const isConnected = config != null && config.is_active;

  async function handleTestConnection() {
    if (!apiKey.trim()) {
      setError("Informe a chave de API");
      return;
    }
    setLoading(true);
    setError(null);
    setTestResult(null);

    try {
      const res = await fetch("/api/billing/asaas", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          action: "test_connection",
          api_key: apiKey,
          environment,
        }),
      });

      const data = await res.json();

      if (!res.ok) {
        setTestResult("fail");
        setError(data.error ?? "Falha ao testar conexão");
        return;
      }

      setTestResult("success");
      setError(null);
    } catch {
      setTestResult("fail");
      setError("Erro de conexão");
    } finally {
      setLoading(false);
    }
  }

  async function handleActivate() {
    if (!apiKey.trim()) {
      setError("Informe a chave de API");
      return;
    }
    setLoading(true);
    setError(null);
    setSuccess(null);

    try {
      const res = await fetch("/api/billing/asaas", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          action: "save_config",
          api_key: apiKey,
          environment,
        }),
      });

      const data = await res.json();

      if (!res.ok) {
        setError(data.error ?? "Falha ao salvar configuração");
        return;
      }

      const res2 = await fetch("/api/billing/asaas", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "setup_webhook" }),
      });

      const data2 = await res2.json();

      if (!res2.ok) {
        setError(data2.error ?? "Configuração salva, mas falha ao configurar webhook");
        router.refresh();
        return;
      }

      setSuccess("Cobrança ativada com sucesso!");
      router.refresh();
    } catch {
      setError("Erro de conexão");
    } finally {
      setLoading(false);
    }
  }

  async function handleDisconnect() {
    setLoading(true);
    setError(null);
    setSuccess(null);

    try {
      const res = await fetch("/api/billing/asaas", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "disconnect" }),
      });

      const data = await res.json();

      if (!res.ok) {
        setError(data.error ?? "Falha ao desconectar");
        return;
      }

      setSuccess("Desconectado com sucesso.");
      setDisconnectConfirm(false);
      router.refresh();
    } catch {
      setError("Erro de conexão");
    } finally {
      setLoading(false);
    }
  }

  const formatDate = (dateStr: string | null) => {
    if (!dateStr) return "—";
    try {
      return new Date(dateStr).toLocaleDateString("pt-BR", {
        day: "2-digit",
        month: "2-digit",
        year: "numeric",
        hour: "2-digit",
        minute: "2-digit",
      });
    } catch {
      return dateStr;
    }
  };

  return (
    <div className="rounded-xl border border-border bg-surface p-6 shadow-sm">
      {!isConnected ? (
        <>
          <h2 className="text-base font-semibold text-content-primary">
            Conectar Asaas
          </h2>
          <p className="mt-1 mb-5 text-sm text-content-secondary">
            Configure sua chave de API do Asaas para habilitar cobranças
            automáticas de assinaturas.
          </p>

          <div className="space-y-4">
            <div>
              <label
                htmlFor="api_key"
                className="mb-1 block text-sm font-medium text-content-primary"
              >
                Chave de API
              </label>
              <div className="relative">
                <input
                  id="api_key"
                  type={showApiKey ? "text" : "password"}
                  value={apiKey}
                  onChange={(e) => setApiKey(e.target.value)}
                  placeholder="$aas_..."
                  className="w-full rounded-lg border border-border bg-surface px-3 py-2 pr-10 text-sm text-content-primary placeholder:text-content-muted"
                  disabled={loading}
                />
                <button
                  type="button"
                  onClick={() => setShowApiKey(!showApiKey)}
                  className="absolute right-2 top-1/2 -translate-y-1/2 text-content-muted hover:text-content-secondary"
                  aria-label={showApiKey ? "Ocultar" : "Mostrar"}
                >
                  {showApiKey ? (
                    <svg
                      className="h-4 w-4"
                      fill="none"
                      viewBox="0 0 24 24"
                      stroke="currentColor"
                    >
                      <path
                        strokeLinecap="round"
                        strokeLinejoin="round"
                        strokeWidth={2}
                        d="M13.875 18.825A10.05 10.05 0 0112 19c-4.478 0-8.268-2.943-9.543-7a9.97 9.97 0 011.563-3.029m5.858.908a3 3 0 114.243 4.243M9.878 9.878l4.242 4.242M9.88 9.88l-3.29-3.29m7.532 7.532l3.29 3.29M3 3l3.59 3.59m0 0A9.953 9.953 0 0112 5c4.478 0 8.268 2.943 9.543 7a10.025 10.025 0 01-4.132 5.411m0 0L21 21"
                      />
                    </svg>
                  ) : (
                    <svg
                      className="h-4 w-4"
                      fill="none"
                      viewBox="0 0 24 24"
                      stroke="currentColor"
                    >
                      <path
                        strokeLinecap="round"
                        strokeLinejoin="round"
                        strokeWidth={2}
                        d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"
                      />
                      <path
                        strokeLinecap="round"
                        strokeLinejoin="round"
                        strokeWidth={2}
                        d="M2.458 12C3.732 7.943 7.523 5 12 5c4.478 0 8.268 2.943 9.542 7-1.274 4.057-5.064 7-9.542 7-4.477 0-8.268-2.943-9.542-7z"
                      />
                    </svg>
                  )}
                </button>
              </div>
            </div>

            <div>
              <label
                htmlFor="environment"
                className="mb-1 block text-sm font-medium text-content-primary"
              >
                Ambiente
              </label>
              <select
                id="environment"
                value={environment}
                onChange={(e) =>
                  setEnvironment(e.target.value as "sandbox" | "production")
                }
                className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm text-content-primary"
                disabled={loading}
              >
                <option value="sandbox">Sandbox (testes)</option>
                <option value="production">Produção</option>
              </select>
            </div>

            <div className="flex flex-wrap gap-3">
              <button
                type="button"
                onClick={handleTestConnection}
                disabled={loading}
                className="rounded-lg border border-border bg-surface px-4 py-2 text-sm font-medium text-content-primary hover:bg-surface-elevated disabled:opacity-50"
              >
                {loading ? "Testando..." : "Testar Conexão"}
              </button>
              {testResult === "success" && (
                <button
                  type="button"
                  onClick={handleActivate}
                  disabled={loading}
                  className="rounded-lg bg-brand px-4 py-2 text-sm font-medium text-white hover:brightness-110 disabled:opacity-50"
                >
                  Ativar Cobrança
                </button>
              )}
            </div>
          </div>
        </>
      ) : (
        <>
          <h2 className="text-base font-semibold text-content-primary">
            Status da Integração
          </h2>
          <p className="mt-1 mb-5 text-sm text-content-secondary">
            O Asaas está conectado e pronto para cobranças automáticas.
          </p>

          <div className="flex flex-wrap items-center gap-3">
            <span className="inline-flex items-center rounded-full bg-success-soft px-3 py-1 text-sm font-medium text-success">
              Conectado
            </span>
            <span
              className={`inline-flex items-center rounded-full px-3 py-1 text-sm font-medium ${
                config.environment === "production"
                  ? "bg-brand/10 text-brand"
                  : "bg-surface-elevated text-content-secondary"
              }`}
            >
              {config.environment === "production" ? "Produção" : "Sandbox"}
            </span>
          </div>

          <p className="mt-4 text-sm text-content-secondary">
            Conectado em: {formatDate(config.connected_at)}
          </p>

          {!disconnectConfirm ? (
            <button
              type="button"
              onClick={() => setDisconnectConfirm(true)}
              className="mt-4 rounded-lg border border-error/50 bg-error-soft px-4 py-2 text-sm font-medium text-error hover:bg-error/10"
            >
              Desconectar
            </button>
          ) : (
            <div className="mt-4 flex flex-wrap items-center gap-3">
              <p className="text-sm text-content-secondary">
                Tem certeza que deseja desconectar? As cobranças automáticas
                serão interrompidas.
              </p>
              <button
                type="button"
                onClick={handleDisconnect}
                disabled={loading}
                className="rounded-lg bg-error px-4 py-2 text-sm font-medium text-white hover:brightness-110 disabled:opacity-50"
              >
                {loading ? "Desconectando..." : "Sim, Desconectar"}
              </button>
              <button
                type="button"
                onClick={() => setDisconnectConfirm(false)}
                disabled={loading}
                className="rounded-lg border border-border px-4 py-2 text-sm font-medium text-content-primary hover:bg-surface-elevated"
              >
                Cancelar
              </button>
            </div>
          )}
        </>
      )}

      {error && (
        <div className="mt-4 rounded-lg border border-error/30 bg-error-soft p-3">
          <p className="text-sm text-error">{error}</p>
        </div>
      )}
      {success && (
        <div className="mt-4 rounded-lg border border-success/30 bg-success-soft p-3">
          <p className="text-sm text-success">{success}</p>
        </div>
      )}
    </div>
  );
}
