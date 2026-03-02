import { createServiceClient } from "@/lib/supabase/service";
import type { Metadata } from "next";

export const metadata: Metadata = { title: "Invariantes do Sistema" };

interface Violation {
  group_id: string;
  total_deposited: number;
  total_committed: number;
  computed_available: number;
  violation: string;
}

interface AccountSummary {
  group_id: string;
  total_deposited_usd: number;
  total_committed: number;
  total_settled_usd: number;
  is_blocked: boolean;
}

const violationLabels: Record<string, string> = {
  committed_negative: "Committed negativo",
  deposited_negative: "Depositado negativo",
  deposited_less_than_committed: "Depositado < Committed (A < 0)",
};

export default async function InvariantsPage() {
  const db = createServiceClient();

  const { data: violations } = await db.rpc("check_custody_invariants");
  const vList: Violation[] = violations ?? [];
  const healthy = vList.length === 0;

  const { data: accounts } = await db
    .from("custody_accounts")
    .select("group_id, total_deposited_usd, total_committed, total_settled_usd, is_blocked")
    .order("total_deposited_usd", { ascending: false })
    .limit(50);

  const accts: AccountSummary[] = accounts ?? [];

  const globalD = accts.reduce((s, a) => s + a.total_deposited_usd, 0);
  const globalR = accts.reduce((s, a) => s + a.total_committed, 0);
  const globalA = globalD - globalR;
  const globalSettled = accts.reduce((s, a) => s + a.total_settled_usd, 0);

  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-2xl font-bold text-gray-900">
          Invariantes do Sistema
        </h1>
        <p className="mt-1 text-sm text-gray-500">
          Verificação em tempo real das invariantes contábeis de custódia.
        </p>
      </div>

      <div
        className={`rounded-xl border-2 p-6 ${
          healthy
            ? "border-green-200 bg-green-50"
            : "border-red-300 bg-red-50"
        }`}
      >
        <div className="flex items-center gap-3">
          <span className="text-3xl">{healthy ? "✓" : "✗"}</span>
          <div>
            <h2
              className={`text-lg font-bold ${
                healthy ? "text-green-800" : "text-red-800"
              }`}
            >
              {healthy ? "Sistema Saudável" : "Violações Detectadas"}
            </h2>
            <p
              className={`text-sm ${
                healthy ? "text-green-600" : "text-red-600"
              }`}
            >
              {healthy
                ? "Todas as invariantes contábeis estão íntegras."
                : `${vList.length} violação(ões) encontrada(s).`}
            </p>
          </div>
        </div>
      </div>

      {!healthy && (
        <div className="rounded-xl border border-red-200 bg-white overflow-hidden">
          <table className="min-w-full text-sm">
            <thead className="bg-red-50">
              <tr>
                <th className="px-4 py-3 text-left font-semibold text-red-800">
                  Grupo
                </th>
                <th className="px-4 py-3 text-right font-semibold text-red-800">
                  D (Depositado)
                </th>
                <th className="px-4 py-3 text-right font-semibold text-red-800">
                  R (Committed)
                </th>
                <th className="px-4 py-3 text-right font-semibold text-red-800">
                  A (Disponível)
                </th>
                <th className="px-4 py-3 text-left font-semibold text-red-800">
                  Violação
                </th>
              </tr>
            </thead>
            <tbody className="divide-y divide-red-100">
              {vList.map((v) => (
                <tr key={v.group_id}>
                  <td className="px-4 py-2 font-mono text-xs">
                    {v.group_id.slice(0, 8)}...
                  </td>
                  <td className="px-4 py-2 text-right tabular-nums">
                    ${v.total_deposited.toFixed(2)}
                  </td>
                  <td className="px-4 py-2 text-right tabular-nums">
                    ${v.total_committed.toFixed(2)}
                  </td>
                  <td className="px-4 py-2 text-right tabular-nums text-red-600">
                    ${v.computed_available.toFixed(2)}
                  </td>
                  <td className="px-4 py-2 text-red-700 font-medium">
                    {violationLabels[v.violation] ?? v.violation}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      <div className="grid gap-4 sm:grid-cols-4">
        <KPI label="D Global (Custódia)" value={globalD} />
        <KPI label="R Global (Reservado)" value={globalR} />
        <KPI label="A Global (Disponível)" value={globalA} />
        <KPI label="Total Liquidado" value={globalSettled} />
      </div>

      <div className="rounded-xl border border-gray-200 bg-white overflow-hidden">
        <div className="px-4 py-3 border-b border-gray-100">
          <h3 className="font-semibold text-gray-900">
            Contas de Custódia ({accts.length})
          </h3>
        </div>
        <table className="min-w-full text-sm">
          <thead className="bg-gray-50">
            <tr>
              <th className="px-4 py-2 text-left font-medium text-gray-600">
                Grupo
              </th>
              <th className="px-4 py-2 text-right font-medium text-gray-600">
                D
              </th>
              <th className="px-4 py-2 text-right font-medium text-gray-600">
                R
              </th>
              <th className="px-4 py-2 text-right font-medium text-gray-600">
                A
              </th>
              <th className="px-4 py-2 text-right font-medium text-gray-600">
                Liquidado
              </th>
              <th className="px-4 py-2 text-center font-medium text-gray-600">
                Status
              </th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-100">
            {accts.map((a) => {
              const avail = a.total_deposited_usd - a.total_committed;
              return (
                <tr key={a.group_id} className="hover:bg-gray-50">
                  <td className="px-4 py-2 font-mono text-xs">
                    {a.group_id.slice(0, 8)}...
                  </td>
                  <td className="px-4 py-2 text-right tabular-nums">
                    ${a.total_deposited_usd.toFixed(2)}
                  </td>
                  <td className="px-4 py-2 text-right tabular-nums">
                    ${a.total_committed.toFixed(2)}
                  </td>
                  <td
                    className={`px-4 py-2 text-right tabular-nums ${
                      avail < 0 ? "text-red-600 font-bold" : ""
                    }`}
                  >
                    ${avail.toFixed(2)}
                  </td>
                  <td className="px-4 py-2 text-right tabular-nums text-gray-500">
                    ${a.total_settled_usd.toFixed(2)}
                  </td>
                  <td className="px-4 py-2 text-center">
                    {a.is_blocked ? (
                      <span className="inline-flex items-center rounded-full bg-red-100 px-2 py-0.5 text-xs font-medium text-red-700">
                        Bloqueado
                      </span>
                    ) : (
                      <span className="inline-flex items-center rounded-full bg-green-100 px-2 py-0.5 text-xs font-medium text-green-700">
                        Ativo
                      </span>
                    )}
                  </td>
                </tr>
              );
            })}
            {accts.length === 0 && (
              <tr>
                <td colSpan={6} className="px-4 py-8 text-center text-gray-400">
                  Nenhuma conta de custódia encontrada.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>

      <div className="rounded-lg bg-gray-50 border border-gray-200 p-4 text-xs text-gray-500 space-y-1">
        <p>
          <strong>Invariantes verificadas:</strong> D &ge; 0, R &ge; 0, D &ge;
          R (para cada clube)
        </p>
        <p>
          <strong>Modelo:</strong> D = R + A | R = coins em circulac&#807;a&#771;o
          | A = lastro dispon&#237;vel para emissa&#771;o
        </p>
        <p>
          <strong>Saudavel:</strong> 0 violac&#807;o&#771;es = sistema
          matematicamente fechado
        </p>
      </div>
    </div>
  );
}

function KPI({ label, value }: { label: string; value: number }) {
  return (
    <div className="rounded-xl border border-gray-200 bg-white p-4">
      <p className="text-xs font-medium text-gray-500">{label}</p>
      <p className="mt-1 text-xl font-bold tabular-nums text-gray-900">
        ${value.toFixed(2)}
      </p>
    </div>
  );
}
