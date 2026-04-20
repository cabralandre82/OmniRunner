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
import {
  apiError,
  apiUnauthorized,
  apiForbidden,
} from "@/lib/api/errors";
import { withErrorHandler } from "@/lib/api-handler";

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
 *   400 — currency inválida (`UNSUPPORTED_CURRENCY`)
 *   401 — não autenticado (`UNAUTHORIZED`)
 *   403 — não é membro de nenhum grupo (`FORBIDDEN`)
 * Response 503:
 *   - `FX_QUOTE_MISSING` — sem cotação ativa
 *   - `FX_QUOTE_STALE`   — idade > 24h
 *   - `FX_QUOTE_UNAVAILABLE` — erro infra
 *
 * L14-05 — todas as respostas usam o envelope canônico
 *   `{ ok:false, error:{ code, message, request_id } }`.
 *   (Pré-L17-01 esta rota retornava `{ error:"string" }` legado e tinha
 *   um `throw err` cru no fim do catch que vazava stack trace.)
 *
 * L17-01 — `withErrorHandler` envelopa tudo: throws inesperados viram
 *   500 INTERNAL_ERROR canônico com Sentry capture e `x-request-id`.
 */
export const GET = withErrorHandler(_get, "api.custody.fx-quote.get");

async function _get(req: NextRequest) {
  const supabase = createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) {
    return apiUnauthorized(req);
  }

  const groupId = cookies().get("portal_group_id")?.value;
  if (!groupId) {
    return apiForbidden(req, "No portal group selected");
  }

  const db = createServiceClient();
  const { data: membership } = await db
    .from("coaching_members")
    .select("role")
    .eq("group_id", groupId)
    .eq("user_id", user.id)
    .maybeSingle();

  if (!membership) {
    return apiForbidden(req);
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
      return apiError(
        req,
        "UNSUPPORTED_CURRENCY",
        `Unsupported currency. Allowed: ${SUPPORTED_CURRENCIES.join(", ")}`,
        400,
        { details: { allowed: SUPPORTED_CURRENCIES } },
      );
    }
    if (err instanceof FxQuoteStaleError) {
      return apiError(req, "FX_QUOTE_STALE", err.message, 503);
    }
    if (err instanceof FxQuoteMissingError) {
      return apiError(req, "FX_QUOTE_MISSING", err.message, 503);
    }
    if (err instanceof FxQuoteError) {
      // Generic FX quote error — message preserved (already curated).
      return apiError(req, "FX_QUOTE_UNAVAILABLE", err.message, 503);
    }
    // Anything else: re-throw and let `withErrorHandler` produce a
    // sanitised 500 INTERNAL_ERROR (no leak of `err.message`).
    throw err;
  }
}
