import { cookies } from "next/headers";
import { createClient } from "@/lib/supabase/server";
import { NoGroupSelected } from "@/components/no-group-selected";
import { formatDateISO } from "@/lib/format";
import { StatBlock, StatusBadge } from "@/components/ui";
import {
  CreateBatchForm,
  GenerateItemsButton,
  PublishButton,
  CopyPayloadButton,
} from "./delivery-actions";

export const dynamic = "force-dynamic";

const STATUS_CONFIG: Record<string, { label: string; variant: "neutral" | "info" | "success" | "warning" | "error" }> = {
  pending: { label: "Pendente", variant: "warning" },
  published: { label: "Publicado", variant: "info" },
  confirmed: { label: "Confirmado", variant: "success" },
  failed: { label: "Falha", variant: "error" },
};

const BATCH_STATUS_LABELS: Record<string, string> = {
  draft: "Rascunho",
  publishing: "Publicando",
  published: "Publicado",
  closed: "Fechado",
};

interface DeliveryItem {
  id: string;
  batch_id: string;
  athlete_user_id: string;
  assignment_id: string | null;
  export_payload: Record<string, unknown>;
  status: string;
  published_at: string | null;
  confirmed_at: string | null;
  athlete_name: string;
  template_name: string;
}

interface DeliveryBatch {
  id: string;
  period_start: string | null;
  period_end: string | null;
  status: string;
  created_at: string;
}

export default async function DeliveryPage() {
  const groupId = cookies().get("portal_group_id")?.value;
  const role = cookies().get("portal_role")?.value;
  if (!groupId) return <NoGroupSelected />;

  const supabase = createClient();
  let fetchError: string | null = null;
  let batches: DeliveryBatch[] = [];
  let items: DeliveryItem[] = [];
  let statusCounts = { total: 0, pending: 0, published: 0, confirmed: 0, failed: 0 };

  try {
    const [batchesRes, itemsRes] = await Promise.all([
      supabase
        .from("workout_delivery_batches")
        .select("id, period_start, period_end, status, created_at")
        .eq("group_id", groupId)
        .order("created_at", { ascending: false })
        .limit(20),
      supabase
        .from("workout_delivery_items")
        .select("id, batch_id, athlete_user_id, assignment_id, export_payload, status, published_at, confirmed_at")
        .eq("group_id", groupId)
        .order("created_at", { ascending: false })
        .limit(200),
    ]);

    batches = (batchesRes.data ?? []) as DeliveryBatch[];
    const rawItems = (itemsRes.data ?? []) as Array<Omit<DeliveryItem, "athlete_name" | "template_name">>;

    for (const it of rawItems) {
      const s = it.status as keyof typeof statusCounts;
      statusCounts.total++;
      if (s in statusCounts) (statusCounts as Record<string, number>)[s]++;
    }

    const athleteIds = Array.from(new Set(rawItems.map((i) => i.athlete_user_id)));
    const profileMap = new Map<string, string>();
    if (athleteIds.length > 0) {
      const { data: profiles } = await supabase
        .from("profiles")
        .select("id, display_name")
        .in("id", athleteIds);
      for (const p of profiles ?? []) {
        profileMap.set(p.id, p.display_name || "Sem nome");
      }
    }

    items = rawItems.map((i) => ({
      ...i,
      athlete_name: profileMap.get(i.athlete_user_id) ?? "Sem nome",
      template_name:
        (i.export_payload as Record<string, unknown>)?.template_name as string ?? "—",
    }));
  } catch (e) {
    fetchError = String(e);
  }

  const isCoachOrAdmin = role === "admin_master" || role === "coach";

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-content-primary">Entrega de Treinos</h1>
        <p className="mt-1 text-sm text-content-secondary">
          Geração e publicação de treinos para atletas via Treinus
        </p>
      </div>

      {fetchError && (
        <div className="rounded-lg border border-error/30 bg-error-soft p-6 text-center">
          <p className="text-error">Erro ao carregar dados. Tente recarregar a página.</p>
        </div>
      )}

      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-5">
        <StatBlock label="Total itens" value={statusCounts.total} />
        <StatBlock label="Pendentes" value={statusCounts.pending} accentClass="text-warning" />
        <StatBlock label="Publicados" value={statusCounts.published} accentClass="text-info" />
        <StatBlock label="Confirmados" value={statusCounts.confirmed} accentClass="text-success" />
        <StatBlock label="Falha" value={statusCounts.failed} accentClass="text-error" alert={statusCounts.failed > 0} />
      </div>

      {isCoachOrAdmin && (
        <div className="rounded-xl border border-border bg-surface p-5 shadow-sm">
          <h2 className="text-sm font-semibold text-content-primary">Criar Lote</h2>
          <p className="mt-1 text-xs text-content-muted">
            Crie um lote de entrega com período opcional para filtrar treinos atribuídos.
          </p>
          <CreateBatchForm groupId={groupId} />
        </div>
      )}

      {batches.length > 0 && (
        <div className="space-y-3">
          <h2 className="text-sm font-semibold text-content-primary">Lotes</h2>
          <div className="overflow-hidden rounded-xl border border-border bg-surface shadow-sm">
            <div className="overflow-x-auto">
              <table className="min-w-full divide-y divide-border text-sm">
                <thead className="bg-bg-secondary">
                  <tr>
                    <th className="px-4 py-3 text-left font-medium text-content-secondary">Período</th>
                    <th className="px-4 py-3 text-left font-medium text-content-secondary">Status</th>
                    <th className="px-4 py-3 text-left font-medium text-content-secondary">Criado em</th>
                    {isCoachOrAdmin && (
                      <th className="px-4 py-3 text-right font-medium text-content-secondary">Ações</th>
                    )}
                  </tr>
                </thead>
                <tbody className="divide-y divide-border-subtle">
                  {batches.map((b) => (
                    <tr key={b.id} className="hover:bg-surface-elevated">
                      <td className="whitespace-nowrap px-4 py-3 text-content-primary">
                        {b.period_start && b.period_end
                          ? `${formatDateISO(b.period_start)} — ${formatDateISO(b.period_end)}`
                          : b.period_start
                            ? `A partir de ${formatDateISO(b.period_start)}`
                            : "Sem período"}
                      </td>
                      <td className="whitespace-nowrap px-4 py-3">
                        <StatusBadge
                          label={BATCH_STATUS_LABELS[b.status] ?? b.status}
                          variant={b.status === "published" ? "success" : b.status === "draft" ? "neutral" : "info"}
                          dot
                        />
                      </td>
                      <td className="whitespace-nowrap px-4 py-3 text-content-secondary">
                        {formatDateISO(b.created_at)}
                      </td>
                      {isCoachOrAdmin && (
                        <td className="whitespace-nowrap px-4 py-3 text-right">
                          {b.status === "draft" && (
                            <GenerateItemsButton batchId={b.id} />
                          )}
                        </td>
                      )}
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        </div>
      )}

      <div className="space-y-3">
        <h2 className="text-sm font-semibold text-content-primary">Itens de Entrega</h2>
        {items.length === 0 && !fetchError ? (
          <div className="rounded-xl border border-border bg-surface p-8 text-center shadow-sm">
            <p className="text-sm text-content-secondary">Nenhum item de entrega encontrado.</p>
          </div>
        ) : (
          <div className="overflow-hidden rounded-xl border border-border bg-surface shadow-sm">
            <div className="overflow-x-auto">
              <table className="min-w-full divide-y divide-border text-sm">
                <thead className="bg-bg-secondary">
                  <tr>
                    <th className="px-4 py-3 text-left font-medium text-content-secondary">Atleta</th>
                    <th className="px-4 py-3 text-left font-medium text-content-secondary">Treino</th>
                    <th className="px-4 py-3 text-center font-medium text-content-secondary">Status</th>
                    <th className="px-4 py-3 text-left font-medium text-content-secondary">Publicado em</th>
                    <th className="px-4 py-3 text-left font-medium text-content-secondary">Confirmado em</th>
                    <th className="px-4 py-3 text-right font-medium text-content-secondary">Ações</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-border-subtle">
                  {items.map((item) => {
                    const cfg = STATUS_CONFIG[item.status] ?? { label: item.status, variant: "neutral" as const };
                    return (
                      <tr key={item.id} className="hover:bg-surface-elevated">
                        <td className="whitespace-nowrap px-4 py-3 font-medium text-content-primary">
                          {item.athlete_name}
                        </td>
                        <td className="whitespace-nowrap px-4 py-3 text-content-secondary">
                          {item.template_name}
                        </td>
                        <td className="whitespace-nowrap px-4 py-3 text-center">
                          <StatusBadge label={cfg.label} variant={cfg.variant} dot />
                        </td>
                        <td className="whitespace-nowrap px-4 py-3 text-content-secondary">
                          {formatDateISO(item.published_at)}
                        </td>
                        <td className="whitespace-nowrap px-4 py-3 text-content-secondary">
                          {formatDateISO(item.confirmed_at)}
                        </td>
                        <td className="whitespace-nowrap px-4 py-3 text-right">
                          <div className="flex items-center justify-end gap-2">
                            <CopyPayloadButton payload={item.export_payload} />
                            {isCoachOrAdmin && item.status === "pending" && (
                              <PublishButton itemId={item.id} />
                            )}
                          </div>
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
