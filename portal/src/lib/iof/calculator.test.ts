/**
 * L09-05 — IOF calculator unit tests.
 */

import { describe, it, expect } from "vitest";
import {
  computeIof,
  IOF_CAMBIO_BRL_USD_OUT_PCT,
  IOF_CREDITO_ADICIONAL_PCT,
  IOF_CREDITO_MAX_DAYS,
  IOF_CREDITO_PF_DAILY_PCT,
  IOF_CREDITO_PJ_DAILY_PCT,
  IOF_SEGURO_OUTROS_PCT,
  IofInputError,
} from "./index";

describe("L09-05 computeIof — input validation", () => {
  it("rejects non-integer principal", () => {
    expect(() =>
      computeIof({ kind: "cambio_brl_usd_out", principalAmountCents: 10.5 }),
    ).toThrow(IofInputError);
  });

  it("rejects non-positive principal", () => {
    expect(() =>
      computeIof({ kind: "cambio_brl_usd_out", principalAmountCents: 0 }),
    ).toThrow(IofInputError);
    expect(() =>
      computeIof({ kind: "cambio_brl_usd_out", principalAmountCents: -1 }),
    ).toThrow(IofInputError);
  });

  it("rejects infinite principal", () => {
    expect(() =>
      computeIof({
        kind: "cambio_brl_usd_out",
        principalAmountCents: Number.POSITIVE_INFINITY,
      }),
    ).toThrow(IofInputError);
  });

  it("rejects negative durationDays", () => {
    expect(() =>
      computeIof({
        kind: "credito_pj",
        principalAmountCents: 100_00,
        taxpayer: "PJ",
        durationDays: -5,
      }),
    ).toThrow(IofInputError);
  });

  it("rejects malformed operationDate", () => {
    expect(() =>
      computeIof({
        kind: "cambio_brl_usd_out",
        principalAmountCents: 100_00,
        operationDate: "not-a-date",
      }),
    ).toThrow(IofInputError);
  });

  it("rejects credit without taxpayer", () => {
    expect(() =>
      computeIof({
        kind: "credito_pj",
        principalAmountCents: 100_00,
      }),
    ).toThrow(IofInputError);
  });

  it("rejects PJ kind with PF taxpayer", () => {
    expect(() =>
      computeIof({
        kind: "credito_pj",
        principalAmountCents: 100_00,
        taxpayer: "PF",
      }),
    ).toThrow(IofInputError);
  });
});

describe("L09-05 computeIof — câmbio BRL↔USD", () => {
  it("applies 0.38% flat on outbound remittance", () => {
    const r = computeIof({
      kind: "cambio_brl_usd_out",
      principalAmountCents: 100_000_00,
    });
    expect(r.effectiveRatePct).toBe(IOF_CAMBIO_BRL_USD_OUT_PCT);
    expect(r.iofAmountCents).toBe(38_000);
    expect(r.collectedBy).toBe("asaas");
    expect(r.legalReference).toContain("Decreto 6.306/2007");
    expect(r.legalReference).toContain("art. 15-B");
    expect(r.warnings.length).toBeGreaterThan(0);
  });

  it("applies 0.38% flat on inbound flow", () => {
    const r = computeIof({
      kind: "cambio_brl_usd_in",
      principalAmountCents: 50_000_00,
    });
    expect(r.effectiveRatePct).toBe(0.38);
    expect(r.iofAmountCents).toBe(19_000);
    expect(r.legalReference).toContain("art. 15-A");
  });

  it("uses banker's rounding for odd cents", () => {
    const r = computeIof({
      kind: "cambio_brl_usd_out",
      principalAmountCents: 12_345,
    });
    // 12345 * 0.0038 = 46.911 → banker's rounding → 47
    expect(r.iofAmountCents).toBe(47);
  });
});

describe("L09-05 computeIof — crédito PF/PJ", () => {
  it("computes PJ daily + adicional for 30 days", () => {
    const r = computeIof({
      kind: "credito_pj",
      principalAmountCents: 10_000_00,
      taxpayer: "PJ",
      durationDays: 30,
    });
    const expected = 30 * IOF_CREDITO_PJ_DAILY_PCT + IOF_CREDITO_ADICIONAL_PCT;
    expect(r.effectiveRatePct).toBeCloseTo(expected, 5);
    expect(r.collectedBy).toBe("asaas");
  });

  it("computes PF daily + adicional for 90 days", () => {
    const r = computeIof({
      kind: "credito_pf",
      principalAmountCents: 5_000_00,
      taxpayer: "PF",
      durationDays: 90,
    });
    const expected = 90 * IOF_CREDITO_PF_DAILY_PCT + IOF_CREDITO_ADICIONAL_PCT;
    expect(r.effectiveRatePct).toBeCloseTo(expected, 5);
  });

  it("caps duration at 365 days and emits warning", () => {
    const r = computeIof({
      kind: "credito_pj",
      principalAmountCents: 1_000_00,
      taxpayer: "PJ",
      durationDays: 1000,
    });
    const capped = IOF_CREDITO_MAX_DAYS * IOF_CREDITO_PJ_DAILY_PCT + IOF_CREDITO_ADICIONAL_PCT;
    expect(r.effectiveRatePct).toBeCloseTo(capped, 5);
    expect(r.warnings.some((w) => /exceeds RIOF cap/.test(w))).toBe(true);
  });

  it("always includes the Asaas reconciliation warning", () => {
    const r = computeIof({
      kind: "credito_pj",
      principalAmountCents: 1_000_00,
      taxpayer: "PJ",
      durationDays: 1,
    });
    expect(r.warnings.some((w) => /Asaas/i.test(w))).toBe(true);
  });

  it("defaults to 1 day when durationDays is omitted", () => {
    const r = computeIof({
      kind: "credito_pj",
      principalAmountCents: 1_000_00,
      taxpayer: "PJ",
    });
    const expected = IOF_CREDITO_PJ_DAILY_PCT + IOF_CREDITO_ADICIONAL_PCT;
    expect(r.effectiveRatePct).toBeCloseTo(expected, 5);
  });
});

describe("L09-05 computeIof — cessão de crédito onerosa (ADR-008)", () => {
  it("returns 0% and collectedBy=none for swap cessions", () => {
    const r = computeIof({
      kind: "cessao_credito_onerosa",
      principalAmountCents: 100_000_00,
    });
    expect(r.effectiveRatePct).toBe(0);
    expect(r.iofAmountCents).toBe(0);
    expect(r.collectedBy).toBe("none");
  });

  it("cites ADR-008 and CTN art. 63 I in the legal reference", () => {
    const r = computeIof({
      kind: "cessao_credito_onerosa",
      principalAmountCents: 1_000_00,
    });
    expect(r.legalReference).toContain("ADR-008");
    expect(r.legalReference).toContain("CTN art. 63 I");
  });

  it("emits a scope-change warning encouraging review on regime drift", () => {
    const r = computeIof({
      kind: "cessao_credito_onerosa",
      principalAmountCents: 1_000_00,
    });
    expect(r.warnings.length).toBeGreaterThan(0);
    expect(r.warnings.join(" ")).toMatch(/tributarista|consulta|escopo/i);
  });
});

describe("L09-05 computeIof — seguros", () => {
  it("applies 0.38% on life insurance", () => {
    const r = computeIof({ kind: "seguro_vida", principalAmountCents: 1_000_00 });
    expect(r.effectiveRatePct).toBe(0.38);
  });

  it("applies 2.38% on health insurance", () => {
    const r = computeIof({ kind: "seguro_saude", principalAmountCents: 1_000_00 });
    expect(r.effectiveRatePct).toBe(2.38);
  });

  it("applies 7.38% on other insurance", () => {
    const r = computeIof({ kind: "seguro_outros", principalAmountCents: 1_000_00 });
    expect(r.effectiveRatePct).toBe(IOF_SEGURO_OUTROS_PCT);
  });
});

describe("L09-05 computeIof — títulos / derivativos", () => {
  it("applies 1.5% on private securities", () => {
    const r = computeIof({
      kind: "titulo_privado",
      principalAmountCents: 10_000_00,
    });
    expect(r.effectiveRatePct).toBe(1.5);
  });

  it("applies 0.005% on derivatives notional", () => {
    const r = computeIof({
      kind: "derivativo",
      principalAmountCents: 10_000_000_00,
    });
    expect(r.effectiveRatePct).toBe(0.005);
  });
});

describe("L09-05 computeIof — audit envelope shape", () => {
  it("returns a JSON-serialisable value", () => {
    const r = computeIof({
      kind: "credito_pj",
      principalAmountCents: 1_234_56,
      taxpayer: "PJ",
      durationDays: 42,
    });
    expect(() => JSON.stringify(r)).not.toThrow();
    const round = JSON.parse(JSON.stringify(r));
    expect(round.kind).toBe(r.kind);
    expect(round.iofAmountCents).toBe(r.iofAmountCents);
  });

  it("every computation includes legalReference and explanation", () => {
    const kinds = [
      { kind: "cambio_brl_usd_out", principalAmountCents: 1_00 },
      { kind: "cambio_brl_usd_in", principalAmountCents: 1_00 },
      { kind: "seguro_vida", principalAmountCents: 1_00 },
      { kind: "seguro_saude", principalAmountCents: 1_00 },
      { kind: "seguro_outros", principalAmountCents: 1_00 },
      { kind: "titulo_privado", principalAmountCents: 1_00 },
      { kind: "derivativo", principalAmountCents: 1_00 },
      { kind: "cessao_credito_onerosa", principalAmountCents: 1_00 },
    ] as const;
    for (const input of kinds) {
      const r = computeIof(input);
      expect(r.legalReference.length).toBeGreaterThan(10);
      expect(r.explanation.length).toBeGreaterThan(10);
    }
  });
});
