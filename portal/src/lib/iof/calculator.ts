/**
 * L09-05 — IOF calculator (pure-domain).
 *
 * Given an {@link IofInput}, returns an auditable {@link IofComputation}
 * describing the rate, amount, collector and legal reference applicable
 * to the operation.
 *
 * No IO, no side-effects, no dynamic imports: the entire computation is
 * deterministic and safe to run in edge, node and worker runtimes.
 */

import {
  IOF_CAMBIO_BRL_USD_IN_PCT,
  IOF_CAMBIO_BRL_USD_OUT_PCT,
  IOF_CREDITO_ADICIONAL_PCT,
  IOF_CREDITO_MAX_DAYS,
  IOF_CREDITO_PF_DAILY_PCT,
  IOF_CREDITO_PJ_DAILY_PCT,
  IOF_DERIVATIVO_PCT,
  IOF_SEGURO_OUTROS_PCT,
  IOF_SEGURO_SAUDE_PCT,
  IOF_SEGURO_VIDA_PCT,
  IOF_TITULO_PRIVADO_PCT,
  IofInput,
  IofInputError,
  IofComputation,
  IofOperationKind,
} from "./types";

// ────────────────────────────────────────────────────────────────────
// Helpers
// ────────────────────────────────────────────────────────────────────

/** Banker's rounding (half-to-even) for monetary integer cents. */
function bankerRound(n: number): number {
  const floor = Math.floor(n);
  const diff = n - floor;
  if (diff < 0.5) return floor;
  if (diff > 0.5) return floor + 1;
  return floor % 2 === 0 ? floor : floor + 1;
}

/** Applies `ratePct` (percent, not ratio) to `principal` in cents. */
function applyRate(principalCents: number, ratePct: number): number {
  return bankerRound((principalCents * ratePct) / 100);
}

function assertInput(input: IofInput): void {
  if (!Number.isFinite(input.principalAmountCents)) {
    throw new IofInputError(
      "principalAmountCents must be a finite number",
      "non_integer_amount",
    );
  }
  if (!Number.isInteger(input.principalAmountCents)) {
    throw new IofInputError(
      "principalAmountCents must be an integer (minor units)",
      "non_integer_amount",
    );
  }
  if (input.principalAmountCents <= 0) {
    throw new IofInputError(
      "principalAmountCents must be greater than zero",
      "non_positive_amount",
    );
  }
  if (input.durationDays !== undefined && input.durationDays < 0) {
    throw new IofInputError(
      "durationDays must be non-negative",
      "negative_duration",
    );
  }
  if (
    input.operationDate !== undefined &&
    Number.isNaN(Date.parse(input.operationDate))
  ) {
    throw new IofInputError(
      "operationDate must be a parsable ISO-8601 date",
      "invalid_operation_date",
    );
  }
}

// ────────────────────────────────────────────────────────────────────
// Per-kind strategies
// ────────────────────────────────────────────────────────────────────

function computeCredit(input: IofInput, kind: "credito_pf" | "credito_pj"): IofComputation {
  if (input.taxpayer === undefined) {
    throw new IofInputError(
      `taxpayer (PF|PJ) is required for kind=${kind}`,
      "missing_taxpayer",
    );
  }

  const declaredKind: IofOperationKind = kind;
  const persona = kind === "credito_pf" ? "PF" : "PJ";

  if (input.taxpayer !== persona) {
    throw new IofInputError(
      `kind=${kind} requires taxpayer=${persona} but received ${input.taxpayer}`,
      "missing_taxpayer",
    );
  }

  const rawDays = input.durationDays ?? 1;
  const days = Math.min(rawDays, IOF_CREDITO_MAX_DAYS);
  const dailyPct =
    kind === "credito_pf"
      ? IOF_CREDITO_PF_DAILY_PCT
      : IOF_CREDITO_PJ_DAILY_PCT;

  const effective =
    Number((days * dailyPct).toFixed(6)) + IOF_CREDITO_ADICIONAL_PCT;

  const iofAmount = applyRate(input.principalAmountCents, effective);

  const warnings: string[] = [];
  if (rawDays > IOF_CREDITO_MAX_DAYS) {
    warnings.push(
      `durationDays=${rawDays} exceeds RIOF cap of ${IOF_CREDITO_MAX_DAYS}; using cap.`,
    );
  }
  warnings.push(
    "IOF/Crédito is collected at source by the Payment Institution partner (Asaas); " +
      "Omni Runner mirrors the amount for reconciliation only.",
  );

  return {
    kind: declaredKind,
    principalAmountCents: input.principalAmountCents,
    effectiveRatePct: Number(effective.toFixed(6)),
    iofAmountCents: iofAmount,
    collectedBy: "asaas",
    legalReference:
      kind === "credito_pf"
        ? "Decreto 6.306/2007 art. 7 I c/c art. 7 §15 (alíquota adicional)"
        : "Decreto 6.306/2007 art. 7 II c/c art. 7 §15 (alíquota adicional)",
    explanation:
      `Crédito ${persona}: ${days}d × ${dailyPct}%/d + adicional ${IOF_CREDITO_ADICIONAL_PCT}% = ` +
      `${effective.toFixed(6)}% sobre ${input.principalAmountCents} centavos.`,
    warnings,
  };
}

function computeCambio(
  input: IofInput,
  kind: "cambio_brl_usd_out" | "cambio_brl_usd_in",
): IofComputation {
  const rate =
    kind === "cambio_brl_usd_out"
      ? IOF_CAMBIO_BRL_USD_OUT_PCT
      : IOF_CAMBIO_BRL_USD_IN_PCT;
  const iofAmount = applyRate(input.principalAmountCents, rate);

  return {
    kind,
    principalAmountCents: input.principalAmountCents,
    effectiveRatePct: rate,
    iofAmountCents: iofAmount,
    collectedBy: "asaas",
    legalReference:
      kind === "cambio_brl_usd_out"
        ? "Decreto 6.306/2007 art. 15-B (remessa ao exterior) · Decreto 11.153/2022"
        : "Decreto 6.306/2007 art. 15-A (ingresso de divisas) · Decreto 11.153/2022",
    explanation:
      `Câmbio ${kind === "cambio_brl_usd_out" ? "saída" : "entrada"}: ` +
      `alíquota flat ${rate}% sobre ${input.principalAmountCents} centavos BRL.`,
    warnings: [
      "Câmbio BRL↔USD é de responsabilidade da Asaas (IP autorizada). " +
        "Valor informado aqui é apenas para reconciliação da assessoria.",
    ],
  };
}

function computeSeguro(
  input: IofInput,
  kind: "seguro_vida" | "seguro_saude" | "seguro_outros",
): IofComputation {
  const rate =
    kind === "seguro_vida"
      ? IOF_SEGURO_VIDA_PCT
      : kind === "seguro_saude"
        ? IOF_SEGURO_SAUDE_PCT
        : IOF_SEGURO_OUTROS_PCT;

  return {
    kind,
    principalAmountCents: input.principalAmountCents,
    effectiveRatePct: rate,
    iofAmountCents: applyRate(input.principalAmountCents, rate),
    collectedBy: "asaas",
    legalReference: "Decreto 6.306/2007 art. 22 §1",
    explanation: `Seguro (${kind}): ${rate}% sobre prêmio de ${input.principalAmountCents} centavos.`,
    warnings: [],
  };
}

function computeTitulo(input: IofInput): IofComputation {
  return {
    kind: "titulo_privado",
    principalAmountCents: input.principalAmountCents,
    effectiveRatePct: IOF_TITULO_PRIVADO_PCT,
    iofAmountCents: applyRate(input.principalAmountCents, IOF_TITULO_PRIVADO_PCT),
    collectedBy: "asaas",
    legalReference: "Decreto 6.306/2007 art. 26",
    explanation: `Título privado: ${IOF_TITULO_PRIVADO_PCT}% sobre valor nominal.`,
    warnings: [],
  };
}

function computeDerivativo(input: IofInput): IofComputation {
  return {
    kind: "derivativo",
    principalAmountCents: input.principalAmountCents,
    effectiveRatePct: IOF_DERIVATIVO_PCT,
    iofAmountCents: applyRate(input.principalAmountCents, IOF_DERIVATIVO_PCT),
    collectedBy: "asaas",
    legalReference: "Decreto 6.306/2007 art. 32-B",
    explanation: `Derivativo: ${IOF_DERIVATIVO_PCT}% sobre valor nocional.`,
    warnings: [],
  };
}

function computeCessao(input: IofInput): IofComputation {
  return {
    kind: "cessao_credito_onerosa",
    principalAmountCents: input.principalAmountCents,
    effectiveRatePct: 0,
    iofAmountCents: 0,
    collectedBy: "none",
    legalReference:
      "CTN art. 63 I · STJ REsp 1.239.223 · ADR-008 (docs/adr/008-swap-as-off-platform-credit-cession.md)",
    explanation:
      "Swap Omni Runner é cessão de crédito pré-existente de custódia entre assessorias (ADR-008). " +
      "Cessão onerosa de crédito já estabelecido não configura operação de crédito nova, " +
      "não incidindo IOF/Crédito (CTN art. 63 I). Pagamento inter-CNPJ é off-platform, " +
      "sem intermediação financeira que atraia câmbio ou IOF sobre operação derivada.",
    warnings: [
      "Classificação confirmada em ADR-008 e reforçada pela ADR de BCB Classification (L09-01). " +
        "Qualquer mudança de escopo (ex.: remuneração on-platform, matching ativo, " +
        "intermediação de pagamento) **requer nova consulta tributarista** e revisão desta função.",
    ],
  };
}

// ────────────────────────────────────────────────────────────────────
// Public entrypoint
// ────────────────────────────────────────────────────────────────────

export function computeIof(input: IofInput): IofComputation {
  assertInput(input);

  switch (input.kind) {
    case "credito_pj":
    case "credito_pf":
      return computeCredit(input, input.kind);
    case "cambio_brl_usd_out":
    case "cambio_brl_usd_in":
      return computeCambio(input, input.kind);
    case "seguro_vida":
    case "seguro_saude":
    case "seguro_outros":
      return computeSeguro(input, input.kind);
    case "titulo_privado":
      return computeTitulo(input);
    case "derivativo":
      return computeDerivativo(input);
    case "cessao_credito_onerosa":
      return computeCessao(input);
    default: {
      // Exhaustiveness guard — TypeScript narrows `never` here.
      const _never: never = input.kind;
      throw new IofInputError(
        `unsupported IOF operation kind: ${_never as string}`,
        "unsupported_kind",
      );
    }
  }
}
