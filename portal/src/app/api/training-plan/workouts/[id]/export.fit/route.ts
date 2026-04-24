import { NextResponse } from "next/server";
import { cookies } from "next/headers";
import { createClient } from "@/lib/supabase/server";
import { rateLimit } from "@/lib/rate-limit";
import { logger } from "@/lib/logger";
import { auditLog } from "@/lib/audit";

// L05-25 — Coach-facing export .fit direto do portal.
//
// Proxy para a Edge Function `generate-fit-workout`, que é a mesma usada
// pelo app do atleta. Autorização dupla:
//   1. Next.js valida session + membership (group_id, role coach/admin).
//   2. Edge Function revalida via RLS com o JWT do coach.
//
// Retorna application/octet-stream com Content-Disposition attachment,
// pronto para o browser baixar via <a href>.
export const dynamic = "force-dynamic";

export async function GET(
  _req: Request,
  { params }: { params: { id: string } },
) {
  const supabase = createClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const rl = await rateLimit(`export-fit:${user.id}`, {
    maxRequests: 10,
    windowMs: 60_000,
  });
  if (!rl.allowed) {
    return NextResponse.json(
      { error: "Too many requests" },
      { status: 429 },
    );
  }

  const groupId = cookies().get("portal_group_id")?.value;
  if (!groupId) {
    return NextResponse.json({ error: "No group" }, { status: 400 });
  }

  const { data: membership } = await supabase
    .from("coaching_members")
    .select("role")
    .eq("group_id", groupId)
    .eq("user_id", user.id)
    .maybeSingle();

  if (
    !membership ||
    !["admin_master", "coach", "assistant"].includes(
      (membership as { role: string }).role,
    )
  ) {
    return NextResponse.json({ error: "Forbidden" }, { status: 403 });
  }

  const { data: template } = await supabase
    .from("coaching_workout_templates")
    .select("id, name")
    .eq("id", params.id)
    .eq("group_id", groupId)
    .maybeSingle();

  if (!template) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }

  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  if (!supabaseUrl || !anonKey) {
    logger.error("export.fit missing SUPABASE env", {
      hasUrl: !!supabaseUrl,
      hasKey: !!anonKey,
    });
    return NextResponse.json(
      { error: "Configuração ausente" },
      { status: 500 },
    );
  }

  const edgeUrl = `${supabaseUrl}/functions/v1/generate-fit-workout`;

  let edgeRes: Response;
  try {
    edgeRes = await fetch(edgeUrl, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${session.access_token}`,
        apikey: anonKey,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        template_id: params.id,
        // L05-26 — tells the Edge Function to tag the export log with the
        // portal surface, so the coach's manual smoke-tests don't get
        // confused with athlete-initiated exports in the assignments page.
        surface: "portal",
      }),
    });
  } catch (err) {
    logger.error("export.fit edge call failed", {
      templateId: params.id,
      err: err instanceof Error ? err.message : String(err),
    });
    return NextResponse.json(
      { error: "Edge function inatingível" },
      { status: 502 },
    );
  }

  if (!edgeRes.ok) {
    const text = await edgeRes.text().catch(() => "");
    logger.error("export.fit edge function returned non-2xx", {
      status: edgeRes.status,
      body: text.slice(0, 200),
      templateId: params.id,
    });
    return NextResponse.json(
      {
        error: "Falha ao gerar arquivo .fit",
        detail: text.slice(0, 200),
      },
      { status: 502 },
    );
  }

  const bytes = await edgeRes.arrayBuffer();

  const templateName = (template as { name: string }).name;
  const safeFilename =
    templateName
      .replace(/[^a-zA-Z0-9_\- ]/g, "")
      .replace(/\s+/g, "_")
      .substring(0, 50) || "workout";

  await auditLog({
    actorId: user.id,
    groupId,
    action: "workout.export_fit",
    metadata: { template_id: params.id, bytes: bytes.byteLength },
  });

  return new NextResponse(bytes, {
    status: 200,
    headers: {
      "Content-Type": "application/octet-stream",
      "Content-Disposition": `attachment; filename="${safeFilename}.fit"`,
      "Cache-Control": "no-store",
    },
  });
}
