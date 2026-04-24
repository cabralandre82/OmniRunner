/**
 * L06-12 — `/api/liveness` is the trivial "is this lambda alive?"
 * probe used by load balancers to decide instance restart. We do
 * NOT touch downstream dependencies here — failure has high blast
 * radius (instance recycle) so we only fail when the process
 * itself is in trouble. Downstream-dep checks live in
 * `/api/readiness`.
 */

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

export async function GET() {
  return Response.json(
    { status: "ok", ts: Date.now() },
    { status: 200 },
  );
}
