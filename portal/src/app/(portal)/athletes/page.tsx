import { cookies } from "next/headers";
import { createServiceClient } from "@/lib/supabase/service";
import { DistributeButton } from "./distribute-button";

interface Athlete {
  user_id: string;
  display_name: string;
  joined_at_ms: number;
  verification_status: string;
  trust_score: number;
  total_sessions: number;
  total_distance_m: number;
  last_session_at: string | null;
}

const STATUS_LABELS: Record<string, { label: string; color: string }> = {
  VERIFIED: { label: "Verificado", color: "bg-green-100 text-green-800" },
  CALIBRATING: { label: "Calibrando", color: "bg-blue-100 text-blue-800" },
  MONITORED: { label: "Observação", color: "bg-yellow-100 text-yellow-800" },
  DOWNGRADED: { label: "Rebaixado", color: "bg-red-100 text-red-800" },
  UNVERIFIED: { label: "Sem status", color: "bg-gray-100 text-gray-600" },
};

function formatKm(meters: number): string {
  return (meters / 1000).toLocaleString("pt-BR", {
    minimumFractionDigits: 1,
    maximumFractionDigits: 1,
  });
}

function formatDate(iso: string | null): string {
  if (!iso) return "—";
  return new Date(iso).toLocaleDateString("pt-BR", {
    day: "2-digit",
    month: "short",
    year: "numeric",
  });
}

function formatJoinDate(ms: number): string {
  return new Date(ms).toLocaleDateString("pt-BR", {
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
  });
}

export default async function AthletesPage() {
  const groupId = cookies().get("portal_group_id")?.value;
  const role = cookies().get("portal_role")?.value;
  if (!groupId) return null;
  const isAdmin = role === "admin_master";

  const db = createServiceClient();

  const { data: members } = await db
    .from("coaching_members")
    .select("user_id, display_name, joined_at_ms")
    .eq("group_id", groupId)
    .eq("role", "atleta")
    .order("joined_at_ms", { ascending: false });

  const allMembers = members ?? [];
  const userIds = allMembers.map((m: { user_id: string }) => m.user_id);

  let verMap = new Map<string, { verification_status: string; trust_score: number }>();
  let sessionMap = new Map<string, { total: number; distance: number; last_at: string | null }>();

  if (userIds.length > 0) {
    const [verRes, sessionsRes] = await Promise.all([
      db
        .from("athlete_verification")
        .select("user_id, verification_status, trust_score")
        .in("user_id", userIds),
      db
        .from("sessions")
        .select("user_id, total_distance_m, start_time_ms")
        .in("user_id", userIds)
        .gte("status", 3),
    ]);

    for (const v of verRes.data ?? []) {
      const row = v as { user_id: string; verification_status: string; trust_score: number };
      verMap.set(row.user_id, { verification_status: row.verification_status, trust_score: row.trust_score });
    }

    for (const s of sessionsRes.data ?? []) {
      const row = s as { user_id: string; total_distance_m: number; start_time_ms: number };
      const existing = sessionMap.get(row.user_id);
      const startIso = new Date(row.start_time_ms).toISOString();
      if (existing) {
        existing.total++;
        existing.distance += row.total_distance_m ?? 0;
        if (!existing.last_at || startIso > existing.last_at) existing.last_at = startIso;
      } else {
        sessionMap.set(row.user_id, {
          total: 1,
          distance: row.total_distance_m ?? 0,
          last_at: startIso,
        });
      }
    }
  }

  const athletes: Athlete[] = allMembers.map((m: { user_id: string; display_name: string; joined_at_ms: number }) => {
    const ver = verMap.get(m.user_id);
    const sess = sessionMap.get(m.user_id);
    return {
      user_id: m.user_id,
      display_name: m.display_name || "Sem nome",
      joined_at_ms: m.joined_at_ms,
      verification_status: ver?.verification_status ?? "UNVERIFIED",
      trust_score: ver?.trust_score ?? 0,
      total_sessions: sess?.total ?? 0,
      total_distance_m: sess?.distance ?? 0,
      last_session_at: sess?.last_at ?? null,
    };
  });

  const activeCount = athletes.filter((a) => a.total_sessions > 0).length;
  const verifiedCount = athletes.filter((a) => a.verification_status === "VERIFIED").length;
  const totalKm = athletes.reduce((s, a) => s + a.total_distance_m, 0);

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Atletas</h1>
          <p className="mt-1 text-sm text-gray-500">
            Todos os atletas vinculados à assessoria
          </p>
        </div>
        {athletes.length > 0 && (
          <a
            href="/api/export/athletes"
            className="rounded-lg border border-gray-300 bg-white px-3 py-1.5 text-xs font-medium text-gray-700 shadow-sm hover:bg-gray-50"
          >
            Exportar CSV
          </a>
        )}
      </div>

      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <KpiCard label="Total" value={athletes.length} />
        <KpiCard label="Ativos (1+ corrida)" value={activeCount} color="text-blue-700" />
        <KpiCard label="Verificados" value={verifiedCount} color="text-green-700" />
        <KpiCard label="Km totais" value={formatKm(totalKm)} color="text-indigo-700" />
      </div>

      {athletes.length === 0 ? (
        <div className="rounded-xl border border-gray-200 bg-white p-8 text-center shadow-sm">
          <p className="text-sm text-gray-500">
            Nenhum atleta vinculado à assessoria.
          </p>
        </div>
      ) : (
        <div className="overflow-hidden rounded-xl border border-gray-200 bg-white shadow-sm">
          <div className="overflow-x-auto">
            <table className="min-w-full divide-y divide-gray-200 text-sm">
              <thead className="bg-gray-50">
                <tr>
                  <th className="px-4 py-3 text-left font-medium text-gray-500">
                    Atleta
                  </th>
                  <th className="px-4 py-3 text-left font-medium text-gray-500">
                    Status
                  </th>
                  <th className="px-4 py-3 text-center font-medium text-gray-500">
                    Trust
                  </th>
                  <th className="px-4 py-3 text-center font-medium text-gray-500">
                    Corridas
                  </th>
                  <th className="px-4 py-3 text-right font-medium text-gray-500">
                    Distância
                  </th>
                  <th className="px-4 py-3 text-left font-medium text-gray-500">
                    Última Corrida
                  </th>
                  <th className="px-4 py-3 text-left font-medium text-gray-500">
                    Membro Desde
                  </th>
                  {isAdmin && (
                    <th className="px-4 py-3 text-center font-medium text-gray-500">
                      OmniCoins
                    </th>
                  )}
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {athletes.map((a) => {
                  const s = STATUS_LABELS[a.verification_status] ?? STATUS_LABELS.UNVERIFIED;
                  return (
                    <tr key={a.user_id} className="hover:bg-gray-50">
                      <td className="whitespace-nowrap px-4 py-3">
                        <p className="font-medium text-gray-900">
                          {a.display_name}
                        </p>
                      </td>
                      <td className="whitespace-nowrap px-4 py-3">
                        <span
                          className={`inline-flex rounded-full px-2.5 py-0.5 text-xs font-medium ${s.color}`}
                        >
                          {s.label}
                        </span>
                      </td>
                      <td className="whitespace-nowrap px-4 py-3 text-center">
                        <span className="font-semibold text-gray-900">
                          {a.trust_score}
                        </span>
                        <span className="text-xs text-gray-400">/100</span>
                      </td>
                      <td className="whitespace-nowrap px-4 py-3 text-center text-gray-700">
                        {a.total_sessions}
                      </td>
                      <td className="whitespace-nowrap px-4 py-3 text-right text-gray-700">
                        {formatKm(a.total_distance_m)} km
                      </td>
                      <td className="whitespace-nowrap px-4 py-3 text-gray-500">
                        {formatDate(a.last_session_at)}
                      </td>
                      <td className="whitespace-nowrap px-4 py-3 text-gray-500">
                        {formatJoinDate(a.joined_at_ms)}
                      </td>
                      {isAdmin && (
                        <td className="whitespace-nowrap px-4 py-3 text-center">
                          <DistributeButton
                            athleteId={a.user_id}
                            athleteName={a.display_name}
                          />
                        </td>
                      )}
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

function KpiCard({
  label,
  value,
  color = "text-gray-900",
}: {
  label: string;
  value: number | string;
  color?: string;
}) {
  return (
    <div className="rounded-xl border border-gray-200 bg-white p-4 shadow-sm">
      <p className="text-xs font-medium uppercase tracking-wide text-gray-500">
        {label}
      </p>
      <p className={`mt-1 text-xl font-bold ${color}`}>{value}</p>
    </div>
  );
}
