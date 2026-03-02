import { createServiceClient } from "@/lib/supabase/service";
import { logger } from "@/lib/logger";

/**
 * Logs a portal action to portal_audit_log.
 * Fire-and-forget — never throws, never blocks the caller.
 */
export async function auditLog(params: {
  actorId: string;
  groupId?: string;
  action: string;
  targetType?: string;
  targetId?: string;
  metadata?: Record<string, unknown>;
}): Promise<void> {
  try {
    const db = createServiceClient();
    const { error } = await db.from("portal_audit_log").insert({
      actor_id: params.actorId,
      group_id: params.groupId ?? null,
      action: params.action,
      target_type: params.targetType ?? null,
      target_id: params.targetId ?? null,
      metadata: params.metadata ?? {},
    });
    if (error) {
      logger.error("AuditLog insert failed", error, {
        action: params.action,
        actorId: params.actorId,
      });
    }
  } catch (e) {
    logger.error("AuditLog unexpected error", e);
  }
}
