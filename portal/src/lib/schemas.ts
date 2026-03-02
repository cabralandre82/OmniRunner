import { z } from "zod";

export const distributeCoinsSchema = z.object({
  athlete_user_id: z.string().uuid("athlete_user_id deve ser UUID válido"),
  amount: z
    .number()
    .int("amount deve ser inteiro")
    .min(1, "amount mínimo é 1")
    .max(1000, "amount máximo é 1000"),
});

export const teamInviteSchema = z.object({
  email: z.string().email("E-mail inválido"),
  role: z.enum(["professor", "assistente"], {
    error: "Role deve ser: professor, assistente",
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

export const checkoutSchema = z.object({
  product_id: z.string().min(1, "product_id is required"),
  gateway: z.enum(["mercadopago", "stripe"]).optional().default("mercadopago"),
});

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
export type TeamInviteInput = z.infer<typeof teamInviteSchema>;
export type BrandingInput = z.infer<typeof brandingSchema>;
export type CheckoutInput = z.infer<typeof checkoutSchema>;
