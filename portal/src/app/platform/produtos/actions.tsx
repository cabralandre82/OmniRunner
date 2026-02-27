"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";

export function ToggleActive({
  productId,
  isActive,
}: {
  productId: string;
  isActive: boolean;
}) {
  const router = useRouter();
  const [loading, setLoading] = useState(false);

  async function toggle() {
    setLoading(true);
    try {
      const res = await fetch("/api/platform/products", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          action: "toggle_active",
          product_id: productId,
          is_active: !isActive,
        }),
      });
      if (!res.ok) {
        const data = await res.json();
        alert(data.error ?? "Erro");
      }
      router.refresh();
    } finally {
      setLoading(false);
    }
  }

  return (
    <button
      onClick={toggle}
      disabled={loading}
      className={`rounded-full px-2.5 py-1 text-xs font-medium transition ${
        isActive
          ? "bg-green-100 text-green-700 hover:bg-green-200"
          : "bg-gray-200 text-gray-500 hover:bg-gray-300"
      }`}
    >
      {loading ? "..." : isActive ? "Ativo" : "Inativo"}
    </button>
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
      alert("Preencha todos os campos obrigatórios");
      return;
    }

    setLoading(true);
    try {
      const res = await fetch("/api/platform/products", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          action: "create",
          name,
          description: description || "",
          credits_amount,
          price_cents: Math.round(price_reais * 100),
          sort_order,
        }),
      });

      if (!res.ok) {
        const data = await res.json();
        alert(data.error ?? "Erro ao criar produto");
      } else {
        (e.target as HTMLFormElement).reset();
      }

      router.refresh();
    } finally {
      setLoading(false);
    }
  }

  return (
    <form onSubmit={handleSubmit} className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
      <div>
        <label className="block text-xs font-medium text-gray-600 mb-1">
          Nome *
        </label>
        <input
          name="name"
          required
          className="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm focus:border-blue-500 focus:outline-none focus:ring-1 focus:ring-blue-500"
          placeholder="Ex: Plus"
        />
      </div>
      <div>
        <label className="block text-xs font-medium text-gray-600 mb-1">
          Descrição
        </label>
        <input
          name="description"
          className="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm focus:border-blue-500 focus:outline-none focus:ring-1 focus:ring-blue-500"
          placeholder="Ex: 300 OmniCoins — melhor custo-benefício"
        />
      </div>
      <div>
        <label className="block text-xs font-medium text-gray-600 mb-1">
          Créditos *
        </label>
        <input
          name="credits_amount"
          type="number"
          min={1}
          required
          className="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm focus:border-blue-500 focus:outline-none focus:ring-1 focus:ring-blue-500"
          placeholder="300"
        />
      </div>
      <div>
        <label className="block text-xs font-medium text-gray-600 mb-1">
          Preço (R$) *
        </label>
        <input
          name="price"
          required
          className="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm focus:border-blue-500 focus:outline-none focus:ring-1 focus:ring-blue-500"
          placeholder="129,90"
        />
      </div>
      <div>
        <label className="block text-xs font-medium text-gray-600 mb-1">
          Ordem
        </label>
        <input
          name="sort_order"
          type="number"
          defaultValue={0}
          className="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm focus:border-blue-500 focus:outline-none focus:ring-1 focus:ring-blue-500"
        />
      </div>
      <div className="flex items-end">
        <button
          type="submit"
          disabled={loading}
          className="w-full rounded-lg bg-blue-600 px-4 py-2 text-sm font-medium text-white hover:bg-blue-700 disabled:opacity-50"
        >
          {loading ? "Criando..." : "Criar pacote"}
        </button>
      </div>
    </form>
  );
}
