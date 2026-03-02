import { cookies } from "next/headers";
import { createClient } from "@/lib/supabase/server";
import { createServiceClient } from "@/lib/supabase/service";
import { formatBRL } from "@/lib/format";
import { BuyButton } from "../credits/buy-button";

export const dynamic = "force-dynamic";

export default async function BadgesPage() {
  const groupId = cookies().get("portal_group_id")?.value;
  const role = cookies().get("portal_role")?.value;
  if (!groupId) return null;

  const supabase = createClient();

  const [inventoryRes, productsRes, activationsRes] = await Promise.all([
    supabase
      .from("coaching_badge_inventory")
      .select("available_badges, lifetime_purchased, lifetime_activated")
      .eq("group_id", groupId)
      .maybeSingle(),

    supabase
      .from("billing_products")
      .select("id, name, description, credits_amount, price_cents, currency, is_active")
      .eq("is_active", true)
      .eq("product_type", "badges")
      .order("sort_order", { ascending: true }),

    supabase
      .from("championship_badges")
      .select("id, championship_id, user_id, granted_at, expires_at, championships(name, status)")
      .eq(
        "championship_id",
        supabase
          .from("championships")
          .select("id")
          .eq("host_group_id", groupId),
      )
      .order("granted_at", { ascending: false })
      .limit(50),
  ]);

  const inventory = inventoryRes.data;
  const available = inventory?.available_badges ?? 0;
  const purchased = inventory?.lifetime_purchased ?? 0;
  const activated = inventory?.lifetime_activated ?? 0;
  const products = productsRes.data ?? [];

  const db = createServiceClient();
  const { data: customer } = await db
    .from("billing_customers")
    .select("preferred_gateway")
    .eq("group_id", groupId)
    .maybeSingle();

  const preferredGateway =
    (customer?.preferred_gateway as "mercadopago" | "stripe") ?? "mercadopago";

  const isAdmin = role === "admin_master";

  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-2xl font-bold text-gray-900">
          Badges de Campeonato
        </h1>
        <p className="mt-1 text-sm text-gray-500">
          Gerencie seus créditos de badges para inscrição em campeonatos
        </p>
      </div>

      {/* KPIs */}
      <div className="grid gap-4 sm:grid-cols-3">
        <div className="rounded-xl border border-gray-200 bg-white p-5 shadow-sm">
          <p className="text-xs font-medium uppercase tracking-wide text-gray-500">
            Disponíveis
          </p>
          <p
            className={`mt-2 text-3xl font-bold ${available === 0 ? "text-red-600" : available <= 5 ? "text-orange-600" : "text-gray-900"}`}
          >
            {available}
          </p>
          <p className="mt-1 text-xs text-gray-400">badges para ativar</p>
        </div>
        <div className="rounded-xl border border-gray-200 bg-white p-5 shadow-sm">
          <p className="text-xs font-medium uppercase tracking-wide text-gray-500">
            Comprados (total)
          </p>
          <p className="mt-2 text-3xl font-bold text-gray-900">{purchased}</p>
          <p className="mt-1 text-xs text-gray-400">desde o início</p>
        </div>
        <div className="rounded-xl border border-gray-200 bg-white p-5 shadow-sm">
          <p className="text-xs font-medium uppercase tracking-wide text-gray-500">
            Ativados (total)
          </p>
          <p className="mt-2 text-3xl font-bold text-gray-900">{activated}</p>
          <p className="mt-1 text-xs text-gray-400">badges utilizados</p>
        </div>
      </div>

      {/* Buy section */}
      {isAdmin && (
        <div>
          <h2 className="text-lg font-semibold text-gray-900">
            Adquirir Badges
          </h2>
          <p className="mt-1 text-sm text-gray-500">
            Selecione um pacote para comprar créditos de badges via Pix, boleto
            ou cartão
          </p>

          {products.length === 0 ? (
            <div className="mt-4 rounded-xl border border-dashed border-gray-300 bg-gray-50 p-8 text-center">
              <p className="text-sm text-gray-500">
                Nenhum pacote de badges disponível no momento. Entre em contato
                com a plataforma.
              </p>
            </div>
          ) : (
            <div className="mt-4 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
              {products.map((product) => {
                const priceCents = product.price_cents as number;
                const credits = product.credits_amount as number;
                const unitPrice = (priceCents / 100 / credits).toLocaleString(
                  "pt-BR",
                  {
                    style: "currency",
                    currency: "BRL",
                    minimumFractionDigits: 2,
                  },
                );

                return (
                  <div
                    key={product.id}
                    className="flex flex-col justify-between rounded-xl border border-gray-200 bg-white p-5 shadow-sm transition hover:border-purple-200 hover:shadow-md"
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
                          {unitPrice} por badge
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
          )}
        </div>
      )}

      {!isAdmin && (
        <div className="rounded-xl border border-gray-200 bg-white p-6 shadow-sm">
          <p className="text-sm text-gray-500">
            Apenas o administrador da assessoria pode adquirir novos badges.
            Entre em contato com o responsável.
          </p>
        </div>
      )}
    </div>
  );
}
