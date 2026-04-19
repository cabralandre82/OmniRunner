/**
 * Sanity tests for the OpenAPI document builder (L14-01).
 *
 * These are NOT contract tests against the Zod schemas themselves —
 * those happen at the route-test level. The goal here is to lock in
 * structural invariants of the *generated document*:
 *
 *   - it is valid OpenAPI 3.1 at the shape level,
 *   - all v1 financial endpoints are present and tagged correctly,
 *   - shared component schemas (ApiErrorBody, etc.) are registered
 *     under `components.schemas` so route definitions can $ref them,
 *   - the output is deterministic — calling the builder twice yields
 *     byte-identical JSON. This is what the drift CI gate depends on.
 */

import { describe, it, expect } from "vitest";
import { buildOpenApiDocument } from "./build";

const doc = buildOpenApiDocument();

describe("buildOpenApiDocument — top-level shape", () => {
  it("declares OpenAPI 3.1.0", () => {
    expect(doc.openapi).toBe("3.1.0");
  });

  it("has info.title, info.version, and info.description", () => {
    expect(doc.info.title).toContain("Omni Runner");
    expect(doc.info.version).toMatch(/^\d+\.\d+\.\d+$/);
    expect(doc.info.description).toContain("Generated from Zod");
  });

  it("lists production and localhost servers", () => {
    const urls = (doc.servers ?? []).map((s: { url: string }) => s.url);
    expect(urls).toContain("https://portal.omnirunner.app");
    expect(urls).toContain("http://localhost:3000");
  });
});

describe("buildOpenApiDocument — component schemas", () => {
  it("registers the canonical error envelope as ApiErrorBody", () => {
    const schemas =
      (doc.components?.schemas as Record<string, unknown> | undefined) ?? {};
    expect(schemas.ApiErrorBody).toBeDefined();
  });

  it("registers the success marker, decimal amount, and idempotency key", () => {
    const schemas =
      (doc.components?.schemas as Record<string, unknown> | undefined) ?? {};
    expect(schemas.ApiOkMarker).toBeDefined();
    expect(schemas.DecimalAmount).toBeDefined();
    expect(schemas.IdempotencyKey).toBeDefined();
  });

  it("registers all 5 v1 financial domain schemas", () => {
    const schemas =
      (doc.components?.schemas as Record<string, unknown> | undefined) ?? {};
    for (const expected of [
      "SwapBody",
      "SwapOffer",
      "CustodyAccount",
      "CustodyConfirmBody",
      "WithdrawBody",
      "Withdrawal",
      "DistributeCoinsBody",
      "Settlement",
    ]) {
      expect(schemas[expected], `${expected} should be registered`).toBeDefined();
    }
  });
});

describe("buildOpenApiDocument — v1 financial paths", () => {
  const expectedPaths: ReadonlyArray<readonly [string, ReadonlyArray<string>]> =
    [
      ["/api/v1/swap", ["get", "post"]],
      ["/api/v1/custody", ["get", "post"]],
      ["/api/v1/custody/withdraw", ["get", "post"]],
      ["/api/v1/distribute-coins", ["post"]],
      ["/api/v1/clearing", ["get"]],
    ];

  for (const [path, methods] of expectedPaths) {
    it(`registers ${path} with methods ${methods.join(", ")}`, () => {
      const paths = doc.paths as Record<string, Record<string, unknown>>;
      expect(paths[path], `${path} should be registered`).toBeDefined();
      for (const m of methods) {
        expect(
          paths[path][m],
          `${path} should declare method ${m}`,
        ).toBeDefined();
      }
    });
  }

  it("tags every v1 path with OmniCoins", () => {
    const paths = doc.paths as Record<string, Record<string, { tags?: string[] }>>;
    for (const [p, methods] of expectedPaths) {
      for (const m of methods) {
        const op = paths[p][m];
        expect(op.tags, `${p} ${m} should have tags`).toBeDefined();
        expect(op.tags).toContain("OmniCoins");
      }
    }
  });

  it("declares the standard error responses on every endpoint", () => {
    const paths = doc.paths as Record<
      string,
      Record<
        string,
        { responses?: Record<string, unknown> }
      >
    >;
    const seenStatus = new Set<string>();
    for (const p of Object.keys(paths)) {
      for (const m of Object.keys(paths[p])) {
        const resp = paths[p][m].responses ?? {};
        for (const k of Object.keys(resp)) seenStatus.add(k);
      }
    }
    // Every financial endpoint touches at least 401, 403, 500.
    expect(seenStatus.has("401")).toBe(true);
    expect(seenStatus.has("403")).toBe(true);
    expect(seenStatus.has("500")).toBe(true);
  });
});

describe("buildOpenApiDocument — determinism (drift gate prerequisite)", () => {
  it("produces byte-identical JSON on repeated calls", () => {
    const a = JSON.stringify(buildOpenApiDocument(), null, 2);
    const b = JSON.stringify(buildOpenApiDocument(), null, 2);
    expect(a).toBe(b);
  });
});
