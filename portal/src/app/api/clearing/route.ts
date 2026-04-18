import { NextRequest, NextResponse } from "next/server";
import { cookies } from "next/headers";
import { createClient } from "@/lib/supabase/server";
import { createServiceClient } from "@/lib/supabase/service";
import { getSettlementsForGroup } from "@/lib/clearing";
import { rateLimit } from "@/lib/rate-limit";
import { logger } from "@/lib/logger";
import {
  apiError,
  apiUnauthorized,
  apiForbidden,
  apiRateLimited,
  apiInternalError,
} from "@/lib/api/errors";
import { rateLimitKey } from "@/lib/api/rate-limit-key";

type ClearingAuthError =
  | { error: "Não autorizado"; status: 401 }
  | { error: "Grupo não selecionado"; status: 400 }
  | { error: "Sem permissão"; status: 403 };

async function requireStaff(): Promise<
  ClearingAuthError | { user: { id: string }; groupId: string }
> {
  const supabase = createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) return { error: "Não autorizado", status: 401 } as const;

  const groupId = cookies().get("portal_group_id")?.value;
  if (!groupId) return { error: "Grupo não selecionado", status: 400 } as const;

  const db = createServiceClient();
  const { data: callerMembership } = await db
    .from("coaching_members")
    .select("role")
    .eq("group_id", groupId)
    .eq("user_id", user.id)
    .maybeSingle();

  if (
    !callerMembership ||
    !["admin_master", "coach"].includes(
      (callerMembership as { role: string }).role
    )
  ) {
    return { error: "Sem permissão", status: 403 } as const;
  }

  return { user, groupId } as const;
}

function authErrorResponse(
  req: NextRequest | null,
  err: ClearingAuthError,
): NextResponse {
  switch (err.status) {
    case 401:
      return apiUnauthorized(req, err.error);
    case 400:
      return apiError(req, "NO_GROUP_SESSION", err.error, 400);
    case 403:
      return apiForbidden(req, err.error);
  }
}

export async function GET(req: NextRequest) {
  try {
    // L14-04 — bucket por grupo (cookie) com fallback para hashed-IP.
    const cookieGroupId = cookies().get("portal_group_id")?.value ?? null;
    const rl = await rateLimit(
      rateLimitKey({ prefix: "clearing", groupId: cookieGroupId, request: req }),
      { maxRequests: 30, windowMs: 60_000 },
    );
    if (!rl.allowed) {
      const retryAfter = Math.ceil((rl.resetAt - Date.now()) / 1000);
      return apiRateLimited(req, retryAfter);
    }

    const auth = await requireStaff();
    if ("error" in auth) return authErrorResponse(req, auth);

    const role =
      (req.nextUrl.searchParams.get("role") as "creditor" | "debtor") || "both";

    const settlements = await getSettlementsForGroup(auth.groupId, role);
    return NextResponse.json({ settlements });
  } catch (error) {
    logger.error("Failed to fetch clearing settlements", error);
    return apiInternalError(req, "Erro interno");
  }
}
