import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

/**
 * L06-06 — Edge function helpers for feature flags / kill switches.
 *
 * Mirror of `portal/src/lib/feature-flags.ts` but adapted for Deno
 * runtime. Cache TTL is shorter (15s) because edge functions are
 * short-lived and a stale flag during a kill switch incident is more
 * costly than the extra DB load.
 */

export type FlagCategory =
  | "product"
  | "kill_switch"
  | "banner"
  | "experimental"
  | "operational";

export interface Flag {
  key: string;
  enabled: boolean;
  rollout_pct: number;
  category: FlagCategory;
  scope: string;
}

export class FeatureDisabledError extends Error {
  readonly code = "FEATURE_DISABLED" as const;
  readonly status = 503 as const;

  constructor(public readonly key: string, public readonly hint?: string) {
    super(`Feature disabled: ${key}${hint ? ` (${hint})` : ""}`);
    this.name = "FeatureDisabledError";
  }
}

let cache: Map<string, Flag> | null = null;
let lastFetchMs = 0;
const TTL_MS = 15_000; // edge: 15s para reagir mais rápido a kill switch

export function invalidateFeatureCache(): void {
  cache = null;
  lastFetchMs = 0;
}

function buildAdminClient(): SupabaseClient {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) {
    throw new Error(
      "feature_flags: SUPABASE_URL/SERVICE_ROLE_KEY missing in env",
    );
  }
  return createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

async function loadFlags(): Promise<Map<string, Flag>> {
  const now = Date.now();
  if (cache && now - lastFetchMs < TTL_MS) return cache;

  try {
    const db = buildAdminClient();
    const { data } = await db
      .from("feature_flags")
      .select("key, enabled, rollout_pct, category, scope")
      .order("key");

    const map = new Map<string, Flag>();
    for (const row of data ?? []) {
      map.set(row.key, {
        key: row.key,
        enabled: row.enabled,
        rollout_pct: row.rollout_pct,
        category: (row.category as FlagCategory) ?? "product",
        scope: (row.scope as string) ?? "global",
      });
    }
    cache = map;
    lastFetchMs = now;
    return map;
  } catch (e) {
    console.error("feature_flags: loadFlags failed", e);
    return cache ?? new Map();
  }
}

/**
 * Fail-OPEN: se a flag não existe no DB, retorna true. Use para kill
 * switches operacionais — sistema continua funcionando enquanto flag
 * não foi cadastrada (durante setup inicial).
 */
export async function isSubsystemEnabled(key: string): Promise<boolean> {
  const flags = await loadFlags();
  const flag = flags.get(key);
  if (!flag) return true;
  return flag.enabled === true;
}

export async function assertSubsystemEnabled(
  key: string,
  hint?: string,
): Promise<void> {
  if (!(await isSubsystemEnabled(key))) {
    throw new FeatureDisabledError(key, hint);
  }
}

/**
 * Helper para retornar response 503 padronizado quando uma rota é
 * bloqueada por kill switch. Use no catch:
 *
 *   try {
 *     await assertSubsystemEnabled("custody.deposits.enabled");
 *     // ...
 *   } catch (e) {
 *     if (e instanceof FeatureDisabledError) return featureDisabledResponse(e);
 *     throw e;
 *   }
 */
export function featureDisabledResponse(err: FeatureDisabledError): Response {
  return new Response(
    JSON.stringify({
      error: "Subsistema temporariamente indisponível",
      code: err.code,
      key: err.key,
      hint: err.hint ?? "Verifique status em /platform/feature-flags",
    }),
    {
      status: err.status,
      headers: {
        "Content-Type": "application/json",
        "Retry-After": "30",
      },
    },
  );
}
