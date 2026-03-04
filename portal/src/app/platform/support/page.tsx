import { createAdminClient } from "@/lib/supabase/admin";
import Link from "next/link";

export const dynamic = "force-dynamic";

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
    .select()
    .order("updated_at", { ascending: false });

  if (filterStatus && filterStatus !== "all") {
    query = query.eq("status", filterStatus);
  }

  const { data: rawTickets } = await query;

  const tickets: Ticket[] = [];
  for (const t of rawTickets ?? []) {
    const { data: group } = await supabase
      .from("coaching_groups")
      .select("name")
      .eq("id", t.group_id)
      .maybeSingle();

    const { count } = await supabase
      .from("support_messages")
      .select("id", { count: "exact", head: true })
      .eq("ticket_id", t.id);

    tickets.push({
      ...t,
      group_name: group?.name ?? "—",
      message_count: count ?? 0,
    });
  }

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
