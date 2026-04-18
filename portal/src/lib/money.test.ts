import { describe, it, expect } from "vitest";
import {
  roundToCents,
  calcPercentFee,
  subtractMoney,
  addMoney,
  multiplyMoney,
  calcSplit,
  MAX_MONEY_CENTS,
} from "./money";

// ─────────────────────────────────────────────────────────────────────────────
// Reference implementation
// ─────────────────────────────────────────────────────────────────────────────
//
// Postgres `ROUND(x::numeric, 2)` uses banker's rounding (half-to-even)
// on exact decimal values. We model this in BigInt to get an exact
// reference that our `roundToCents` must match.
//
// `parseDecimalToBigInt(value, scale)` interprets the JS number as the
// decimal representation produced by `value.toString()` at full
// precision (which is what a developer "sees" when they read the value
// in code or in a JSON payload). For the inputs we care about — sums
// of products of fixed-precision numerics — this matches what Postgres
// would receive if the same expression were evaluated server-side.

const REF_BIG_ONE = BigInt(1);
const REF_BIG_TEN = BigInt(10);

function pow10(n: number): bigint {
  let r = REF_BIG_ONE;
  for (let i = 0; i < n; i++) r *= REF_BIG_TEN;
  return r;
}

/** Decode a JS number into (mantissa: bigint, scale: number). */
function decodeDecimal(value: number): { mantissa: bigint; scale: number } {
  if (!Number.isFinite(value)) {
    throw new Error(`decodeDecimal: non-finite ${value}`);
  }
  const str = value.toString();
  if (/e/i.test(str)) {
    const [mantStr, expStr] = str.toLowerCase().split("e");
    const exp = parseInt(expStr, 10);
    const sign = mantStr.startsWith("-") ? -REF_BIG_ONE : REF_BIG_ONE;
    const cleanMant = mantStr.replace(/^-/, "");
    const dotIdx = cleanMant.indexOf(".");
    const digits = cleanMant.replace(".", "");
    const fracLen = dotIdx === -1 ? 0 : cleanMant.length - dotIdx - 1;
    const scale = fracLen - exp;
    const mantissa = sign * BigInt(digits);
    if (scale >= 0) return { mantissa, scale };
    return { mantissa: mantissa * pow10(-scale), scale: 0 };
  }
  const sign = str.startsWith("-") ? -REF_BIG_ONE : REF_BIG_ONE;
  const clean = str.replace(/^-/, "");
  const dotIdx = clean.indexOf(".");
  if (dotIdx === -1) {
    return { mantissa: sign * BigInt(clean), scale: 0 };
  }
  const intPart = clean.slice(0, dotIdx);
  const fracPart = clean.slice(dotIdx + 1);
  return {
    mantissa: sign * BigInt(intPart + fracPart),
    scale: fracPart.length,
  };
}

/**
 * Reference: rounds `value` to 2 decimals using banker's rounding,
 * exactly as Postgres `ROUND(value::numeric, 2)` does. Returns the
 * result as a JS number for comparison.
 */
const REF_BIG_ZERO = BigInt(0);
const REF_BIG_TWO = BigInt(2);

function pgRoundToCents(value: number): number {
  const { mantissa, scale } = decodeDecimal(value);
  if (scale <= 2) {
    return Number(mantissa) / Math.pow(10, scale);
  }
  const divisor = pow10(scale - 2);
  const half = divisor / REF_BIG_TWO;
  const sign = mantissa < REF_BIG_ZERO ? -REF_BIG_ONE : REF_BIG_ONE;
  const absMant = mantissa < REF_BIG_ZERO ? -mantissa : mantissa;
  const quotient = absMant / divisor;
  const remainder = absMant % divisor;
  let rounded: bigint;
  if (remainder < half) {
    rounded = quotient;
  } else if (remainder > half) {
    rounded = quotient + REF_BIG_ONE;
  } else {
    rounded = quotient % REF_BIG_TWO === REF_BIG_ZERO ? quotient : quotient + REF_BIG_ONE;
  }
  return Number(sign * rounded) / 100;
}

/**
 * Reference: emulates Postgres `ROUND((gross * ratePct / 100)::numeric, 2)`
 * using exact BigInt arithmetic on decoded decimals.
 */
function pgCalcPercentFee(gross: number, ratePct: number): number {
  const g = decodeDecimal(gross);
  const r = decodeDecimal(ratePct);
  const productMantissa = g.mantissa * r.mantissa;
  const productScale = g.scale + r.scale;
  const scale = productScale + 2;
  if (scale <= 2) {
    return Number(productMantissa) / Math.pow(10, scale);
  }
  const divisor = pow10(scale - 2);
  const half = divisor / REF_BIG_TWO;
  const sign = productMantissa < REF_BIG_ZERO ? -REF_BIG_ONE : REF_BIG_ONE;
  const absMant = productMantissa < REF_BIG_ZERO ? -productMantissa : productMantissa;
  const quotient = absMant / divisor;
  const remainder = absMant % divisor;
  let rounded: bigint;
  if (remainder < half) {
    rounded = quotient;
  } else if (remainder > half) {
    rounded = quotient + REF_BIG_ONE;
  } else {
    rounded = quotient % REF_BIG_TWO === REF_BIG_ZERO ? quotient : quotient + REF_BIG_ONE;
  }
  return Number(sign * rounded) / 100;
}

// ─────────────────────────────────────────────────────────────────────────────
// roundToCents
// ─────────────────────────────────────────────────────────────────────────────

describe("roundToCents", () => {
  it("trivial values pass through", () => {
    expect(roundToCents(0)).toBe(0);
    expect(roundToCents(1)).toBe(1);
    expect(roundToCents(1.0)).toBe(1);
    expect(roundToCents(1.23)).toBe(1.23);
    expect(roundToCents(99.99)).toBe(99.99);
  });

  it("absorbs IEEE-754 drift", () => {
    expect(roundToCents(0.1 + 0.2)).toBe(0.3);
    expect(roundToCents(0.1 * 3)).toBe(0.3);
  });

  it("uses banker's rounding for exact halves at the cent boundary", () => {
    expect(roundToCents(1.005)).toBe(1.0);
    expect(roundToCents(1.015)).toBe(1.02);
    expect(roundToCents(2.345)).toBe(2.34);
    expect(roundToCents(2.355)).toBe(2.36);
    expect(roundToCents(0.005)).toBe(0.0);
    expect(roundToCents(0.015)).toBe(0.02);
  });

  it("handles negatives symmetrically", () => {
    expect(roundToCents(-1.005)).toBe(-1.0);
    expect(roundToCents(-1.015)).toBe(-1.02);
    expect(roundToCents(-99.99)).toBe(-99.99);
  });

  it("rejects non-finite", () => {
    expect(() => roundToCents(NaN)).toThrow();
    expect(() => roundToCents(Infinity)).toThrow();
    expect(() => roundToCents(-Infinity)).toThrow();
  });

  it("rejects out-of-range numeric(14,2) values", () => {
    expect(() => roundToCents(MAX_MONEY_CENTS / 100 + 1)).toThrow(/range/);
  });

  it("matches Postgres ROUND for 5,000 random scaled values", () => {
    let mismatches = 0;
    for (let i = 0; i < 5000; i++) {
      // Random value in $0.000 … $99,999.999 (3 decimal places).
      const v = Math.round(Math.random() * 100_000_000) / 1_000;
      const ours = roundToCents(v);
      const ref = pgRoundToCents(v);
      if (ours !== ref) mismatches++;
    }
    expect(mismatches).toBe(0);
  });

  it("explicit half-to-even at every position 0..99 cents", () => {
    // For each pair of adjacent cents x.x05 we expect rounding to the
    // even cent. We sweep 0..99 to confirm coverage of the even/odd
    // toggle without false positives.
    for (let cents = 0; cents < 100; cents++) {
      const half = cents + 0.005;
      const value = 1 + half / 100; // 1.005, 1.015, …
      // Reference computed in BigInt (no FP drift).
      const ref = pgRoundToCents(value);
      const ours = roundToCents(value);
      expect(ours).toBe(ref);
    }
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// calcPercentFee
// ─────────────────────────────────────────────────────────────────────────────

describe("calcPercentFee", () => {
  it("matches the documented examples", () => {
    expect(calcPercentFee(60, 3.0)).toBe(1.8);
    expect(calcPercentFee(100, 3.0)).toBe(3.0);
    expect(calcPercentFee(33.33, 3.0)).toBe(1.0);
    expect(calcPercentFee(1, 3.0)).toBe(0.03);
    expect(calcPercentFee(500, 1.0)).toBe(5.0);
    expect(calcPercentFee(200, 0.75)).toBe(1.5);
  });

  it("uses banker's rounding (matches Postgres ROUND, not Math.round)", () => {
    // 0.5 * 1.0 / 100 = 0.005 → banker's: 0.00 (even); Math.round: 0.01
    expect(calcPercentFee(0.5, 1.0)).toBe(0.0);
    // 2.5 * 1.0 / 100 = 0.025 → banker's: 0.02 (even); Math.round: 0.03
    expect(calcPercentFee(2.5, 1.0)).toBe(0.02);
    // 1.5 * 1.0 / 100 = 0.015 → banker's: 0.02 (even); Math.round: 0.02
    expect(calcPercentFee(1.5, 1.0)).toBe(0.02);
    // 3.5 * 1.0 / 100 = 0.035 → banker's: 0.04 (even); Math.round: 0.04
    expect(calcPercentFee(3.5, 1.0)).toBe(0.04);
  });

  it("matches Postgres ROUND for 5,000 random (gross, rate) pairs", () => {
    const mismatches: Array<{ g: number; r: number; ours: number; ref: number }> = [];
    for (let i = 0; i < 5000; i++) {
      // gross ∈ $0.00 … $9,999.99
      const gross = Math.round(Math.random() * 999_999) / 100;
      // ratePct ∈ 0.00% … 9.99%, 2 decimals (matches platform_fee_config.rate_pct)
      const ratePct = Math.round(Math.random() * 999) / 100;
      const ours = calcPercentFee(gross, ratePct);
      const ref = pgCalcPercentFee(gross, ratePct);
      if (ours !== ref) mismatches.push({ g: gross, r: ratePct, ours, ref });
    }
    if (mismatches.length > 0) {
      // Surface the first divergence for debuggability.
      // eslint-disable-next-line no-console
      console.error("first divergences:", mismatches.slice(0, 5));
    }
    expect(mismatches).toEqual([]);
  });

  it("does not diverge from old `Math.round(g*r)/100` on the documented happy paths", () => {
    // The old formula's happy-path outputs are preserved (so existing
    // settlement rows remain reconcilable); only the corner cases at
    // exact halves and IEEE-drift fix.
    const cases: Array<[number, number]> = [
      [60, 3.0],
      [100, 3.0],
      [25, 3.0],
      [500, 1.0],
      [200, 0.75],
    ];
    for (const [g, r] of cases) {
      const oldFormula = Math.round(g * r) / 100;
      expect(calcPercentFee(g, r)).toBe(oldFormula);
    }
  });

  it("rejects non-finite", () => {
    expect(() => calcPercentFee(NaN, 3.0)).toThrow();
    expect(() => calcPercentFee(100, NaN)).toThrow();
    expect(() => calcPercentFee(Infinity, 1.0)).toThrow();
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// subtractMoney / addMoney / multiplyMoney
// ─────────────────────────────────────────────────────────────────────────────

describe("subtractMoney", () => {
  it("absorbs IEEE-754 drift", () => {
    // Without quantisation: 100 - 3 = 97.00000000000001 in some
    // hosts; expect exact 97.
    expect(subtractMoney(100, 3.0)).toBe(97.0);
    expect(subtractMoney(60, 1.8)).toBe(58.2);
    expect(subtractMoney(0.3, 0.1)).toBe(0.2);
  });

  it("commutes with calcPercentFee for net = gross - fee", () => {
    const gross = 60;
    const rate = 3.0;
    const fee = calcPercentFee(gross, rate);
    expect(fee).toBe(1.8);
    expect(subtractMoney(gross, fee)).toBe(58.2);
  });
});

describe("addMoney", () => {
  it("absorbs IEEE-754 drift", () => {
    expect(addMoney(0.1, 0.2)).toBe(0.3);
    expect(addMoney(58.2, 1.8)).toBe(60);
  });
});

describe("multiplyMoney", () => {
  it("rounds product to cents", () => {
    expect(multiplyMoney(100, 1.0)).toBe(100);
    expect(multiplyMoney(100, 0.005)).toBe(0.5);
    // 50 * 0.075 = 3.75; banker's: stays 3.75
    expect(multiplyMoney(50, 0.075)).toBe(3.75);
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// calcSplit
// ─────────────────────────────────────────────────────────────────────────────

describe("calcSplit", () => {
  it("trivial 70/30 of 100", () => {
    const r = calcSplit(100, 70);
    expect(r.counterparty).toBe(70);
    expect(r.platform).toBe(30);
    expect(r.counterparty + r.platform).toBe(100);
  });

  it("preserves total exactly even when the percentage rounds", () => {
    const r = calcSplit(33.33, 33);
    // 33.33 * 33 / 100 = 10.9989 → banker's: 11.00 (rounds up; 9>5)
    expect(r.counterparty).toBe(11.0);
    expect(r.platform).toBe(22.33);
    expect(addMoney(r.counterparty, r.platform)).toBe(33.33);
  });

  it("100% goes entirely to counterparty", () => {
    const r = calcSplit(99.99, 100);
    expect(r.counterparty).toBe(99.99);
    expect(r.platform).toBe(0);
  });

  it("0% goes entirely to platform", () => {
    const r = calcSplit(99.99, 0);
    expect(r.counterparty).toBe(0);
    expect(r.platform).toBe(99.99);
  });

  it("never loses or invents cents in 1,000 random splits", () => {
    let drifts = 0;
    for (let i = 0; i < 1000; i++) {
      const total = Math.round(Math.random() * 100_000) / 100;
      const splitPct = Math.round(Math.random() * 10_000) / 100;
      const r = calcSplit(total, splitPct);
      if (addMoney(r.counterparty, r.platform) !== total) drifts++;
    }
    expect(drifts).toBe(0);
  });
});
