/**
 * L01-02 — Server-side authoritative FX quote.
 *
 * Retorna a cotação oficial mantida em `public.platform_fx_quotes`. Portal NUNCA
 * aceita fx_rate vindo do cliente para operações financeiras (saque, deposit).
 *
 * Staleness: por padrão, cotações com mais de {@link MAX_QUOTE_AGE_SECONDS} são
 * rejeitadas com `FxQuoteStaleError`. O chamador deve retornar 503 e sinalizar
 * para o platform_admin refrescar em `/platform/fx`.
 *
 * Ref: docs/audit/findings/L01-02-post-api-custody-withdraw-criacao-e-execucao-de.md
 */

import { createServiceClient } from "@/lib/supabase/service";

export type SupportedCurrency = "BRL" | "EUR" | "GBP";

export const SUPPORTED_CURRENCIES: readonly SupportedCurrency[] = [
  "BRL",
  "EUR",
  "GBP",
] as const;

/**
 * Idade máxima (em segundos) que uma cotação pode ter antes de ser considerada
 * stale. 24h é conservador para uma plataforma B2B — cotações reais variam
 * alguns % em 24h mas evita bloquear operações por API de refresh offline.
 *
 * Override via `OMNI_FX_MAX_AGE_SECONDS` para testes/tuning.
 */
export const MAX_QUOTE_AGE_SECONDS = Number(
  process.env.OMNI_FX_MAX_AGE_SECONDS ?? 60 * 60 * 24,
);

export class FxQuoteError extends Error {
  constructor(
    message: string,
    public readonly code: "missing" | "stale" | "unsupported" | "db_error",
    public readonly detail?: unknown,
  ) {
    super(message);
    this.name = "FxQuoteError";
  }
}

export class FxQuoteMissingError extends FxQuoteError {
  constructor(currency: string) {
    super(
      `Nenhuma cotação ativa para ${currency} em platform_fx_quotes. ` +
        `platform_admin deve cadastrar/refrescar em /platform/fx.`,
      "missing",
      { currency },
    );
    this.name = "FxQuoteMissingError";
  }
}

export class FxQuoteStaleError extends FxQuoteError {
  constructor(currency: string, ageSeconds: number, maxAge: number) {
    super(
      `Cotação de ${currency} está stale (idade=${ageSeconds}s > max=${maxAge}s). ` +
        `platform_admin deve refrescar em /platform/fx antes de novas operações.`,
      "stale",
      { currency, ageSeconds, maxAge },
    );
    this.name = "FxQuoteStaleError";
  }
}

export class FxQuoteUnsupportedError extends FxQuoteError {
  constructor(currency: string) {
    super(
      `Moeda ${currency} não suportada. Moedas válidas: ${SUPPORTED_CURRENCIES.join(", ")}.`,
      "unsupported",
      { currency },
    );
    this.name = "FxQuoteUnsupportedError";
  }
}

export interface AuthoritativeFxQuote {
  currency: SupportedCurrency;
  rate: number;
  source: string;
  fetchedAt: string;
  ageSeconds: number;
}

function normalizeCurrency(input: string): SupportedCurrency {
  const upper = input.trim().toUpperCase();
  if ((SUPPORTED_CURRENCIES as readonly string[]).includes(upper)) {
    return upper as SupportedCurrency;
  }
  throw new FxQuoteUnsupportedError(input);
}

/**
 * Busca a cotação autoritativa para uma moeda.
 *
 * @throws FxQuoteUnsupportedError — moeda fora de {@link SUPPORTED_CURRENCIES}.
 * @throws FxQuoteMissingError — nenhum registro ativo em platform_fx_quotes.
 * @throws FxQuoteStaleError — idade acima do limite (default 24h).
 * @throws FxQuoteError('db_error') — erro de infra (Postgres down, RPC quebrada).
 */
export async function getAuthoritativeFxQuote(
  rawCurrency: string,
  opts: { maxAgeSeconds?: number } = {},
): Promise<AuthoritativeFxQuote> {
  const currency = normalizeCurrency(rawCurrency);
  const maxAge = opts.maxAgeSeconds ?? MAX_QUOTE_AGE_SECONDS;

  const db = createServiceClient();
  const { data, error } = await db.rpc("get_latest_fx_quote", {
    p_currency: currency,
  });

  if (error) {
    throw new FxQuoteError(
      `Erro ao buscar fx quote para ${currency}: ${error.message}`,
      "db_error",
      error,
    );
  }

  const row = Array.isArray(data) ? data[0] : data;
  if (!row || row.rate_per_usd == null) {
    throw new FxQuoteMissingError(currency);
  }

  const rate = Number(row.rate_per_usd);
  const ageSeconds = Number(row.age_seconds ?? 0);
  const fetchedAt = row.fetched_at ?? new Date().toISOString();
  const source = row.source ?? "unknown";

  if (!Number.isFinite(rate) || rate <= 0) {
    // L01-02 defesa em profundidade: mesmo que o CHECK no DB falhe, rejeitamos.
    throw new FxQuoteError(
      `Rate inválido em platform_fx_quotes para ${currency}: ${rate}`,
      "db_error",
      { rate },
    );
  }

  if (ageSeconds > maxAge) {
    throw new FxQuoteStaleError(currency, ageSeconds, maxAge);
  }

  return { currency, rate, source, fetchedAt, ageSeconds };
}

/**
 * Versão "safe" que retorna null em vez de throw quando não há cotação disponível.
 * Útil para UIs que apenas exibem o rate como informação (não executam operação).
 */
export async function tryGetAuthoritativeFxQuote(
  rawCurrency: string,
  opts: { maxAgeSeconds?: number } = {},
): Promise<AuthoritativeFxQuote | null> {
  try {
    return await getAuthoritativeFxQuote(rawCurrency, opts);
  } catch (err) {
    if (err instanceof FxQuoteError) return null;
    throw err;
  }
}
