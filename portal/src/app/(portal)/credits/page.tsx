import { cookies } from "next/headers";
import { createClient } from "@/lib/supabase/server";
import { createServiceClient } from "@/lib/supabase/service";

export const dynamic = "force-dynamic";
import { trackBillingEvent } from "@/lib/analytics";
import { BuyButton } from "./buy-button";

function formatBRL(cents: number): string {
  return (cents / 100).toLocaleString("pt-BR", {
    style: "currency",
    currency: "BRL",
  });
}

function costPerCoin(priceCents: number, credits: number): string {
  return (priceCents / 100 / credits).toLocaleString("pt-BR", {
    style: "currency",
    currency: "BRL",
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  });
}

export default async function CreditsPage() {
  const groupId = cookies().get("portal_group_id")?.value;
  const role = cookies().get("portal_role")?.value;
  if (!groupId) return null;

  const supabase = createClient();

  const [inventoryRes, productsRes] = await Promise.all([
    supabase
      .from("coaching_token_inventory")
      .select("available_tokens")
      .eq("group_id", groupId)
      .maybeSingle(),

    supabase
      .from("billing_products")
      .select("id, name, description, credits_amount, price_cents, currency, is_active")
      .eq("is_active", true)
      .order("sort_order", { ascending: true }),
  ]);

  const balance = inventoryRes.data?.available_tokens ?? 0;
  const products = productsRes.data ?? [];

  const db = createServiceClient();
  const { data: customer } = await db
    .from("billing_customers")
    .select("preferred_gateway")
    .eq("group_id", groupId)
    .maybeSingle();

  const preferredGateway = (customer?.preferred_gateway as "mercadopago" | "stripe") ?? "mercadopago";

  await trackBillingEvent("billing_credits_viewed", {
    group_id: groupId,
    balance,
    products_count: products.length,
  });

  const isAdmin = role === "admin_master";

  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-2xl font-bold text-gray-900">Créditos</h1>
        <p className="mt-1 text-sm text-gray-500">
          Estoque atual e pacotes disponíveis para compra
        </p>
      </div>

      <div className="rounded-xl border border-gray-200 bg-white p-6 shadow-sm">
        <p className="text-xs font-medium uppercase tracking-wide text-gray-500">
          Saldo Disponível
        </p>
        <p className="mt-2 text-3xl font-bold text-gray-900">
          {balance.toLocaleString("pt-BR")}
        </p>
        <p className="mt-1 text-xs text-gray-400">OmniCoins</p>
      </div>

      {isAdmin && (
        <div>
          <h2 className="text-lg font-semibold text-gray-900">
            Pacotes de Créditos
          </h2>
          <p className="mt-1 text-sm text-gray-500">
            Selecione um pacote para adquirir créditos via Pix, boleto ou cartão
          </p>

          <div className="mt-4 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {products.map((product) => {
              const priceCents = product.price_cents as number;
              const credits = product.credits_amount as number;

              return (
                <div
                  key={product.id}
                  className="flex flex-col justify-between rounded-xl border border-gray-200 bg-white p-5 shadow-sm transition hover:border-blue-200 hover:shadow-md"
                >
                  <div>
                    <h3 className="text-base font-semibold text-gray-900">
                      {product.name}
                    </h3>
                    <p className="mt-1 text-xs text-gray-500">
                      {product.description}
                    </p>
                    <div className="mt-4 space-y-1">
                      <p className="text-2xl font-bold text-gray-900">
                        {formatBRL(priceCents)}
                      </p>
                      <p className="text-xs text-gray-400">
                        {costPerCoin(priceCents, credits)} por OmniCoin
                      </p>
                    </div>
                  </div>

                  <BuyButton
                    productId={product.id as string}
                    productName={product.name as string}
                    preferredGateway={preferredGateway}
                  />
                </div>
              );
            })}
          </div>
        </div>
      )}

      {!isAdmin && (
        <div className="rounded-xl border border-gray-200 bg-white p-6 shadow-sm">
          <p className="text-sm text-gray-500">
            Apenas o administrador da assessoria pode adquirir novos pacotes de
            créditos. Entre em contato com o responsável.
          </p>
        </div>
      )}
    </div>
  );
}
