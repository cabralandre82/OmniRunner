/**
 * /financial/agenda — L09-15 · Agenda de Recebíveis
 *
 * Visão consolidada das invoices de assinatura do grupo, agrupadas por
 * due_date, com KPIs de janela (7/30 dias, vencidas) e botão admin-only
 * para forçar geração do ciclo (catch-up / demo).
 *
 * Lê de `athlete_subscription_invoices` (L23-09, populada por
 * `fn_subscription_generate_cycle` via cron L09-13 ou via a RPC
 * admin `fn_subscription_admin_generate_cycle_scoped` deste finding).
 */

import { cookies } from "next/headers";
import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { NoGroupSelected } from "@/components/no-group-selected";
import { formatBRL, formatDateISO } from "@/lib/format";
import { GenerateCycleButton } from "./_components/generate-cycle-button";

export const dynamic = "force-dynamic";

type InvoiceStatus = "pending" | "paid" | "overdue" | "cancelled";

interface InvoiceRow {
  id: string;
  subscription_id: string;
  athlete_user_id: string;
  amount_cents: number;
  currency: string;
  due_date: string;
  period_month: string;
  status: InvoiceStatus;
  athlete_display_name: string;
}

interface AgendaKpis {
  next7: number;
  next30: number;
  overdue: number;
  monthTotal: number;
}

function firstDayOfMonthISO(input?: string | null): string {
  if (input && /^\d{4}-\d{2}-\d{2}$/.test(input)) {
    return input.slice(0, 8) + "01";
  }
  const now = new Date();
  const y = now.getUTCFullYear();
  const m = (now.getUTCMonth() + 1).toString().padStart(2, "0");
  return `${y}-${m}-01`;
}

function addMonthsISO(iso: string, months: number): string {
  const [y, m] = iso.split("-").map(Number);
  const d = new Date(Date.UTC(y, m - 1 + months, 1));
  const yy = d.getUTCFullYear();
  const mm = (d.getUTCMonth() + 1).toString().padStart(2, "0");
  return `${yy}-${mm}-01`;
}

function labelPeriod(iso: string): string {
  const [y, m] = iso.split("-").map(Number);
  const date = new Date(Date.UTC(y, m - 1, 1));
  return date.toLocaleDateString("pt-BR", {
    month: "long",
    year: "numeric",
    timeZone: "UTC",
  });
}

async function getAgenda(
  groupId: string,
  periodMonth: string,
): Promise<{ rows: InvoiceRow[]; kpis: AgendaKpis; isAdmin: boolean }> {
  const supabase = createClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();

  let isAdmin = false;
  if (user) {
    const { data: membership } = await supabase
      .from("coaching_members")
      .select("role")
      .eq("group_id", groupId)
      .eq("user_id", user.id)
      .maybeSingle();
    isAdmin = membership?.role === "admin_master";
  }

  const nextPeriod = addMonthsISO(periodMonth, 1);

  const { data, error } = await supabase
    .from("athlete_subscription_invoices")
    .select(
      "id, subscription_id, athlete_user_id, amount_cents, currency, due_date, period_month, status, profiles!athlete_user_id(display_name)",
    )
    .eq("group_id", groupId)
    .gte("period_month", periodMonth)
    .lt("period_month", nextPeriod)
    .order("due_date", { ascending: true });

  if (error) {
    throw new Error(error.message);
  }

  const rows: InvoiceRow[] = (data ?? []).map((r: Record<string, unknown>) => ({
    id: r.id as string,
    subscription_id: r.subscription_id as string,
    athlete_user_id: r.athlete_user_id as string,
    amount_cents: r.amount_cents as number,
    currency: (r.currency as string) ?? "BRL",
    due_date: r.due_date as string,
    period_month: r.period_month as string,
    status: r.status as InvoiceStatus,
    athlete_display_name:
      ((r.profiles as Record<string, unknown> | null)?.display_name as
        | string
        | undefined) ?? "—",
  }));

  // KPIs: as invoices vêm só do mês filtrado (scope da agenda),
  // mas os KPIs de janela (7/30d) precisam considerar TODO pending/overdue
  // do grupo — não só do mês. Segunda query curta pra isso.
  const today = new Date();
  const in7 = new Date(today);
  in7.setDate(in7.getDate() + 7);
  const in30 = new Date(today);
  in30.setDate(in30.getDate() + 30);

  const toISO = (d: Date) => d.toISOString().slice(0, 10);

  const { data: openInvoices, error: openErr } = await supabase
    .from("athlete_subscription_invoices")
    .select("amount_cents, due_date, status")
    .eq("group_id", groupId)
    .in("status", ["pending", "overdue"]);

  if (openErr) throw new Error(openErr.message);

  const todayISO = toISO(today);
  const in7ISO = toISO(in7);
  const in30ISO = toISO(in30);

  let next7 = 0;
  let next30 = 0;
  let overdue = 0;
  for (const inv of openInvoices ?? []) {
    const row = inv as {
      amount_cents: number;
      due_date: string;
      status: string;
    };
    if (row.status === "overdue") {
      overdue += row.amount_cents;
      continue;
    }
    if (row.due_date >= todayISO && row.due_date <= in7ISO) {
      next7 += row.amount_cents;
    }
    if (row.due_date >= todayISO && row.due_date <= in30ISO) {
      next30 += row.amount_cents;
    }
  }

  const monthTotal = rows.reduce((sum, r) => sum + r.amount_cents, 0);

  return {
    rows,
    kpis: { next7, next30, overdue, monthTotal },
    isAdmin,
  };
}

const STATUS_BADGE: Record<InvoiceStatus, { label: string; cls: string }> = {
  pending: { label: "Pendente", cls: "bg-brand-soft text-brand" },
  paid: { label: "Paga", cls: "bg-success-soft text-success" },
  overdue: { label: "Vencida", cls: "bg-error-soft text-error" },
  cancelled: {
    label: "Cancelada",
    cls: "bg-surface-elevated text-content-secondary",
  },
};

function daysBetween(isoA: string, isoB: string): number {
  const a = Date.UTC(
    Number(isoA.slice(0, 4)),
    Number(isoA.slice(5, 7)) - 1,
    Number(isoA.slice(8, 10)),
  );
  const b = Date.UTC(
    Number(isoB.slice(0, 4)),
    Number(isoB.slice(5, 7)) - 1,
    Number(isoB.slice(8, 10)),
  );
  return Math.round((a - b) / (1000 * 60 * 60 * 24));
}

function groupByDueDate(rows: InvoiceRow[]): Array<{
  dueDate: string;
  rows: InvoiceRow[];
  totalCents: number;
}> {
  const map = new Map<string, InvoiceRow[]>();
  for (const r of rows) {
    const arr = map.get(r.due_date) ?? [];
    arr.push(r);
    map.set(r.due_date, arr);
  }
  const entries = Array.from(map.entries()).sort(([a], [b]) =>
    a.localeCompare(b),
  );
  return entries.map(([dueDate, rs]) => ({
    dueDate,
    rows: rs,
    totalCents: rs.reduce((s, x) => s + x.amount_cents, 0),
  }));
}

export default async function FinancialAgendaPage({
  searchParams,
}: {
  searchParams: Promise<{ period?: string }>;
}) {
  const groupId = cookies().get("portal_group_id")?.value;
  if (!groupId) return <NoGroupSelected />;

  const params = await searchParams;
  const periodMonth = firstDayOfMonthISO(params.period);
  const prevPeriod = addMonthsISO(periodMonth, -1);
  const nextPeriod = addMonthsISO(periodMonth, 1);

  let rows: InvoiceRow[] = [];
  let kpis: AgendaKpis = { next7: 0, next30: 0, overdue: 0, monthTotal: 0 };
  let isAdmin = false;
  let fetchError: string | null = null;

  try {
    const result = await getAgenda(groupId, periodMonth);
    rows = result.rows;
    kpis = result.kpis;
    isAdmin = result.isAdmin;
  } catch (e) {
    fetchError = e instanceof Error ? e.message : String(e);
  }

  const todayISO = new Date().toISOString().slice(0, 10);
  const grouped = groupByDueDate(rows);

  return (
    <div className="space-y-6">
      <div className="flex items-start justify-between">
        <div>
          <h1 className="text-2xl font-bold text-content-primary">
            Agenda de Recebíveis
          </h1>
          <p className="mt-1 text-sm text-content-secondary">
            Faturas por vencimento · {labelPeriod(periodMonth)}
          </p>
        </div>
        <Link
          href="/financial"
          className="text-sm text-brand hover:text-brand hover:underline"
        >
          ← Dashboard
        </Link>
      </div>

      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="flex items-center gap-2">
          <Link
            href={`/financial/agenda?period=${prevPeriod}`}
            className="rounded-lg border border-border bg-surface px-3 py-1.5 text-xs font-medium text-content-secondary hover:bg-surface-elevated"
          >
            ← {labelPeriod(prevPeriod)}
          </Link>
          <span className="rounded-lg bg-bg-secondary px-3 py-1.5 text-xs font-semibold text-content-primary">
            {labelPeriod(periodMonth)}
          </span>
          <Link
            href={`/financial/agenda?period=${nextPeriod}`}
            className="rounded-lg border border-border bg-surface px-3 py-1.5 text-xs font-medium text-content-secondary hover:bg-surface-elevated"
          >
            {labelPeriod(nextPeriod)} →
          </Link>
        </div>
        {isAdmin && (
          <GenerateCycleButton
            periodMonth={periodMonth}
            label={`Forçar geração · ${labelPeriod(periodMonth)}`}
          />
        )}
      </div>

      {fetchError && (
        <div className="rounded-lg border border-error/30 bg-error-soft p-6 text-center">
          <p className="text-error">
            Erro ao carregar a agenda: {fetchError}
          </p>
        </div>
      )}

      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <KpiCard
          label="Próximos 7 dias"
          value={formatBRL(kpis.next7)}
          bg="bg-brand-soft"
          color="text-brand"
        />
        <KpiCard
          label="Próximos 30 dias"
          value={formatBRL(kpis.next30)}
          bg="bg-surface"
          color="text-content-primary"
        />
        <KpiCard
          label="Vencidas"
          value={formatBRL(kpis.overdue)}
          bg="bg-error-soft"
          color="text-error"
        />
        <KpiCard
          label={`Total · ${labelPeriod(periodMonth)}`}
          value={formatBRL(kpis.monthTotal)}
          bg="bg-success-soft"
          color="text-success"
        />
      </div>

      {rows.length === 0 && !fetchError ? (
        <div className="rounded-xl border border-border bg-surface p-8 text-center shadow-sm">
          <p className="text-sm text-content-secondary">
            Nenhuma fatura encontrada para {labelPeriod(periodMonth)}.
          </p>
          <p className="mt-2 text-xs text-content-secondary">
            As faturas são geradas automaticamente no dia 1 de cada mês
            (cron L09-13). Para forçar a geração agora (demo/backfill),
            clique em &ldquo;Forçar geração&rdquo; acima.
          </p>
          {!isAdmin && (
            <p className="mt-2 text-xs text-content-secondary">
              Apenas admin_master pode forçar a geração manualmente.
            </p>
          )}
        </div>
      ) : (
        <div className="space-y-4">
          {grouped.map((bucket) => {
            const delta = daysBetween(bucket.dueDate, todayISO);
            const isPast = delta < 0;
            const isToday = delta === 0;
            const isSoon = delta > 0 && delta <= 7;

            return (
              <div
                key={bucket.dueDate}
                className="rounded-xl border border-border bg-surface shadow-sm"
              >
                <div className="flex items-center justify-between border-b border-border-subtle px-4 py-2.5">
                  <div className="flex items-center gap-3">
                    <span className="text-sm font-semibold text-content-primary">
                      {formatDateISO(bucket.dueDate)}
                    </span>
                    {isPast && (
                      <span className="rounded-full bg-error-soft px-2 py-0.5 text-xs font-medium text-error">
                        venceu há {Math.abs(delta)}d
                      </span>
                    )}
                    {isToday && (
                      <span className="rounded-full bg-warning-soft px-2 py-0.5 text-xs font-medium text-warning">
                        hoje
                      </span>
                    )}
                    {isSoon && (
                      <span className="rounded-full bg-brand-soft px-2 py-0.5 text-xs font-medium text-brand">
                        em {delta}d
                      </span>
                    )}
                  </div>
                  <span className="text-sm font-semibold text-content-primary">
                    {formatBRL(bucket.totalCents)}
                  </span>
                </div>
                <ul className="divide-y divide-border-subtle">
                  {bucket.rows.map((inv) => {
                    const badge = STATUS_BADGE[inv.status];
                    return (
                      <li
                        key={inv.id}
                        className="flex items-center justify-between px-4 py-2.5"
                      >
                        <div className="flex min-w-0 items-center gap-3">
                          <span className="truncate text-sm text-content-primary">
                            {inv.athlete_display_name}
                          </span>
                          <span
                            className={`inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium ${badge.cls}`}
                          >
                            {badge.label}
                          </span>
                        </div>
                        <span className="text-sm text-content-secondary">
                          {formatBRL(inv.amount_cents)}
                        </span>
                      </li>
                    );
                  })}
                </ul>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}

function KpiCard({
  label,
  value,
  bg = "bg-surface",
  color = "text-content-primary",
}: {
  label: string;
  value: string;
  bg?: string;
  color?: string;
}) {
  return (
    <div className={`rounded-xl border border-border ${bg} p-4 shadow-sm`}>
      <p className="text-xs font-medium uppercase tracking-wide text-content-secondary">
        {label}
      </p>
      <p className={`mt-1 text-xl font-bold ${color}`}>{value}</p>
    </div>
  );
}
