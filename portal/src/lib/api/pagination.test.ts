/**
 * Tests for L14-06 — cursor-based pagination contract.
 */

import { describe, it, expect } from "vitest";
import {
  encodeCursor,
  decodeCursor,
  parsePaginationParams,
  paginate,
  PaginationError,
  DEFAULT_PAGE_LIMIT,
  MAX_PAGE_LIMIT,
} from "./pagination";

function paramsOf(input: Record<string, string>): URLSearchParams {
  return new URLSearchParams(input);
}

describe("encodeCursor / decodeCursor — round-trip", () => {
  it("returns null for null/undefined input", () => {
    expect(encodeCursor(null)).toBeNull();
    expect(encodeCursor(undefined)).toBeNull();
  });

  it("encodes base64url (no +, /, =)", () => {
    const encoded = encodeCursor({ x: "y", n: 1 });
    expect(encoded).not.toBeNull();
    expect(encoded!).not.toMatch(/[+/=]/);
  });

  it("survives a round-trip with arbitrary JSON-shaped data", () => {
    const original = {
      created_at: "2026-04-17T20:30:00Z",
      id: "abc-123",
      special: "★",
    };
    const round = decodeCursor<typeof original>(encodeCursor(original)!);
    expect(round).toEqual(original);
  });

  it("decodeCursor throws PaginationError on non-base64url input", () => {
    expect(() => decodeCursor("***not base64***")).toThrow(PaginationError);
    try {
      decodeCursor("***");
    } catch (e) {
      expect((e as PaginationError).code).toBe("INVALID_CURSOR");
    }
  });

  it("decodeCursor throws PaginationError on non-JSON payload", () => {
    const malformed = Buffer.from("notjson")
      .toString("base64")
      .replace(/\+/g, "-")
      .replace(/\//g, "_")
      .replace(/=+$/g, "");
    expect(() => decodeCursor(malformed)).toThrow(PaginationError);
  });
});

describe("parsePaginationParams", () => {
  it("uses defaults when no params are provided", () => {
    const out = parsePaginationParams(paramsOf({}));
    expect(out.limit).toBe(DEFAULT_PAGE_LIMIT);
    expect(out.cursor).toBeNull();
  });

  it("clamps limit to MAX_PAGE_LIMIT", () => {
    const out = parsePaginationParams(paramsOf({ limit: "9999" }));
    expect(out.limit).toBe(MAX_PAGE_LIMIT);
  });

  it("rejects non-numeric limit with INVALID_LIMIT", () => {
    expect(() => parsePaginationParams(paramsOf({ limit: "abc" }))).toThrow(
      PaginationError,
    );
    try {
      parsePaginationParams(paramsOf({ limit: "abc" }));
    } catch (e) {
      expect((e as PaginationError).code).toBe("INVALID_LIMIT");
    }
  });

  it("rejects limit < 1 with INVALID_LIMIT", () => {
    expect(() => parsePaginationParams(paramsOf({ limit: "0" }))).toThrow(
      PaginationError,
    );
  });

  it("treats empty limit string as missing (uses default)", () => {
    expect(parsePaginationParams(paramsOf({ limit: "" })).limit).toBe(
      DEFAULT_PAGE_LIMIT,
    );
  });

  it("decodes the cursor when present", () => {
    const cursor = encodeCursor({ id: "row-1" })!;
    const out = parsePaginationParams<{ id: string }>(
      paramsOf({ cursor, limit: "10" }),
    );
    expect(out.limit).toBe(10);
    expect(out.cursor).toEqual({ id: "row-1" });
  });

  it("honours custom defaultLimit and maxLimit", () => {
    const out = parsePaginationParams(paramsOf({ limit: "75" }), {
      defaultLimit: 20,
      maxLimit: 25,
    });
    expect(out.limit).toBe(25);

    const def = parsePaginationParams(paramsOf({}), {
      defaultLimit: 20,
      maxLimit: 25,
    });
    expect(def.limit).toBe(20);
  });

  it("rejects malformed cursor with INVALID_CURSOR", () => {
    expect(() =>
      parsePaginationParams(paramsOf({ cursor: "not_base64!!!" })),
    ).toThrow(PaginationError);
  });

  it("treats empty cursor as null", () => {
    expect(parsePaginationParams(paramsOf({ cursor: "" })).cursor).toBeNull();
  });
});

describe("paginate", () => {
  type Row = { id: number; created_at: string };

  function makeRows(n: number): Row[] {
    return Array.from({ length: n }, (_, i) => ({
      id: i + 1,
      created_at: `2026-04-17T20:${String(i).padStart(2, "0")}:00Z`,
    }));
  }

  it("returns has_more=false and next_cursor=null when fewer rows than limit+1", () => {
    const out = paginate(makeRows(3), 5, (r) => ({ id: r.id }));
    expect(out.has_more).toBe(false);
    expect(out.next_cursor).toBeNull();
    expect(out.items).toHaveLength(3);
  });

  it("returns has_more=false when rows == limit (exact fit, no over-fetch sentinel)", () => {
    const out = paginate(makeRows(5), 5, (r) => ({ id: r.id }));
    expect(out.has_more).toBe(false);
    expect(out.next_cursor).toBeNull();
    expect(out.items).toHaveLength(5);
  });

  it("trims the over-fetched sentinel and emits a cursor when rows == limit + 1", () => {
    const out = paginate(makeRows(6), 5, (r) => ({ id: r.id }));
    expect(out.has_more).toBe(true);
    expect(out.items).toHaveLength(5);
    expect(out.next_cursor).not.toBeNull();
    const decoded = decodeCursor<{ id: number }>(out.next_cursor!);
    expect(decoded).toEqual({ id: 5 });
  });

  it("returns next_cursor=null on empty input", () => {
    const out = paginate<Row, { id: number }>([], 10, (r) => ({ id: r.id }));
    expect(out.has_more).toBe(false);
    expect(out.next_cursor).toBeNull();
    expect(out.items).toEqual([]);
  });

  it("never calls extractCursor on an over-fetched sentinel", () => {
    const calls: Row[] = [];
    paginate(makeRows(6), 5, (r) => {
      calls.push(r);
      return { id: r.id };
    });
    // exactly one invocation, on the LAST visible row (id=5), not the
    // over-fetched id=6 sentinel.
    expect(calls).toHaveLength(1);
    expect(calls[0].id).toBe(5);
  });
});
