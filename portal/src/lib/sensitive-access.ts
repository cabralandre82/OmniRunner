/**
 * L04-04 — helper para endpoints coach-facing que leem dados sensíveis
 * (saúde, biométrico, GPS) de atletas.
 *
 * Contexto auditoria:
 *   docs/audit/findings/L04-04-dados-de-saude-biometricos-dados-sensiveis-lgpd-art.md
 *   docs/audit/runbooks/L04-04-sensitive-health-data-protection.md
 *
 * Por quê:
 *   Endpoints server-side usam `createServiceClient()` (service_role) que
 *   BYPASSA RLS. A policy consent-gated (baselines_coach_consent_read etc.)
 *   só protege clients authenticated. Para respeitar LGPD Art. 11 em service
 *   role, cada caller DEVE:
 *     1. Checar consentimento via `fn_can_read_athlete_health`.
 *     2. Registrar a leitura via `fn_log_sensitive_access`.
 *     3. Fail-closed se atleta não consentiu — retornar mensagem específica
 *        para o coach ("atleta não autorizou compartilhamento").
 */
import type { SupabaseClient } from "@supabase/supabase-js";
import { logger } from "@/lib/logger";

export type SensitiveReadOutcome =
  | {
      ok: true;
      actor_role: "self" | "coach" | "assistant" | "admin_master";
    }
  | {
      ok: false;
      code: "CONSENT_REVOKED" | "NOT_AUTHORIZED";
      message: string;
    };

export interface EnsureCoachHealthAccessInput {
  db: SupabaseClient;
  actorId: string;
  athleteId: string;
  resource:
    | "sessions"
    | "runs"
    | "athlete_baselines"
    | "athlete_trends"
    | "coaching_athlete_kpis_daily"
    | "running_dna_profiles"
    | "athlete_health_snapshot"
    | "support_tickets";
  action?: "read" | "export" | "share";
  rowCountHint?: number | null;
  requestId?: string | null;
  ip?: string | null;
  userAgent?: string | null;
}

/**
 * Valida que o caller (coach/admin) pode ler dados sensíveis do atleta E
 * registra o acesso no log de auditoria. Retorna `ok=false` quando o atleta
 * revogou `coach_data_share` ou quando caller não está no mesmo grupo.
 *
 * Deve ser chamado ANTES de qualquer query direta em sessions/baselines/etc.
 * via service_role. Para clients authenticated a policy RLS já bloqueia, mas
 * chamar esta função também é recomendado para produzir audit log.
 */
export async function ensureCoachHealthAccess(
  input: EnsureCoachHealthAccessInput,
): Promise<SensitiveReadOutcome> {
  const {
    db,
    actorId,
    athleteId,
    resource,
    action = "read",
    rowCountHint = null,
    requestId = null,
    ip = null,
    userAgent = null,
  } = input;

  if (actorId === athleteId) {
    // Self-read sempre permitido; ainda assim logamos com actor_role=self.
    await logAccess({ db, resource, action, requestId, ip, userAgent, actorId, athleteId, denied: false, rowCountHint, reason: null });
    return { ok: true, actor_role: "self" };
  }

  const { data: canRead, error: checkErr } = await db.rpc("fn_can_read_athlete_health", {
    p_athlete_id: athleteId,
  });

  if (checkErr) {
    logger.error("ensureCoachHealthAccess: fn_can_read_athlete_health erro", {
      actorId, athleteId, resource, err: checkErr.message,
    });
    await logAccess({
      db, resource, action, requestId, ip, userAgent,
      actorId, athleteId, denied: true, rowCountHint,
      reason: "rpc_error",
    });
    return { ok: false, code: "NOT_AUTHORIZED", message: "Erro ao validar consentimento do atleta." };
  }

  if (!canRead) {
    await logAccess({
      db, resource, action, requestId, ip, userAgent,
      actorId, athleteId, denied: true, rowCountHint,
      reason: "missing_coach_data_share_consent",
    });
    return {
      ok: false,
      code: "CONSENT_REVOKED",
      message: "Atleta não autorizou compartilhamento de dados sensíveis com a assessoria.",
    };
  }

  const actorRole = await resolveActorRole(db, actorId, athleteId);
  await logAccess({
    db, resource, action, requestId, ip, userAgent,
    actorId, athleteId, denied: false, rowCountHint, reason: null,
  });
  return { ok: true, actor_role: actorRole };
}

interface LogAccessArgs {
  db: SupabaseClient;
  actorId: string;
  athleteId: string;
  resource: EnsureCoachHealthAccessInput["resource"];
  action: "read" | "export" | "share";
  requestId: string | null;
  ip: string | null;
  userAgent: string | null;
  rowCountHint: number | null;
  denied: boolean;
  reason: string | null;
}

async function logAccess(args: LogAccessArgs): Promise<void> {
  const { error } = await args.db.rpc("fn_log_sensitive_access", {
    p_subject_id: args.athleteId,
    p_resource: args.resource,
    p_action: args.action,
    p_row_count: args.rowCountHint,
    p_denied: args.denied,
    p_denial_reason: args.reason,
    p_request_id: args.requestId,
    p_ip: args.ip,
    p_user_agent: args.userAgent,
  });
  if (error) {
    logger.warn("ensureCoachHealthAccess: fn_log_sensitive_access falhou", {
      resource: args.resource, athleteId: args.athleteId, err: error.message,
    });
  }
}

async function resolveActorRole(
  db: SupabaseClient,
  actorId: string,
  athleteId: string,
): Promise<"coach" | "assistant" | "admin_master"> {
  const { data } = await db
    .from("coaching_members")
    .select("role, group_id")
    .eq("user_id", actorId)
    .in("role", ["coach", "assistant", "admin_master"])
    .limit(10);

  const actorGroups = new Set((data ?? []).map((r: { group_id: string }) => r.group_id));
  if (actorGroups.size === 0) return "coach";

  const { data: athMembers } = await db
    .from("coaching_members")
    .select("role, group_id")
    .eq("user_id", athleteId)
    .in("group_id", Array.from(actorGroups))
    .eq("role", "athlete")
    .limit(1);

  if (!athMembers || athMembers.length === 0) return "coach";

  const sharedGroup = athMembers[0].group_id;
  const actorRow = (data ?? []).find((r: { group_id: string }) => r.group_id === sharedGroup);
  return (actorRow?.role as "coach" | "assistant" | "admin_master") ?? "coach";
}
