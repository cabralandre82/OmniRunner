import { NextRequest, NextResponse } from "next/server";
import { cookies } from "next/headers";
import { createClient } from "@/lib/supabase/server";
import { createServiceClient } from "@/lib/supabase/service";
import {
  getAuthoritativeFxQuote,
  SUPPORTED_CURRENCIES,
  FxQuoteError,
  FxQuoteMissingError,
  FxQuoteStaleError,
  FxQuoteUnsupportedError,
} from "@/lib/fx/quote";

/**
 * GET /api/custody/fx-quote?currency=BRL
 *
 * L01-02: retorna a cotação autoritativa mantida em `platform_fx_quotes` para
 * exibição read-only no UI (formulário de saque, simulador FX, dashboard).
 *
 * Authz: qualquer membro autenticado de um grupo (coaching_members) pode ler —
 * cotação é pública do ponto de vista financeiro (já exposta em extratos).
 *
 * Response 200:
 *   { currency, rate, source, fetched_at, age_seconds }
 * Response 4xx:
 *   400 — currency inválida
 *   401 — não autenticado
 *   403 — não é membro de nenhum grupo (sem portal_group_id)
 * Response 503:
 *   - missing — sem cotação ativa
 *   - stale   — idade > 24h
 *   - db_error — erro infra
 */
export async function GET(req: NextRequest) {
  const supabase = createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const groupId = cookies().get("portal_group_id")?.value;
  if (!groupId) {
    return NextResponse.json({ error: "No group" }, { status: 403 });
  }

  const db = createServiceClient();
  const { data: membership } = await db
    .from("coaching_members")
    .select("role")
    .eq("group_id", groupId)
    .eq("user_id", user.id)
    .maybeSingle();

  if (!membership) {
    return NextResponse.json({ error: "Forbidden" }, { status: 403 });
  }

  const currencyParam =
    new URL(req.url).searchParams.get("currency") ?? "BRL";

  try {
    const quote = await getAuthoritativeFxQuote(currencyParam);
    return NextResponse.json(
      {
        currency: quote.currency,
        rate: quote.rate,
        source: quote.source,
        fetched_at: quote.fetchedAt,
        age_seconds: quote.ageSeconds,
      },
      {
        headers: {
          "Cache-Control": "private, max-age=60, stale-while-revalidate=30",
        },
      },
    );
  } catch (err) {
    if (err instanceof FxQuoteUnsupportedError) {
      return NextResponse.json(
        {
          error: "Unsupported currency",
          detail: `Válidas: ${SUPPORTED_CURRENCIES.join(", ")}`,
          code: err.code,
        },
        { status: 400 },
      );
    }
    if (err instanceof FxQuoteMissingError || err instanceof FxQuoteStaleError) {
      return NextResponse.json(
        {
          error: err.code === "stale" ? "FX quote stale" : "FX quote missing",
          detail: err.message,
          code: err.code,
        },
        { status: 503 },
      );
    }
    if (err instanceof FxQuoteError) {
      return NextResponse.json(
        { error: "FX quote unavailable", code: err.code },
        { status: 503 },
      );
    }
    throw err;
  }
}
