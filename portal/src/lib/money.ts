/**
 * Money math helpers (L03-01).
 *
 * Single source of truth for monetary arithmetic in the portal. Replaces
 * the patchwork of `Math.round(x * y) / 100` and `Math.round(x * 100) /
 * 100` that previously diverged from the SQL helpers used inside
 * `execute_burn_atomic`, `execute_swap`, and `execute_withdrawal`.
 *
 * # Why not just `Number`?
 *
 * The platform stores all monetary values as `numeric(14,2)` in
 * Postgres. Postgres `numeric` is decimal, exact, and uses **banker's
 * rounding** (half-to-even) for `ROUND(x, 2)`. JavaScript `Number` is
 * IEEE-754 double precision binary and `Math.round(x)` rounds half
 * **away from zero** (toward +∞ for positives). The two diverge in two
 * distinct ways:
 *
 *   1. **Floating-point representation.** Products of two `numeric(_,2)`
 *      values have up to 4 fractional digits — not representable
 *      exactly in IEEE-754 in general. Naively dividing by 100 and
 *      rounding therefore loses the precision needed to disambiguate
 *      the rounding direction at the cent boundary.
 *
 *   2. **Rounding mode.** For exact halves the two differ:
 *      `Math.round(0.5) = 1`, `Postgres ROUND(0.005, 2) = 0.00`
 *      (half-to-even: 0 is even). At ~5k clearings/day in GA, even a
 *      1-in-200 divergence is a daily reconciliation discrepancy.
 *
 * # Implementation
 *
 * To replicate Postgres `numeric` semantics without pulling in a full
 * decimal library, we operate internally on `BigInt` mantissas plus a
 * decimal scale. The flow for `calcPercentFee(g, r)` is:
 *
 *   1. Decode each input via its `.toString()` representation, which
 *      JS guarantees is the shortest decimal string round-tripping to
 *      the same number — i.e. the value the developer "wrote".
 *   2. Multiply mantissas as BigInt (exact); add scales.
 *   3. Add 2 to the scale (the `/100` in the percentage formula).
 *   4. Round to scale 2 using banker's rounding on the BigInt remainder.
 *
 * This is bit-identical to Postgres `ROUND((g * r / 100)::numeric, 2)`
 * for any inputs whose JS-canonical string form is what the SQL helper
 * also receives — which is the case for every value loaded from the
 * DB or supplied via JSON.
 *
 * # Where this is used
 *
 *   - `clearing.ts`             — `feeUsd = calcPercentFee(grossUsd, feeRate)`
 *   - `swap.ts`                 — `feeAmount = calcPercentFee(amountUsd, feeRate)`
 *   - `custody.ts`              — `convertToUsdWithSpread`, `convertFromUsdWithSpread`
 *   - `billing/edge-cases.ts`   — `calculateSplitValue`
 *   - `qa-reconciliation.test.ts` — fee model checks
 *
 * # Where this is NOT used
 *
 *   - SQL functions (`execute_burn_atomic`, `execute_swap`,
 *     `execute_withdrawal`) compute fees natively in `numeric(14,2)`.
 *     The TS helpers exist to produce the same value the SQL helper
 *     *would* produce, for UI previews and pre-flight calculations.
 *   - The mobile app does not compute fees client-side; it consumes
 *     server-provided values.
 */

// ─────────────────────────────────────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Maximum monetary magnitude we will accept in cents. Mirrors the
 * `numeric(14,2)` column constraints used across the schema. Rejecting
 * out-of-range inputs early prevents silent overflow into floats whose
 * least-significant bit no longer represents 0.01 USD.
 *
 * `numeric(14,2)` permits up to 12 digits before the decimal, i.e.
 * $9_999_999_999_999.99. In cents, that is 999_999_999_999_999 — within
 * `Number.MAX_SAFE_INTEGER (2^53 - 1 = 9_007_199_254_740_991)`.
 */
export const MAX_MONEY_CENTS = 999_999_999_999_999;

// ─────────────────────────────────────────────────────────────────────────────
// Internal: decimal decoding via the JS canonical string form
// ─────────────────────────────────────────────────────────────────────────────

interface Decimal {
  /** Signed integer mantissa. */
  mantissa: bigint;
  /** Number of fractional digits. Always ≥ 0. */
  scale: number;
}

const BIG_ZERO = BigInt(0);
const BIG_ONE = BigInt(1);
const BIG_TWO = BigInt(2);
const BIG_TEN = BigInt(10);

/**
 * Exponentiation `10 ** n` over BigInt. Avoids the `**` operator,
 * which `tsc` rejects without `target: "es2016"`. Cached for the
 * scales we routinely see (0..18) to keep the hot path allocation-free.
 *
 * @internal
 */
const POW10_CACHE: bigint[] = (() => {
  const arr: bigint[] = [BIG_ONE];
  for (let i = 1; i <= 18; i++) {
    arr.push(arr[i - 1] * BIG_TEN);
  }
  return arr;
})();

function pow10(n: number): bigint {
  if (n < 0) throw new Error(`pow10: negative exponent ${n}`);
  if (n < POW10_CACHE.length) return POW10_CACHE[n];
  let result = BIG_ONE;
  for (let i = 0; i < n; i++) result *= BIG_TEN;
  return result;
}

/**
 * Decode a JS `number` into (mantissa: bigint, scale: number) using
 * the shortest decimal string that round-trips to the same `number`
 * (which is what JS `value.toString()` returns).
 *
 * Examples:
 *   3.0     → { mantissa: 30n,        scale: 1 }
 *   33.33   → { mantissa: 3333n,      scale: 2 }
 *   0.0001  → { mantissa: 1n,         scale: 4 }
 *   1e-7    → { mantissa: 1n,         scale: 7 }
 *   1.5e3   → { mantissa: 1500n,      scale: 0 }
 *
 * @internal
 */
function decodeDecimal(value: number): Decimal {
  if (!Number.isFinite(value)) {
    throw new Error(`money: non-finite input ${value}`);
  }
  const str = value.toString();
  // Exponent notation, e.g. "1e-7" or "2.5e+10"
  if (/e/i.test(str)) {
    const [mantStr, expStr] = str.toLowerCase().split("e");
    const exp = parseInt(expStr, 10);
    const sign = mantStr.startsWith("-") ? -BIG_ONE : BIG_ONE;
    const cleanMant = mantStr.replace(/^-/, "");
    const dotIdx = cleanMant.indexOf(".");
    const digits = cleanMant.replace(".", "");
    const fracLen = dotIdx === -1 ? 0 : cleanMant.length - dotIdx - 1;
    const scale = fracLen - exp;
    const mantissa = sign * BigInt(digits);
    if (scale >= 0) return { mantissa, scale };
    return {
      mantissa: mantissa * pow10(-scale),
      scale: 0,
    };
  }
  const sign = str.startsWith("-") ? -BIG_ONE : BIG_ONE;
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
 * Round a Decimal to `targetScale` fractional digits using banker's
 * rounding (half-to-even). Identical to Postgres `ROUND(x::numeric, n)`
 * for any value representable as a `numeric`.
 *
 * @internal
 */
function roundDecimal(d: Decimal, targetScale: number): Decimal {
  if (d.scale === targetScale) return d;
  if (d.scale < targetScale) {
    return { mantissa: d.mantissa * pow10(targetScale - d.scale), scale: targetScale };
  }
  const dropDigits = d.scale - targetScale;
  const divisor = pow10(dropDigits);
  const half = divisor / BIG_TWO;
  const sign = d.mantissa < BIG_ZERO ? -BIG_ONE : BIG_ONE;
  const abs = d.mantissa < BIG_ZERO ? -d.mantissa : d.mantissa;
  const quotient = abs / divisor;
  const remainder = abs % divisor;
  let rounded: bigint;
  if (remainder < half) {
    rounded = quotient;
  } else if (remainder > half) {
    rounded = quotient + BIG_ONE;
  } else {
    rounded = quotient % BIG_TWO === BIG_ZERO ? quotient : quotient + BIG_ONE;
  }
  return { mantissa: sign * rounded, scale: targetScale };
}

/**
 * Convert a Decimal back to a JS number with the requested scale.
 * The result may not be exactly representable in IEEE-754 (e.g. 0.1)
 * but round-trips through `decodeDecimal` cleanly thanks to
 * `Number.toString`'s shortest-string guarantee.
 *
 * @internal
 */
function decimalToNumber(d: Decimal): number {
  if (d.scale === 0) {
    return Number(d.mantissa);
  }
  // For very large mantissas we need to be careful about precision —
  // but our domain is capped at `numeric(14,2)`, so the absolute
  // mantissa fits in MAX_SAFE_INTEGER comfortably.
  const sign = d.mantissa < BIG_ZERO ? -1 : 1;
  const abs = d.mantissa < BIG_ZERO ? -d.mantissa : d.mantissa;
  const divisor = Math.pow(10, d.scale);
  return (sign * Number(abs)) / divisor;
}

/**
 * Validate that the integer-cents form is within the `numeric(14,2)`
 * envelope. Throws otherwise so the caller fails fast at the boundary
 * rather than silently rounding a value the DB would reject anyway.
 *
 * @internal
 */
function assertWithinRange(d: Decimal): void {
  // After roundDecimal(d, 2) the mantissa is exactly cents.
  if (d.scale !== 2) {
    throw new Error(
      `money: assertWithinRange called with scale=${d.scale} (expected 2)`,
    );
  }
  const abs = d.mantissa < BIG_ZERO ? -d.mantissa : d.mantissa;
  if (abs > BigInt(MAX_MONEY_CENTS)) {
    throw new Error(
      `money: value out of range — exceeds numeric(14,2)`,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Public API
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Round a monetary value to 2 decimal places using banker's rounding
 * (half-to-even), matching Postgres `ROUND(value::numeric, 2)`.
 *
 *   roundToCents(1.005)               // 1.00 (half-to-even: 0 is even)
 *   roundToCents(1.015)               // 1.02 (half-to-even: 2 is even)
 *   roundToCents(2.345)               // 2.34 (half-to-even: 4 is even)
 *   roundToCents(2.355)               // 2.36 (half-to-even: 6 is even)
 *   roundToCents(0.30000000000000004) // 0.30 (IEEE drift absorbed)
 */
export function roundToCents(value: number): number {
  const d = decodeDecimal(value);
  const r = roundDecimal(d, 2);
  assertWithinRange(r);
  return decimalToNumber(r);
}

/**
 * Compute a percentage fee, rounded to 2 decimal places via banker's
 * rounding. Equivalent SQL:
 *
 *   ROUND((gross * ratePct / 100)::numeric, 2)
 *
 * which is exactly the formula used by `execute_burn_atomic` (see
 * `supabase/migrations/20260417140000_execute_burn_atomic_hardening.sql`)
 * and by `gateway_fee_backing_fix`.
 *
 * Both `gross` and `ratePct` are unitless `number`s; `ratePct` is in
 * percentage points (e.g. `3.0` for "3%"). Returns the fee in the
 * same unit as `gross`.
 *
 *   calcPercentFee(60,    3.0)  // 1.80
 *   calcPercentFee(100,   3.0)  // 3.00
 *   calcPercentFee(33.33, 3.0)  // 1.00
 *   calcPercentFee(0.5,   1.0)  // 0.00 (banker's: 0 is even)
 *   calcPercentFee(2.5,   1.0)  // 0.02 (banker's: 2 is even)
 */
export function calcPercentFee(gross: number, ratePct: number): number {
  if (!Number.isFinite(gross) || !Number.isFinite(ratePct)) {
    throw new Error(
      `money.calcPercentFee: non-finite inputs (gross=${gross}, ratePct=${ratePct})`,
    );
  }
  const g = decodeDecimal(gross);
  const r = decodeDecimal(ratePct);
  // Multiply and divide by 100 (i.e. add 2 to scale).
  const product: Decimal = {
    mantissa: g.mantissa * r.mantissa,
    scale: g.scale + r.scale + 2,
  };
  const rounded = roundDecimal(product, 2);
  assertWithinRange(rounded);
  return decimalToNumber(rounded);
}

/**
 * Subtract `b` from `a` and quantise to cents. Use this whenever you
 * need `net = gross - fee` to avoid IEEE-754 noise like
 * `100 - 3.0 = 97.00000000000001`.
 *
 *   subtractMoney(100, 3)   // 97.00
 *   subtractMoney(60, 1.80) // 58.20
 */
export function subtractMoney(a: number, b: number): number {
  if (!Number.isFinite(a) || !Number.isFinite(b)) {
    throw new Error(
      `money.subtractMoney: non-finite inputs (a=${a}, b=${b})`,
    );
  }
  const da = decodeDecimal(a);
  const db = decodeDecimal(b);
  const targetScale = Math.max(da.scale, db.scale);
  const aMant = da.mantissa * pow10(targetScale - da.scale);
  const bMant = db.mantissa * pow10(targetScale - db.scale);
  const diff: Decimal = { mantissa: aMant - bMant, scale: targetScale };
  const rounded = roundDecimal(diff, 2);
  assertWithinRange(rounded);
  return decimalToNumber(rounded);
}

/**
 * Add two monetary values, quantising to cents.
 */
export function addMoney(a: number, b: number): number {
  if (!Number.isFinite(a) || !Number.isFinite(b)) {
    throw new Error(`money.addMoney: non-finite inputs (a=${a}, b=${b})`);
  }
  const da = decodeDecimal(a);
  const db = decodeDecimal(b);
  const targetScale = Math.max(da.scale, db.scale);
  const aMant = da.mantissa * pow10(targetScale - da.scale);
  const bMant = db.mantissa * pow10(targetScale - db.scale);
  const sum: Decimal = { mantissa: aMant + bMant, scale: targetScale };
  const rounded = roundDecimal(sum, 2);
  assertWithinRange(rounded);
  return decimalToNumber(rounded);
}

/**
 * Multiply a monetary value by a unit-less factor and quantise to cents.
 * Useful for FX conversion: `convertedUsd = multiplyMoney(local, 1/fx)`.
 */
export function multiplyMoney(a: number, factor: number): number {
  if (!Number.isFinite(a) || !Number.isFinite(factor)) {
    throw new Error(
      `money.multiplyMoney: non-finite inputs (a=${a}, factor=${factor})`,
    );
  }
  const da = decodeDecimal(a);
  const df = decodeDecimal(factor);
  const product: Decimal = {
    mantissa: da.mantissa * df.mantissa,
    scale: da.scale + df.scale,
  };
  const rounded = roundDecimal(product, 2);
  assertWithinRange(rounded);
  return decimalToNumber(rounded);
}

/**
 * Parse a user-entered decimal *string* into integer cents (L03-17).
 *
 * # Why a string-only path?
 *
 * The naive recipe `Math.round(parseFloat(s) * 100)` throws away the
 * exact decimal the user typed by routing it through IEEE-754. The
 * canonical regression case is `"1.105"`:
 *
 *   parseFloat("1.105")        // 1.105  (rounded for display)
 *   parseFloat("1.105") * 100  // 110.49999999999999
 *   Math.round(110.4999…)      // 110   ← expected 111 cents
 *
 * That single mis-rounding silently shaves a centavo off every product
 * priced in fractional reais. At the platform's BRL price column it
 * also propagates into the BRL→OmniCoin unit-price displayed in the
 * shop, so the discrepancy is *visible* to athletes and a recurring
 * support ticket source.
 *
 * # Strategy
 *
 * Operate on the typed string directly:
 *
 *   1. Sanitise — trim, accept either "," or "." as the decimal mark
 *      (the Brazilian portal hands us comma-formatted input from
 *      `<input type="text" inputMode="decimal">`).
 *   2. Strip thousands separators inferred from the position of the
 *      *other* mark relative to the decimal one. We deliberately do
 *      NOT call `Intl.NumberFormat#parse` — its locale-resolution
 *      behaviour is browser-dependent and not portable to the test
 *      runtime.
 *   3. Validate the canonical form against `^-?\d+(\.\d+)?$`.
 *   4. Quantise: if the fractional part has > 2 digits, apply
 *      banker's rounding (half-to-even) to the dropped tail using
 *      BigInt arithmetic — bit-identical to Postgres
 *      `ROUND(x::numeric, 2)`.
 *   5. Convert the (now exactly-2-fractional-digit) string into an
 *      integer cents `number`. The result is a safe integer for any
 *      input within `±MAX_MONEY_CENTS`, validated explicitly.
 *
 * # Examples
 *
 *   parseDecimalToCents("0.295")     // 30    ← parseFloat(0.295)*100 = 29.4999…, Math.round → 29 (lost a cent)
 *   parseDecimalToCents("1.235")     // 124   ← parseFloat(1.235)*100 = 123.499…, Math.round → 123 (lost a cent)
 *   parseDecimalToCents("0,295")     // 30    ← Brazilian comma-decimal accepted
 *   parseDecimalToCents("1.005")     // 100   ← banker's: 0 is even (matches Postgres ROUND)
 *   parseDecimalToCents("1.015")     // 102   ← banker's: 2 is even
 *   parseDecimalToCents("1.115")     // 112   ← banker's; old half-up Math.round also returned 111 (wrong by Postgres)
 *   parseDecimalToCents("1.5")       // 150
 *   parseDecimalToCents("42")        // 4200
 *   parseDecimalToCents("-3.50")     // -350
 *   parseDecimalToCents("  1,99  ")  // 199
 *   parseDecimalToCents("1.234,56")  // 123456 (BR thousands + comma decimal)
 *   parseDecimalToCents("1,234.56")  // 123456 (US thousands + dot decimal)
 *
 * # Errors (throws `Error`)
 *
 *   ""           → "money: empty input"
 *   "abc"        → "money: malformed decimal …"
 *   "1.2.3"      → "money: malformed decimal …"
 *   "1e5"        → "money: malformed decimal …" (rejecting exponent
 *                                                notation in user input
 *                                                is intentional — UIs
 *                                                that need it should
 *                                                pre-normalise)
 *   value above MAX_MONEY_CENTS → "money: value out of range …"
 */
export function parseDecimalToCents(input: string): number {
  if (typeof input !== "string") {
    throw new Error(`money.parseDecimalToCents: non-string input (${typeof input})`);
  }
  const trimmed = input.trim();
  if (trimmed.length === 0) {
    throw new Error("money: empty input");
  }

  // ── Detect sign, then work on the absolute string ──────────────────────────
  let sign: bigint = BIG_ONE;
  let body = trimmed;
  if (body.startsWith("-")) {
    sign = -BIG_ONE;
    body = body.slice(1).trimStart();
  } else if (body.startsWith("+")) {
    body = body.slice(1).trimStart();
  }
  if (body.length === 0) {
    throw new Error(`money: malformed decimal "${input}" (sign without digits)`);
  }

  // ── Resolve the decimal separator vs thousands separator ──────────────────
  //
  // We support four typed shapes commonly produced by `<input>`:
  //   "1234.56"      ─ single ".",  decimal mark = "."
  //   "1234,56"      ─ single ",",  decimal mark = ","
  //   "1,234.56"     ─ both, "." rightmost → "." is decimal, "," is thousands
  //   "1.234,56"     ─ both, "," rightmost → "," is decimal, "." is thousands
  //
  // Unknown shapes (e.g. "1,2,3,4" or "1.234.567") fail the
  // post-strip regex below — we don't try to outsmart bad input.
  const lastDot = body.lastIndexOf(".");
  const lastComma = body.lastIndexOf(",");
  let normalised: string;
  if (lastDot === -1 && lastComma === -1) {
    normalised = body;
  } else if (lastDot === -1) {
    normalised = body.replace(/,/g, ".");
  } else if (lastComma === -1) {
    normalised = body;
  } else if (lastDot > lastComma) {
    // "1,234.56" → drop the commas (thousands), keep the dot (decimal)
    normalised = body.replace(/,/g, "");
  } else {
    // "1.234,56" → drop the dots (thousands), swap comma for dot
    normalised = body.replace(/\./g, "").replace(",", ".");
  }

  if (!/^\d+(\.\d+)?$/.test(normalised)) {
    throw new Error(`money: malformed decimal "${input}"`);
  }

  // ── Decode into (mantissa, scale) over BigInt (no IEEE-754 anywhere) ──────
  const dotIdx = normalised.indexOf(".");
  let intPart: string;
  let fracPart: string;
  if (dotIdx === -1) {
    intPart = normalised;
    fracPart = "";
  } else {
    intPart = normalised.slice(0, dotIdx);
    fracPart = normalised.slice(dotIdx + 1);
  }
  // Strip leading zeros to keep the BigInt allocation tight; preserve
  // at least one digit so "0" / "0.5" still parse.
  intPart = intPart.replace(/^0+(?=\d)/, "");
  const rawMantissa = BigInt(intPart + fracPart);
  const decimal: Decimal = {
    mantissa: sign * rawMantissa,
    scale: fracPart.length,
  };

  // ── Quantise to cents using banker's rounding (matches Postgres) ──────────
  const cents = roundDecimal(decimal, 2);
  assertWithinRange(cents);

  // cents.scale === 2, cents.mantissa is exactly the integer cents.
  // Number() over a BigInt within MAX_SAFE_INTEGER is lossless.
  return Number(cents.mantissa);
}

/**
 * Split a total into (counterparty, platform) by percentage.
 * `splitPct` is the counterparty's share in percentage points; the
 * platform keeps the remainder. Both halves sum exactly to `total`
 * (the platform absorbs any rounding residue).
 *
 *   calcSplit(100, 70)   // { counterparty: 70.00, platform: 30.00 }
 *   calcSplit(33.33, 33) // { counterparty: 11.00, platform: 22.33 }
 */
export function calcSplit(
  total: number,
  splitPct: number,
): { counterparty: number; platform: number } {
  const counterparty = calcPercentFee(total, splitPct);
  const platform = subtractMoney(total, counterparty);
  return { counterparty, platform };
}
