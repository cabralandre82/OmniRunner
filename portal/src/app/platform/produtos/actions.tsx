"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";
import { toast } from "sonner";
import type { Product } from "./page";

async function apiCall(body: Record<string, unknown>) {
  const res = await fetch("/api/platform/products", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  if (!res.ok) {
    const data = await res.json();
    toast.error(data.error ?? "Erro");
    return false;
  }
  return true;
}

function fmt(cents: number) {
  return (cents / 100).toLocaleString("pt-BR", {
    style: "currency",
    currency: "BRL",
  });
}

export function ProductCard({ product: p }: { product: Product }) {
  const router = useRouter();
  const [editing, setEditing] = useState(false);
  const [loading, setLoading] = useState(false);

  async function handleToggle() {
    setLoading(true);
    await apiCall({
      action: "toggle_active",
      product_id: p.id,
      is_active: !p.is_active,
    });
    router.refresh();
    setLoading(false);
  }

  async function handleDelete() {
    const ok = confirm(
      `Remover "${p.name}" permanentemente? Se houver compras vinculadas, a remoção pode falhar.`,
    );
    if (!ok) return;
    setLoading(true);
    await apiCall({ action: "delete", product_id: p.id });
    router.refresh();
    setLoading(false);
  }

  if (editing) {
    return (
      <EditForm
        product={p}
        onClose={() => setEditing(false)}
      />
    );
  }

  const unitPrice = (p.price_cents / p.credits_amount / 100).toFixed(2);

  return (
    <div
      className={`rounded-xl border bg-surface p-4 shadow-sm ${
        p.is_active ? "border-border" : "border-dashed border-border opacity-60"
      }`}
    >
      <div className="flex items-start justify-between gap-2">
        <div>
          <div className="flex items-center gap-2">
            <h3 className="text-sm font-semibold text-content-primary">{p.name}</h3>
            <span
              className={`rounded-full px-2 py-0.5 text-[10px] font-medium ${
                p.product_type === "badges"
                  ? "bg-purple-100 text-purple-700"
                  : "bg-blue-100 text-brand"
              }`}
            >
              {p.product_type === "badges" ? "Badge" : "Coins"}
            </span>
            <span
              className={`rounded-full px-2 py-0.5 text-[10px] font-medium ${
                p.is_active
                  ? "bg-success-soft text-success"
                  : "bg-surface-elevated text-content-secondary"
              }`}
            >
              {p.is_active ? "Ativo" : "Inativo"}
            </span>
          </div>
          {p.description && (
            <p className="mt-1 text-xs text-content-secondary">{p.description}</p>
          )}
        </div>
        <span className="text-xs text-content-muted">#{p.sort_order}</span>
      </div>

      <div className="mt-3 flex flex-wrap gap-x-4 gap-y-1 text-xs text-content-secondary">
        <span>
          <strong>{p.credits_amount}</strong> créditos
        </span>
        <span>
          <strong>{fmt(p.price_cents)}</strong>
        </span>
        <span>R$ {unitPrice}/créd.</span>
      </div>

      <div className="mt-3 flex flex-wrap gap-2 border-t border-border-subtle pt-3">
        <button
          onClick={() => setEditing(true)}
          className="rounded-lg bg-surface-elevated px-3 py-1.5 text-xs font-medium text-content-secondary hover:bg-bg-secondary"
        >
          Editar
        </button>
        <button
          onClick={handleToggle}
          disabled={loading}
          className={`rounded-lg px-3 py-1.5 text-xs font-medium ${
            p.is_active
              ? "bg-orange-50 text-orange-600 hover:bg-orange-100"
              : "bg-success-soft text-green-600 hover:bg-success-soft"
          }`}
        >
          {loading ? "..." : p.is_active ? "Suspender" : "Ativar"}
        </button>
        <button
          onClick={handleDelete}
          disabled={loading}
          className="rounded-lg bg-error-soft px-3 py-1.5 text-xs font-medium text-error hover:bg-error-soft"
        >
          {loading ? "..." : "Remover"}
        </button>
      </div>
    </div>
  );
}

function EditForm({
  product: p,
  onClose,
}: {
  product: Product;
  onClose: () => void;
}) {
  const router = useRouter();
  const [loading, setLoading] = useState(false);

  async function handleSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const form = new FormData(e.currentTarget);
    const name = form.get("name") as string;
    const description = form.get("description") as string;
    const credits_amount = parseInt(form.get("credits_amount") as string, 10);
    const priceStr = (form.get("price") as string).replace(",", ".");
    const price_cents = Math.round(parseFloat(priceStr) * 100);
    const sort_order = parseInt(form.get("sort_order") as string, 10) || 0;

    if (!name || !credits_amount || !price_cents) {
      toast.error("Preencha todos os campos obrigatórios");
      return;
    }

    setLoading(true);
    const ok = await apiCall({
      action: "update",
      product_id: p.id,
      name,
      description,
      credits_amount,
      price_cents,
      sort_order,
    });
    if (ok) {
      onClose();
      router.refresh();
    }
    setLoading(false);
  }

  return (
    <div className="rounded-xl border-2 border-blue-300 bg-brand-soft/30 p-4 shadow-sm">
      <h3 className="mb-3 text-sm font-semibold text-content-primary">
        Editando: {p.name}
      </h3>
      <form onSubmit={handleSubmit} className="space-y-3">
        <div className="grid grid-cols-2 gap-3">
          <Input label="Nome *" name="name" defaultValue={p.name} required />
          <Input
            label="Descrição"
            name="description"
            defaultValue={p.description}
          />
          <Input
            label="Créditos *"
            name="credits_amount"
            type="number"
            defaultValue={String(p.credits_amount)}
            required
          />
          <Input
            label="Preço (R$) *"
            name="price"
            defaultValue={(p.price_cents / 100).toFixed(2).replace(".", ",")}
            required
          />
          <Input
            label="Ordem"
            name="sort_order"
            type="number"
            defaultValue={String(p.sort_order)}
          />
        </div>
        <div className="flex gap-2">
          <button
            type="submit"
            disabled={loading}
            className="rounded-lg bg-brand px-4 py-1.5 text-xs font-medium text-white hover:brightness-110 disabled:opacity-50"
          >
            {loading ? "Salvando..." : "Salvar"}
          </button>
          <button
            type="button"
            onClick={onClose}
            className="rounded-lg bg-surface-elevated px-4 py-1.5 text-xs font-medium text-content-secondary hover:bg-bg-secondary"
          >
            Cancelar
          </button>
        </div>
      </form>
    </div>
  );
}

function Input({
  label,
  name,
  type = "text",
  defaultValue,
  required = false,
}: {
  label: string;
  name: string;
  type?: string;
  defaultValue?: string;
  required?: boolean;
}) {
  return (
    <div>
      <label className="block text-[10px] font-medium text-content-secondary mb-0.5">
        {label}
      </label>
      <input
        name={name}
        type={type}
        defaultValue={defaultValue}
        required={required}
        className="w-full rounded-lg border border-border px-2.5 py-1.5 text-sm focus:border-brand focus:outline-none focus:ring-1 focus:ring-brand"
      />
    </div>
  );
}

export function ProductForm() {
  const router = useRouter();
  const [loading, setLoading] = useState(false);

  async function handleSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const form = new FormData(e.currentTarget);
    const name = form.get("name") as string;
    const description = form.get("description") as string;
    const credits_amount = parseInt(form.get("credits_amount") as string, 10);
    const price_reais = parseFloat(
      (form.get("price") as string).replace(",", "."),
    );
    const sort_order = parseInt(form.get("sort_order") as string, 10) || 0;

    if (!name || !credits_amount || !price_reais) {
      toast.error("Preencha todos os campos obrigatórios");
      return;
    }

    const product_type = (form.get("product_type") as string) || "coins";

    setLoading(true);
    const ok = await apiCall({
      action: "create",
      name,
      description: description || "",
      credits_amount,
      price_cents: Math.round(price_reais * 100),
      sort_order,
      product_type,
    });
    if (ok) {
      (e.target as HTMLFormElement).reset();
    }
    router.refresh();
    setLoading(false);
  }

  return (
    <form
      onSubmit={handleSubmit}
      className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3"
    >
      <div>
        <label className="block text-xs font-medium text-content-secondary mb-1">
          Nome *
        </label>
        <input
          name="name"
          required
          className="w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-brand focus:outline-none focus:ring-1 focus:ring-brand"
          placeholder="Ex: Plus"
        />
      </div>
      <div>
        <label className="block text-xs font-medium text-content-secondary mb-1">
          Descrição
        </label>
        <input
          name="description"
          className="w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-brand focus:outline-none focus:ring-1 focus:ring-brand"
          placeholder="Ex: 300 OmniCoins — melhor custo-benefício"
        />
      </div>
      <div>
        <label className="block text-xs font-medium text-content-secondary mb-1">
          Créditos *
        </label>
        <input
          name="credits_amount"
          type="number"
          min={1}
          required
          className="w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-brand focus:outline-none focus:ring-1 focus:ring-brand"
          placeholder="300"
        />
      </div>
      <div>
        <label className="block text-xs font-medium text-content-secondary mb-1">
          Preço (R$) *
        </label>
        <input
          name="price"
          required
          className="w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-brand focus:outline-none focus:ring-1 focus:ring-brand"
          placeholder="129,90"
        />
      </div>
      <div>
        <label className="block text-xs font-medium text-content-secondary mb-1">
          Ordem
        </label>
        <input
          name="sort_order"
          type="number"
          defaultValue={0}
          className="w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-brand focus:outline-none focus:ring-1 focus:ring-brand"
        />
      </div>
      <div>
        <label className="block text-xs font-medium text-content-secondary mb-1">
          Tipo
        </label>
        <select
          name="product_type"
          defaultValue="coins"
          className="w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-brand focus:outline-none focus:ring-1 focus:ring-brand"
        >
          <option value="coins">OmniCoins</option>
          <option value="badges">Badge Campeonato</option>
        </select>
      </div>
      <div className="flex items-end">
        <button
          type="submit"
          disabled={loading}
          className="w-full rounded-lg bg-brand px-4 py-2 text-sm font-medium text-white hover:brightness-110 disabled:opacity-50"
        >
          {loading ? "Criando..." : "Criar pacote"}
        </button>
      </div>
    </form>
  );
}
