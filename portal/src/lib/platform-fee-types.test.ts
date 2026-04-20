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
  PLATFORM_PASSTHROUGH_FEE_TYPES,
  PLATFORM_REVENUE_FEE_TYPES,
  FEE_TYPE_LABELS,
  isPlatformFeeType,
  isPlatformRevenueFeeType,
  platformFeeTypeSchema,
  platformRevenueFeeTypeSchema,
  type PlatformFeeType,
  type PlatformRevenueFeeType,
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

// ─────────────────────────────────────────────────────────────────────────────
// L03-03: PLATFORM_REVENUE_FEE_TYPES (superset including pass-through fees)
// ─────────────────────────────────────────────────────────────────────────────

const REVENUE_CANONICAL = [
  ...CANONICAL,
  "provider_fee", // L03-03: gateway/bank pass-through fee on withdrawals
] as const;

describe("PLATFORM_REVENUE_FEE_TYPES — superset of configurable + pass-through (L03-03)", () => {
  it("equals exactly the canonical configurable + passthrough union", () => {
    expect(PLATFORM_REVENUE_FEE_TYPES).toEqual(REVENUE_CANONICAL);
  });

  it("includes 'provider_fee' (L03-03 regression guard)", () => {
    expect(PLATFORM_REVENUE_FEE_TYPES).toContain("provider_fee");
  });

  it("PLATFORM_PASSTHROUGH_FEE_TYPES contains exactly the pass-through set", () => {
    expect(PLATFORM_PASSTHROUGH_FEE_TYPES).toEqual(["provider_fee"]);
  });

  it("PLATFORM_FEE_TYPES and PLATFORM_PASSTHROUGH_FEE_TYPES are disjoint (no overlap)", () => {
    const configurable = new Set<string>(PLATFORM_FEE_TYPES);
    for (const passthrough of PLATFORM_PASSTHROUGH_FEE_TYPES) {
      expect(
        configurable.has(passthrough),
        `${passthrough} is both configurable AND pass-through — pick one`,
      ).toBe(false);
    }
  });

  it("PLATFORM_REVENUE_FEE_TYPES is a strict superset of PLATFORM_FEE_TYPES", () => {
    const revenue = new Set<string>(PLATFORM_REVENUE_FEE_TYPES);
    for (const fee of PLATFORM_FEE_TYPES) {
      expect(
        revenue.has(fee),
        `revenue list is missing configurable fee ${fee}`,
      ).toBe(true);
    }
    expect(PLATFORM_REVENUE_FEE_TYPES.length).toBeGreaterThan(
      PLATFORM_FEE_TYPES.length,
    );
  });

  it("PLATFORM_REVENUE_FEE_TYPES = PLATFORM_FEE_TYPES ∪ PLATFORM_PASSTHROUGH_FEE_TYPES", () => {
    const union = new Set<string>([
      ...PLATFORM_FEE_TYPES,
      ...PLATFORM_PASSTHROUGH_FEE_TYPES,
    ]);
    const revenue = new Set<string>(PLATFORM_REVENUE_FEE_TYPES);
    expect(revenue).toEqual(union);
  });

  it("platformRevenueFeeTypeSchema accepts both configurable and pass-through types", () => {
    for (const fee of PLATFORM_REVENUE_FEE_TYPES) {
      expect(platformRevenueFeeTypeSchema.safeParse(fee).success).toBe(true);
    }
    for (const bogus of ["", "PROVIDER_FEE", "  provider_fee", "shipping", null, 7]) {
      expect(platformRevenueFeeTypeSchema.safeParse(bogus).success).toBe(false);
    }
  });

  it("platformFeeTypeSchema (configurable) STILL rejects 'provider_fee' (deliberate divergence)", () => {
    // This is the safety net for L03-03: provider_fee must NEVER appear in
    // /api/platform/fees because it's not configurable. If a future
    // contributor adds it to PLATFORM_FEE_TYPES "to fix the test", the next
    // assertion in PLATFORM_FEE_TYPES contract block will fail too.
    expect(platformFeeTypeSchema.safeParse("provider_fee").success).toBe(
      false,
    );
  });

  it("isPlatformRevenueFeeType narrows correctly across both subsets", () => {
    for (const fee of PLATFORM_REVENUE_FEE_TYPES) {
      expect(isPlatformRevenueFeeType(fee)).toBe(true);
    }
    for (const bogus of [undefined, null, 0, {}, "fx-spread", "provider-fee"]) {
      expect(isPlatformRevenueFeeType(bogus)).toBe(false);
    }
  });

  it("isPlatformFeeType (configurable subset) returns false for 'provider_fee'", () => {
    expect(isPlatformFeeType("provider_fee")).toBe(false);
  });
});

describe("Cross-surface lockstep — SQL CHECK ↔ TS (revenue superset, L03-03)", () => {
  it("L03-03 migration widens platform_revenue.fee_type CHECK to all PLATFORM_REVENUE_FEE_TYPES", () => {
    const sqlPath = join(
      process.cwd(),
      "..",
      "supabase",
      "migrations",
      "20260420090000_l03_provider_fee_revenue_track.sql",
    );
    const sql = readFileSync(sqlPath, "utf8");

    // Locate the CHECK widening block — sanity check that we're reading
    // the right migration (cheap canary against future renames).
    expect(
      sql.includes("platform_revenue_fee_type_check"),
      "L03-03 migration must widen platform_revenue_fee_type_check",
    ).toBe(true);

    for (const fee of PLATFORM_REVENUE_FEE_TYPES) {
      expect(
        sql.includes(`'${fee}'`),
        `L03-03 migration is missing fee_type '${fee}' in the widened CHECK`,
      ).toBe(true);
    }

    // Sanity: the migration must also patch execute_withdrawal to insert
    // the provider_fee row. Otherwise the schema accepts the type but
    // the data path never produces it.
    expect(
      sql.includes("'provider_fee'"),
      "L03-03 migration must reference provider_fee",
    ).toBe(true);
    expect(
      sql.includes("CREATE OR REPLACE FUNCTION public.execute_withdrawal"),
      "L03-03 migration must re-create execute_withdrawal",
    ).toBe(true);
    expect(
      sql.includes("CREATE OR REPLACE FUNCTION public.fail_withdrawal"),
      "L03-03 migration must re-create fail_withdrawal (to also reverse provider_fee on rollback)",
    ).toBe(true);
  });

  it("L03-03 migration short-circuits the L09-04 fiscal-receipts trigger on provider_fee", () => {
    const sqlPath = join(
      process.cwd(),
      "..",
      "supabase",
      "migrations",
      "20260420090000_l03_provider_fee_revenue_track.sql",
    );
    const sql = readFileSync(sqlPath, "utf8");

    expect(
      sql.includes("CREATE OR REPLACE FUNCTION public._enqueue_fiscal_receipt"),
      "L03-03 migration must re-create _enqueue_fiscal_receipt to skip provider_fee",
    ).toBe(true);
    // Specifically the early return on fee_type='provider_fee'.
    expect(
      sql.match(/IF\s+NEW\.fee_type\s*=\s*'provider_fee'/i),
      "L03-03 migration must add an early-return guard for provider_fee in the fiscal trigger",
    ).not.toBeNull();
  });

  it("L01-44 migration CHECK on platform_fee_config does NOT include provider_fee (deliberate divergence)", () => {
    // Pass-through fees stay out of platform_fee_config because they
    // are not admin-configurable. If a future contributor 'fixes' this
    // by adding provider_fee, the deliberate divergence is broken.
    const sqlPath = join(
      process.cwd(),
      "..",
      "supabase",
      "migrations",
      "20260417130000_fix_platform_fee_config_check.sql",
    );
    const sql = readFileSync(sqlPath, "utf8");

    // Find the CHECK clause line(s) and assert provider_fee absent there.
    // (The migration may mention provider_fee in comments — we strictly
    // look at the CHECK literal list block.)
    const checkBlock = sql.match(
      /CHECK\s*\(\s*fee_type\s+IN\s*\(([^)]*)\)\s*\)/i,
    );
    expect(
      checkBlock,
      "L01-44 migration must contain a CHECK (fee_type IN (...)) clause",
    ).not.toBeNull();
    const literals = checkBlock?.[1] ?? "";
    expect(
      literals.includes("'provider_fee'"),
      "platform_fee_config CHECK must NOT list 'provider_fee' (pass-through, not configurable)",
    ).toBe(false);
  });
});

describe("Type system — PlatformRevenueFeeType is exhaustive", () => {
  it("every literal in PLATFORM_REVENUE_FEE_TYPES is assignable to PlatformRevenueFeeType", () => {
    const sample: PlatformRevenueFeeType[] = [
      "clearing",
      "swap",
      "fx_spread",
      "billing_split",
      "maintenance",
      "provider_fee",
    ];
    expect(sample).toHaveLength(PLATFORM_REVENUE_FEE_TYPES.length);
  });
});
