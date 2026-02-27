import { createAdminClient } from "@/lib/supabase/admin";
import { AssessoriaActions } from "./actions";

export const dynamic = "force-dynamic";

interface Assessoria {
  id: string;
  name: string;
  city: string;
  approval_status: string;
  approval_reject_reason: string | null;
  approval_reviewed_at: string | null;
  created_at: string;
  coach_user_id: string;
  coach_name?: string;
  member_count?: number;
}

export default async function AssessoriasPage() {
  const supabase = createAdminClient();

  const { data: groups } = await supabase
    .from("coaching_groups")
    .select(
      "id, name, city, approval_status, approval_reject_reason, approval_reviewed_at, created_at, coach_user_id",
    )
    .order("created_at", { ascending: false });

  const assessorias: Assessoria[] = [];

  for (const g of groups ?? []) {
    const { data: profile } = await supabase
      .from("profiles")
      .select("display_name")
      .eq("id", g.coach_user_id)
      .maybeSingle();

    const { count } = await supabase
      .from("coaching_members")
      .select("id", { count: "exact", head: true })
      .eq("group_id", g.id);

    assessorias.push({
      ...g,
      coach_name: profile?.display_name ?? "—",
      member_count: count ?? 0,
    });
  }

  const pending = assessorias.filter(
    (a) => a.approval_status === "pending_approval",
  );
  const approved = assessorias.filter(
    (a) => a.approval_status === "approved",
  );
  const rejected = assessorias.filter(
    (a) => a.approval_status === "rejected",
  );
  const suspended = assessorias.filter(
    (a) => a.approval_status === "suspended",
  );

  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-2xl font-bold text-gray-900">Assessorias</h1>
        <p className="mt-1 text-sm text-gray-500">
          Gerencie as assessorias cadastradas na plataforma
        </p>
      </div>

      {/* Stats */}
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-4 sm:gap-4">
        <StatCard
          label="Pendentes"
          value={pending.length}
          color="text-orange-600"
          bg="bg-orange-50"
        />
        <StatCard
          label="Aprovadas"
          value={approved.length}
          color="text-green-600"
          bg="bg-green-50"
        />
        <StatCard
          label="Rejeitadas"
          value={rejected.length}
          color="text-red-600"
          bg="bg-red-50"
        />
        <StatCard
          label="Suspensas"
          value={suspended.length}
          color="text-gray-600"
          bg="bg-gray-100"
        />
      </div>

      {/* Pending */}
      {pending.length > 0 && (
        <Section title="Aguardando aprovação" badge={pending.length}>
          {pending.map((a) => (
            <AssessoriaCard key={a.id} assessoria={a} showActions />
          ))}
        </Section>
      )}

      {/* Approved */}
      <Section title="Aprovadas" badge={approved.length}>
        {approved.length === 0 ? (
          <p className="py-8 text-center text-sm text-gray-400">
            Nenhuma assessoria aprovada ainda.
          </p>
        ) : (
          approved.map((a) => (
            <AssessoriaCard key={a.id} assessoria={a} showSuspend />
          ))
        )}
      </Section>

      {/* Rejected + Suspended */}
      {(rejected.length > 0 || suspended.length > 0) && (
        <Section
          title="Rejeitadas / Suspensas"
          badge={rejected.length + suspended.length}
        >
          {[...rejected, ...suspended].map((a) => (
            <AssessoriaCard key={a.id} assessoria={a} showReapprove />
          ))}
        </Section>
      )}
    </div>
  );
}

function StatCard({
  label,
  value,
  color,
  bg,
}: {
  label: string;
  value: number;
  color: string;
  bg: string;
}) {
  return (
    <div
      className={`rounded-xl border border-gray-200 ${bg} p-5 shadow-sm`}
    >
      <p className="text-xs font-medium uppercase tracking-wide text-gray-500">
        {label}
      </p>
      <p className={`mt-2 text-2xl font-bold ${color}`}>{value}</p>
    </div>
  );
}

function Section({
  title,
  badge,
  children,
}: {
  title: string;
  badge: number;
  children: React.ReactNode;
}) {
  return (
    <div>
      <div className="mb-3 flex items-center gap-2">
        <h2 className="text-sm font-semibold text-gray-900">{title}</h2>
        <span className="rounded-full bg-gray-200 px-2 py-0.5 text-xs font-medium text-gray-600">
          {badge}
        </span>
      </div>
      <div className="space-y-3">{children}</div>
    </div>
  );
}

function AssessoriaCard({
  assessoria,
  showActions = false,
  showSuspend = false,
  showReapprove = false,
}: {
  assessoria: Assessoria;
  showActions?: boolean;
  showSuspend?: boolean;
  showReapprove?: boolean;
}) {
  const statusLabel: Record<string, string> = {
    pending_approval: "Pendente",
    approved: "Aprovada",
    rejected: "Rejeitada",
    suspended: "Suspensa",
  };

  const statusColor: Record<string, string> = {
    pending_approval: "bg-orange-100 text-orange-700",
    approved: "bg-green-100 text-green-700",
    rejected: "bg-red-100 text-red-700",
    suspended: "bg-gray-200 text-gray-700",
  };

  const createdAt = new Date(assessoria.created_at).toLocaleDateString(
    "pt-BR",
  );

  return (
    <div className="rounded-xl border border-gray-200 bg-white p-4 sm:p-5 shadow-sm">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-center gap-2">
            <h3 className="text-sm sm:text-base font-semibold text-gray-900">
              {assessoria.name}
            </h3>
            <span
              className={`rounded-full px-2 py-0.5 text-xs font-medium ${
                statusColor[assessoria.approval_status] ?? "bg-gray-100"
              }`}
            >
              {statusLabel[assessoria.approval_status] ??
                assessoria.approval_status}
            </span>
          </div>
          <div className="mt-1 flex flex-wrap gap-x-3 gap-y-1 text-xs text-gray-500">
            {assessoria.city && <span>{assessoria.city}</span>}
            <span>{assessoria.coach_name}</span>
            <span>{assessoria.member_count} membros</span>
            <span>{createdAt}</span>
          </div>
          {assessoria.approval_reject_reason && (
            <p className="mt-2 text-xs text-red-600">
              Motivo: {assessoria.approval_reject_reason}
            </p>
          )}
        </div>

        <div className="flex shrink-0 flex-wrap gap-2">
          {showActions && (
            <>
              <AssessoriaActions
                groupId={assessoria.id}
                action="approve"
                label="Aprovar"
                className="rounded-lg bg-green-600 px-3 py-1.5 text-xs font-medium text-white hover:bg-green-700"
              />
              <AssessoriaActions
                groupId={assessoria.id}
                action="reject"
                label="Rejeitar"
                className="rounded-lg bg-red-50 px-3 py-1.5 text-xs font-medium text-red-600 hover:bg-red-100"
                requireReason
              />
            </>
          )}
          {showSuspend && (
            <AssessoriaActions
              groupId={assessoria.id}
              action="suspend"
              label="Suspender"
              className="rounded-lg bg-gray-100 px-3 py-1.5 text-xs font-medium text-gray-600 hover:bg-gray-200"
              requireReason
            />
          )}
          {showReapprove && (
            <AssessoriaActions
              groupId={assessoria.id}
              action="approve"
              label="Reaprovar"
              className="rounded-lg bg-green-50 px-3 py-1.5 text-xs font-medium text-green-600 hover:bg-green-100"
            />
          )}
        </div>
      </div>
    </div>
  );
}
