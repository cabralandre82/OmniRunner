/**
 * L09-05 — IOF (Imposto sobre Operações Financeiras) types.
 *
 * Pure-domain value objects for classifying and computing IOF
 * exposure across the operational surfaces of Omni Runner.
 *
 * Scope of this module (per ADR `docs/compliance/BCB_CLASSIFICATION.md`,
 * Option B — Asaas partnership):
 *
 *   • Asaas (IP autorizada BCB) is the statutory taxpayer for IOF/Câmbio
 *     on BRL↔USD currency operations.  This module **advises** the amount
 *     for reconciliation and for decision-making inside the portal; it
 *     does NOT collect IOF by itself.
 *   • Omni Runner executes USD→USD custody cessions (see ADR-008).
 *     These are not câmbio and, per Decreto 6.306/2007 art. 7 §3 III,
 *     do not incur IOF/Crédito as a mere transfer of an existing right;
 *     this module returns zero with an explanatory note to remove
 *     ambiguity and to support a possible future scope change.
 *
 * The legal references are embedded as fields on every computation
 * result so operations, audit and finance can trace the exact rule
 * applied — required by L09-05 and L09-01 for BCB/Receita Federal.
 */

// ────────────────────────────────────────────────────────────────────
// Operation classification
// ────────────────────────────────────────────────────────────────────

/**
 * Canonical IOF-taxable operation types recognised by Omni Runner.
 *
 * Mirrors RIOF (Decreto 6.306/2007) articles 1-A through 40:
 *  • crédito   → Art. 2-7   (loans / factoring / advances)
 *  • câmbio    → Art. 11-16 (currency conversion)
 *  • seguro    → Art. 18-25
 *  • título    → Art. 25-A-33 (private securities)
 *  • derivativo→ Art. 32-B (futuros / hedging)
 *
 * `cessao_credito_onerosa` is not a canonical RIOF category; it is
 * Omni Runner's ADR-008 classification of swap_orders as cessão of
 * existing credit (non-taxable per CTN art. 63 I + STJ REsp 1.239.223).
 * Declared here to make the absence of IOF explicit.
 */
export type IofOperationKind =
  | "credito_pj"            // Art. 7 inc. II (PJ tomador)
  | "credito_pf"            // Art. 7 inc. I  (PF tomador)
  | "cambio_brl_usd_out"    // Art. 15-B (remessa para exterior)
  | "cambio_brl_usd_in"     // Art. 15-A (ingresso de divisas)
  | "seguro_vida"           // Art. 22 §1 I
  | "seguro_saude"          // Art. 22 §1 II
  | "seguro_outros"         // Art. 22 §1 III
  | "titulo_privado"        // Art. 26
  | "derivativo"            // Art. 32-B
  | "cessao_credito_onerosa"; // ADR-008 (non-taxable, documented)

export type TaxpayerPersonType = "PF" | "PJ";

// ────────────────────────────────────────────────────────────────────
// Input envelope
// ────────────────────────────────────────────────────────────────────

export interface IofInput {
  /** Which kind of operation is being classified. */
  readonly kind: IofOperationKind;

  /** Principal amount in minor units (BRL cents for cambio_*, USD cents for others). */
  readonly principalAmountCents: number;

  /** Tomador do crédito / pagador; required for `credito_*`, ignored elsewhere. */
  readonly taxpayer?: TaxpayerPersonType;

  /**
   * Operation duration in days.  Only relevant for `credito_*`
   * (IOF/Crédito has daily accrual).  Capped internally at 365.
   * Defaults to 1 when not provided (same-day spot credit).
   */
  readonly durationDays?: number;

  /**
   * ISO date of the operation.  Used to select the rate table when
   * multiple regimes have applied historically (e.g. the 3-year 2022
   * gradual reduction to 0% of câmbio IOF is irrelevant to BRL→USD
   * remittance, which was preserved).  Defaults to today.
   */
  readonly operationDate?: string;
}

// ────────────────────────────────────────────────────────────────────
// Output envelope
// ────────────────────────────────────────────────────────────────────

/**
 * Exhaustive, auditable output for an IOF calculation.  All fields
 * are serialisable JSON primitives so the value can be persisted
 * directly into `swap_orders.iof_quote_json`, an outbox event, or
 * an audit log.
 */
export interface IofComputation {
  /** Echoed input.kind for symmetry. */
  readonly kind: IofOperationKind;

  /** Principal used in the calculation (unchanged). */
  readonly principalAmountCents: number;

  /**
   * The effective percentage rate (not a ratio): 0.38 means 0.38%.
   * For cumulative daily operations (crédito), this is the total
   * effective rate over `durationDays`, already including the fixed
   * 0.38% "adicional".
   */
  readonly effectiveRatePct: number;

  /** Calculated tax amount in minor units of the principal currency. */
  readonly iofAmountCents: number;

  /**
   * Who collects the IOF in the Omni Runner + Asaas architecture.
   *  - "asaas"      → Payment Institution partner (BCB Option B).
   *  - "omni"       → hypothetical future path where Omni would collect.
   *  - "none"       → operation is not IOF-taxable.
   */
  readonly collectedBy: "asaas" | "omni" | "none";

  /** Primary RIOF article backing this rate (for audit). */
  readonly legalReference: string;

  /**
   * Human-readable explanation of how the rate was derived; printed
   * verbatim in audit logs and reconciliation reports.
   */
  readonly explanation: string;

  /**
   * Non-blocking warnings (scope triggers, tributarist-review flags,
   * rate-table boundary conditions).  Empty array when clean.
   */
  readonly warnings: readonly string[];
}

// ────────────────────────────────────────────────────────────────────
// Errors
// ────────────────────────────────────────────────────────────────────

/** Thrown for malformed inputs (pure-domain; never wraps IO). */
export class IofInputError extends Error {
  constructor(
    message: string,
    public readonly code:
      | "non_positive_amount"
      | "non_integer_amount"
      | "unsupported_kind"
      | "missing_taxpayer"
      | "negative_duration"
      | "invalid_operation_date",
  ) {
    super(message);
    this.name = "IofInputError";
  }
}

// ────────────────────────────────────────────────────────────────────
// Rate constants (Decreto 6.306/2007 + Decreto 10.305/2020 + Decreto 11.153/2022)
// ────────────────────────────────────────────────────────────────────

/** Fixed "adicional" surcharge applied to every credit operation. */
export const IOF_CREDITO_ADICIONAL_PCT = 0.38;

/** Daily accrual rate for PF (natural-person) borrowers. */
export const IOF_CREDITO_PF_DAILY_PCT = 0.0082;

/** Daily accrual rate for PJ (legal-person) borrowers. */
export const IOF_CREDITO_PJ_DAILY_PCT = 0.0041;

/** Hard cap imposed by RIOF on daily accrual (365 days). */
export const IOF_CREDITO_MAX_DAYS = 365;

/** Flat câmbio rate for BRL→USD remittance (Decreto 11.153/2022). */
export const IOF_CAMBIO_BRL_USD_OUT_PCT = 0.38;

/** Flat câmbio rate for USD→BRL inbound flows. */
export const IOF_CAMBIO_BRL_USD_IN_PCT = 0.38;

/** Life insurance (seguro vida). */
export const IOF_SEGURO_VIDA_PCT = 0.38;

/** Health insurance (seguro saúde). */
export const IOF_SEGURO_SAUDE_PCT = 2.38;

/** All other insurance policies. */
export const IOF_SEGURO_OUTROS_PCT = 7.38;

/** Private securities (títulos de renda fixa). */
export const IOF_TITULO_PRIVADO_PCT = 1.5;

/** Derivatives (notional-based flat rate). */
export const IOF_DERIVATIVO_PCT = 0.005;
