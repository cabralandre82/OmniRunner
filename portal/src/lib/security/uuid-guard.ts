/**
 * L01-50 — UUID guards for PostgREST .or() / .eq() composition
 *
 * PostgREST parses `.or("a.eq.X,b.eq.Y")` server-side. If `X` or `Y`
 * is attacker-controlled and contains `,` or `)`, the resulting OR
 * expression can leak rows from groups outside the caller's scope.
 *
 * This module is pure (no I/O, no Supabase client). All call sites
 * that interpolate a uuid into a PostgREST expression MUST pass it
 * through `assertUuid` first. The CI guard
 * `tools/audit/check-uuid-guard.ts` enforces this by failing on any
 * `.or(\`...${...}\`)` template literal that does not have a
 * preceding `assertUuid` call in the same function body.
 */

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export class InvalidUuidError extends Error {
  readonly name = "InvalidUuidError";
  constructor(label: string, value: unknown) {
    super(
      `L01-50: ${label} must be a v1-5 UUID (received: ${
        typeof value === "string" ? `"${value.slice(0, 64)}"` : typeof value
      })`,
    );
  }
}

export function isUuid(value: unknown): value is string {
  return typeof value === "string" && UUID_RE.test(value);
}

export function assertUuid(value: unknown, label: string): string {
  if (!isUuid(value)) throw new InvalidUuidError(label, value);
  return value;
}

/**
 * Convenience helper for the `.or()` pattern used by getSwapOrdersForGroup
 * and getSettlementsForGroup. Both columns must be valid PostgREST
 * column names (caller-controlled, never from user input).
 */
export function buildOrEqExpression(
  columnA: string,
  columnB: string,
  uuid: string,
  label: string,
): string {
  assertUuid(uuid, label);
  if (!/^[a-z_][a-z0-9_]*$/i.test(columnA) || !/^[a-z_][a-z0-9_]*$/i.test(columnB)) {
    throw new Error(`L01-50: column names must be safe identifiers`);
  }
  return `${columnA}.eq.${uuid},${columnB}.eq.${uuid}`;
}
