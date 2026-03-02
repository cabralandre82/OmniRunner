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
  const { data: fees } = await supabase
    .from("platform_fee_config")
    .select("*")
    .order("fee_type");

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-gray-900">Taxas da Plataforma</h1>
        <p className="mt-1 text-sm text-gray-500">
          Configure as taxas aplicadas nas operações B2B
        </p>
      </div>

      <div className="rounded-xl border border-gray-200 bg-white shadow-sm">
        <table className="min-w-full divide-y divide-gray-200">
          <thead className="bg-gray-50">
            <tr>
              <th className="px-6 py-3 text-left text-xs font-medium uppercase text-gray-500">
                Tipo
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium uppercase text-gray-500">
                Taxa (%)
              </th>
              <th className="px-6 py-3 text-center text-xs font-medium uppercase text-gray-500">
                Ativa
              </th>
              <th className="px-6 py-3 text-right text-xs font-medium uppercase text-gray-500">
                Ação
              </th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-200">
            {(fees ?? []).map((fee: Fee) => {
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
    </div>
  );
}
