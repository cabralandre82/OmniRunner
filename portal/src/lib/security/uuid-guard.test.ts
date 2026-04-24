import { describe, it, expect } from "vitest";
import {
  assertUuid,
  buildOrEqExpression,
  InvalidUuidError,
  isUuid,
} from "./uuid-guard";

const VALID_V4 = "550e8400-e29b-41d4-a716-446655440000";
const VALID_V1 = "00000000-0000-1000-8000-000000000000";

describe("L01-50 uuid-guard", () => {
  it("accepts a v4 UUID", () => {
    expect(isUuid(VALID_V4)).toBe(true);
  });

  it("accepts a v1 UUID", () => {
    expect(isUuid(VALID_V1)).toBe(true);
  });

  it("rejects truncated UUID", () => {
    expect(isUuid("550e8400-e29b-41d4-a716-44665544000")).toBe(false);
  });

  it("rejects non-UUID string with PostgREST injection chars", () => {
    expect(isUuid("anything,buyer_group_id.eq.x")).toBe(false);
  });

  it("rejects empty string and non-strings", () => {
    expect(isUuid("")).toBe(false);
    expect(isUuid(undefined)).toBe(false);
    expect(isUuid(123)).toBe(false);
    expect(isUuid(null)).toBe(false);
  });

  it("assertUuid throws InvalidUuidError on invalid input", () => {
    expect(() => assertUuid("nope", "groupId")).toThrowError(InvalidUuidError);
    expect(() => assertUuid("nope", "groupId")).toThrowError(/L01-50/);
  });

  it("assertUuid returns the value when valid", () => {
    expect(assertUuid(VALID_V4, "groupId")).toBe(VALID_V4);
  });

  it("buildOrEqExpression composes a safe filter string", () => {
    const expr = buildOrEqExpression(
      "seller_group_id",
      "buyer_group_id",
      VALID_V4,
      "groupId",
    );
    expect(expr).toBe(
      `seller_group_id.eq.${VALID_V4},buyer_group_id.eq.${VALID_V4}`,
    );
  });

  it("buildOrEqExpression refuses unsafe column identifiers", () => {
    expect(() =>
      buildOrEqExpression(
        "seller_group_id;DROP TABLE",
        "buyer_group_id",
        VALID_V4,
        "groupId",
      ),
    ).toThrowError(/safe identifiers/);
  });

  it("buildOrEqExpression refuses non-uuid input (PostgREST injection)", () => {
    expect(() =>
      buildOrEqExpression(
        "seller_group_id",
        "buyer_group_id",
        "evil),(or some.eq.x",
        "groupId",
      ),
    ).toThrowError(InvalidUuidError);
  });
});
