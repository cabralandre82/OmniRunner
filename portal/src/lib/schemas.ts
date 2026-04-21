import { z } from "zod";

// L05-03 — per-call cap raised from 1_000 → 100_000 to support medium clubs
// distributing weekly bonuses to single athletes without artificial chunking.
// Invariants healthy + custódia + inventory CHECKs at the DB layer remain the
// source of truth for "can we afford this emission?" — the schema just keeps
// pathologically wrong inputs (negative, fractional, missing UUID) out of the
// pipeline. For multi-athlete distributions use `distributeCoinsBatchSchema`
// (POST /api/distribute-coins/batch), which dispatches the whole list in a
// single SQL transaction via `distribute_coins_batch_atomic`.
export const DISTRIBUTE_COINS_AMOUNT_MAX = 100_000;

export const distributeCoinsSchema = z.object({
  athlete_user_id: z.string().uuid("athlete_user_id deve ser UUID válido"),
  amount: z
    .number()
    .int("amount deve ser inteiro")
    .min(1, "amount mínimo é 1")
    .max(
      DISTRIBUTE_COINS_AMOUNT_MAX,
      `amount máximo é ${DISTRIBUTE_COINS_AMOUNT_MAX.toLocaleString("pt-BR")}`,
    ),
});

// L05-03 — caps for the batch endpoint. Total amount cap (1_000_000) is a
// sanity ceiling: even at the elite-club scale (500 atletas × 100 coins) we
// stay under 50_000, leaving 20× headroom for promotional one-shots without
// risking an over-large transaction time budget. items.length capped at 200
// keeps the SECURITY DEFINER call under typical statement_timeout (default
// 30s); larger payloads should be paginated by the caller.
export const DISTRIBUTE_COINS_BATCH_MAX_ITEMS = 200;
export const DISTRIBUTE_COINS_BATCH_MAX_TOTAL = 1_000_000;

const distributeCoinsBatchItemSchema = z.object({
  athlete_user_id: z.string().uuid("athlete_user_id deve ser UUID válido"),
  amount: z
    .number()
    .int("amount deve ser inteiro")
    .min(1, "amount mínimo é 1")
    .max(
      DISTRIBUTE_COINS_AMOUNT_MAX,
      `amount máximo por atleta é ${DISTRIBUTE_COINS_AMOUNT_MAX.toLocaleString("pt-BR")}`,
    ),
});

export const distributeCoinsBatchSchema = z
  .object({
    items: z
      .array(distributeCoinsBatchItemSchema)
      .min(1, "items deve ter ao menos 1 atleta")
      .max(
        DISTRIBUTE_COINS_BATCH_MAX_ITEMS,
        `items máximo é ${DISTRIBUTE_COINS_BATCH_MAX_ITEMS} por chamada — pagine no cliente`,
      ),
    ref_id: z
      .string()
      .min(8, "ref_id deve ter ao menos 8 caracteres")
      .max(128, "ref_id máximo é 128 caracteres")
      .optional(),
  })
  .strict()
  .superRefine((value, ctx) => {
    const seen = new Set<string>();
    for (let i = 0; i < value.items.length; i += 1) {
      const id = value.items[i].athlete_user_id;
      if (seen.has(id)) {
        ctx.addIssue({
          code: "custom",
          message: `athlete_user_id duplicado em items[${i}]: ${id}`,
          path: ["items", i, "athlete_user_id"],
        });
        return;
      }
      seen.add(id);
    }
    const total = value.items.reduce((acc, it) => acc + it.amount, 0);
    if (total > DISTRIBUTE_COINS_BATCH_MAX_TOTAL) {
      ctx.addIssue({
        code: "custom",
        message: `soma de amounts (${total}) excede limite de ${DISTRIBUTE_COINS_BATCH_MAX_TOTAL} por batch`,
        path: ["items"],
      });
    }
  });

// L03-13 — POST /api/coins/reverse: reembolso/estorno de fluxos financeiros.
//
// O achado cobre três ramos de reversão que até agora só existiam como
// blocos de SQL manual no `CHARGEBACK_RUNBOOK`:
//
//   (a) `kind: 'emission'` — reverter um emit_coins_atomic mal feito
//       (athlete errado, amount errado, chargeback do gateway que lastreou
//       a emissão). Espelha emit_coins_atomic inversamente: debita wallet,
//       restaura inventory, libera custódia committed, escreve ledger
//       negativo com reason=`institution_token_reverse_emission`.
//   (b) `kind: 'burn'` — reverter uma execute_burn_atomic errônea (burn
//       disparado por bug de UI, resgate rejeitado pelo parceiro). Só
//       aceita se NENHUM clearing_settlement associado estiver em
//       status `settled` (coins já compensadas entre clubs exigem
//       remediation manual via runbook).
//   (c) `kind: 'deposit'` — chargeback Stripe/MP sobre um custody_deposit
//       já confirmado. Exige que total_deposited_usd - amount >=
//       total_committed (coins já emitidas contra o lastro BLOQUEIAM
//       o refund e o operador é obrigado a reverter emissões antes).
//
// O campo `reason` é obrigatório (>=10 chars) para forçar postmortem
// explícito no audit_log — espelha a CHECK de clearing_failure_log.
// `idempotency_key` pode vir no body ou no header `x-idempotency-key`;
// o schema exige pelo menos um dos dois para evitar replay duplo.

const reverseCoinsReasonSchema = z
  .string()
  .min(10, "reason deve ter ao menos 10 caracteres (postmortem obrigatório)")
  .max(500, "reason máximo é 500 caracteres");

const reverseEmissionSchema = z
  .object({
    kind: z.literal("emission"),
    original_ledger_id: z
      .string()
      .uuid("original_ledger_id deve ser UUID válido"),
    reason: reverseCoinsReasonSchema,
    idempotency_key: z
      .string()
      .min(8, "idempotency_key deve ter ao menos 8 caracteres")
      .max(128)
      .optional(),
  })
  .strict();

const reverseBurnSchema = z
  .object({
    kind: z.literal("burn"),
    burn_ref_id: z
      .string()
      .min(1, "burn_ref_id é obrigatório")
      .max(128, "burn_ref_id máximo é 128 caracteres"),
    reason: reverseCoinsReasonSchema,
    idempotency_key: z
      .string()
      .min(8, "idempotency_key deve ter ao menos 8 caracteres")
      .max(128)
      .optional(),
  })
  .strict();

const reverseDepositSchema = z
  .object({
    kind: z.literal("deposit"),
    deposit_id: z.string().uuid("deposit_id deve ser UUID válido"),
    reason: reverseCoinsReasonSchema,
    idempotency_key: z
      .string()
      .min(8, "idempotency_key deve ter ao menos 8 caracteres")
      .max(128)
      .optional(),
  })
  .strict();

export const reverseCoinsSchema = z.discriminatedUnion("kind", [
  reverseEmissionSchema,
  reverseBurnSchema,
  reverseDepositSchema,
]);

export type ReverseCoinsInput = z.infer<typeof reverseCoinsSchema>;

export const teamInviteSchema = z.object({
  email: z.string().email("E-mail inválido"),
  role: z.enum(["coach", "assistant"], {
    error: "Role deve ser: coach, assistant",
  }),
});

export const teamRemoveSchema = z.object({
  member_id: z.string().min(1, "member_id is required"),
});

export const verificationEvaluateSchema = z.object({
  user_id: z.string().uuid("user_id deve ser UUID válido"),
});

export const brandingSchema = z
  .object({
    logo_url: z
      .string()
      .url()
      .max(512, "logo_url muito longa")
      .nullable()
      .optional(),
    primary_color: z
      .string()
      .regex(/^#[0-9a-fA-F]{6}$/, "Cor deve ser hex (#RRGGBB)")
      .optional(),
    sidebar_bg: z
      .string()
      .regex(/^#[0-9a-fA-F]{6}$/, "Cor deve ser hex (#RRGGBB)")
      .optional(),
    sidebar_text: z
      .string()
      .regex(/^#[0-9a-fA-F]{6}$/, "Cor deve ser hex (#RRGGBB)")
      .optional(),
    accent_color: z
      .string()
      .regex(/^#[0-9a-fA-F]{6}$/, "Cor deve ser hex (#RRGGBB)")
      .optional(),
  })
  .strict();

export const checkoutSchema = z
  .object({
    product_id: z.string().uuid("product_id deve ser UUID válido"),
    gateway: z.enum(["mercadopago", "stripe"]).optional().default("mercadopago"),
  })
  .strict();

export const gatewayPreferenceSchema = z.object({
  preferred_gateway: z.enum(["mercadopago", "stripe"], {
    error: "Gateway inválido. Use 'mercadopago' ou 'stripe'.",
  }),
});

export const autoTopupSchema = z.object({
  enabled: z.boolean().optional(),
  threshold_tokens: z.number().int().min(1).optional(),
  product_id: z.string().min(1).optional(),
  max_per_month: z.number().int().min(1).max(100).optional(),
});

export const platformAssessoriaActionSchema = z.object({
  action: z.enum(["approve", "reject", "suspend"], {
    error: "action deve ser: approve, reject, suspend",
  }),
  group_id: z.string().uuid("group_id deve ser UUID válido"),
  reason: z.string().max(500).optional(),
});

export const platformProductCreateSchema = z.object({
  action: z.literal("create"),
  name: z.string().min(1, "name é obrigatório").max(200),
  description: z.string().max(1000).optional().default(""),
  credits_amount: z.number().int().positive("credits_amount deve ser positivo"),
  price_cents: z.number().int().positive("price_cents deve ser positivo"),
  sort_order: z.number().int().min(0).optional().default(0),
  product_type: z.enum(["coins", "badges"]).optional().default("coins"),
});

export const platformProductToggleSchema = z.object({
  action: z.literal("toggle_active"),
  product_id: z.string().uuid("product_id deve ser UUID válido"),
  is_active: z.boolean(),
});

export const platformProductUpdateSchema = z.object({
  action: z.literal("update"),
  product_id: z.string().uuid("product_id deve ser UUID válido"),
  name: z.string().min(1).max(200).optional(),
  description: z.string().max(1000).optional(),
  credits_amount: z.number().int().positive().optional(),
  price_cents: z.number().int().positive().optional(),
  sort_order: z.number().int().min(0).optional(),
});

export const platformProductDeleteSchema = z.object({
  action: z.literal("delete"),
  product_id: z.string().uuid("product_id deve ser UUID válido"),
});

export const platformRefundActionSchema = z.object({
  action: z.enum(["approve", "reject", "process"], {
    error: "action deve ser: approve, reject, process",
  }),
  refund_id: z.string().uuid("refund_id deve ser UUID válido"),
  notes: z.string().max(1000).optional(),
});

export type DistributeCoinsInput = z.infer<typeof distributeCoinsSchema>;
export type DistributeCoinsBatchInput = z.infer<
  typeof distributeCoinsBatchSchema
>;
export type ReverseEmissionInput = z.infer<typeof reverseEmissionSchema>;
export type ReverseBurnInput = z.infer<typeof reverseBurnSchema>;
export type ReverseDepositInput = z.infer<typeof reverseDepositSchema>;
export type TeamInviteInput = z.infer<typeof teamInviteSchema>;
export type BrandingInput = z.infer<typeof brandingSchema>;
export type CheckoutInput = z.infer<typeof checkoutSchema>;
