import type { Metadata } from "next";
import { cookies } from "next/headers";
import { createClient } from "@/lib/supabase/server";
import { createServiceClient } from "@/lib/supabase/service";
import { NoGroupSelected } from "@/components/no-group-selected";

export const metadata: Metadata = { title: "Configurações" };
export const dynamic = "force-dynamic";
import { trackBillingEvent } from "@/lib/analytics";
import { InviteForm } from "./invite-form";
import { RemoveButton } from "./remove-button";
import { PortalButton } from "./portal-button";
import { AutoTopupForm } from "./auto-topup-form";
import { GatewaySelector } from "./gateway-selector";
import { BrandingForm } from "./branding-form";
import { formatDateMs } from "@/lib/format";

const ROLE_LABELS: Record<string, { label: string; color: string }> = {
  admin_master: { label: "Admin", color: "bg-purple-100 text-purple-800" },
  coach:        { label: "Coach", color: "bg-info-soft text-info" },
  assistant:    { label: "Assistente", color: "bg-surface-elevated text-content-secondary" },
  athlete:      { label: "Atleta", color: "bg-success-soft text-success" },
};

const formatDate = formatDateMs;

interface Member {
  id: string;
  user_id: string;
  display_name: string;
  role: string;
  joined_at_ms: number;
}

interface Product {
  id: string;
  name: string;
  credits_amount: number;
  price_cents: number;
}

interface TopupSettings {
  enabled: boolean;
  threshold_tokens: number;
  product_id: string;
  max_per_month: number;
}

export default async function SettingsPage() {
  const groupId = cookies().get("portal_group_id")?.value;
  const role = cookies().get("portal_role")?.value;
  if (!groupId) return <NoGroupSelected />;

  const isAdmin = role === "admin_master";
  const supabase = createClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();

  const { data: members } = await supabase
    .from("coaching_members")
    .select("id, user_id, display_name, role, joined_at_ms")
    .eq("group_id", groupId)
    .in("role", ["admin_master", "coach", "assistant"])
    .order("joined_at_ms", { ascending: true });

  const staff = (members ?? []) as Member[];

  // Billing data (admin only, uses service client to bypass RLS for auto_topup)
  let topupSettings: TopupSettings | null = null;
  let products: Product[] = [];
  let hasStripeCustomer = false;
  let hasStripePaymentMethod = false;
  let preferredGateway: "mercadopago" | "stripe" = "mercadopago";

  if (isAdmin) {
    const db = createServiceClient();

    const { data: settings } = await db
      .from("billing_auto_topup_settings")
      .select("enabled, threshold_tokens, product_id, max_per_month")
      .eq("group_id", groupId)
      .maybeSingle();

    topupSettings = settings as TopupSettings | null;

    const { data: prods } = await supabase
      .from("billing_products")
      .select("id, name, credits_amount, price_cents")
      .eq("is_active", true)
      .order("sort_order", { ascending: true });

    products = (prods ?? []) as Product[];

    const { data: customer } = await db
      .from("billing_customers")
      .select("stripe_customer_id, stripe_default_pm, preferred_gateway")
      .eq("group_id", groupId)
      .maybeSingle();

    hasStripeCustomer = !!customer?.stripe_customer_id;
    hasStripePaymentMethod = !!(customer?.stripe_customer_id && customer?.stripe_default_pm);
    preferredGateway = (customer?.preferred_gateway as "mercadopago" | "stripe") ?? "mercadopago";

    await trackBillingEvent("billing_settings_viewed", { group_id: groupId });
  }

  const db2 = createServiceClient();
  const [feesRes, accountRes] = await Promise.all([
    db2.from("platform_fee_config").select("fee_type, rate_pct, is_active").order("fee_type"),
    db2.from("custody_accounts").select("total_deposited_usd, total_committed, is_blocked, blocked_reason").eq("group_id", groupId).maybeSingle(),
  ]);
  const fees = (feesRes.data ?? []) as { fee_type: string; rate_pct: number; is_active: boolean }[];
  const custodyAcct = accountRes.data;

  return (
    <div className="space-y-10">
      {/* ── Billing Section (admin only) ─────────────────────────────── */}
      {isAdmin && (
        <>
          <div>
            <h1 className="text-2xl font-bold text-content-primary">Configurações</h1>
            <p className="mt-1 text-sm text-content-secondary">
              Gerencie pagamentos, recarga automática e equipe
            </p>
          </div>

          {/* Gateway Preference */}
          <div className="rounded-xl border border-border bg-surface p-6 shadow-sm">
            <h2 className="text-base font-semibold text-content-primary">
              Gateway de Pagamento Preferido
            </h2>
            <p className="mt-1 mb-5 text-sm text-content-secondary">
              Escolha como sua assessoria prefere pagar. Você pode trocar a qualquer momento.
            </p>
            <GatewaySelector currentGateway={preferredGateway} />
          </div>

          {/* Stripe Customer Portal (optional) */}
          {hasStripeCustomer && (
            <div className="rounded-xl border border-border bg-surface p-6 shadow-sm">
              <h2 className="text-base font-semibold text-content-primary">
                Métodos de Pagamento e Faturas (Stripe)
              </h2>
              <p className="mt-1 text-sm text-content-secondary">
                Gerencie seus cartões, veja faturas e recibos no portal seguro do Stripe.
              </p>
              <PortalButton />
            </div>
          )}

          {/* Auto Top-Up */}
          <div className="rounded-xl border border-border bg-surface p-6 shadow-sm">
            <h2 className="text-base font-semibold text-content-primary">
              Recarga Automática
            </h2>
            <p className="mt-1 text-sm text-content-secondary">
              Quando seus créditos caírem abaixo do limite configurado:
            </p>
            <ul className="mt-1 text-sm text-content-secondary list-disc list-inside space-y-0.5">
              <li>
                <strong>Com cartão Stripe salvo:</strong> cobrança automática
              </li>
              <li>
                <strong>Sem cartão salvo:</strong> você recebe uma notificação push para comprar manualmente pelo portal
              </li>
            </ul>
            <AutoTopupForm
              currentSettings={topupSettings}
              products={products}
              hasStripePaymentMethod={hasStripePaymentMethod}
            />
          </div>
        </>
      )}

      {/* ── Branding Section (admin only) ──────────────────────────── */}
      {isAdmin && (
        <div className="rounded-xl border border-border bg-surface p-6 shadow-sm">
          <h2 className="text-base font-semibold text-content-primary">
            Identidade Visual
          </h2>
          <p className="mt-1 mb-5 text-sm text-content-secondary">
            Personalize o portal com o logo e as cores da sua assessoria
          </p>
          <BrandingForm />
        </div>
      )}

      {/* ── Team Section ─────────────────────────────────────────────── */}
      {!isAdmin && (
        <div>
          <h1 className="text-2xl font-bold text-content-primary">Equipe</h1>
          <p className="mt-1 text-sm text-content-secondary">
            Membros da assessoria
          </p>
        </div>
      )}

      {isAdmin && (
        <div>
          <h2 className="text-lg font-bold text-content-primary">Equipe</h2>
          <p className="mt-1 text-sm text-content-secondary">
            Gerencie o staff da assessoria — convide professores e assistentes
          </p>
        </div>
      )}

      {/* Invite form (admin only) */}
      {isAdmin && (
        <div className="rounded-xl border border-border bg-surface p-6 shadow-sm">
          <h2 className="text-base font-semibold text-content-primary">
            Convidar Membro
          </h2>
          <p className="mt-1 text-sm text-content-secondary">
            O usuário precisa já ter uma conta cadastrada na plataforma.
          </p>
          <InviteForm />
        </div>
      )}

      {/* Staff list */}
      <div className="rounded-xl border border-border bg-surface shadow-sm">
        <div className="border-b border-border px-6 py-4">
          <h2 className="text-base font-semibold text-content-primary">
            Membros do Staff ({staff.length})
          </h2>
        </div>

        {staff.length === 0 ? (
          <div className="px-6 py-8 text-center">
            <p className="text-sm text-content-secondary">
              Nenhum membro de staff encontrado.
            </p>
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="min-w-full divide-y divide-border text-sm">
              <thead className="bg-bg-secondary">
                <tr>
                  <th className="px-6 py-3 text-left font-medium text-content-secondary">
                    Nome
                  </th>
                  <th className="px-6 py-3 text-left font-medium text-content-secondary">
                    Função
                  </th>
                  <th className="px-6 py-3 text-left font-medium text-content-secondary">
                    Desde
                  </th>
                  {isAdmin && (
                    <th className="px-6 py-3 text-right font-medium text-content-secondary">
                      Ação
                    </th>
                  )}
                </tr>
              </thead>
              <tbody className="divide-y divide-border-subtle">
                {staff.map((m) => {
                  const cfg = ROLE_LABELS[m.role] ?? {
                    label: m.role,
                    color: "bg-surface-elevated text-content-secondary",
                  };
                  const isSelf = m.user_id === user?.id;
                  const isMasterOrCoach =
                    m.role === "admin_master" || m.role === "coach";

                  return (
                    <tr key={m.id} className="hover:bg-surface-elevated">
                      <td className="whitespace-nowrap px-6 py-4 font-medium text-content-primary">
                        {m.display_name}
                        {isSelf && (
                          <span className="ml-2 text-xs text-content-muted">
                            (você)
                          </span>
                        )}
                      </td>
                      <td className="whitespace-nowrap px-6 py-4">
                        <span
                          className={`inline-flex rounded-full px-2.5 py-0.5 text-xs font-medium ${cfg.color}`}
                        >
                          {cfg.label}
                        </span>
                      </td>
                      <td className="whitespace-nowrap px-6 py-4 text-content-secondary">
                        {formatDate(m.joined_at_ms)}
                      </td>
                      {isAdmin && (
                        <td className="whitespace-nowrap px-6 py-4 text-right">
                          {!isSelf && !isMasterOrCoach ? (
                            <RemoveButton
                              memberId={m.id}
                              memberName={m.display_name}
                            />
                          ) : (
                            <span className="text-xs text-content-muted">—</span>
                          )}
                        </td>
                      )}
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {/* Taxas e Custodia */}
      <div className="rounded-xl border border-border bg-surface p-6 shadow-sm">
        <h2 className="text-base font-semibold text-content-primary">Taxas Aplicadas</h2>
        <p className="mt-1 mb-4 text-sm text-content-secondary">
          Taxas vigentes para o seu clube conforme contrato da plataforma.
        </p>
        <table className="min-w-full text-sm">
          <thead>
            <tr className="text-left text-xs font-medium uppercase text-content-secondary">
              <th className="pb-2 pr-4">Tipo</th>
              <th className="pb-2 pr-4 text-right">Taxa (%)</th>
              <th className="pb-2">Status</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-border-subtle">
            {fees.map((f) => (
              <tr key={f.fee_type}>
                <td className="py-2 pr-4 text-content-primary capitalize">{f.fee_type.replace(/_/g, " ")}</td>
                <td className="py-2 pr-4 text-right font-medium text-content-primary">{f.rate_pct}%</td>
                <td className="py-2">
                  <span className={`inline-flex rounded-full px-2 py-0.5 text-xs font-medium ${f.is_active ? "bg-success-soft text-success" : "bg-surface-elevated text-content-secondary"}`}>
                    {f.is_active ? "Ativa" : "Inativa"}
                  </span>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {custodyAcct && (
        <div className="rounded-xl border border-border bg-surface p-6 shadow-sm">
          <h2 className="text-base font-semibold text-content-primary">Status de Custodia</h2>
          <div className="mt-3 grid grid-cols-2 gap-4 text-sm sm:grid-cols-4">
            <div>
              <p className="text-content-secondary">Total Depositado</p>
              <p className="text-lg font-bold text-content-primary">US$ {Number(custodyAcct.total_deposited_usd ?? 0).toFixed(2)}</p>
            </div>
            <div>
              <p className="text-content-secondary">Reservado</p>
              <p className="text-lg font-bold text-brand">US$ {Number(custodyAcct.total_committed ?? 0).toFixed(2)}</p>
            </div>
            <div>
              <p className="text-content-secondary">Disponivel</p>
              <p className="text-lg font-bold text-success">US$ {(Number(custodyAcct.total_deposited_usd ?? 0) - Number(custodyAcct.total_committed ?? 0)).toFixed(2)}</p>
            </div>
            <div>
              <p className="text-content-secondary">Bloqueio</p>
              <p className={`text-lg font-bold ${custodyAcct.is_blocked ? "text-error" : "text-success"}`}>
                {custodyAcct.is_blocked ? (custodyAcct.blocked_reason ?? "Sim") : "Nao"}
              </p>
            </div>
          </div>
        </div>
      )}

    </div>
  );
}