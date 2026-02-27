import { createAdminClient } from "@/lib/supabase/admin";
import { ProductForm, ToggleActive } from "./actions";
import Link from "next/link";

export const dynamic = "force-dynamic";

interface Product {
  id: string;
  name: string;
  description: string;
  credits_amount: number;
  price_cents: number;
  currency: string;
  is_active: boolean;
  sort_order: number;
  created_at: string;
}

export default async function ProdutosPage() {
  const supabase = createAdminClient();

  const { data: products } = await supabase
    .from("billing_products")
    .select("*")
    .order("sort_order", { ascending: true });

  const items: Product[] = products ?? [];

  const fmt = (cents: number) =>
    (cents / 100).toLocaleString("pt-BR", {
      style: "currency",
      currency: "BRL",
    });

  return (
    <div className="space-y-6">
      <div className="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Produtos</h1>
          <p className="mt-1 text-sm text-gray-500">
            Pacotes de créditos disponíveis para compra
          </p>
        </div>
        <Link
          href="/platform"
          className="text-sm text-gray-500 hover:text-gray-700"
        >
          ← Dashboard
        </Link>
      </div>

      {/* Product list */}
      <div className="overflow-x-auto rounded-xl border border-gray-200 bg-white shadow-sm">
        <table className="min-w-full text-sm">
          <thead>
            <tr className="border-b border-gray-100 bg-gray-50 text-left">
              <th className="px-4 py-3 font-medium text-gray-500">Ordem</th>
              <th className="px-4 py-3 font-medium text-gray-500">Nome</th>
              <th className="px-4 py-3 font-medium text-gray-500">Descrição</th>
              <th className="px-4 py-3 font-medium text-gray-500">Créditos</th>
              <th className="px-4 py-3 font-medium text-gray-500">Preço</th>
              <th className="px-4 py-3 font-medium text-gray-500">R$/Crédito</th>
              <th className="px-4 py-3 font-medium text-gray-500">Ativo</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-100">
            {items.map((p) => (
              <tr key={p.id} className="hover:bg-gray-50">
                <td className="px-4 py-3 text-gray-500">{p.sort_order}</td>
                <td className="px-4 py-3 font-medium text-gray-900">
                  {p.name}
                </td>
                <td className="px-4 py-3 text-gray-500 max-w-[200px] truncate">
                  {p.description}
                </td>
                <td className="px-4 py-3 text-gray-700">{p.credits_amount}</td>
                <td className="px-4 py-3 text-gray-700">{fmt(p.price_cents)}</td>
                <td className="px-4 py-3 text-gray-500">
                  {(p.price_cents / p.credits_amount / 100).toFixed(2)}
                </td>
                <td className="px-4 py-3">
                  <ToggleActive productId={p.id} isActive={p.is_active} />
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {/* New product form */}
      <div className="rounded-xl border border-gray-200 bg-white p-5 shadow-sm">
        <h2 className="mb-4 text-base font-semibold text-gray-900">
          Novo pacote
        </h2>
        <ProductForm />
      </div>
    </div>
  );
}
