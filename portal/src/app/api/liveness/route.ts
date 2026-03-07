import { createServiceClient } from "@/lib/supabase/service";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

export async function GET() {
  const start = Date.now();
  let dbOk = false;

  try {
    const db = createServiceClient();
    const { error } = await db.from("profiles").select("id").limit(1);
    dbOk = !error;
  } catch {
    dbOk = false;
  }

  return Response.json(
    { status: dbOk ? "ok" : "down", ts: Date.now(), latencyMs: Date.now() - start },
    { status: dbOk ? 200 : 503 },
  );
}
