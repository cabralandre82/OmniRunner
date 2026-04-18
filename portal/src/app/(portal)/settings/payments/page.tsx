import { cookies } from "next/headers";
import { createClient } from "@/lib/supabase/server";
import { NoGroupSelected } from "@/components/no-group-selected";
import Link from "next/link";
import { PaymentsClient } from "./payments-client";

export const dynamic = "force-dynamic";

export default async function PaymentsPage() {
  const groupId = cookies().get("portal_group_id")?.value;
  const role = cookies().get("portal_role")?.value;

  if (!groupId) return <NoGroupSelected />;

  if (role !== "admin_master") {
    return (
      <div className="space-y-6">
        <div>
          <h1 className="text-2xl font-bold text-content-primary">
            Configuração de Pagamentos
          </h1>
          <p className="mt-1 text-sm text-content-secondary">
            Acesso restrito a administradores.
          </p>
        </div>
        <div className="rounded-xl border border-border bg-surface p-6 shadow-sm">
          <p className="text-content-secondary">
            Apenas administradores podem configurar a integração com o Asaas.
          </p>
          <Link
            href="/settings"
            className="mt-4 inline-block text-sm text-brand hover:underline"
          >
            ← Voltar às Configurações
          </Link>
        </div>
      </div>
    );
  }

  const supabase = createClient();

  const { data: configRow } = await supabase
    .from("payment_provider_config")
    .select("id, environment, is_active, connected_at, webhook_id")
    .eq("group_id", groupId)
    .eq("provider", "asaas")
    .maybeSingle();

  const config = configRow
    ? {
        id: configRow.id,
        environment: configRow.environment,
        is_active: configRow.is_active ?? false,
        connected_at: configRow.connected_at,
        webhook_id: configRow.webhook_id,
      }
    : null;

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-content-primary">
            Configuração de Pagamentos
          </h1>
          <p className="mt-1 text-sm text-content-secondary">
            Conecte o Asaas para cobranças automáticas
          </p>
        </div>
        <Link
          href="/settings"
          className="text-sm text-content-secondary hover:text-brand"
        >
          ← Configurações
        </Link>
      </div>

      <PaymentsClient config={config} />
    </div>
  );
}
