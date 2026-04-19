import { createHash } from "node:crypto";

import { createServiceClient } from "@/lib/supabase/service";

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
  category?: FlagCategory;
  scope?: string;
}

/**
 * Lançada quando um caller chama `assertFeature` / `assertSubsystemEnabled`
 * e o flag está OFF. Route handlers devem capturar e responder 503 com
 * `Retry-After` adequado e mensagem orientando o admin.
 */
export class FeatureDisabledError extends Error {
  readonly code = "FEATURE_DISABLED" as const;
  readonly status = 503 as const;

  constructor(
    public readonly key: string,
    public readonly hint?: string,
  ) {
    super(`Feature disabled: ${key}${hint ? ` (${hint})` : ""}`);
    this.name = "FeatureDisabledError";
  }
}

let cachedFlags: Map<string, Flag> | null = null;
let lastFetchMs = 0;

// L18-06: TTL stratification.
//
//   • Default flags (product/experimental/banner/operational) cache for 60s
//     — admin tweaks are not time-critical and the load on `feature_flags`
//     is cheap, so we keep the original throughput.
//   • Kill switches cache for 5s — when an operator flips a critical
//     subsystem off (e.g. `custody.withdrawals.enabled`) we want every
//     serverless instance to honor it within ~5s, not within ~60s.
//
// `loadFlags()` chooses the effective TTL by inspecting the cached payload:
// if any cached flag has `category='kill_switch'`, the short TTL applies to
// the WHOLE refresh cycle (cheaper than two separate caches and avoids
// races between them). The same `setFeatureFlag()` call still
// `invalidateFeatureCache()`s on the writer instance, so a manual
// invalidation is always immediate locally.
const TTL_MS = 60_000;
const KILL_SWITCH_TTL_MS = 5_000;

/**
 * Limpa o cache. Chamado por testes e pelo route handler de mutação
 * de flag (para que admins vejam efeito imediato após toggle).
 */
export function invalidateFeatureCache(): void {
  cachedFlags = null;
  lastFetchMs = 0;
}

function effectiveTtlMs(flags: Map<string, Flag>): number {
  for (const flag of flags.values()) {
    if (flag.category === "kill_switch") return KILL_SWITCH_TTL_MS;
  }
  return TTL_MS;
}

async function loadFlags(): Promise<Map<string, Flag>> {
  const now = Date.now();
  if (cachedFlags && now - lastFetchMs < effectiveTtlMs(cachedFlags)) {
    return cachedFlags;
  }

  try {
    const supabase = createServiceClient();
    // Pedimos category/scope mas tratamos `null`/`undefined` para
    // backwards-compat com mock antigo de testes que só retorna 3 campos.
    const { data } = await supabase
      .from("feature_flags")
      .select("key, enabled, rollout_pct, category, scope")
      .order("key");

    const map = new Map<string, Flag>();
    for (const row of data ?? []) {
      // Resolução de scope: por enquanto só usamos 'global'. Se houver
      // duplicatas (key+scope diferentes), a última vence — admins devem
      // saber qual scope estão tocando.
      map.set(row.key, {
        key: row.key,
        enabled: row.enabled,
        rollout_pct: row.rollout_pct,
        category: (row.category as FlagCategory | undefined) ?? "product",
        scope: (row.scope as string | undefined) ?? "global",
      });
    }

    cachedFlags = map;
    lastFetchMs = now;
    return map;
  } catch {
    return cachedFlags ?? new Map();
  }
}

// L18-07: SHA-256-based bucketing.
//
// The previous implementation used a DJB2-style hash
// `(hash << 5) - hash + charCodeAt(i)` which is fast but not
// statistically uniform across short inputs (UUID prefix overlap creates
// visible bias when rollout_pct is far from 50). SHA-256 over
// `userId:key` is overkill cryptographically but produces an excellent
// uniform distribution for free; we read the first 4 bytes as an
// unsigned 32-bit integer and modulo 100.
//
// Caveat (documented for the runbook): switching the hash function is a
// one-time **re-randomisation** of every running A/B experiment — users
// previously in the "in" bucket may flip to "out" and vice-versa. For
// 50/50 splits this is invisible; for 90/10 it's a deliberate cost we
// accept in exchange for unbiased buckets going forward.
function userBucket(userId: string, key: string): number {
  const digest = createHash("sha256").update(`${userId}:${key}`).digest();
  return digest.readUInt32BE(0) % 100;
}

// Exported only for tests; internal helper.
export const __test_userBucket = userBucket;
export const __test_KILL_SWITCH_TTL_MS = KILL_SWITCH_TTL_MS;
export const __test_TTL_MS = TTL_MS;

/**
 * Boolean check com semântica de rollout por user. Mantém assinatura
 * histórica para retrocompat: se a flag não existe no DB, retorna `false`.
 *
 * Para checks operacionais de subsistema que devem fail-open quando flag
 * não está cadastrada (preservar operação durante setup), usar
 * `isSubsystemEnabled` ou `assertSubsystemEnabled`.
 */
export async function isFeatureEnabled(
  key: string,
  userId?: string,
): Promise<boolean> {
  const flags = await loadFlags();
  const flag = flags.get(key);

  if (!flag || !flag.enabled) return false;
  if (flag.rollout_pct >= 100) return true;
  if (flag.rollout_pct <= 0) return false;
  if (!userId) return false;

  return userBucket(userId, key) < flag.rollout_pct;
}

/**
 * L06-06 — check operacional de subsistema. Diferente de
 * `isFeatureEnabled`:
 *   - Retorna `true` se a flag NÃO existe no DB (fail-open — sistema
 *     opera normalmente quando feature_flags ainda não foi populada).
 *   - Ignora rollout_pct (kill switches são all-or-nothing).
 *
 * Use para o check no início de route handlers financeiros:
 *
 *   if (!(await isSubsystemEnabled("custody.withdrawals.enabled"))) ...
 */
export async function isSubsystemEnabled(key: string): Promise<boolean> {
  const flags = await loadFlags();
  const flag = flags.get(key);
  if (!flag) return true;
  return flag.enabled === true;
}

/**
 * L06-06 — versão com throw. Padrão para route handlers que querem
 * curto-circuito limpo:
 *
 *   try {
 *     await assertSubsystemEnabled("custody.withdrawals.enabled");
 *     // ... processa request
 *   } catch (e) {
 *     if (e instanceof FeatureDisabledError) {
 *       return NextResponse.json(
 *         { error: "Subsistema temporariamente indisponível", code: e.code },
 *         { status: e.status, headers: { "Retry-After": "30" } },
 *       );
 *     }
 *     throw e;
 *   }
 */
export async function assertSubsystemEnabled(
  key: string,
  hint?: string,
): Promise<void> {
  if (!(await isSubsystemEnabled(key))) {
    throw new FeatureDisabledError(key, hint);
  }
}

export async function getAllFlags(): Promise<Flag[]> {
  const flags = await loadFlags();
  return Array.from(flags.values());
}

/**
 * L06-06 — escrita auditada. Wrapper sobre o UPDATE direto que:
 *   • Sempre persiste `reason` (obrigatório — runbooks exigem).
 *   • Persiste `updated_by` (RLS usa para auditar).
 *   • Invalida o cache local — admins veem o efeito no próximo request.
 *
 * RLS exige profiles.platform_role='admin' OU service_role. Caller
 * é responsável por já ter feito esse check.
 */
export async function setFeatureFlag(input: {
  key: string;
  enabled: boolean;
  rollout_pct?: number;
  reason: string;
  updated_by?: string;
  scope?: string;
}): Promise<{ ok: true } | { ok: false; error: string }> {
  if (!input.reason || input.reason.trim().length < 3) {
    return { ok: false, error: "reason is required (min 3 chars)" };
  }

  const supabase = createServiceClient();
  const patch: Record<string, unknown> = {
    enabled: input.enabled,
    reason: input.reason,
    updated_at: new Date().toISOString(),
  };
  if (input.rollout_pct !== undefined) patch.rollout_pct = input.rollout_pct;
  if (input.updated_by) patch.updated_by = input.updated_by;

  const { error } = await supabase
    .from("feature_flags")
    .update(patch)
    .eq("key", input.key)
    .eq("scope", input.scope ?? "global");

  if (error) return { ok: false, error: error.message };

  invalidateFeatureCache();
  return { ok: true };
}
