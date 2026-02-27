import { createServiceClient } from "@/lib/supabase/service";

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
    await db.from("portal_audit_log").insert({
      actor_id: params.actorId,
      group_id: params.groupId ?? null,
      action: params.action,
      target_type: params.targetType ?? null,
      target_id: params.targetId ?? null,
      metadata: params.metadata ?? {},
    });
  } catch {
    // Audit must never block the user flow
  }
}
