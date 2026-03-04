import { createAdminClient } from "@/lib/supabase/admin";
import Link from "next/link";

export const dynamic = "force-dynamic";
export const revalidate = 60;

interface Ticket {
  id: string;
  group_id: string;
  subject: string;
  status: string;
  created_at: string;
  updated_at: string;
  group_name?: string;
  message_count?: number;
}

export default async function SupportListPage({
  searchParams,
}: {
  searchParams: { status?: string };
}) {
  const supabase = createAdminClient();
  const filterStatus = searchParams.status;

  let query = supabase
    .from("support_tickets")
    .select("id, group_id, subject, status, created_at, updated_at", { count: "exact" })
    .order("updated_at", { ascending: false })
    .limit(500);

  if (filterStatus && filterStatus !== "all") {
    query = query.eq("status", filterStatus);
  }

  const { data: rawTickets, count: totalCount } = await query;

  const raw = rawTickets ?? [];
  const groupIds = Array.from(new Set(raw.map((t) => t.group_id).filter(Boolean)));
  const ticketIds = raw.map((t) => t.id);

  const [groupsRes, countsRes] = await Promise.all([
    groupIds.length > 0
      ? supabase.from("coaching_groups").select("id, name").in("id", groupIds)
      : { data: [] as { id: string; name: string }[] },
    ticketIds.length > 0
      ? supabase
          .from("support_messages")
          .select("ticket_id", { count: "exact", head: false })
          .in("ticket_id", ticketIds)
      : { data: [] as { ticket_id: string }[] },
  ]);

  const groupMap = new Map(
    (groupsRes.data ?? []).map((g: { id: string; name: string }) => [g.id, g.name]),
  );
  const countMap = new Map<string, number>();
  for (const m of countsRes.data ?? []) {
    const tid = (m as { ticket_id: string }).ticket_id;
    countMap.set(tid, (countMap.get(tid) ?? 0) + 1);
  }

  const tickets: Ticket[] = raw.map((t) => ({
    ...t,
    group_name: groupMap.get(t.group_id) ?? "—",
    message_count: countMap.get(t.id) ?? 0,
  }));

  const openCount = tickets.filter((t) => t.status === "open").length;
  const answeredCount = tickets.filter((t) => t.status === "answered").length;
  const closedCount = tickets.filter((t) => t.status === "closed").length;

  const statusLabel: Record<string, string> = {
    open: "Aberto",
    answered: "Respondido",
    closed: "Fechado",
  };

  const statusColor: Record<string, string> = {
    open: "bg-orange-100 text-orange-700",
    answered: "bg-blue-100 text-brand",
    closed: "bg-surface-elevated text-content-secondary",
  };

  const filters = [
    { key: "all", label: "Todos", count: tickets.length },
    { key: "open", label: "Abertos", count: openCount },
    { key: "answered", label: "Respondidos", count: answeredCount },
    { key: "closed", label: "Fechados", count: closedCount },
  ];

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-content-primary">Suporte</h1>
        <p className="mt-1 text-sm text-content-secondary">
          Chamados das assessorias
        </p>
      </div>

      {/* Filters */}
      <div className="flex flex-wrap gap-2">
        {filters.map((f) => {
          const active =
            (filterStatus ?? "all") === f.key ||
            (!filterStatus && f.key === "all");
          return (
            <Link
              key={f.key}
              href={`/platform/support?status=${f.key}`}
              className={`rounded-full px-3.5 py-1.5 text-sm font-medium transition ${
                active
                  ? "bg-surface-elevated text-white"
                  : "bg-surface-elevated text-content-secondary hover:bg-bg-secondary"
              }`}
            >
              {f.label}{" "}
              <span
                className={`ml-1 ${active ? "text-content-muted" : "text-content-muted"}`}
              >
                {f.count}
              </span>
            </Link>
          );
        })}
      </div>

      {(totalCount ?? 0) > tickets.length && (
        <p className="text-sm text-content-secondary">
          Mostrando {tickets.length} de {totalCount} chamados
        </p>
      )}

      {/* Tickets */}
      {tickets.length === 0 ? (
        <div className="py-16 text-center">
          <p className="text-sm text-content-muted">Nenhum chamado encontrado.</p>
        </div>
      ) : (
        <div className="space-y-3">
          {tickets.map((t) => {
            const updatedAt = new Date(t.updated_at).toLocaleDateString(
              "pt-BR",
              { day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit" },
            );

            return (
              <Link
                key={t.id}
                href={`/platform/support/${t.id}`}
                className="block rounded-xl border border-border bg-surface p-4 shadow-sm transition hover:border-border hover:shadow"
              >
                <div className="flex items-start justify-between gap-3">
                  <div className="min-w-0 flex-1">
                    <h3 className="text-sm font-semibold text-content-primary truncate">
                      {t.subject}
                    </h3>
                    <div className="mt-1 flex flex-wrap items-center gap-2 text-xs text-content-secondary">
                      <span className="font-medium text-content-secondary">
                        {t.group_name}
                      </span>
                      <span>·</span>
                      <span>{t.message_count} msg</span>
                      <span>·</span>
                      <span>{updatedAt}</span>
                    </div>
                  </div>
                  <span
                    className={`shrink-0 rounded-full px-2.5 py-1 text-xs font-medium ${
                      statusColor[t.status] ?? "bg-surface-elevated text-content-secondary"
                    }`}
                  >
                    {statusLabel[t.status] ?? t.status}
                  </span>
                </div>
              </Link>
            );
          })}
        </div>
      )}
    </div>
  );
}
