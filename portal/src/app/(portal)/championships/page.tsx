import type { Metadata } from "next";
import { cookies } from "next/headers";
import { createClient } from "@/lib/supabase/server";
import { NoGroupSelected } from "@/components/no-group-selected";

export const metadata: Metadata = { title: "Campeonatos" };
export const dynamic = "force-dynamic";

const STATUS_LABELS: Record<string, { label: string; color: string }> = {
  draft: { label: "Rascunho", color: "bg-neutral-soft text-content-muted" },
  open: { label: "Aberto", color: "bg-info-soft text-info" },
  active: { label: "Ativo", color: "bg-success-soft text-success" },
  completed: { label: "Finalizado", color: "bg-surface-elevated text-content-secondary" },
  cancelled: { label: "Cancelado", color: "bg-error-soft text-error" },
};

function formatDate(iso: string) {
  return new Date(iso).toLocaleDateString("pt-BR", {
    day: "2-digit",
    month: "short",
    year: "numeric",
  });
}

export default async function ChampionshipsPage() {
  const groupId = cookies().get("portal_group_id")?.value;
  if (!groupId) return <NoGroupSelected />;

  const supabase = createClient();

  const { data: championships, error } = await supabase
    .from("championships")
    .select("id, name, status, metric, start_at, end_at, max_participants, created_at")
    .eq("host_group_id", groupId)
    .order("created_at", { ascending: false });

  if (error) {
    return (
      <div className="py-16 text-center">
        <p className="text-sm text-error">Erro ao carregar campeonatos.</p>
      </div>
    );
  }

  const items = championships ?? [];

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-content-primary">Campeonatos</h1>
        <p className="mt-1 text-sm text-content-secondary">
          Gerencie os campeonatos da sua assessoria
        </p>
      </div>

      {items.length === 0 ? (
        <div className="py-16 text-center">
          <p className="text-sm text-content-muted">
            Nenhum campeonato encontrado.
          </p>
          <p className="mt-1 text-xs text-content-muted">
            Campeonatos criados pelo app aparecerão aqui.
          </p>
        </div>
      ) : (
        <div className="space-y-3">
          {items.map((c) => {
            const st = STATUS_LABELS[c.status] ?? STATUS_LABELS.draft;
            return (
              <div
                key={c.id}
                className="rounded-xl border border-border bg-surface p-4 shadow-sm"
              >
                <div className="flex items-start justify-between gap-3">
                  <div className="min-w-0 flex-1">
                    <h3 className="text-sm font-semibold text-content-primary truncate">
                      {c.name}
                    </h3>
                    <div className="mt-1 flex flex-wrap items-center gap-2 text-xs text-content-secondary">
                      <span>{formatDate(c.start_at)} — {formatDate(c.end_at)}</span>
                      <span>·</span>
                      <span className="capitalize">{c.metric}</span>
                      {c.max_participants && (
                        <>
                          <span>·</span>
                          <span>Máx {c.max_participants}</span>
                        </>
                      )}
                    </div>
                  </div>
                  <span
                    className={`shrink-0 rounded-full px-2.5 py-1 text-xs font-medium ${st.color}`}
                  >
                    {st.label}
                  </span>
                </div>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
