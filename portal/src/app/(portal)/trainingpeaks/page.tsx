import { createClient } from "@/lib/supabase/server";
import { cookies } from "next/headers";
import { isFeatureEnabled } from "@/lib/feature-flags";

export const dynamic = "force-dynamic";

export default async function TrainingPeaksPage() {
  const tpEnabled = await isFeatureEnabled("trainingpeaks_enabled");
  if (!tpEnabled) {
    return (
      <div className="flex items-center justify-center min-h-[50vh]">
        <div className="rounded-xl border border-border p-8 text-center max-w-md">
          <h2 className="text-lg font-semibold text-content-primary">Funcionalidade indisponível</h2>
          <p className="mt-2 text-sm text-content-secondary">
            A integração com TrainingPeaks não está habilitada para este grupo.
          </p>
        </div>
      </div>
    );
  }

  const supabase = createClient();
  const cookieStore = await cookies();
  const groupId = cookieStore.get("portal_group_id")?.value;

  if (!groupId) {
    return (
      <div className="p-6">
        <p className="text-content-secondary">Selecione um grupo primeiro.</p>
      </div>
    );
  }

  // Get sync status
  const { data: syncResult } = await supabase.rpc("fn_tp_sync_status", {
    p_group_id: groupId,
  });

  const syncs: any[] =
    syncResult != null &&
    typeof syncResult === "object" &&
    "ok" in syncResult &&
    syncResult.ok === true &&
    Array.isArray(syncResult.data)
      ? syncResult.data
      : [];

  // Get linked athletes
  const { data: links } = await supabase
    .from("coaching_device_links")
    .select("athlete_user_id, provider_user_id, linked_at, expires_at")
    .eq("group_id", groupId)
    .eq("provider", "trainingpeaks");

  const statusColor = (status: string) => {
    switch (status) {
      case "pushed": return "bg-success-soft text-success";
      case "pending": return "bg-warning-soft text-warning";
      case "completed": return "bg-info-soft text-info";
      case "failed": return "bg-error-soft text-error";
      default: return "bg-surface-elevated text-content-primary";
    }
  };

  return (
    <div className="space-y-8 p-6">
      <div>
        <h1 className="text-2xl font-bold text-content-primary">TrainingPeaks</h1>
        <p className="mt-1 text-sm text-content-secondary">
          Sincronização de treinos com TrainingPeaks
        </p>
      </div>

      {/* Linked Athletes */}
      <section>
        <h2 className="text-lg font-semibold text-content-primary mb-4">
          Atletas Vinculados ({links?.length ?? 0})
        </h2>
        {!links?.length ? (
          <div className="rounded-xl border border-dashed border-border p-8 text-center">
            <p className="text-content-secondary">Nenhum atleta vinculou TrainingPeaks ainda.</p>
            <p className="mt-2 text-sm text-content-muted">
              Os atletas podem vincular pelo aplicativo em Configurações → Dispositivos.
            </p>
          </div>
        ) : (
          <div className="overflow-x-auto rounded-xl border">
            <table className="min-w-full divide-y divide-border">
              <thead className="bg-bg-secondary">
                <tr>
                  <th className="px-4 py-3 text-left text-xs font-medium text-content-secondary uppercase">Atleta</th>
                  <th className="px-4 py-3 text-left text-xs font-medium text-content-secondary uppercase">TP User ID</th>
                  <th className="px-4 py-3 text-left text-xs font-medium text-content-secondary uppercase">Vinculado em</th>
                  <th className="px-4 py-3 text-left text-xs font-medium text-content-secondary uppercase">Token Expira</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-border bg-surface">
                {links.map((link: any, i: number) => (
                  <tr key={i}>
                    <td className="px-4 py-3 text-sm">{link.athlete_user_id?.slice(0, 8)}...</td>
                    <td className="px-4 py-3 text-sm text-content-secondary">{link.provider_user_id ?? "—"}</td>
                    <td className="px-4 py-3 text-sm text-content-secondary">
                      {new Date(link.linked_at).toLocaleDateString("pt-BR")}
                    </td>
                    <td className="px-4 py-3 text-sm text-content-secondary">
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
        <h2 className="text-lg font-semibold text-content-primary mb-4">
          Status de Sincronização ({syncs.length})
        </h2>
        {!syncs.length ? (
          <div className="rounded-xl border border-dashed border-border p-8 text-center">
            <p className="text-content-secondary">Nenhum treino sincronizado ainda.</p>
          </div>
        ) : (
          <div className="overflow-x-auto rounded-xl border">
            <table className="min-w-full divide-y divide-border">
              <thead className="bg-bg-secondary">
                <tr>
                  <th className="px-4 py-3 text-left text-xs font-medium text-content-secondary uppercase">Assignment</th>
                  <th className="px-4 py-3 text-left text-xs font-medium text-content-secondary uppercase">Atleta</th>
                  <th className="px-4 py-3 text-left text-xs font-medium text-content-secondary uppercase">Status</th>
                  <th className="px-4 py-3 text-left text-xs font-medium text-content-secondary uppercase">Enviado em</th>
                  <th className="px-4 py-3 text-left text-xs font-medium text-content-secondary uppercase">Erro</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-border bg-surface">
                {syncs.map((s: any) => (
                  <tr key={s.sync_id}>
                    <td className="px-4 py-3 text-sm font-mono">{s.assignment_id?.slice(0, 8)}...</td>
                    <td className="px-4 py-3 text-sm">{s.athlete_user_id?.slice(0, 8)}...</td>
                    <td className="px-4 py-3">
                      <span className={`inline-flex rounded-full px-2 py-1 text-xs font-medium ${statusColor(s.sync_status)}`}>
                        {s.sync_status}
                      </span>
                    </td>
                    <td className="px-4 py-3 text-sm text-content-secondary">
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
