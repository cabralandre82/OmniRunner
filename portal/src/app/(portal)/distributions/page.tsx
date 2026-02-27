import { cookies } from "next/headers";
import { createServiceClient } from "@/lib/supabase/service";

interface Distribution {
  id: string;
  created_at: string;
  metadata: { amount?: number; athlete_name?: string };
  target_id: string | null;
  actor_id: string;
}

interface ActorProfile {
  id: string;
  display_name: string;
}

export default async function DistributionsPage() {
  const groupId = cookies().get("portal_group_id")?.value;
  if (!groupId) return null;

  const db = createServiceClient();

  const [logsRes, inventoryRes] = await Promise.all([
    db
      .from("portal_audit_log")
      .select("id, created_at, metadata, target_id, actor_id")
      .eq("group_id", groupId)
      .eq("action", "coins.distribute")
      .order("created_at", { ascending: false })
      .limit(200),
    db
      .from("coaching_token_inventory")
      .select("available_tokens")
      .eq("group_id", groupId)
      .maybeSingle(),
  ]);

  const logs: Distribution[] = (logsRes.data ?? []) as Distribution[];
  const balance = inventoryRes.data?.available_tokens ?? 0;

  const actorIds = Array.from(new Set(logs.map((l) => l.actor_id)));
  let actorMap = new Map<string, string>();
  if (actorIds.length > 0) {
    const { data: profiles } = await db
      .from("profiles")
      .select("id, display_name")
      .in("id", actorIds);
    actorMap = new Map(
      ((profiles ?? []) as ActorProfile[]).map((p) => [p.id, p.display_name]),
    );
  }

  const totalDistributed = logs.reduce(
    (sum, l) => sum + ((l.metadata?.amount as number) ?? 0),
    0,
  );
  const uniqueAthletes = new Set(logs.map((l) => l.target_id)).size;

  const last30d = logs.filter((l) => {
    const d = new Date(l.created_at);
    return d.getTime() > Date.now() - 30 * 86400000;
  });
  const distributed30d = last30d.reduce(
    (sum, l) => sum + ((l.metadata?.amount as number) ?? 0),
    0,
  );

  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-2xl font-bold text-gray-900">Distribuição de OmniCoins</h1>
        <p className="mt-1 text-sm text-gray-500">
          Histórico completo de distribuições para atletas
        </p>
      </div>

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <KPI label="Saldo Disponível" value={balance.toLocaleString("pt-BR")} sub="OmniCoins em estoque" />
        <KPI label="Total Distribuído" value={totalDistributed.toLocaleString("pt-BR")} sub="Desde o início" />
        <KPI label="Distribuído (30d)" value={distributed30d.toLocaleString("pt-BR")} sub="Últimos 30 dias" />
        <KPI label="Atletas Contemplados" value={uniqueAthletes.toString()} sub="Únicos" />
      </div>

      {logs.length === 0 ? (
        <div className="rounded-xl border border-gray-200 bg-white p-8 text-center text-sm text-gray-500">
          Nenhuma distribuição realizada ainda.
          <br />
          Distribua OmniCoins pela página de <a href="/athletes" className="text-blue-600 hover:underline">Atletas</a>.
        </div>
      ) : (
        <div className="rounded-xl border border-gray-200 bg-white shadow-sm overflow-hidden">
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b bg-gray-50 text-left text-xs font-medium uppercase tracking-wide text-gray-500">
                  <th className="px-4 py-3">Data</th>
                  <th className="px-4 py-3">Atleta</th>
                  <th className="px-4 py-3 text-right">Quantidade</th>
                  <th className="px-4 py-3">Distribuído por</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {logs.map((log) => {
                  const date = new Date(log.created_at);
                  const athleteName =
                    (log.metadata?.athlete_name as string) ?? "—";
                  const amount = (log.metadata?.amount as number) ?? 0;
                  const actorName = actorMap.get(log.actor_id) ?? "—";

                  return (
                    <tr key={log.id} className="hover:bg-gray-50">
                      <td className="whitespace-nowrap px-4 py-3 text-gray-700">
                        {date.toLocaleDateString("pt-BR", {
                          day: "2-digit",
                          month: "2-digit",
                          year: "numeric",
                        })}{" "}
                        <span className="text-gray-400">
                          {date.toLocaleTimeString("pt-BR", {
                            hour: "2-digit",
                            minute: "2-digit",
                          })}
                        </span>
                      </td>
                      <td className="px-4 py-3 font-medium text-gray-900">
                        {athleteName}
                      </td>
                      <td className="whitespace-nowrap px-4 py-3 text-right font-semibold text-emerald-600">
                        +{amount.toLocaleString("pt-BR")}
                      </td>
                      <td className="px-4 py-3 text-gray-500">{actorName}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </div>
  );
}

function KPI({ label, value, sub }: { label: string; value: string; sub: string }) {
  return (
    <div className="rounded-xl border border-gray-200 bg-white p-5 shadow-sm">
      <p className="text-xs font-medium uppercase tracking-wide text-gray-500">{label}</p>
      <p className="mt-2 text-2xl font-bold text-gray-900">{value}</p>
      <p className="mt-1 text-xs text-gray-400">{sub}</p>
    </div>
  );
}
