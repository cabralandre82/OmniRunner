import { createAdminClient } from "@/lib/supabase/admin";
import { FeatureFlagRow } from "./feature-flag-row";

export const dynamic = "force-dynamic";

interface FlagRow {
  id: string;
  key: string;
  enabled: boolean;
  rollout_pct: number;
  category: string;
  scope: string;
  reason: string | null;
  updated_at: string;
}

const CATEGORY_ORDER: Record<string, number> = {
  kill_switch: 0,
  banner: 1,
  operational: 2,
  product: 3,
  experimental: 4,
};

export default async function FeatureFlagsPage() {
  const supabase = createAdminClient();
  const { data: flags } = await supabase
    .from("feature_flags")
    .select("id, key, enabled, rollout_pct, category, scope, reason, updated_at")
    .order("category")
    .order("key");

  const rows = ((flags as FlagRow[] | null) ?? []).slice().sort((a, b) => {
    const ca = CATEGORY_ORDER[a.category] ?? 99;
    const cb = CATEGORY_ORDER[b.category] ?? 99;
    if (ca !== cb) return ca - cb;
    return a.key.localeCompare(b.key);
  });

  const killSwitchOff = rows.filter(
    (r) => r.category === "kill_switch" && !r.enabled,
  );
  const bannerOn = rows.filter((r) => r.category === "banner" && r.enabled);

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-content-primary">
            Feature Flags
          </h1>
          <p className="mt-1 text-sm text-content-secondary">
            Kill switches operacionais, banners públicos e rollout de produto.
            Toda mudança é auditada (ver{" "}
            <code className="rounded bg-surface-elevated px-1.5 py-0.5 text-xs">
              public.feature_flag_audit
            </code>
            ).
          </p>
        </div>
      </div>

      {(killSwitchOff.length > 0 || bannerOn.length > 0) && (
        <div className="rounded-xl border border-warning bg-warning/10 p-4">
          <h2 className="text-sm font-semibold text-warning">
            Estado operacional atípico
          </h2>
          <ul className="mt-2 space-y-1 text-sm text-content-secondary">
            {killSwitchOff.map((r) => (
              <li key={r.id}>
                <strong className="text-danger">Kill switch ATIVO</strong>:{" "}
                <code>{r.key}</code>
                {r.reason ? ` — ${r.reason}` : ""}
              </li>
            ))}
            {bannerOn.map((r) => (
              <li key={r.id}>
                <strong className="text-warning">Banner exibido</strong>:{" "}
                <code>{r.key}</code>
                {r.reason ? ` — ${r.reason}` : ""}
              </li>
            ))}
          </ul>
        </div>
      )}

      <div className="rounded-xl border border-border bg-surface shadow-sm">
        <div className="overflow-x-auto">
          <table className="min-w-full divide-y divide-border">
            <thead className="bg-bg-secondary">
              <tr>
                <th className="px-5 py-3 text-left text-xs font-semibold uppercase tracking-wide text-content-secondary">
                  Flag
                </th>
                <th className="px-5 py-3 text-left text-xs font-semibold uppercase tracking-wide text-content-secondary">
                  Categoria
                </th>
                <th className="px-5 py-3 text-center text-xs font-semibold uppercase tracking-wide text-content-secondary">
                  Status
                </th>
                <th className="px-5 py-3 text-center text-xs font-semibold uppercase tracking-wide text-content-secondary">
                  Rollout %
                </th>
                <th className="px-5 py-3 text-right text-xs font-semibold uppercase tracking-wide text-content-secondary">
                  Atualizado
                </th>
              </tr>
            </thead>
            <tbody className="divide-y divide-border-subtle">
              {rows.length === 0 && (
                <tr>
                  <td
                    colSpan={5}
                    className="px-5 py-12 text-center text-sm text-content-muted"
                  >
                    Nenhuma feature flag cadastrada
                  </td>
                </tr>
              )}
              {rows.map((flag) => (
                <FeatureFlagRow key={flag.id} flag={flag} />
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
