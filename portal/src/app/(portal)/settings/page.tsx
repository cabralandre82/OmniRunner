import { cookies } from "next/headers";
import { createClient } from "@/lib/supabase/server";
import { createServiceClient } from "@/lib/supabase/service";
import { trackBillingEvent } from "@/lib/analytics";
import { InviteForm } from "./invite-form";
import { RemoveButton } from "./remove-button";
import { PortalButton } from "./portal-button";
import { AutoTopupForm } from "./auto-topup-form";

const ROLE_LABELS: Record<string, { label: string; color: string }> = {
  admin_master: { label: "Admin", color: "bg-purple-100 text-purple-800" },
  professor:    { label: "Professor", color: "bg-blue-100 text-blue-800" },
  assistente:   { label: "Assistente", color: "bg-gray-100 text-gray-700" },
  coach:        { label: "Coach", color: "bg-purple-100 text-purple-800" },
  assistant:    { label: "Assistente", color: "bg-gray-100 text-gray-700" },
  athlete:      { label: "Atleta", color: "bg-green-100 text-green-800" },
};

function formatDate(ms: number): string {
  return new Date(ms).toLocaleDateString("pt-BR", {
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
  });
}

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
  if (!groupId) return null;

  const isAdmin = role === "admin_master";
  const supabase = createClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();

  const { data: members } = await supabase
    .from("coaching_members")
    .select("id, user_id, display_name, role, joined_at_ms")
    .eq("group_id", groupId)
    .in("role", ["admin_master", "professor", "assistente", "coach", "assistant"])
    .order("joined_at_ms", { ascending: true });

  const staff = (members ?? []) as Member[];

  // Billing data (admin only, uses service client to bypass RLS for auto_topup)
  let topupSettings: TopupSettings | null = null;
  let products: Product[] = [];
  let hasStripeCustomer = false;

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
      .select("stripe_customer_id")
      .eq("group_id", groupId)
      .maybeSingle();

    hasStripeCustomer = !!customer;

    await trackBillingEvent("billing_settings_viewed", { group_id: groupId });
  }

  return (
    <div className="space-y-10">
      {/* ── Billing Section (admin only) ─────────────────────────────── */}
      {isAdmin && (
        <>
          <div>
            <h1 className="text-2xl font-bold text-gray-900">Configurações</h1>
            <p className="mt-1 text-sm text-gray-500">
              Gerencie pagamentos, recarga automática e equipe
            </p>
          </div>

          {/* Stripe Customer Portal */}
          <div className="rounded-xl border border-gray-200 bg-white p-6 shadow-sm">
            <h2 className="text-base font-semibold text-gray-900">
              Métodos de Pagamento e Faturas
            </h2>
            <p className="mt-1 text-sm text-gray-500">
              Gerencie seus cartões, veja faturas e recibos no portal seguro do Stripe.
            </p>
            {hasStripeCustomer ? (
              <PortalButton />
            ) : (
              <p className="mt-4 text-sm text-amber-700 bg-amber-50 rounded-lg p-3">
                Configure seu perfil de faturamento para acessar o portal de pagamento.
                Realize sua primeira compra de créditos para ativar.
              </p>
            )}
          </div>

          {/* Auto Top-Up */}
          <div className="rounded-xl border border-gray-200 bg-white p-6 shadow-sm">
            <h2 className="text-base font-semibold text-gray-900">
              Recarga Automática
            </h2>
            <p className="mt-1 text-sm text-gray-500">
              Quando seus créditos caírem abaixo do limite, o sistema recarrega
              automaticamente usando o cartão salvo.
            </p>
            <AutoTopupForm
              currentSettings={topupSettings}
              products={products}
            />
          </div>
        </>
      )}

      {/* ── Team Section ─────────────────────────────────────────────── */}
      {!isAdmin && (
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Equipe</h1>
          <p className="mt-1 text-sm text-gray-500">
            Membros da assessoria
          </p>
        </div>
      )}

      {isAdmin && (
        <div>
          <h2 className="text-lg font-bold text-gray-900">Equipe</h2>
          <p className="mt-1 text-sm text-gray-500">
            Gerencie o staff da assessoria — convide professores e assistentes
          </p>
        </div>
      )}

      {/* Invite form (admin only) */}
      {isAdmin && (
        <div className="rounded-xl border border-gray-200 bg-white p-6 shadow-sm">
          <h2 className="text-base font-semibold text-gray-900">
            Convidar Membro
          </h2>
          <p className="mt-1 text-sm text-gray-500">
            O usuário precisa já ter uma conta cadastrada na plataforma.
          </p>
          <InviteForm />
        </div>
      )}

      {/* Staff list */}
      <div className="rounded-xl border border-gray-200 bg-white shadow-sm">
        <div className="border-b border-gray-200 px-6 py-4">
          <h2 className="text-base font-semibold text-gray-900">
            Membros do Staff ({staff.length})
          </h2>
        </div>

        {staff.length === 0 ? (
          <div className="px-6 py-8 text-center">
            <p className="text-sm text-gray-500">
              Nenhum membro de staff encontrado.
            </p>
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="min-w-full divide-y divide-gray-200 text-sm">
              <thead className="bg-gray-50">
                <tr>
                  <th className="px-6 py-3 text-left font-medium text-gray-500">
                    Nome
                  </th>
                  <th className="px-6 py-3 text-left font-medium text-gray-500">
                    Função
                  </th>
                  <th className="px-6 py-3 text-left font-medium text-gray-500">
                    Desde
                  </th>
                  {isAdmin && (
                    <th className="px-6 py-3 text-right font-medium text-gray-500">
                      Ação
                    </th>
                  )}
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {staff.map((m) => {
                  const cfg = ROLE_LABELS[m.role] ?? {
                    label: m.role,
                    color: "bg-gray-100 text-gray-600",
                  };
                  const isSelf = m.user_id === user?.id;
                  const isMasterOrCoach =
                    m.role === "admin_master" || m.role === "coach";

                  return (
                    <tr key={m.id} className="hover:bg-gray-50">
                      <td className="whitespace-nowrap px-6 py-4 font-medium text-gray-900">
                        {m.display_name}
                        {isSelf && (
                          <span className="ml-2 text-xs text-gray-400">
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
                      <td className="whitespace-nowrap px-6 py-4 text-gray-600">
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
                            <span className="text-xs text-gray-400">—</span>
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
    </div>
  );
}
