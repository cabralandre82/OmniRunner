/**
 * L07-01 — i18n registry for API error codes.
 *
 * The HTTP contract (L14-05) guarantees that every error response
 * carries a machine-readable `error.code` in SCREAMING_SNAKE form
 * alongside the human `error.message`. Historically the portal
 * shipped pt-BR message strings server-side, which (a) leaked
 * Portuguese to English-speaking clients and (b) made the contract
 * "what does this code mean?" depend on reading route source code.
 *
 * This module is the single source of truth for the human-readable
 * copy behind each canonical error code. Server responses SHOULD
 * use the English variant (so Sentry / logs / partner integrations
 * are consistent). Clients that want localised UX call
 * {@link resolveErrorMessage} with their locale to render
 * translated copy.
 *
 * Contract:
 *   - codes are SCREAMING_SNAKE, exactly as they travel on the wire
 *   - at minimum each code has en + ptBR + es entries
 *   - any new code added anywhere in portal/src/app/api/** must be
 *     registered here, enforced by `npm run audit:api-error-i18n`
 *
 * Why English as the server default:
 *   - logs + dashboards + Sentry tags must be one canonical language
 *   - i18n is UX, not infra — rendering is the client's job
 *   - aligns with OpenAPI spec (L14-01) which ships English examples
 */

export type ErrorLocale = "en" | "ptBR" | "es";

export const ERROR_LOCALES: ReadonlyArray<ErrorLocale> = ["en", "ptBR", "es"];

export interface LocalisedMessage {
  en: string;
  ptBR: string;
  es: string;
}

/**
 * Canonical message registry. Keys are the `error.code` values
 * that travel on the wire.
 *
 * When adding a new entry:
 *   1. Use SCREAMING_SNAKE with no leading/trailing underscores.
 *   2. Keep the English copy short (≤ 80 chars) and actionable.
 *   3. ptBR and es should preserve the same information density
 *      (do not collapse details; better to expand than omit).
 *   4. Never put PII, IDs, or concrete numeric thresholds into the
 *      message — those belong in `error.details`.
 */
export const ERROR_MESSAGES: Record<string, LocalisedMessage> = {
  // ─── Cross-cutting (mirror COMMON_ERROR_CODES in errors.ts) ──────────────
  UNAUTHORIZED: {
    en: "Authentication required.",
    ptBR: "Autenticação necessária.",
    es: "Autenticación requerida.",
  },
  FORBIDDEN: {
    en: "You do not have permission to perform this action.",
    ptBR: "Você não tem permissão para executar esta ação.",
    es: "No tiene permiso para realizar esta acción.",
  },
  NOT_FOUND: {
    en: "Resource not found.",
    ptBR: "Recurso não encontrado.",
    es: "Recurso no encontrado.",
  },
  CONFLICT: {
    en: "The request conflicts with the current resource state.",
    ptBR: "A requisição conflita com o estado atual do recurso.",
    es: "La solicitud entra en conflicto con el estado actual del recurso.",
  },
  GONE: {
    en: "This resource is no longer available.",
    ptBR: "Este recurso não está mais disponível.",
    es: "Este recurso ya no está disponible.",
  },
  VALIDATION_FAILED: {
    en: "Request validation failed. See details.",
    ptBR: "Validação da requisição falhou. Veja detalhes.",
    es: "Validación de la solicitud falló. Consulte los detalles.",
  },
  BAD_REQUEST: {
    en: "Bad request.",
    ptBR: "Requisição inválida.",
    es: "Solicitud inválida.",
  },
  RATE_LIMITED: {
    en: "Too many requests. Retry after the indicated delay.",
    ptBR: "Requisições demais. Tente novamente após o intervalo indicado.",
    es: "Demasiadas solicitudes. Reintente después del intervalo indicado.",
  },
  INTERNAL_ERROR: {
    en: "Internal server error.",
    ptBR: "Erro interno do servidor.",
    es: "Error interno del servidor.",
  },
  SERVICE_UNAVAILABLE: {
    en: "Service is temporarily unavailable.",
    ptBR: "Serviço temporariamente indisponível.",
    es: "Servicio temporalmente no disponible.",
  },
  FEATURE_DISABLED: {
    en: "This feature is temporarily disabled by ops.",
    ptBR: "Esta funcionalidade está temporariamente desativada pelo time de ops.",
    es: "Esta funcionalidad está temporalmente desactivada por el equipo de ops.",
  },
  NO_GROUP_SESSION: {
    en: "No active group session. Pick a group and retry.",
    ptBR: "Nenhuma sessão de grupo ativa. Selecione um grupo e tente novamente.",
    es: "Sin sesión de grupo activa. Seleccione un grupo y reintente.",
  },

  // ─── Domain: coin distribution ───────────────────────────────────────────
  ATHLETE_NOT_FOUND: {
    en: "Athlete not found in this coaching group.",
    ptBR: "Atleta não encontrado nesta assessoria.",
    es: "Atleta no encontrado en esta asesoría.",
  },
  CUSTODY_FAILED: {
    en: "Insufficient custody backing. Top up custody before distributing.",
    ptBR: "Lastro insuficiente na custódia. Deposite lastro antes de distribuir.",
    es: "Respaldo de custodia insuficiente. Deposite respaldo antes de distribuir.",
  },
  CUSTODY_CONFIRM_FAILED: {
    en: "Custody deposit confirmation failed.",
    ptBR: "Confirmação do depósito de custódia falhou.",
    es: "Confirmación del depósito de custodia falló.",
  },
  WITHDRAWAL_FAILED: {
    en: "Withdrawal could not be processed. Retry later.",
    ptBR: "Saque não pôde ser processado. Tente novamente mais tarde.",
    es: "El retiro no pudo procesarse. Reintente más tarde.",
  },
  INVENTORY_INSUFFICIENT: {
    en: "Insufficient OmniCoin balance.",
    ptBR: "Saldo insuficiente de OmniCoins.",
    es: "Saldo insuficiente de OmniCoins.",
  },
  LOCK_NOT_AVAILABLE: {
    en: "Resource is locked, please retry in a moment.",
    ptBR: "Recurso em uso, tente novamente em instantes.",
    es: "Recurso en uso, reintente en unos instantes.",
  },

  // ─── Domain: swap / FX ───────────────────────────────────────────────────
  FX_QUOTE_MISSING: {
    en: "FX quote is missing for this swap.",
    ptBR: "Cotação de câmbio ausente para este swap.",
    es: "Cotización de cambio ausente para este swap.",
  },
  FX_QUOTE_STALE: {
    en: "FX quote is stale. Request a fresh quote.",
    ptBR: "Cotação de câmbio desatualizada. Solicite uma nova cotação.",
    es: "Cotización de cambio desactualizada. Solicite una nueva cotización.",
  },
  FX_QUOTE_UNAVAILABLE: {
    en: "FX quote provider is unavailable. Retry later.",
    ptBR: "Provedor de cotação de câmbio indisponível. Tente novamente mais tarde.",
    es: "Proveedor de cotización de cambio no disponible. Reintente más tarde.",
  },

  // ─── Domain: AI / integrations ───────────────────────────────────────────
  AI_NOT_CONFIGURED: {
    en: "AI provider is not configured.",
    ptBR: "Provedor de IA não está configurado.",
    es: "Proveedor de IA no está configurado.",
  },
  AI_API_ERROR: {
    en: "AI provider returned an error.",
    ptBR: "Provedor de IA retornou um erro.",
    es: "Proveedor de IA devolvió un error.",
  },
  AI_PARSE_ERROR: {
    en: "AI provider response could not be parsed.",
    ptBR: "Resposta do provedor de IA não pôde ser interpretada.",
    es: "La respuesta del proveedor de IA no pudo ser interpretada.",
  },
  AI_EMPTY_RESPONSE: {
    en: "AI provider returned an empty response.",
    ptBR: "Provedor de IA retornou resposta vazia.",
    es: "Proveedor de IA devolvió una respuesta vacía.",
  },

  // ─── Domain: pagination / query ──────────────────────────────────────────
  INVALID_CURSOR: {
    en: "Invalid pagination cursor.",
    ptBR: "Cursor de paginação inválido.",
    es: "Cursor de paginación inválido.",
  },
  INVALID_LIMIT: {
    en: "Invalid pagination limit.",
    ptBR: "Limite de paginação inválido.",
    es: "Límite de paginación inválido.",
  },
  INVALID_QUERY: {
    en: "Invalid query parameters.",
    ptBR: "Parâmetros de consulta inválidos.",
    es: "Parámetros de consulta inválidos.",
  },
  INVALID_STATUS: {
    en: "Invalid status value.",
    ptBR: "Valor de status inválido.",
    es: "Valor de estado inválido.",
  },

  // ─── Domain: training plans ──────────────────────────────────────────────
  WEEK_NOT_FOUND: {
    en: "Training plan week not found.",
    ptBR: "Semana do plano de treino não encontrada.",
    es: "Semana del plan de entrenamiento no encontrada.",
  },
  EMPTY_WEEK: {
    en: "Training plan week has no workouts.",
    ptBR: "Semana do plano de treino não tem workouts.",
    es: "La semana del plan de entrenamiento no tiene entrenamientos.",
  },
  NO_CHANGES: {
    en: "No changes to apply.",
    ptBR: "Nenhuma mudança para aplicar.",
    es: "Sin cambios para aplicar.",
  },
  TIME_IN_PAST: {
    en: "Requested time is in the past.",
    ptBR: "Horário solicitado está no passado.",
    es: "El horario solicitado está en el pasado.",
  },
  NO_GROUP: {
    en: "No group context provided.",
    ptBR: "Contexto de grupo não fornecido.",
    es: "Contexto de grupo no proporcionado.",
  },
  PRODUCT_INACTIVE: {
    en: "Product is not active.",
    ptBR: "Produto não está ativo.",
    es: "Producto no está activo.",
  },

  // ─── Domain: gateway / DB / infra ────────────────────────────────────────
  DB_ERROR: {
    en: "Database error. Retry later.",
    ptBR: "Erro de banco de dados. Tente novamente mais tarde.",
    es: "Error de base de datos. Reintente más tarde.",
  },
  GATEWAY_BAD_RESPONSE: {
    en: "Upstream gateway returned an unexpected response.",
    ptBR: "Gateway upstream retornou uma resposta inesperada.",
    es: "La pasarela upstream devolvió una respuesta inesperada.",
  },
  PAYLOAD_TOO_LARGE: {
    en: "Request payload is too large.",
    ptBR: "Payload da requisição é muito grande.",
    es: "El payload de la solicitud es demasiado grande.",
  },
  CRON_HEALTH_CHECK_FAILED: {
    en: "Scheduled job health check failed.",
    ptBR: "Verificação de saúde do job agendado falhou.",
    es: "Verificación de salud del trabajo programado falló.",
  },
  CRON_SLA_CHECK_FAILED: {
    en: "Scheduled job SLA check failed.",
    ptBR: "Verificação de SLA do job agendado falhou.",
    es: "Verificación de SLA del trabajo programado falló.",
  },
  INTEGRATION_HEALTH_FAILED: {
    en: "Integration health check failed.",
    ptBR: "Verificação de saúde da integração falhou.",
    es: "Verificación de salud de la integración falló.",
  },
  VALIDATION_ERROR: {
    en: "Validation error.",
    ptBR: "Erro de validação.",
    es: "Error de validación.",
  },
};

/**
 * Look up the localised message for an error code. Returns the
 * English entry when the locale is unknown or when the code is
 * not registered — the server always has an English fallback so
 * client rendering never blanks out on unseen codes.
 */
export function resolveErrorMessage(
  code: string,
  locale: ErrorLocale = "en",
): string {
  const entry = ERROR_MESSAGES[code];
  if (!entry) return code;
  const localeKey: ErrorLocale = ERROR_LOCALES.includes(locale) ? locale : "en";
  return entry[localeKey] ?? entry.en;
}

/**
 * Parse the `Accept-Language` header into one of our three
 * supported locales. Falls back to `en` when unknown.
 *
 * Acceptable inputs: `pt`, `pt-BR`, `pt-br`, `pt_BR`, `pt;q=0.8`,
 * `es`, `es-MX`, `es-AR`, `en`, `en-US`. Anything else → `en`.
 */
export function resolveClientLocale(
  acceptLanguageHeader: string | null | undefined,
): ErrorLocale {
  if (!acceptLanguageHeader) return "en";
  const raw = acceptLanguageHeader.split(",")[0]?.trim().toLowerCase() ?? "";
  if (raw.startsWith("pt")) return "ptBR";
  if (raw.startsWith("es")) return "es";
  return "en";
}

/**
 * List of codes currently registered. Exported for the CI guard
 * (`check-api-error-i18n.ts`) and for any consumer that wants to
 * iterate the contract.
 */
export const REGISTERED_ERROR_CODES: ReadonlyArray<string> =
  Object.keys(ERROR_MESSAGES);
