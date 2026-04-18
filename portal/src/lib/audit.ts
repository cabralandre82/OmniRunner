import { createServiceClient } from "@/lib/supabase/service";
import { logger } from "@/lib/logger";
import { currentTraceId, currentSpanId, withSpan } from "@/lib/observability/tracing";

/**
 * Logs a portal action to portal_audit_log.
 * Fire-and-forget — never throws, never blocks the caller.
 *
 * L20-03 — auto-attaches `trace_id` + `span_id` to metadata when a span is
 * active, enabling post-incident pivot from a DB row to the Sentry trace
 * tree (impossible before this change). The trace_id is only set if NOT
 * already present in metadata (caller wins — useful for replays/backfills
 * that want to preserve original trace_id from a prior context).
 */
export async function auditLog(params: {
  actorId: string;
  groupId?: string;
  action: string;
  targetType?: string;
  targetId?: string;
  metadata?: Record<string, unknown>;
}): Promise<void> {
  const enrichedMetadata = enrichMetadataWithTrace(params.metadata);

  await withSpan(
    `audit ${params.action}`,
    "audit.write",
    async (setAttr) => {
      setAttr("omni.actor_id", params.actorId);
      setAttr("omni.group_id", params.groupId);
      setAttr("omni.action", params.action);
      try {
        const db = createServiceClient();
        const { error } = await db.from("portal_audit_log").insert({
          actor_id: params.actorId,
          group_id: params.groupId ?? null,
          action: params.action,
          target_type: params.targetType ?? null,
          target_id: params.targetId ?? null,
          metadata: enrichedMetadata,
        });
        if (error) {
          setAttr("audit.insert_error", error.message ?? "unknown");
          logger.error("AuditLog insert failed", error, {
            action: params.action,
            actorId: params.actorId,
          });
        }
      } catch (e) {
        logger.error("AuditLog unexpected error", e);
      }
    },
    { "omni.action": params.action },
  );
}

/**
 * If the caller didn't already set `trace_id`, append the active trace
 * context. Caller's value wins (e.g. a replay from a webhook may want to
 * reuse the original webhook trace_id, not the current one).
 */
function enrichMetadataWithTrace(
  metadata: Record<string, unknown> | undefined,
): Record<string, unknown> {
  const base = metadata ?? {};
  const traceId = currentTraceId();
  const spanId = currentSpanId();
  if (!traceId) return base;
  return {
    ...base,
    trace_id: base.trace_id ?? traceId,
    span_id: base.span_id ?? spanId,
  };
}
