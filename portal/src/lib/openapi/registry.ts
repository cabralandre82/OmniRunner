/**
 * Central OpenAPI registry (L14-01).
 *
 * Why this exists
 * ===============
 * Before this module, OpenAPI documentation lived in a hand-maintained
 * 1770-line `public/openapi.json`. New routes were rarely added to it
 * because:
 *
 *   - the cost of writing every schema by hand was high,
 *   - drift between code and docs was invisible (no CI gate),
 *   - there was no single source of truth — the Zod validation schema
 *     in the route handler and the JSON schema in openapi.json could
 *     and did diverge silently.
 *
 * The audit (L14-01, critical) found 30 of 76 route handlers
 * undocumented. The cure is contract-first generation: write the
 * schema once in Zod, register it with this registry, and have a CI
 * gate fail when the generated document drifts from the committed
 * snapshot.
 *
 * What this module does
 * ---------------------
 *   - Bootstraps `@asteasolutions/zod-to-openapi` exactly once
 *     (`extendZodWithOpenApi` mutates the Zod prototype — calling
 *     it twice is harmless but wasteful).
 *   - Exposes a single `registry` instance that route definitions
 *     register themselves against.
 *   - Defines shared component schemas (error envelope, paginated
 *     response, common scalar types) and registers them up-front so
 *     individual routes refer to them by `$ref` and we don't get
 *     duplicate definitions per endpoint.
 *
 * Out of scope (intentional)
 * --------------------------
 *   - Replacing the legacy hand-maintained `public/openapi.json`. We
 *     ship the new generator alongside. Existing v0 routes stay
 *     hand-documented for now; new routes (and the v1 aliases) flow
 *     through this registry. Migration is incremental.
 *   - Authoring schemas for all 30 currently-undocumented routes in
 *     a single PR. The registry framework + drift gate prevent the
 *     gap from growing; closing it is tracked as ongoing decrement.
 */

import {
  OpenAPIRegistry,
  extendZodWithOpenApi,
} from "@asteasolutions/zod-to-openapi";
import { z } from "zod";

// Idempotent — but we still want the call to happen at module-load
// time so that any consumer of this module gets `.openapi()` on
// Zod schemas without a separate setup step.
extendZodWithOpenApi(z);

/**
 * The single registry instance. Route definition modules import this,
 * register their endpoints, and the build script generates the final
 * document from it.
 */
export const registry = new OpenAPIRegistry();

// -- Shared component schemas ------------------------------------------------
//
// These are the building blocks that every endpoint reuses. Registering
// them as components (via `.openapi("Name")` then `registry.register`)
// makes the generated document terse: routes refer to `$ref:
// #/components/schemas/ApiErrorBody` instead of inlining the same
// object shape dozens of times.

/**
 * Canonical error envelope (matches `lib/api/errors.ts` exactly).
 * Every error response across the API conforms to this shape.
 */
export const ApiErrorBodySchema = z
  .object({
    ok: z.literal(false).openapi({
      description:
        "Discriminator. `false` for error responses; success responses use `true`.",
    }),
    error: z
      .object({
        code: z.string().openapi({
          description:
            "Machine-readable error code. See `lib/api/errors.ts` " +
            "→ `COMMON_ERROR_CODES` for the canonical set.",
          example: "VALIDATION_FAILED",
        }),
        message: z.string().openapi({
          description: "Human-readable error message (Portuguese).",
          example: "Body inválido.",
        }),
        request_id: z.string().openapi({
          description:
            "Request correlation ID. Same value as the `x-request-id` " +
            "response header (L13-06). Echo this when reporting bugs.",
          example: "9b7f3c5a-1f6d-4e0a-9d3a-1d2c0c8a7e9f",
        }),
        details: z
          .record(z.string(), z.unknown())
          .optional()
          .openapi({
            description:
              "Optional structured detail (e.g. Zod issue list, " +
              "FX-quote diagnostic, withdrawal lock status).",
          }),
      })
      .openapi({
        description:
          "Error envelope. The discriminator pair (`ok=false`, `error`) " +
          "is enforced by `apiError()`; clients can switch on `error.code`.",
      }),
  })
  .openapi("ApiErrorBody");
registry.register("ApiErrorBody", ApiErrorBodySchema);

/**
 * Canonical success envelope marker. Routes that return raw payloads
 * (e.g. `apiOk(data)`) merge `{ ok: true }` with the data object.
 * Used as a *component* primarily so its description is documented
 * once.
 */
export const ApiOkMarkerSchema = z
  .object({
    ok: z.literal(true).openapi({
      description:
        "Discriminator. `true` for success responses; error responses " +
        "use `false`.",
    }),
  })
  .openapi("ApiOkMarker");
registry.register("ApiOkMarker", ApiOkMarkerSchema);

/**
 * Cursor-paginated response shape (matches `lib/api/pagination.ts`
 * exactly). `T` is the item type — endpoints declare a concrete
 * paginated shape via `paginatedSchema(itemSchema)` rather than
 * referencing this generic directly.
 */
export const PaginatedEnvelopeShape = {
  ok: z.literal(true),
  items: z.array(z.unknown()).openapi({
    description: "Page of items in display order.",
  }),
  next_cursor: z
    .string()
    .nullable()
    .openapi({
      description:
        "Opaque cursor for the next page. `null` when there are no " +
        "more pages. Pass back as the `cursor` query parameter to " +
        "fetch the subsequent page.",
    }),
  has_more: z.boolean().openapi({
    description:
      "Whether more items are available beyond this page. Always " +
      "consistent with `next_cursor !== null`.",
  }),
} as const;

/**
 * Build a typed paginated-response Zod schema for a given item
 * schema. Use as:
 *
 *     const SwapOfferList = paginatedSchema(SwapOfferSchema)
 *       .openapi("SwapOfferList");
 */
export function paginatedSchema<T extends z.ZodTypeAny>(
  itemSchema: T,
): z.ZodObject<{
  ok: z.ZodLiteral<true>;
  items: z.ZodArray<T>;
  next_cursor: z.ZodNullable<z.ZodString>;
  has_more: z.ZodBoolean;
}> {
  return z.object({
    ok: PaginatedEnvelopeShape.ok,
    items: z.array(itemSchema),
    next_cursor: PaginatedEnvelopeShape.next_cursor,
    has_more: PaginatedEnvelopeShape.has_more,
  });
}

// -- Reusable scalar formats -------------------------------------------------

/**
 * Decimal monetary string. We always serialise money as a
 * `numeric(14,2)` string (BRL or USD with 2 fractional digits) to
 * avoid floating-point drift on the wire. Mirrors the convention
 * established by L01-04 / L01-05 (centralised money math).
 */
export const DecimalAmountSchema = z
  .string()
  .regex(/^-?\d{1,12}\.\d{2}$/, "must be a fixed-2 decimal string")
  .openapi("DecimalAmount", {
    description:
      "Money amount serialised as a fixed-2 decimal string (e.g. " +
      "`'1234.56'`). Never a JS `number` — see L01-04 for rationale.",
    example: "1500.00",
  });
registry.register("DecimalAmount", DecimalAmountSchema);

/**
 * Idempotency-Key header value. Issued by clients on POST requests
 * that mutate financial state (custody confirms, swap accepts).
 * Matches the validation in `/api/custody/route.ts`.
 */
export const IdempotencyKeySchema = z
  .string()
  .min(8)
  .max(128)
  .regex(/^[A-Za-z0-9._:-]+$/)
  .openapi("IdempotencyKey", {
    description:
      "Client-generated idempotency key (8-128 chars, alphanumeric " +
      "plus `._:-`). When the same key is replayed, the original " +
      "response is returned with `Idempotent-Replayed: true`.",
    example: "swap-accept-2026-04-17-001",
  });
registry.register("IdempotencyKey", IdempotencyKeySchema);

// -- Standard response builders ---------------------------------------------
//
// Every route ends up declaring 401, 403, 429, 500 with the same
// envelope. Centralising the response declarations keeps endpoint
// modules terse and uniform.

import type { ResponseConfig } from "@asteasolutions/zod-to-openapi";

const errorRef = { $ref: "#/components/schemas/ApiErrorBody" } as const;

export const STD_ERROR_RESPONSES: Record<
  401 | 403 | 422 | 429 | 500 | 503,
  ResponseConfig
> = {
  401: {
    description: "Unauthorized — no valid session.",
    content: { "application/json": { schema: errorRef } },
  },
  403: {
    description: "Forbidden — authenticated but not allowed.",
    content: { "application/json": { schema: errorRef } },
  },
  422: {
    description: "Validation failed — see `error.details`.",
    content: { "application/json": { schema: errorRef } },
  },
  429: {
    description:
      "Rate limited (L14-04 — keyed by group/user, not raw IP). " +
      "Honour the `Retry-After` header.",
    content: { "application/json": { schema: errorRef } },
    headers: {
      "Retry-After": {
        description: "Seconds until the next attempt is permitted.",
        schema: { type: "integer", minimum: 0 },
      } as never,
    },
  },
  500: {
    description: "Unexpected server error.",
    content: { "application/json": { schema: errorRef } },
  },
  503: {
    description: "Service unavailable (e.g. feature flag off).",
    content: { "application/json": { schema: errorRef } },
  },
};

/**
 * Common response headers emitted on every `/api/*` response by the
 * portal middleware (L13-06, L14-02). Documenting these once and
 * referencing them keeps endpoint definitions DRY.
 */
export const STD_API_HEADERS = {
  "x-request-id": {
    description:
      "Request correlation ID (L13-06). Echoed by error envelopes " +
      "as `error.request_id`.",
    schema: { type: "string", format: "uuid" } as const,
  },
  "x-api-version": {
    description: "API contract major version (L14-02).",
    schema: { type: "string", example: "1" } as const,
  },
} as const;
