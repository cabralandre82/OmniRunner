import { createAdminClient } from "@/lib/supabase/admin";
import { FeatureFlagRow } from "./feature-flag-row";

export const dynamic = "force-dynamic";

export default async function FeatureFlagsPage() {
  const supabase = createAdminClient();
  const { data: flags } = await supabase
    .from("feature_flags")
    .select("id, key, enabled, rollout_pct, created_at, updated_at")
    .order("key");

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-content-primary">Feature Flags</h1>
          <p className="mt-1 text-sm text-content-secondary">
            Gerenciar rollout de funcionalidades
          </p>
        </div>
      </div>

      <div className="rounded-xl border border-border bg-surface shadow-sm">
        <div className="overflow-x-auto">
          <table className="min-w-full divide-y divide-border">
            <thead className="bg-bg-secondary">
              <tr>
                <th className="px-5 py-3 text-left text-xs font-semibold uppercase tracking-wide text-content-secondary">
                  Flag
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
              {(flags ?? []).length === 0 && (
                <tr>
                  <td
                    colSpan={4}
                    className="px-5 py-12 text-center text-sm text-content-muted"
                  >
                    Nenhuma feature flag cadastrada
                  </td>
                </tr>
              )}
              {(flags ?? []).map((flag) => (
                <FeatureFlagRow key={flag.id} flag={flag} />
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
