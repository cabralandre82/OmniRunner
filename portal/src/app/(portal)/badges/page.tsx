import { cookies } from "next/headers";
import { createClient } from "@/lib/supabase/server";
import { createServiceClient } from "@/lib/supabase/service";
import { NoGroupSelected } from "@/components/no-group-selected";
import { formatBRL } from "@/lib/format";
import { BuyButton } from "../credits/buy-button";

export const dynamic = "force-dynamic";

export default async function BadgesPage() {
  const groupId = cookies().get("portal_group_id")?.value;
  const role = cookies().get("portal_role")?.value;
  if (!groupId) return <NoGroupSelected />;

  const supabase = createClient();

  const [inventoryRes, productsRes] = await Promise.all([
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
        <h1 className="text-2xl font-bold text-content-primary">
          Badges de Campeonato
        </h1>
        <p className="mt-1 text-sm text-content-secondary">
          Gerencie seus créditos de badges para inscrição em campeonatos
        </p>
      </div>

      {/* KPIs */}
      <div className="grid gap-4 sm:grid-cols-3">
        <div className="rounded-xl border border-border bg-surface p-5 shadow-sm">
          <p className="text-xs font-medium uppercase tracking-wide text-content-secondary">
            Disponíveis
          </p>
          <p
            className={`mt-2 text-3xl font-bold ${available === 0 ? "text-error" : available <= 5 ? "text-orange-600" : "text-content-primary"}`}
          >
            {available}
          </p>
          <p className="mt-1 text-xs text-content-muted">badges para ativar</p>
        </div>
        <div className="rounded-xl border border-border bg-surface p-5 shadow-sm">
          <p className="text-xs font-medium uppercase tracking-wide text-content-secondary">
            Comprados (total)
          </p>
          <p className="mt-2 text-3xl font-bold text-content-primary">{purchased}</p>
          <p className="mt-1 text-xs text-content-muted">desde o início</p>
        </div>
        <div className="rounded-xl border border-border bg-surface p-5 shadow-sm">
          <p className="text-xs font-medium uppercase tracking-wide text-content-secondary">
            Ativados (total)
          </p>
          <p className="mt-2 text-3xl font-bold text-content-primary">{activated}</p>
          <p className="mt-1 text-xs text-content-muted">badges utilizados</p>
        </div>
      </div>

      {/* Buy section */}
      {isAdmin && (
        <div>
          <h2 className="text-lg font-semibold text-content-primary">
            Adquirir Badges
          </h2>
          <p className="mt-1 text-sm text-content-secondary">
            Selecione um pacote para comprar créditos de badges via Pix, boleto
            ou cartão
          </p>

          {products.length === 0 ? (
            <div className="mt-4 rounded-xl border border-dashed border-border bg-bg-secondary p-8 text-center">
              <p className="text-sm text-content-secondary">
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
                    className="flex flex-col justify-between rounded-xl border border-border bg-surface p-5 shadow-sm transition hover:border-purple-200 hover:shadow-md"
                  >
                    <div>
                      <h3 className="text-base font-semibold text-content-primary">
                        {product.name}
                      </h3>
                      <p className="mt-1 text-xs text-content-secondary">
                        {product.description}
                      </p>
                      <div className="mt-4 space-y-1">
                        <p className="text-2xl font-bold text-content-primary">
                          {formatBRL(priceCents)}
                        </p>
                        <p className="text-xs text-content-muted">
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
        <div className="rounded-xl border border-border bg-surface p-6 shadow-sm">
          <p className="text-sm text-content-secondary">
            Apenas o administrador da assessoria pode adquirir novos badges.
            Entre em contato com o responsável.
          </p>
        </div>
      )}
    </div>
  );
}
