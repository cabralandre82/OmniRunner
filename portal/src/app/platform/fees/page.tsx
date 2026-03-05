import { createAdminClient } from "@/lib/supabase/admin";
import { FeeRow } from "./fee-row";

export const dynamic = "force-dynamic";

const FEE_LABELS: Record<string, { label: string; description: string }> = {
  clearing: {
    label: "Clearing (Compensação Interclub)",
    description: "Aplicada quando coins de um emissor são queimadas em outro clube",
  },
  swap: {
    label: "Swap de Lastro",
    description: "Aplicada quando assessorias negociam lastro entre si",
  },
  maintenance: {
    label: "Manutenção",
    description: "Taxa mensal por assessoria ativa (opcional)",
  },
};

interface Fee {
  id: string;
  fee_type: string;
  rate_pct: number;
  is_active: boolean;
  updated_at: string;
}

export default async function FeesPage() {
  const supabase = createAdminClient();
  const { data: fees, error } = await supabase
    .from("platform_fee_config")
    .select("id, fee_type, rate_pct, is_active, updated_at")
    .order("fee_type");

  const hasFees = fees && fees.length > 0;

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-content-primary">Taxas da Plataforma</h1>
        <p className="mt-1 text-sm text-content-secondary">
          Configure as taxas aplicadas nas operações B2B
        </p>
      </div>

      {error && (
        <div className="rounded-lg border border-red-200 bg-red-50 p-4">
          <p className="text-sm font-medium text-red-800">
            Erro ao carregar taxas
          </p>
          <p className="mt-1 text-xs text-red-600">
            {error.message.includes("platform_fee_config")
              ? "A tabela de taxas ainda não foi criada. Execute a migração 20260305100000_platform_fee_config.sql no banco de dados."
              : error.message}
          </p>
        </div>
      )}

      {!error && !hasFees && (
        <div className="rounded-xl border border-border bg-surface p-8 text-center shadow-sm">
          <p className="text-sm font-medium text-content-primary">
            Nenhuma taxa configurada
          </p>
          <p className="mt-2 text-xs text-content-secondary">
            Execute a migração <code className="rounded bg-bg-secondary px-1.5 py-0.5 font-mono text-xs">20260305100000_platform_fee_config.sql</code> para
            criar as taxas padrão (Clearing 3%, Swap 1%, Manutenção 0%).
          </p>
        </div>
      )}

      {hasFees && (
        <div className="rounded-xl border border-border bg-surface shadow-sm">
          <table className="min-w-full divide-y divide-border">
            <thead className="bg-bg-secondary">
              <tr>
                <th className="px-6 py-3 text-left text-xs font-medium uppercase text-content-secondary">
                  Tipo
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium uppercase text-content-secondary">
                  Taxa (%)
                </th>
                <th className="px-6 py-3 text-center text-xs font-medium uppercase text-content-secondary">
                  Ativa
                </th>
                <th className="px-6 py-3 text-right text-xs font-medium uppercase text-content-secondary">
                  Ação
                </th>
              </tr>
            </thead>
            <tbody className="divide-y divide-border">
              {fees.map((fee: Fee) => {
                const info = FEE_LABELS[fee.fee_type] ?? {
                  label: fee.fee_type,
                  description: "",
                };
                return (
                  <FeeRow
                    key={fee.id}
                    fee={fee}
                    label={info.label}
                    description={info.description}
                  />
                );
              })}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
