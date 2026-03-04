import { cookies } from "next/headers";
import { createServiceClient } from "@/lib/supabase/service";
import { formatDateISO } from "@/lib/format";
import Link from "next/link";
import { RiskActions } from "./risk-actions";

export const dynamic = "force-dynamic";

const STATUS_LABELS: Record<string, string> = {
  active: "Ativo",
  paused: "Pausado",
  injured: "Lesionado",
  inactive: "Inativo",
  trial: "Teste",
};

const ALERT_TYPE_LABELS: Record<string, string> = {
  athlete_high_risk: "Risco Alto de Churn",
  athlete_medium_risk: "Risco Médio de Churn",
  engagement_drop: "Queda de Engajamento",
  milestone_reached: "Marco Atingido",
  inactive_7d: "Inativo 7 dias",
  inactive_14d: "Inativo 14 dias",
  inactive_30d: "Inativo 30 dias",
};

interface AlertRow {
  id: string;
  user_id: string;
  group_id: string;
  day: string;
  alert_type: string;
  title: string;
  severity: string;
  resolved: boolean;
  resolved_at: string | null;
  display_name: string | null;
  avatar_url: string | null;
  status: string | null;
}

const HIGH_RISK_TYPES = new Set([
  "athlete_high_risk",
  "inactive_30d",
]);
const HIGH_RISK_SEVERITY = "critical";

function isHighRisk(alert: AlertRow): boolean {
  return (
    HIGH_RISK_TYPES.has(alert.alert_type) ||
    alert.severity === HIGH_RISK_SEVERITY
  );
}

async function getAlertsData(groupId: string) {
  const db = createServiceClient();

  const thirtyDaysAgo = new Date();
  thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);

  const { data: alerts } = await db
    .from("coaching_alerts")
    .select("id, user_id, group_id, day, alert_type, title, severity, resolved, resolved_at")
    .eq("group_id", groupId)
    .eq("resolved", false)
    .order("day", { ascending: false })
    .limit(100);

  if (!alerts || alerts.length === 0) {
    return {
      activeAlerts: [],
      resolvedCount30d: 0,
      highCount: 0,
      mediumCount: 0,
    };
  }

  const userIds = Array.from(new Set((alerts as { user_id: string }[]).map((a) => a.user_id)));

  const [profilesRes, statusRes, resolvedRes] = await Promise.all([
    db.from("profiles").select("id, display_name, avatar_url").in("id", userIds),
    db
      .from("coaching_member_status")
      .select("user_id, status")
      .eq("group_id", groupId)
      .in("user_id", userIds),
    db
      .from("coaching_alerts")
      .select("id", { count: "exact", head: true })
      .eq("group_id", groupId)
      .eq("resolved", true)
      .gte("resolved_at", thirtyDaysAgo.toISOString()),
  ]);

  const profileMap = new Map(
    (profilesRes.data ?? []).map((p: { id: string; display_name: string | null; avatar_url: string | null }) => [
      p.id,
      { display_name: p.display_name, avatar_url: p.avatar_url },
    ])
  );
  const statusMap = new Map(
    (statusRes.data ?? []).map((s: { user_id: string; status: string }) => [s.user_id, s.status])
  );

  const activeAlerts: AlertRow[] = (alerts as AlertRow[]).map((a) => {
    const p = profileMap.get(a.user_id);
    return {
      ...a,
      display_name: p?.display_name ?? null,
      avatar_url: p?.avatar_url ?? null,
      status: statusMap.get(a.user_id) ?? null,
    };
  });

  const highCount = activeAlerts.filter(isHighRisk).length;
  const mediumCount = activeAlerts.length - highCount;
  const resolvedCount30d = resolvedRes.count ?? 0;

  return {
    activeAlerts,
    resolvedCount30d,
    highCount,
    mediumCount,
  };
}

export default async function RiskPage() {
  const groupId = cookies().get("portal_group_id")?.value;
  if (!groupId) return null;

  let activeAlerts: AlertRow[] = [];
  let resolvedCount30d = 0;
  let highCount = 0;
  let mediumCount = 0;
  let fetchError: string | null = null;

  try {
    const result = await getAlertsData(groupId);
    activeAlerts = result.activeAlerts;
    resolvedCount30d = result.resolvedCount30d;
    highCount = result.highCount;
    mediumCount = result.mediumCount;
  } catch (e) {
    fetchError = String(e);
  }

  const highRiskAlerts = activeAlerts.filter(isHighRisk);
  const mediumRiskAlerts = activeAlerts.filter((a) => !isHighRisk(a));

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-content-primary">Alertas e Risco</h1>
        <p className="mt-1 text-sm text-content-secondary">
          Atletas com alertas ativos para acompanhamento
        </p>
      </div>

      {fetchError && (
        <div className="rounded-lg border border-error/30 bg-error-soft p-6 text-center">
          <p className="text-error">Erro ao carregar dados. Tente recarregar a página.</p>
        </div>
      )}

      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <KpiCard label="Total alertas ativos" value={activeAlerts.length} color="text-content-primary" />
        <KpiCard label="Atletas em risco alto" value={highCount} color="text-error" />
        <KpiCard label="Atletas em risco médio" value={mediumCount} color="text-amber-600" />
        <KpiCard label="Alertas resolvidos (30d)" value={resolvedCount30d} color="text-success" />
      </div>

      <section className="space-y-4">
        <h2 className="text-lg font-semibold text-content-primary">Risco Alto</h2>
        {highRiskAlerts.length === 0 ? (
          <div className="rounded-xl border border-border bg-surface p-6 text-center shadow-sm">
            <p className="text-sm text-content-secondary">Nenhum atleta em risco alto no momento.</p>
          </div>
        ) : (
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {highRiskAlerts.map((alert) => (
              <AlertCard key={alert.id} alert={alert} />
            ))}
          </div>
        )}
      </section>

      <section className="space-y-4">
        <h2 className="text-lg font-semibold text-content-primary">Risco Médio</h2>
        {mediumRiskAlerts.length === 0 ? (
          <div className="rounded-xl border border-border bg-surface p-6 text-center shadow-sm">
            <p className="text-sm text-content-secondary">Nenhum atleta em risco médio no momento.</p>
          </div>
        ) : (
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {mediumRiskAlerts.map((alert) => (
              <AlertCard key={alert.id} alert={alert} />
            ))}
          </div>
        )}
      </section>
    </div>
  );
}

function KpiCard({
  label,
  value,
  color = "text-content-primary",
}: {
  label: string;
  value: number;
  color?: string;
}) {
  return (
    <div className="rounded-xl border border-border bg-surface p-4 shadow-sm">
      <p className="text-xs font-medium uppercase tracking-wide text-content-secondary">{label}</p>
      <p className={`mt-1 text-xl font-bold ${color}`}>{value}</p>
    </div>
  );
}

function AlertCard({ alert }: { alert: AlertRow }) {
  const label =
    ALERT_TYPE_LABELS[alert.alert_type] ?? alert.alert_type ?? alert.title;
  const statusLabel = alert.status ? STATUS_LABELS[alert.status] ?? alert.status : "Sem status";

  return (
    <div className="rounded-xl border border-border bg-surface p-4 shadow-sm">
      <div className="flex items-start justify-between gap-3">
        <Link
          href={`/crm/${alert.user_id}`}
          className="font-semibold text-brand hover:text-brand hover:underline"
        >
          {alert.display_name ?? "Sem nome"}
        </Link>
      </div>
      <p className="mt-1 text-xs font-medium text-content-secondary">{label}</p>
      <p className="mt-0.5 text-xs text-content-muted">{formatDateISO(alert.day)}</p>
      <p className="mt-2 text-xs text-content-secondary">Status: {statusLabel}</p>
      <div className="mt-4 flex gap-2">
        <RiskActions alertId={alert.id} />
      </div>
    </div>
  );
}
