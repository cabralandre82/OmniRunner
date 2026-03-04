"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

export function CreateBatchForm({ groupId }: { groupId: string }) {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const router = useRouter();
  const supabase = createClient();

  async function handleSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    if (loading) return;
    setLoading(true);
    setError(null);

    const form = new FormData(e.currentTarget);
    const periodStart = (form.get("period_start") as string) || null;
    const periodEnd = (form.get("period_end") as string) || null;

    try {
      const { error: rpcError } = await supabase.rpc("fn_create_delivery_batch", {
        p_group_id: groupId,
        p_period_start: periodStart,
        p_period_end: periodEnd,
      });

      if (rpcError) {
        setError(rpcError.message);
        return;
      }
      router.refresh();
    } catch {
      setError("Erro inesperado ao criar lote.");
    } finally {
      setLoading(false);
    }
  }

  return (
    <form onSubmit={handleSubmit} className="mt-3 flex flex-wrap items-end gap-3">
      <div>
        <label htmlFor="period_start" className="block text-xs font-medium text-content-secondary">
          Início do período
        </label>
        <input
          type="date"
          id="period_start"
          name="period_start"
          className="mt-1 rounded-lg border border-border bg-surface px-3 py-1.5 text-sm text-content-primary shadow-sm focus:border-brand focus:ring-1 focus:ring-brand"
        />
      </div>
      <div>
        <label htmlFor="period_end" className="block text-xs font-medium text-content-secondary">
          Fim do período
        </label>
        <input
          type="date"
          id="period_end"
          name="period_end"
          className="mt-1 rounded-lg border border-border bg-surface px-3 py-1.5 text-sm text-content-primary shadow-sm focus:border-brand focus:ring-1 focus:ring-brand"
        />
      </div>
      <button
        type="submit"
        disabled={loading}
        className="rounded-lg bg-brand px-4 py-1.5 text-sm font-medium text-white shadow-sm hover:brightness-110 disabled:opacity-50"
      >
        {loading ? "Criando…" : "Criar Lote"}
      </button>
      {error && <p className="w-full text-xs text-error">{error}</p>}
    </form>
  );
}

export function GenerateItemsButton({ batchId }: { batchId: string }) {
  const [loading, setLoading] = useState(false);
  const [result, setResult] = useState<string | null>(null);
  const router = useRouter();
  const supabase = createClient();

  async function handleClick() {
    if (loading) return;
    setLoading(true);
    setResult(null);

    try {
      const { data, error } = await supabase.rpc("fn_generate_delivery_items", {
        p_batch_id: batchId,
      });

      if (error) {
        setResult(`Erro: ${error.message}`);
        return;
      }
      setResult(`${data} itens gerados`);
      router.refresh();
    } catch {
      setResult("Erro inesperado.");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="inline-flex items-center gap-2">
      <button
        type="button"
        onClick={handleClick}
        disabled={loading}
        className="rounded-lg bg-brand px-2.5 py-1.5 text-xs font-medium text-white hover:brightness-110 disabled:opacity-50"
      >
        {loading ? "Gerando…" : "Gerar Itens"}
      </button>
      {result && <span className="text-xs text-content-muted">{result}</span>}
    </div>
  );
}

export function PublishButton({ itemId }: { itemId: string }) {
  const [loading, setLoading] = useState(false);
  const router = useRouter();
  const supabase = createClient();

  async function handleClick() {
    if (loading) return;
    setLoading(true);

    try {
      const { error } = await supabase.rpc("fn_mark_item_published", {
        p_item_id: itemId,
      });

      if (error) {
        console.error("Erro ao publicar item:", error);
        return;
      }
      router.refresh();
    } finally {
      setLoading(false);
    }
  }

  return (
    <button
      type="button"
      onClick={handleClick}
      disabled={loading}
      className="rounded-lg bg-brand px-2.5 py-1.5 text-xs font-medium text-white hover:brightness-110 disabled:opacity-50"
    >
      {loading ? "…" : "Marcar Publicado"}
    </button>
  );
}

export function CopyPayloadButton({ payload }: { payload: Record<string, unknown> }) {
  const [copied, setCopied] = useState(false);

  async function handleClick() {
    try {
      await navigator.clipboard.writeText(JSON.stringify(payload, null, 2));
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      console.error("Falha ao copiar para clipboard");
    }
  }

  return (
    <button
      type="button"
      onClick={handleClick}
      className="rounded-lg border border-border bg-surface px-2.5 py-1.5 text-xs font-medium text-content-secondary hover:bg-surface-elevated disabled:opacity-50"
    >
      {copied ? "Copiado!" : "Copiar Treino"}
    </button>
  );
}
