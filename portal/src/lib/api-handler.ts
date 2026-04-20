/**
 * L17-01 — `withErrorHandler` é o **outermost** safety-net para todas as
 * rotas em `app/api/**` (e MUST-USE para todos os endpoints financeiros
 * críticos, ver `tools/check_financial_routes_have_error_handler.ts`).
 *
 * Responsabilidades:
 *   1. **Envelope canônico** (L14-05) — qualquer throw vira
 *      `{ ok:false, error:{ code, message, request_id } }` com status 500
 *      via `apiInternalError`, em vez de Next devolver o `{ statusCode:500,
 *      stack:"…" }` cru e vazar trace para o cliente.
 *   2. **request_id propagado** (L13-06) — o header `x-request-id` que
 *      entra na request também sai na response (sucesso ou erro). Quando
 *      ausente, geramos um `crypto.randomUUID()` e devolvemos no header da
 *      resposta de erro (success-path mantém comportamento do handler).
 *   3. **Observabilidade** — `logger.error` já encaminha para Sentry e
 *      anexa `trace_id`/`span_id` da span ativa (ver `lib/logger.ts`).
 *      Aqui só garantimos que o nome da rota + método entram nos `extra`,
 *      pra Sentry agrupar issues por endpoint, não por linha.
 *   4. **Forwarding correto do segundo argumento** — Next.js 13+ App
 *      Router passa `{ params: { ... } }` como segundo argumento para
 *      handlers em rotas dinâmicas (`[id]`, `[slug]`). Versões antigas
 *      desse arquivo tipavam o segundo arg como `Record<string, unknown>`
 *      e perdiam tipagem; agora propagamos `routeArgs` com `any` apenas
 *      no boundary, mas o handler interno preserva sua assinatura
 *      genérica `(req, ctx) => Promise<NextResponse>`.
 *   5. **errorMap opcional** — endpoints financeiros costumam capturar
 *      manualmente `SwapError`, `FxQuoteError`, `FeatureDisabledError`
 *      em try/catch interno. Isso continua valendo, mas o wrapper
 *      aceita um `errorMap` para mapear esses tipos de erro DIRETO
 *      para `apiError(...)` quando o handler escolher `throw`. Tornar
 *      o mapeamento opcional evita refator desnecessário das rotas que
 *      já fazem o catch inline.
 *
 * Uso típico:
 *
 * ```ts
 * import { withErrorHandler } from "@/lib/api-handler";
 *
 * export const POST = withErrorHandler(
 *   async (req: NextRequest) => {
 *     // ...lógica que pode throw...
 *     return NextResponse.json({ ok: true });
 *   },
 *   "api.swap.post",
 * );
 * ```
 *
 * Com errorMap:
 *
 * ```ts
 * export const POST = withErrorHandler(handler, "api.swap.post", {
 *   errorMap: (err, req) => {
 *     if (err instanceof SwapError) return swapErrorToResponse(req, err);
 *     return null; // fall-through para o 500 canônico
 *   },
 * });
 * ```
 */

import { NextRequest, NextResponse } from "next/server";
import * as Sentry from "@sentry/nextjs";

import { apiError } from "./api/errors";
import { logger } from "./logger";

export type ApiHandler = (
  req: NextRequest,
  context?: unknown,
) => Promise<NextResponse>;

/** Mapeia um erro lançado pelo handler para uma resposta HTTP custom.
 *  Retorne `null` para deixar o wrapper devolver o 500 canônico. */
export type ErrorMap = (
  err: unknown,
  req: NextRequest,
) => NextResponse | null | undefined;

export interface WithErrorHandlerOptions {
  /** Hook de mapeamento de erros de domínio antes do fallback 500. */
  errorMap?: ErrorMap;
  /** Mensagem custom para o 500 canônico. Default: `"Internal server error"`. */
  fallbackMessage?: string;
}

/**
 * Wraps a Next.js App-Router handler with logging, Sentry capture,
 * `x-request-id` propagation and a canonical 500 envelope.
 *
 * The second argument (`routeArgs`) is forwarded verbatim — Next.js
 * supplies `{ params }` for dynamic segments (`[id]`, `[slug]`).
 */
export function withErrorHandler<
  H extends (req: NextRequest, ...routeArgs: any[]) => Promise<NextResponse>,
>(handler: H, routeName: string, options?: WithErrorHandlerOptions): H {
  const fallbackMessage = options?.fallbackMessage ?? "Internal server error";

  const wrapped = async (
    req: NextRequest,
    ...routeArgs: any[]
  ): Promise<NextResponse> => {
    const incomingId = req.headers.get("x-request-id");
    const requestId = incomingId && incomingId.length > 0
      ? incomingId
      : crypto.randomUUID();

    // Tag the active Sentry span with the canonical route name so
    // discover queries (`route:api.swap.post`) work without grep.
    try {
      const span = Sentry.getActiveSpan();
      if (span) {
        span.setAttribute("omni.route", routeName);
        span.setAttribute("http.method", req.method);
      }
    } catch {
      // Sentry not initialised (tests, dev sem DSN) — no-op.
    }

    try {
      const result = await handler(req, ...routeArgs);
      // Best-effort: surface request_id on every successful response too.
      // We don't overwrite if the handler already set its own value.
      if (result && !result.headers.get("x-request-id")) {
        result.headers.set("x-request-id", requestId);
      }
      return result;
    } catch (error) {
      // Domain-error short-circuit (opt-in via options.errorMap).
      if (options?.errorMap) {
        try {
          const mapped = options.errorMap(error, req);
          if (mapped) {
            if (!mapped.headers.get("x-request-id")) {
              mapped.headers.set("x-request-id", requestId);
            }
            return mapped;
          }
        } catch (mapErr) {
          // errorMap itself threw — log and fall through to 500.
          logger.error(`API errorMap threw in ${routeName}`, mapErr, {
            requestId,
            originalError:
              error instanceof Error ? error.message : String(error),
          });
        }
      }

      logger.error(`API error in ${routeName}`, error, {
        requestId,
        method: req.method,
        url: req.nextUrl?.pathname ?? new URL(req.url).pathname,
        route: routeName,
      });

      // Build the canonical 500 envelope passing requestId explicitly so
      // both header and body carry the same value — important when we had
      // to *generate* one (apiError's default reads only from the request
      // headers and would emit `request_id: null`).
      const response = apiError(req, "INTERNAL_ERROR", fallbackMessage, 500, {
        requestId,
      });
      response.headers.set("x-request-id", requestId);
      return response;
    }
  };

  return wrapped as unknown as H;
}
