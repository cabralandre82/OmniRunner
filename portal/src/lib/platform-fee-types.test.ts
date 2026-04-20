/**
 * Contract tests for `PLATFORM_FEE_TYPES` (L01-45).
 *
 * These tests are the "lockstep" guarantee: they fail loudly if any of the
 * five surfaces that consume this list drift apart. Specifically they
 * cross-check, in a single CI run:
 *
 *   • Zod enum on POST /api/platform/fees
 *   • FEE_TYPE_LABELS keys
 *   • OpenAPI enum in public/openapi.json
 *   • Postgres CHECK constraints in the canonical migration
 *
 * Adding a new fee_type that misses any one of these will fail this file.
 */

import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import { join } from "node:path";

import {
  PLATFORM_FEE_TYPES,
  FEE_TYPE_LABELS,
  isPlatformFeeType,
  platformFeeTypeSchema,
  type PlatformFeeType,
} from "./platform-fee-types";

const CANONICAL = [
  "clearing",
  "swap",
  "fx_spread",
  "billing_split",
  "maintenance",
] as const;

describe("PLATFORM_FEE_TYPES — canonical list (L01-45)", () => {
  it("exposes exactly the five canonical fee types in the documented order", () => {
    expect(PLATFORM_FEE_TYPES).toEqual(CANONICAL);
  });

  it("includes 'fx_spread' (L01-44 / L01-45 regression guard)", () => {
    expect(PLATFORM_FEE_TYPES).toContain("fx_spread");
  });

  it("Zod enum accepts every canonical type and rejects unknowns", () => {
    for (const fee of PLATFORM_FEE_TYPES) {
      expect(platformFeeTypeSchema.safeParse(fee).success).toBe(true);
    }
    for (const bogus of ["", "FX_SPREAD", " fx_spread", "marketing", null, 7]) {
      expect(platformFeeTypeSchema.safeParse(bogus).success).toBe(false);
    }
  });

  it("FEE_TYPE_LABELS has a non-empty label and description for every type", () => {
    for (const fee of PLATFORM_FEE_TYPES) {
      const entry = FEE_TYPE_LABELS[fee];
      expect(entry, `missing label for ${fee}`).toBeDefined();
      expect(entry.label.length, `empty label for ${fee}`).toBeGreaterThan(0);
      expect(
        entry.description.length,
        `empty description for ${fee}`,
      ).toBeGreaterThan(0);
    }
  });

  it("FEE_TYPE_LABELS does not have stray keys (would orphan UI rows)", () => {
    const labelKeys = Object.keys(FEE_TYPE_LABELS).sort();
    const canonicalSorted = [...PLATFORM_FEE_TYPES].sort();
    expect(labelKeys).toEqual(canonicalSorted);
  });

  it("isPlatformFeeType narrows correctly", () => {
    for (const fee of PLATFORM_FEE_TYPES) {
      expect(isPlatformFeeType(fee)).toBe(true);
    }
    for (const bogus of [undefined, null, 0, {}, "fx-spread"]) {
      expect(isPlatformFeeType(bogus)).toBe(false);
    }
  });
});

describe("Cross-surface lockstep — OpenAPI ↔ TS", () => {
  it("OpenAPI fee_type.enum matches PLATFORM_FEE_TYPES exactly", () => {
    const openapiPath = join(
      process.cwd(),
      "public",
      "openapi.json",
    );
    const spec = JSON.parse(readFileSync(openapiPath, "utf8")) as {
      paths: Record<
        string,
        {
          post?: {
            requestBody?: {
              content?: {
                "application/json"?: {
                  schema?: {
                    properties?: {
                      fee_type?: { enum?: string[] };
                    };
                  };
                };
              };
            };
          };
        }
      >;
    };

    const enumValues =
      spec.paths["/api/platform/fees"]?.post?.requestBody?.content?.[
        "application/json"
      ]?.schema?.properties?.fee_type?.enum;

    expect(
      enumValues,
      "OpenAPI is missing /api/platform/fees POST fee_type enum",
    ).toBeDefined();

    // Use sorted comparison so order drift in the spec is tolerated; we only
    // care that the *set* matches. The TS constant order is the rendering
    // truth for the UI.
    expect([...(enumValues ?? [])].sort()).toEqual(
      [...PLATFORM_FEE_TYPES].sort(),
    );
  });
});

describe("Cross-surface lockstep — SQL CHECK ↔ TS", () => {
  it("platform_fee_config CHECK constraint covers PLATFORM_FEE_TYPES", () => {
    // The L01-44 fix migration is the canonical source for the CHECK; if a
    // new fee_type is added without updating that migration the table will
    // reject inserts in fresh environments.
    const sqlPath = join(
      process.cwd(),
      "..",
      "supabase",
      "migrations",
      "20260417130000_fix_platform_fee_config_check.sql",
    );
    const sql = readFileSync(sqlPath, "utf8");

    for (const fee of PLATFORM_FEE_TYPES) {
      expect(
        sql.includes(`'${fee}'`),
        `SQL CHECK migration is missing fee_type '${fee}' — update 20260417130000_fix_platform_fee_config_check.sql`,
      ).toBe(true);
    }
  });
});

describe("Type system — PlatformFeeType is exhaustive", () => {
  it("every literal in PLATFORM_FEE_TYPES is assignable to PlatformFeeType", () => {
    const sample: PlatformFeeType[] = [
      "clearing",
      "swap",
      "fx_spread",
      "billing_split",
      "maintenance",
    ];
    expect(sample).toHaveLength(PLATFORM_FEE_TYPES.length);
  });
});
