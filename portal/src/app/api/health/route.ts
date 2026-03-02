import { createServiceClient } from "@/lib/supabase/service";
import { metrics } from "@/lib/metrics";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

export async function GET() {
  const start = Date.now();
  let dbOk = false;
  let invariantsOk = true;
  let invariantCount = 0;

  try {
    const db = createServiceClient();
    const { error } = await db.from("profiles").select("id").limit(1);
    dbOk = !error;

    if (dbOk) {
      const { data: violations } = await db.rpc("check_custody_invariants");
      invariantCount = violations?.length ?? 0;
      invariantsOk = invariantCount === 0;
    }
  } catch {
    dbOk = false;
  }

  const latencyMs = Date.now() - start;
  const allOk = dbOk && invariantsOk;

  metrics.timing("health.check.duration", latencyMs);
  metrics.gauge("health.db", dbOk ? 1 : 0);
  metrics.gauge("health.invariants", invariantsOk ? 1 : 0);
  if (invariantCount > 0) {
    metrics.gauge("health.invariant_violations", invariantCount);
  }

  return Response.json(
    {
      status: allOk ? "ok" : dbOk ? "degraded" : "down",
      ts: Date.now(),
      latencyMs,
      checks: {
        db: dbOk ? "connected" : "unreachable",
        invariants: invariantsOk ? "healthy" : `${invariantCount} violation(s)`,
      },
    },
    { status: allOk ? 200 : 503 },
  );
}
