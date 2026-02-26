import { createClient } from "@/lib/supabase/server";
import { redirect } from "next/navigation";
import { TicketChat } from "./ticket-chat";

export const dynamic = "force-dynamic";

interface Props {
  params: { id: string };
}

export default async function SupportTicketPage({ params }: Props) {
  const supabase = createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) redirect("/login");

  const { data: ticket } = await supabase
    .from("support_tickets")
    .select()
    .eq("id", params.id)
    .single();

  if (!ticket) redirect("/platform/support");

  const { data: group } = await supabase
    .from("coaching_groups")
    .select("name")
    .eq("id", ticket.group_id)
    .maybeSingle();

  const { data: messages } = await supabase
    .from("support_messages")
    .select()
    .eq("ticket_id", params.id)
    .order("created_at", { ascending: true });

  return (
    <div className="mx-auto max-w-3xl space-y-4">
      {/* Header */}
      <div>
        <a
          href="/platform/support"
          className="mb-3 inline-flex items-center gap-1 text-sm text-gray-500 hover:text-gray-700"
        >
          ← Voltar
        </a>
        <div className="flex flex-wrap items-center gap-3">
          <h1 className="text-xl font-bold text-gray-900">{ticket.subject}</h1>
          <StatusBadge status={ticket.status} />
        </div>
        <p className="mt-1 text-sm text-gray-500">
          {group?.name ?? "—"} ·{" "}
          {new Date(ticket.created_at).toLocaleDateString("pt-BR", {
            day: "2-digit",
            month: "long",
            year: "numeric",
            hour: "2-digit",
            minute: "2-digit",
          })}
        </p>
      </div>

      {/* Chat */}
      <TicketChat
        ticketId={params.id}
        status={ticket.status}
        initialMessages={messages ?? []}
        userId={user.id}
      />
    </div>
  );
}

function StatusBadge({ status }: { status: string }) {
  const styles: Record<string, string> = {
    open: "bg-orange-100 text-orange-700",
    answered: "bg-blue-100 text-blue-700",
    closed: "bg-gray-200 text-gray-600",
  };
  const labels: Record<string, string> = {
    open: "Aberto",
    answered: "Respondido",
    closed: "Fechado",
  };

  return (
    <span
      className={`rounded-full px-2.5 py-1 text-xs font-medium ${
        styles[status] ?? "bg-gray-100"
      }`}
    >
      {labels[status] ?? status}
    </span>
  );
}
