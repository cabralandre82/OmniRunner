import { cookies } from "next/headers";
import { createClient } from "@/lib/supabase/server";
import { NoGroupSelected } from "@/components/no-group-selected";
import Link from "next/link";
import { formatDateISO } from "@/lib/format";

export const dynamic = "force-dynamic";

const STATUS_LABELS: Record<string, string> = {
  active: "Ativo",
  paused: "Pausado",
  injured: "Lesionado",
  inactive: "Inativo",
  trial: "Teste",
};

interface AtRiskAthlete {
  user_id: string;
  display_name: string;
  status: string | null;
  tags: string[];
  alerts: { alert_type: string; title: string; day: string; severity: string }[];
}

async function getAtRiskAthletes(groupId: string): Promise<AtRiskAthlete[]> {
  const supabase = createClient();

  const { data: alertRows } = await supabase
    .from("coaching_alerts")
    .select("user_id, alert_type, title, day, severity")
    .eq("group_id", groupId)
    .eq("resolved", false)
    .order("day", { ascending: false });

  if (!alertRows || alertRows.length === 0) return [];

  const userIds = Array.from(new Set(alertRows.map((a: { user_id: string }) => a.user_id)));

  const [profilesRes, statusRes, tagsRes] = await Promise.all([
    supabase
      .from("profiles")
      .select("id, display_name")
      .in("id", userIds),
    supabase
      .from("coaching_member_status")
      .select("user_id, status")
      .eq("group_id", groupId)
      .in("user_id", userIds),
    supabase
      .from("coaching_athlete_tags")
      .select("athlete_user_id, coaching_tags(name)")
      .eq("group_id", groupId)
      .in("athlete_user_id", userIds),
  ]);

  const profileMap = new Map(
    (profilesRes.data ?? []).map((p: { id: string; display_name: string }) => [
      p.id,
      p.display_name || "Sem nome",
    ])
  );
  const statusMap = new Map(
    (statusRes.data ?? []).map((s: { user_id: string; status: string }) => [
      s.user_id,
      s.status,
    ])
  );
  const tagsByUser = new Map<string, string[]>();
  for (const t of tagsRes.data ?? []) {
    const uid = (t as any).athlete_user_id;
    const rawTag = (t as any).coaching_tags;
    const tag = Array.isArray(rawTag) ? rawTag[0] : rawTag;
    if (tag?.name) {
      const arr = tagsByUser.get(uid) ?? [];
      arr.push(tag.name);
      tagsByUser.set(uid, arr);
    }
  }

  const alertsByUser = new Map<
    string,
    { alert_type: string; title: string; day: string; severity: string }[]
  >();
  for (const a of alertRows) {
    const row = a as {
      user_id: string;
      alert_type: string;
      title: string;
      day: string;
      severity: string;
    };
    const arr = alertsByUser.get(row.user_id) ?? [];
    arr.push({
      alert_type: row.alert_type,
      title: row.title,
      day: row.day,
      severity: row.severity,
    });
    alertsByUser.set(row.user_id, arr);
  }

  return userIds.map((uid) => ({
    user_id: uid,
    display_name: profileMap.get(uid) ?? "Sem nome",
    status: statusMap.get(uid) ?? null,
    tags: tagsByUser.get(uid) ?? [],
    alerts: alertsByUser.get(uid) ?? [],
  }));
}

export default async function AtRiskPage() {
  const groupId = cookies().get("portal_group_id")?.value;
  if (!groupId) return <NoGroupSelected />;

  const athletes = await getAtRiskAthletes(groupId);

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-content-primary">Atletas em Risco</h1>
        <p className="mt-1 text-sm text-content-secondary">
          Atletas com alertas ativos para acompanhamento
        </p>
      </div>

      {athletes.length === 0 ? (
        <div className="rounded-xl border border-border bg-surface p-8 text-center shadow-sm">
          <p className="text-sm text-content-secondary">
            Nenhum atleta em risco no momento.
          </p>
        </div>
      ) : (
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {athletes.map((a) => (
            <Link
              key={a.user_id}
              href={`/crm/${a.user_id}`}
              className="block rounded-xl border border-border bg-surface p-4 shadow-sm transition hover:border-border hover:shadow-md"
            >
              <h3 className="font-semibold text-content-primary">{a.display_name}</h3>
              <p className="mt-1 text-sm text-content-secondary">
                {a.status ? STATUS_LABELS[a.status] ?? a.status : "Sem status"}
              </p>
              {a.tags.length > 0 && (
                <div className="mt-2 flex flex-wrap gap-1">
                  {a.tags.slice(0, 3).map((t) => (
                    <span
                      key={t}
                      className="rounded bg-surface-elevated px-1.5 py-0.5 text-xs text-content-secondary"
                    >
                      {t}
                    </span>
                  ))}
                </div>
              )}
              <div className="mt-3 space-y-1 border-t border-border-subtle pt-3">
                {a.alerts.slice(0, 2).map((al, i) => (
                  <div key={i} className="text-xs">
                    <span
                      className={
                        al.severity === "critical"
                          ? "font-medium text-error"
                          : al.severity === "warning"
                            ? "font-medium text-orange-600"
                            : "text-content-secondary"
                      }
                    >
                      {al.title}
                    </span>
                    <span className="ml-1 text-content-muted">
                      ({formatDateISO(al.day)})
                    </span>
                  </div>
                ))}
                {a.alerts.length > 2 && (
                  <p className="text-xs text-content-muted">
                    +{a.alerts.length - 2} outros alertas
                  </p>
                )}
              </div>
            </Link>
          ))}
        </div>
      )}
    </div>
  );
}
