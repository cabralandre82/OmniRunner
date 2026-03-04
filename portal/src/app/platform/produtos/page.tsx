import { createAdminClient } from "@/lib/supabase/admin";
import { ProductForm, ProductCard } from "./actions";
import Link from "next/link";

export const dynamic = "force-dynamic";

export interface Product {
  id: string;
  name: string;
  description: string;
  credits_amount: number;
  price_cents: number;
  currency: string;
  is_active: boolean;
  sort_order: number;
  product_type: "coins" | "badges";
  created_at: string;
}

export default async function ProdutosPage() {
  const supabase = createAdminClient();

  const { data: products } = await supabase
    .from("billing_products")
    .select("id, name, description, credits_amount, price_cents, currency, is_active, sort_order, product_type, created_at")
    .order("sort_order", { ascending: true });

  const items: Product[] = products ?? [];
  const active = items.filter((p) => p.is_active);
  const inactive = items.filter((p) => !p.is_active);

  return (
    <div className="space-y-6">
      <div className="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <h1 className="text-2xl font-bold text-content-primary">Produtos</h1>
          <p className="mt-1 text-sm text-content-secondary">
            {active.length} ativo(s) · {inactive.length} inativo(s)
          </p>
        </div>
        <Link
          href="/platform"
          className="text-sm text-content-secondary hover:text-content-secondary"
        >
          ← Dashboard
        </Link>
      </div>

      {/* Active products */}
      {active.length > 0 && (
        <div>
          <h2 className="mb-3 text-sm font-semibold text-content-primary">Ativos</h2>
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
            {active.map((p) => (
              <ProductCard key={p.id} product={p} />
            ))}
          </div>
        </div>
      )}

      {/* Inactive products */}
      {inactive.length > 0 && (
        <div>
          <h2 className="mb-3 text-sm font-semibold text-content-secondary">Inativos</h2>
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
            {inactive.map((p) => (
              <ProductCard key={p.id} product={p} />
            ))}
          </div>
        </div>
      )}

      {/* New product form */}
      <div className="rounded-xl border border-border bg-surface p-5 shadow-sm">
        <h2 className="mb-4 text-base font-semibold text-content-primary">
          Novo pacote
        </h2>
        <ProductForm />
      </div>
    </div>
  );
}
