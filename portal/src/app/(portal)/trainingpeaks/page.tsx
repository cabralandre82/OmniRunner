import { createClient } from "@/lib/supabase/server";
import { cookies } from "next/headers";

export const dynamic = "force-dynamic";

export default async function TrainingPeaksPage() {
  const supabase = createClient();
  const cookieStore = await cookies();
  const groupId = cookieStore.get("group_id")?.value;

  if (!groupId) {
    return (
      <div className="p-6">
        <p className="text-gray-500">Selecione um grupo primeiro.</p>
      </div>
    );
  }

  // Get sync status
  const { data: syncResult } = await supabase.rpc("fn_tp_sync_status", {
    p_group_id: groupId,
  });

  const syncs = syncResult?.ok ? (syncResult.data ?? []) : [];

  // Get linked athletes
  const { data: links } = await supabase
    .from("coaching_device_links")
    .select("athlete_user_id, provider_user_id, linked_at, expires_at")
    .eq("group_id", groupId)
    .eq("provider", "trainingpeaks");

  const statusColor = (status: string) => {
    switch (status) {
      case "pushed": return "bg-green-100 text-green-800";
      case "pending": return "bg-yellow-100 text-yellow-800";
      case "completed": return "bg-blue-100 text-blue-800";
      case "failed": return "bg-red-100 text-red-800";
      default: return "bg-gray-100 text-gray-800";
    }
  };

  return (
    <div className="space-y-8 p-6">
      <div>
        <h1 className="text-2xl font-bold text-gray-900">TrainingPeaks</h1>
        <p className="mt-1 text-sm text-gray-500">
          Sincronização de treinos com TrainingPeaks
        </p>
      </div>

      {/* Linked Athletes */}
      <section>
        <h2 className="text-lg font-semibold text-gray-900 mb-4">
          Atletas Vinculados ({links?.length ?? 0})
        </h2>
        {!links?.length ? (
          <div className="rounded-xl border border-dashed border-gray-300 p-8 text-center">
            <p className="text-gray-500">Nenhum atleta vinculou TrainingPeaks ainda.</p>
            <p className="mt-2 text-sm text-gray-400">
              Os atletas podem vincular pelo aplicativo em Configurações → Dispositivos.
            </p>
          </div>
        ) : (
          <div className="overflow-x-auto rounded-xl border">
            <table className="min-w-full divide-y divide-gray-200">
              <thead className="bg-gray-50">
                <tr>
                  <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Atleta</th>
                  <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">TP User ID</th>
                  <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Vinculado em</th>
                  <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Token Expira</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-200 bg-white">
                {links.map((link: any, i: number) => (
                  <tr key={i}>
                    <td className="px-4 py-3 text-sm">{link.athlete_user_id?.slice(0, 8)}...</td>
                    <td className="px-4 py-3 text-sm text-gray-500">{link.provider_user_id ?? "—"}</td>
                    <td className="px-4 py-3 text-sm text-gray-500">
                      {new Date(link.linked_at).toLocaleDateString("pt-BR")}
                    </td>
                    <td className="px-4 py-3 text-sm text-gray-500">
                      {link.expires_at
                        ? new Date(link.expires_at).toLocaleDateString("pt-BR")
                        : "—"}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      {/* Sync Status */}
      <section>
        <h2 className="text-lg font-semibold text-gray-900 mb-4">
          Status de Sincronização ({syncs.length})
        </h2>
        {!syncs.length ? (
          <div className="rounded-xl border border-dashed border-gray-300 p-8 text-center">
            <p className="text-gray-500">Nenhum treino sincronizado ainda.</p>
          </div>
        ) : (
          <div className="overflow-x-auto rounded-xl border">
            <table className="min-w-full divide-y divide-gray-200">
              <thead className="bg-gray-50">
                <tr>
                  <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Assignment</th>
                  <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Atleta</th>
                  <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Status</th>
                  <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Enviado em</th>
                  <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Erro</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-200 bg-white">
                {syncs.map((s: any) => (
                  <tr key={s.sync_id}>
                    <td className="px-4 py-3 text-sm font-mono">{s.assignment_id?.slice(0, 8)}...</td>
                    <td className="px-4 py-3 text-sm">{s.athlete_user_id?.slice(0, 8)}...</td>
                    <td className="px-4 py-3">
                      <span className={`inline-flex rounded-full px-2 py-1 text-xs font-medium ${statusColor(s.sync_status)}`}>
                        {s.sync_status}
                      </span>
                    </td>
                    <td className="px-4 py-3 text-sm text-gray-500">
                      {s.pushed_at ? new Date(s.pushed_at).toLocaleString("pt-BR") : "—"}
                    </td>
                    <td className="px-4 py-3 text-sm text-red-500">{s.error_message ?? "—"}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>
    </div>
  );
}
