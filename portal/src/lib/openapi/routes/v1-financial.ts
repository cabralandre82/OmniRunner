/**
 * OpenAPI definitions for the v1 financial API surface (L14-01 + L14-02).
 *
 * These are the **canonical exemplars** of the new contract-first
 * pattern: every schema below is the same Zod type the route handler
 * uses for runtime validation. There is no separate JSON-schema copy
 * to drift from.
 *
 * Conventions:
 *
 *   - Request bodies/queries reuse the validation schemas from the
 *     route module (or `lib/schemas.ts`) directly, decorated with
 *     `.openapi({ description })`.
 *   - Responses use `paginatedSchema(...)` / `apiOk` markers from
 *     `registry.ts` so they're consistent across endpoints.
 *   - Every endpoint declares the standard `STD_ERROR_RESPONSES`
 *     for 401/403/422/429/500/503 — financial routes never deviate.
 *   - The `tags` are mirrored from the legacy hand-maintained
 *     `public/openapi.json` so Swagger UI shows the v1 endpoints
 *     alongside their v0 counterparts under the same headings.
 */

import { z } from "zod";
import {
  registry,
  STD_ERROR_RESPONSES,
  STD_API_HEADERS,
  ApiOkMarkerSchema,
  IdempotencyKeySchema,
} from "../registry";

// -- Domain schemas ---------------------------------------------------------

/**
 * Swap action discriminated union — mirrors the validation in
 * `app/api/swap/route.ts`. Kept inline here (not imported from the
 * route file) because route files transitively pull in next/server +
 * supabase + redis, which we don't want loading at OpenAPI build
 * time. The two definitions MUST stay in sync; the runtime is the
 * source of truth.
 */
const SwapCreateBody = z
  .object({
    action: z.literal("create"),
    amount_usd: z.number().min(100).max(500_000).openapi({
      description: "Amount of USD to offer for swap.",
      example: 1500,
    }),
    expires_in_days: z.union([
      z.literal(1),
      z.literal(7),
      z.literal(30),
      z.literal(90),
    ]).optional().openapi({
      description:
        "TTL in days (1, 7, 30, or 90). Defaults to 7 if omitted.",
    }),
  })
  .openapi("SwapCreateBody");

const SwapAcceptBody = z
  .object({
    action: z.literal("accept"),
    order_id: z.string().uuid().openapi({
      description: "ID of the swap offer to accept.",
    }),
    external_payment_ref: z
      .string()
      .min(8)
      .max(128)
      .optional()
      .openapi({
        description:
          "Optional reference to off-platform payment (e.g. PIX " +
          "transaction ID). Logged for CFO review when present.",
      }),
  })
  .openapi("SwapAcceptBody");

const SwapCancelBody = z
  .object({
    action: z.literal("cancel"),
    order_id: z.string().uuid(),
  })
  .openapi("SwapCancelBody");

const SwapBody = z
  .union([SwapCreateBody, SwapAcceptBody, SwapCancelBody])
  .openapi("SwapBody", {
    description:
      "Discriminated union over `action`. Each variant has its own " +
      "required fields.",
  });

const SwapOffer = z
  .object({
    id: z.string().uuid(),
    amount_usd: z.number(),
    status: z.enum(["open", "accepted", "cancelled", "expired"]),
    creator_user_id: z.string().uuid(),
    expires_at: z.string().datetime(),
  })
  .openapi("SwapOffer");

const SwapListResponse = ApiOkMarkerSchema.extend({
  offers: z.array(SwapOffer),
}).openapi("SwapListResponse");

// -- Custody ----------------------------------------------------------------

const CustodyAccount = z
  .object({
    group_id: z.string().uuid(),
    balance_usd: z.string().openapi({ example: "1500.00" }),
    backing_usd: z.string().openapi({ example: "1500.00" }),
  })
  .openapi("CustodyAccount");

const CustodyConfirmBody = z
  .object({
    deposit_id: z.string().uuid(),
  })
  .openapi("CustodyConfirmBody");

const CustodyAccountResponse = ApiOkMarkerSchema.extend({
  account: CustodyAccount,
}).openapi("CustodyAccountResponse");

// -- Withdraw ---------------------------------------------------------------

const WithdrawBody = z
  .object({
    amount_usd: z.number().min(1).max(1_000_000),
    target_currency: z
      .enum(["BRL", "EUR", "GBP"])
      .default("BRL")
      .openapi({
        description:
          "Local currency for the payout. Determines which FX quote " +
          "is fetched server-side.",
      }),
    provider_fee_usd: z.number().min(0).optional().openapi({
      description:
        "Optional provider fee in USD (e.g. wire fee from the BaaS).",
    }),
  })
  .openapi("WithdrawBody");

const Withdrawal = z
  .object({
    id: z.string().uuid(),
    amount_usd: z.number(),
    target_currency: z.enum(["BRL", "EUR", "GBP"]),
    fx_rate: z.string(),
    payout_local: z.string(),
    status: z.enum(["pending", "executed", "failed", "cancelled"]),
    created_at: z.string().datetime(),
  })
  .openapi("Withdrawal");

const WithdrawalListResponse = ApiOkMarkerSchema.extend({
  withdrawals: z.array(Withdrawal),
}).openapi("WithdrawalListResponse");

// -- Distribute Coins -------------------------------------------------------

const DistributeCoinsBody = z
  .object({
    athlete_user_id: z.string().uuid().openapi({
      description: "Athlete (auth.users.id) receiving the coins.",
    }),
    amount: z.number().int().min(1).max(100_000).openapi({
      description:
        "Amount of coins to mint (integer, 1-100 000). Cap raised " +
        "from the legacy 1 000 by L05-03 to fit weekly bonus " +
        "distributions for medium clubs.",
    }),
  })
  .openapi("DistributeCoinsBody");

const DistributeCoinsResponse = ApiOkMarkerSchema.extend({
  ledger_entry_id: z.string().uuid(),
  athlete_user_id: z.string().uuid(),
  amount: z.number().int(),
}).openapi("DistributeCoinsResponse");

// -- Distribute Coins (Batch) — L05-03 --------------------------------------

const DistributeCoinsBatchItem = z
  .object({
    athlete_user_id: z.string().uuid().openapi({
      description: "Athlete (auth.users.id) receiving this slice.",
    }),
    amount: z.number().int().min(1).max(100_000).openapi({
      description: "Amount of coins for this athlete (1-100 000).",
    }),
  })
  .openapi("DistributeCoinsBatchItem");

const DistributeCoinsBatchBody = z
  .object({
    items: z
      .array(DistributeCoinsBatchItem)
      .min(1)
      .max(200)
      .openapi({
        description:
          "1-200 athlete slices, total Σ amount ≤ 1 000 000. Duplicate " +
          "athlete_user_id is rejected.",
      }),
    ref_id: z
      .string()
      .min(8)
      .max(128)
      .optional()
      .openapi({
        description:
          "Optional explicit batch reference. Falls back to " +
          "`x-idempotency-key` header or a derived value. " +
          "Used to derive deterministic per-item ref_ids.",
      }),
  })
  .openapi("DistributeCoinsBatchBody");

const DistributeCoinsBatchItemResult = z
  .object({
    athlete_user_id: z.string().uuid(),
    amount: z.number().int(),
    new_balance: z.number().int().nullable(),
    was_idempotent: z.boolean(),
    ledger_id: z.string().uuid().nullable(),
  })
  .openapi("DistributeCoinsBatchItemResult");

const DistributeCoinsBatchResponse = ApiOkMarkerSchema.extend({
  batch_ref_id: z.string(),
  total_amount: z.number().int(),
  total_distributions: z.number().int(),
  batch_was_idempotent: z.boolean(),
  items: z.array(DistributeCoinsBatchItemResult),
}).openapi("DistributeCoinsBatchResponse");

// -- Clearing ---------------------------------------------------------------

const Settlement = z
  .object({
    id: z.string().uuid(),
    creditor_group_id: z.string().uuid(),
    debtor_group_id: z.string().uuid(),
    amount_usd: z.string(),
    settled_at: z.string().datetime().nullable(),
  })
  .openapi("Settlement");

const ClearingResponse = ApiOkMarkerSchema.extend({
  settlements: z.array(Settlement),
}).openapi("ClearingResponse");

// -- Path registrations -----------------------------------------------------

registry.registerPath({
  method: "get",
  path: "/api/v1/swap",
  tags: ["OmniCoins"],
  summary: "List open swap offers for the current group",
  description:
    "Lists all swap offers for the current portal group. Requires " +
    "`admin_master` role on the group. Rate-limited at 30 req/min " +
    "per group (L14-04).",
  responses: {
    200: {
      description: "Open offers for the current group.",
      content: { "application/json": { schema: SwapListResponse } },
      headers: STD_API_HEADERS,
    },
    400: {
      description: "No portal group selected.",
      content: {
        "application/json": {
          schema: { $ref: "#/components/schemas/ApiErrorBody" },
        },
      },
    },
    401: STD_ERROR_RESPONSES[401],
    403: STD_ERROR_RESPONSES[403],
    429: STD_ERROR_RESPONSES[429],
    500: STD_ERROR_RESPONSES[500],
  },
});

registry.registerPath({
  method: "post",
  path: "/api/v1/swap",
  tags: ["OmniCoins"],
  summary: "Create, accept, or cancel a swap offer",
  description:
    "Discriminated by the `action` field. `create` opens a new " +
    "offer; `accept` settles an existing offer; `cancel` closes one " +
    "the caller owns. Rate-limited at 10 req/min per group.",
  request: {
    body: {
      required: true,
      content: { "application/json": { schema: SwapBody } },
    },
  },
  responses: {
    200: {
      description: "Action succeeded; updated offer returned.",
      content: { "application/json": { schema: SwapOffer } },
    },
    400: {
      description: "Validation failed or no group selected.",
      content: {
        "application/json": {
          schema: { $ref: "#/components/schemas/ApiErrorBody" },
        },
      },
    },
    401: STD_ERROR_RESPONSES[401],
    403: STD_ERROR_RESPONSES[403],
    409: {
      description: "Swap not in `open` state.",
      content: {
        "application/json": {
          schema: { $ref: "#/components/schemas/ApiErrorBody" },
        },
      },
    },
    410: {
      description: "Swap expired (TTL past, see L05-02).",
      content: {
        "application/json": {
          schema: { $ref: "#/components/schemas/ApiErrorBody" },
        },
      },
    },
    422: STD_ERROR_RESPONSES[422],
    429: STD_ERROR_RESPONSES[429],
    503: STD_ERROR_RESPONSES[503],
  },
});

registry.registerPath({
  method: "get",
  path: "/api/v1/custody",
  tags: ["OmniCoins"],
  summary: "Read the custody account for the current group",
  description:
    "Returns the custody account snapshot (balance + backing). " +
    "Used by the dashboard to render the funds widget.",
  responses: {
    200: {
      description: "Custody account snapshot.",
      content: {
        "application/json": { schema: CustodyAccountResponse },
      },
      headers: STD_API_HEADERS,
    },
    401: STD_ERROR_RESPONSES[401],
    403: STD_ERROR_RESPONSES[403],
    500: STD_ERROR_RESPONSES[500],
  },
});

registry.registerPath({
  method: "post",
  path: "/api/v1/custody",
  tags: ["OmniCoins"],
  summary: "Confirm a custody deposit",
  description:
    "Confirms a deposit by ID. The `Idempotency-Key` header is " +
    "REQUIRED — replays return the original response with " +
    "`Idempotent-Replayed: true`.",
  request: {
    headers: z.object({
      "idempotency-key": IdempotencyKeySchema,
    }),
    body: {
      required: true,
      content: { "application/json": { schema: CustodyConfirmBody } },
    },
  },
  responses: {
    200: {
      description: "Deposit confirmed.",
      content: { "application/json": { schema: ApiOkMarkerSchema } },
    },
    400: STD_ERROR_RESPONSES[422],
    401: STD_ERROR_RESPONSES[401],
    403: STD_ERROR_RESPONSES[403],
    422: STD_ERROR_RESPONSES[422],
    429: STD_ERROR_RESPONSES[429],
    500: STD_ERROR_RESPONSES[500],
  },
});

registry.registerPath({
  method: "get",
  path: "/api/v1/custody/withdraw",
  tags: ["OmniCoins"],
  summary: "List withdrawals for the current group",
  responses: {
    200: {
      description: "Withdrawal history.",
      content: {
        "application/json": { schema: WithdrawalListResponse },
      },
      headers: STD_API_HEADERS,
    },
    401: STD_ERROR_RESPONSES[401],
    403: STD_ERROR_RESPONSES[403],
    500: STD_ERROR_RESPONSES[500],
  },
});

registry.registerPath({
  method: "post",
  path: "/api/v1/custody/withdraw",
  tags: ["OmniCoins"],
  summary: "Initiate a custody withdrawal (USD → local currency)",
  description:
    "FX rate is resolved server-side from `platform_fx_quotes` " +
    "(L01-02 — never accepted from the client). On stale quote, " +
    "503 with retry guidance.",
  request: {
    body: {
      required: true,
      content: { "application/json": { schema: WithdrawBody } },
    },
  },
  responses: {
    200: {
      description: "Withdrawal created.",
      content: { "application/json": { schema: Withdrawal } },
    },
    401: STD_ERROR_RESPONSES[401],
    403: STD_ERROR_RESPONSES[403],
    422: STD_ERROR_RESPONSES[422],
    429: STD_ERROR_RESPONSES[429],
    500: STD_ERROR_RESPONSES[500],
    503: STD_ERROR_RESPONSES[503],
  },
});

registry.registerPath({
  method: "post",
  path: "/api/v1/distribute-coins",
  tags: ["OmniCoins"],
  summary: "Mint coins to an athlete wallet",
  description:
    "Atomic mint: custody → inventory → wallet → ledger in a single " +
    "RPC (see migration `20260417120000_emit_coins_atomic.sql`). " +
    "Idempotent by `coin_ledger.ref_id` UNIQUE constraint.",
  request: {
    body: {
      required: true,
      content: {
        "application/json": { schema: DistributeCoinsBody },
      },
    },
  },
  responses: {
    200: {
      description: "Coins minted; ledger entry returned.",
      content: {
        "application/json": { schema: DistributeCoinsResponse },
      },
    },
    401: STD_ERROR_RESPONSES[401],
    403: STD_ERROR_RESPONSES[403],
    404: {
      description: "Athlete not found in this group.",
      content: {
        "application/json": {
          schema: { $ref: "#/components/schemas/ApiErrorBody" },
        },
      },
    },
    422: STD_ERROR_RESPONSES[422],
    429: STD_ERROR_RESPONSES[429],
    500: STD_ERROR_RESPONSES[500],
    503: STD_ERROR_RESPONSES[503],
  },
});

registry.registerPath({
  method: "post",
  path: "/api/v1/distribute-coins/batch",
  tags: ["OmniCoins"],
  summary: "Mint coins to up to 200 athletes in a single transaction (L05-03)",
  description:
    "Bulk version of `/api/v1/distribute-coins`. Dispatches the whole " +
    "batch through `distribute_coins_batch_atomic` (see migration " +
    "`20260421120000_l05_distribute_coins_batch.sql`) which loops over " +
    "items in a single SQL transaction — any item failing rolls back " +
    "the entire batch. Idempotency is per-batch via `ref_id` plus a " +
    "deterministic `<batch>__<idx>` derivation per item, so replays " +
    "are safe (`batch_was_idempotent: true`). Rate-limited at 5 req/min " +
    "per group.",
  request: {
    body: {
      required: true,
      content: {
        "application/json": { schema: DistributeCoinsBatchBody },
      },
    },
  },
  responses: {
    200: {
      description:
        "Batch dispatched. `items[].was_idempotent` flags slices that " +
        "were already credited in a prior call with the same ref_id.",
      content: {
        "application/json": { schema: DistributeCoinsBatchResponse },
      },
    },
    400: STD_ERROR_RESPONSES[422],
    401: STD_ERROR_RESPONSES[401],
    403: STD_ERROR_RESPONSES[403],
    422: STD_ERROR_RESPONSES[422],
    429: STD_ERROR_RESPONSES[429],
    500: STD_ERROR_RESPONSES[500],
    503: STD_ERROR_RESPONSES[503],
  },
});

registry.registerPath({
  method: "get",
  path: "/api/v1/clearing",
  tags: ["OmniCoins"],
  summary: "List clearing settlements involving the current group",
  request: {
    query: z.object({
      role: z
        .enum(["creditor", "debtor", "both"])
        .default("both")
        .openapi({
          description:
            "Filter to settlements where the current group is the " +
            "creditor, debtor, or either (default).",
        }),
    }),
  },
  responses: {
    200: {
      description: "Settlements list.",
      content: { "application/json": { schema: ClearingResponse } },
      headers: STD_API_HEADERS,
    },
    401: STD_ERROR_RESPONSES[401],
    403: STD_ERROR_RESPONSES[403],
    500: STD_ERROR_RESPONSES[500],
  },
});
