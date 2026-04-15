import { cookies } from "next/headers";
import { createClient } from "@/lib/supabase/server";
import { createServiceClient } from "@/lib/supabase/service";
import { NoGroupSelected } from "@/components/no-group-selected";
import { InfoTooltip } from "@/components/ui/info-tooltip";
import { logger } from "@/lib/logger";

export const dynamic = "force-dynamic";

interface LedgerEntry {
  id: string;
  user_id: string;
  delta_coins: number;
  ref_id: string | null;
  created_at: string;
}

interface Profile {
  id: string;
  display_name: string;
}

export default async function DistributionsPage() {
  const groupId = cookies().get("portal_group_id")?.value;
  if (!groupId) return <NoGroupSelected />;

  const db = createClient();
  // Use service client for coin_ledger: the table's RLS only lets users see
  // their own rows, so a coach querying their athletes' entries would get 0.
  const svc = createServiceClient();

  // Get group members to scope distributions to this assessoria
  const [membersRes, inventoryRes] = await Promise.all([
    db
      .from("coaching_members")
      .select("user_id")
      .eq("group_id", groupId),
    db
      .from("coaching_token_inventory")
      .select("available_tokens")
      .eq("group_id", groupId)
      .maybeSingle(),
  ]);

  const balance = inventoryRes.data?.available_tokens ?? 0;

  let entries: LedgerEntry[] = [];

  // Query by issuer_group_id (correct for modern entries) and fall back to
  // user_id-based query for legacy entries without issuer_group_id.
  const { data: byIssuer, error: issuerErr } = await svc
    .from("coin_ledger")
    .select("id, user_id, delta_coins, ref_id, created_at")
    .eq("issuer_group_id", groupId)
    .eq("reason", "institution_token_issue")
    .order("created_at", { ascending: false })
    .limit(200);

  if (issuerErr) {
    logger.error("coin_ledger issuer query failed", issuerErr, { page: "distributions" });
  }

  const memberIds = (membersRes.data ?? []).map((m: { user_id: string }) => m.user_id);

  if (memberIds.length > 0) {
    // Legacy entries (no issuer_group_id) — collect user_id-based records not already found
    const foundIds = new Set((byIssuer ?? []).map((e) => e.id));
    const { data: byMember, error: memberErr } = await svc
      .from("coin_ledger")
      .select("id, user_id, delta_coins, ref_id, created_at")
      .in("user_id", memberIds)
      .eq("reason", "institution_token_issue")
      .is("issuer_group_id", null)
      .order("created_at", { ascending: false })
      .limit(200);

    if (memberErr) {
      logger.error("coin_ledger member query failed", memberErr, { page: "distributions" });
    }

    const legacy = (byMember ?? []).filter((e) => !foundIds.has(e.id));
    entries = [...(byIssuer ?? []), ...legacy].sort(
      (a, b) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime(),
    ).slice(0, 200) as LedgerEntry[];
  } else {
    entries = (byIssuer ?? []) as LedgerEntry[];
  }

  // Resolve display names for athletes and actors
  const athleteIds = Array.from(new Set(entries.map((e) => e.user_id)));
  const actorIds = Array.from(
    new Set(
      entries
        .map((e) => {
          // ref_id format: portal_{actorId}_{timestamp}
          const parts = e.ref_id?.split("_") ?? [];
          return parts.length >= 2 ? parts[1] : null;
        })
        .filter(Boolean) as string[],
    ),
  );

  const allProfileIds = Array.from(new Set([...athleteIds, ...actorIds]));
  let profileMap = new Map<string, string>();
  if (allProfileIds.length > 0) {
    const { data: profiles } = await db
      .from("profiles")
      .select("id, display_name")
      .in("id", allProfileIds);
    profileMap = new Map(
      ((profiles ?? []) as Profile[]).map((p) => [p.id, p.display_name]),
    );
  }

  const totalDistributed = entries.reduce((sum, e) => sum + e.delta_coins, 0);
  const uniqueAthletes = new Set(entries.map((e) => e.user_id)).size;

  const last30d = entries.filter((e) => {
    const d = new Date(e.created_at);
    return d.getTime() > Date.now() - 30 * 86400000;
  });
  const distributed30d = last30d.reduce((sum, e) => sum + e.delta_coins, 0);

  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-2xl font-bold text-content-primary">
          <InfoTooltip text="Distribuir OmniCoins significa transferir créditos do estoque da sua assessoria para os atletas. Eles podem usar esses créditos para pagar treinos, participar de desafios e acessar funcionalidades premium.">
            Distribuição de OmniCoins
          </InfoTooltip>
        </h1>
        <p className="mt-1 text-sm text-content-secondary">
          Histórico completo de distribuições para atletas
        </p>
      </div>

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <KPI label="Saldo Disponível" value={balance.toLocaleString("pt-BR")} sub="OmniCoins em estoque" />
        <KPI label="Total Distribuído" value={totalDistributed.toLocaleString("pt-BR")} sub="Desde o início" />
        <KPI label="Distribuído (30d)" value={distributed30d.toLocaleString("pt-BR")} sub="Últimos 30 dias" />
        <KPI label="Atletas Contemplados" value={uniqueAthletes.toString()} sub="Únicos" />
      </div>

      {entries.length === 0 ? (
        <div className="rounded-xl border border-border bg-surface p-8 text-center text-sm text-content-secondary">
          Nenhuma distribuição realizada ainda.
          <br />
          Distribua OmniCoins pela página de <a href="/athletes" className="text-brand hover:underline">Atletas</a>.
        </div>
      ) : (
        <div className="rounded-xl border border-border bg-surface shadow-sm overflow-hidden">
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b bg-bg-secondary text-left text-xs font-medium uppercase tracking-wide text-content-secondary">
                  <th className="px-4 py-3">Data</th>
                  <th className="px-4 py-3">Atleta</th>
                  <th className="px-4 py-3 text-right">Quantidade</th>
                  <th className="px-4 py-3">Distribuído por</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-border-subtle">
                {entries.map((entry) => {
                  const date = new Date(entry.created_at);
                  const athleteName = profileMap.get(entry.user_id) ?? "Atleta";
                  const actorId = entry.ref_id?.split("_")[1] ?? null;
                  const actorName = actorId ? (profileMap.get(actorId) ?? "Staff") : "—";

                  return (
                    <tr key={entry.id} className="hover:bg-surface-elevated">
                      <td className="whitespace-nowrap px-4 py-3 text-content-secondary">
                        {date.toLocaleDateString("pt-BR", {
                          day: "2-digit",
                          month: "2-digit",
                          year: "numeric",
                        })}{" "}
                        <span className="text-content-muted">
                          {date.toLocaleTimeString("pt-BR", {
                            hour: "2-digit",
                            minute: "2-digit",
                          })}
                        </span>
                      </td>
                      <td className="px-4 py-3 font-medium text-content-primary">
                        {athleteName}
                      </td>
                      <td className="whitespace-nowrap px-4 py-3 text-right font-semibold text-emerald-600">
                        +{entry.delta_coins.toLocaleString("pt-BR")}
                      </td>
                      <td className="px-4 py-3 text-content-secondary">{actorName}</td>
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
    <div className="rounded-xl border border-border bg-surface p-5 shadow-sm">
      <p className="text-xs font-medium uppercase tracking-wide text-content-secondary">{label}</p>
      <p className="mt-2 text-2xl font-bold text-content-primary">{value}</p>
      <p className="mt-1 text-xs text-content-muted">{sub}</p>
    </div>
  );
}
