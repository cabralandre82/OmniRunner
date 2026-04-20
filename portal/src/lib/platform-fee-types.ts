/**
 * Canonical list of platform fee types — single source of truth.
 *
 * Why this module exists (L01-44 / L01-45)
 * ────────────────────────────────────────
 * Historically the list of valid `fee_type` values was duplicated in at least
 * five places, each evolving independently:
 *
 *   1. `platform_fee_config.fee_type` CHECK constraint (Postgres)
 *   2. `platform_revenue.fee_type` CHECK constraint (Postgres)
 *   3. Zod enum in `portal/src/app/api/platform/fees/route.ts`
 *   4. `FEE_LABELS` keys in `portal/src/app/platform/fees/page.tsx`
 *   5. `enum` in `public/openapi.json` for the same endpoint
 *
 * The drift produced two distinct prod incidents:
 *
 *   • L01-44 — `fx_spread` was inserted by migration 20260228170000 but the
 *     CHECK constraint hadn't yet been widened, so fresh installs failed at
 *     `psql ... < schema.sql` time.
 *   • L01-45 — The Zod enum on `POST /api/platform/fees` rejected
 *     `fee_type='fx_spread'` even after L01-44 fixed the CHECK, so platform
 *     admins could not adjust the FX spread via UI during the
 *     2026-04-13 BRL crisis. Mitigation required raw SQL on prod, in the
 *     middle of the night, by an SRE.
 *
 * Both stem from the same root cause: there was no canonical list. This file
 * IS that canonical list. Every consumer (route handler, page, OpenAPI build,
 * SQL invariant test) imports from here and a contract test in
 * `platform-fee-types.test.ts` asserts that ALL surfaces stay in lockstep.
 *
 * Adding a new fee_type
 * ─────────────────────
 *   1. Add the slug to `PLATFORM_FEE_TYPES` below.
 *   2. Add a `FEE_TYPE_LABELS[<slug>]` entry — the contract test will fail
 *      if you forget.
 *   3. Write a Postgres migration that:
 *        - DROPs and re-ADDs `platform_fee_config.fee_type` CHECK to include
 *          the new slug;
 *        - DROPs and re-ADDs `platform_revenue.fee_type` CHECK identically;
 *        - INSERTs a default row in `platform_fee_config` (idempotent via
 *          `ON CONFLICT (fee_type) DO NOTHING`).
 *   4. Update `portal/public/openapi.json` `fee_type.enum` (the lint script
 *      checks for parity at build time once L14-* is wired; today it's a
 *      manual step but the contract test catches it via the same import).
 *
 * NEVER inline fee_type strings as literals outside this file. The contract
 * test deliberately greps for `'fx_spread'` etc. in route handlers; new
 * occurrences will fail CI.
 */

import { z } from "zod";

/**
 * Canonical, ordered list of platform fee types. Order matters for UI
 * rendering: the platform fees page renders rows in this exact order so that
 * the most consequential fees (clearing, swap, fx_spread) appear at the top.
 *
 * Marked `as const` so TypeScript infers the literal-union type.
 */
export const PLATFORM_FEE_TYPES = [
  "clearing",
  "swap",
  "fx_spread",
  "billing_split",
  "maintenance",
] as const;

/**
 * Discriminated literal type for any valid platform fee type. Use this in
 * function signatures, not `string`, so the compiler enforces the canonical
 * set at every call-site.
 */
export type PlatformFeeType = (typeof PLATFORM_FEE_TYPES)[number];

/**
 * Pre-built Zod enum for use in request schemas. Re-exported separately so
 * route handlers don't need to call `z.enum(PLATFORM_FEE_TYPES)` themselves
 * (which would risk dropping `as const` and turning the enum into
 * `z.enum(string[])`, defeating the type narrowing).
 */
export const platformFeeTypeSchema = z.enum(PLATFORM_FEE_TYPES);

/**
 * Display labels and short descriptions for the platform admin UI. Keyed by
 * `PlatformFeeType` so the type system enforces full coverage — adding a new
 * slug to `PLATFORM_FEE_TYPES` without a label here will be caught by `tsc`
 * AND by the contract test in `platform-fee-types.test.ts`.
 *
 * Copy is in pt-BR (the platform admin surface is single-language).
 */
export const FEE_TYPE_LABELS: Record<
  PlatformFeeType,
  { label: string; description: string }
> = {
  clearing: {
    label: "Clearing (Compensação Interclub)",
    description:
      "Aplicada quando coins de um emissor são queimadas em outro clube",
  },
  swap: {
    label: "Swap de Lastro",
    description:
      "Aplicada quando assessorias negociam lastro entre si",
  },
  fx_spread: {
    label: "FX Spread (Saques)",
    description:
      "Percentual retido como spread cambial quando uma assessoria solicita saque em moeda local (ex.: BRL). Crítico em crises cambiais — ajuste imediato aqui evita saques com prejuízo operacional.",
  },
  billing_split: {
    label: "Split de Cobrança",
    description:
      "Percentual retido pela plataforma nas cobranças de assinaturas",
  },
  maintenance: {
    label: "Manutenção",
    description:
      "Valor em USD por atleta ativo. Deduzida automaticamente quando o atleta paga a mensalidade.",
  },
};

/**
 * Type guard for runtime validation outside Zod (e.g. parsing untyped
 * payloads from internal queues). Prefer `platformFeeTypeSchema.safeParse`
 * inside route handlers — this helper is for plumbing/tests only.
 */
export function isPlatformFeeType(value: unknown): value is PlatformFeeType {
  return (
    typeof value === "string" &&
    (PLATFORM_FEE_TYPES as readonly string[]).includes(value)
  );
}

/**
 * Pass-through fee types that appear in `platform_revenue` but are NOT
 * configurable by platform admins (no row in `platform_fee_config`).
 *
 * Pass-through means: the platform records the line for accounting trail
 * but does not keep the money — it forwards it to a third party (e.g.
 * gateway, bank, custodian). Brazilian tax law: pass-through fees are
 * NOT service revenue, so the L09-04 fiscal-receipts trigger
 * (`_enqueue_fiscal_receipt`) explicitly skips them.
 *
 * Why a separate constant?
 * ────────────────────────
 * The CFO ledger (`platform_revenue`) needs to record EVERY USD that
 * leaves custody, including the slice the gateway pockets. But the
 * platform-admin UI only configures rates the platform itself charges
 * (the `PLATFORM_FEE_TYPES` set). Mixing them in the same configurable
 * list would let an admin "edit" the provider fee — which is meaningless
 * because each gateway quotes its own per-transaction fee at withdraw
 * time.
 *
 * History
 * ───────
 *   • L03-03 — `execute_withdrawal` was decrementing custody by the GROSS
 *     `amount_usd` but only recording `fx_spread` in `platform_revenue`.
 *     The provider fee just disappeared from the ledger, breaking the
 *     custody invariant `deposits_in = withdrawals_out + revenue + held`.
 *     Fix: insert a `provider_fee` row in the same TX as the existing
 *     `fx_spread` insert, AND skip the fiscal-receipts trigger for it.
 */
export const PLATFORM_PASSTHROUGH_FEE_TYPES = [
  "provider_fee",
] as const;

export type PlatformPassthroughFeeType =
  (typeof PLATFORM_PASSTHROUGH_FEE_TYPES)[number];

/**
 * Superset of every `fee_type` that may appear in `platform_revenue`:
 * configurable platform fees + pass-through fees. This is the value
 * the `platform_revenue.fee_type` Postgres CHECK constraint mirrors.
 *
 * The contract test in `platform-fee-types.test.ts` asserts:
 *
 *   - `PLATFORM_REVENUE_FEE_TYPES` ⊃ `PLATFORM_FEE_TYPES`
 *   - `PLATFORM_REVENUE_FEE_TYPES` = `PLATFORM_FEE_TYPES` ∪
 *     `PLATFORM_PASSTHROUGH_FEE_TYPES`
 *   - The Postgres CHECK in
 *     `supabase/migrations/20260420090000_l03_provider_fee_revenue_track.sql`
 *     contains exactly these literals.
 */
export const PLATFORM_REVENUE_FEE_TYPES = [
  ...PLATFORM_FEE_TYPES,
  ...PLATFORM_PASSTHROUGH_FEE_TYPES,
] as const;

export type PlatformRevenueFeeType =
  (typeof PLATFORM_REVENUE_FEE_TYPES)[number];

/**
 * Pre-built Zod enum for code that filters/validates against the full
 * revenue-side fee type list (e.g. CFO reporting tools, ledger
 * reconciliation jobs). DO NOT use this in `POST /api/platform/fees` —
 * that endpoint configures rates and must reject pass-through types.
 */
export const platformRevenueFeeTypeSchema = z.enum(
  PLATFORM_REVENUE_FEE_TYPES,
);

/**
 * Type guard companion to `isPlatformFeeType`, scoped to the broader
 * revenue-side fee type set.
 */
export function isPlatformRevenueFeeType(
  value: unknown,
): value is PlatformRevenueFeeType {
  return (
    typeof value === "string" &&
    (PLATFORM_REVENUE_FEE_TYPES as readonly string[]).includes(value)
  );
}
