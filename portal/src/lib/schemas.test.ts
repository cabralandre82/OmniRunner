import { describe, it, expect } from "vitest";
import {
  distributeCoinsSchema,
  distributeCoinsBatchSchema,
  DISTRIBUTE_COINS_AMOUNT_MAX,
  DISTRIBUTE_COINS_BATCH_MAX_ITEMS,
  DISTRIBUTE_COINS_BATCH_MAX_TOTAL,
  teamInviteSchema,
  teamRemoveSchema,
  verificationEvaluateSchema,
  brandingSchema,
  checkoutSchema,
  gatewayPreferenceSchema,
  autoTopupSchema,
} from "./schemas";

describe("distributeCoinsSchema", () => {
  it("accepts valid input", () => {
    const result = distributeCoinsSchema.safeParse({
      athlete_user_id: "550e8400-e29b-41d4-a716-446655440000",
      amount: 50,
    });
    expect(result.success).toBe(true);
  });

  it("rejects non-integer amount", () => {
    const result = distributeCoinsSchema.safeParse({
      athlete_user_id: "550e8400-e29b-41d4-a716-446655440000",
      amount: 10.5,
    });
    expect(result.success).toBe(false);
  });

  // L05-03 — per-call cap raised from 1_000 → 100_000.
  it("L05-03: accepts amounts above the legacy 1_000 cap", () => {
    expect(
      distributeCoinsSchema.safeParse({
        athlete_user_id: "550e8400-e29b-41d4-a716-446655440000",
        amount: 5_000,
      }).success,
    ).toBe(true);
    expect(
      distributeCoinsSchema.safeParse({
        athlete_user_id: "550e8400-e29b-41d4-a716-446655440000",
        amount: DISTRIBUTE_COINS_AMOUNT_MAX,
      }).success,
    ).toBe(true);
  });

  it("L05-03: rejects amounts above the new cap (DISTRIBUTE_COINS_AMOUNT_MAX)", () => {
    const result = distributeCoinsSchema.safeParse({
      athlete_user_id: "550e8400-e29b-41d4-a716-446655440000",
      amount: DISTRIBUTE_COINS_AMOUNT_MAX + 1,
    });
    expect(result.success).toBe(false);
  });

  it("rejects invalid UUID", () => {
    const result = distributeCoinsSchema.safeParse({
      athlete_user_id: "not-a-uuid",
      amount: 10,
    });
    expect(result.success).toBe(false);
  });
});

describe("distributeCoinsBatchSchema (L05-03)", () => {
  const A1 = "550e8400-e29b-41d4-a716-446655440001";
  const A2 = "550e8400-e29b-41d4-a716-446655440002";
  const A3 = "550e8400-e29b-41d4-a716-446655440003";

  const okPayload = {
    items: [
      { athlete_user_id: A1, amount: 10 },
      { athlete_user_id: A2, amount: 20 },
    ],
  };

  it("accepts a small valid batch", () => {
    expect(distributeCoinsBatchSchema.safeParse(okPayload).success).toBe(true);
  });

  it("accepts an explicit ref_id", () => {
    expect(
      distributeCoinsBatchSchema.safeParse({
        ...okPayload,
        ref_id: "weekly-bonus-2026-w17",
      }).success,
    ).toBe(true);
  });

  it("rejects ref_id shorter than 8 chars", () => {
    expect(
      distributeCoinsBatchSchema.safeParse({ ...okPayload, ref_id: "short" })
        .success,
    ).toBe(false);
  });

  it("rejects unknown extra fields (.strict)", () => {
    expect(
      distributeCoinsBatchSchema.safeParse({ ...okPayload, sneaky: "x" })
        .success,
    ).toBe(false);
  });

  it("rejects empty items array", () => {
    expect(
      distributeCoinsBatchSchema.safeParse({ items: [] }).success,
    ).toBe(false);
  });

  it("rejects items.length above DISTRIBUTE_COINS_BATCH_MAX_ITEMS", () => {
    const items = Array.from(
      { length: DISTRIBUTE_COINS_BATCH_MAX_ITEMS + 1 },
      (_, i) => ({
        athlete_user_id: `550e8400-e29b-41d4-a716-44665544${(1000 + i)
          .toString()
          .padStart(4, "0")}`,
        amount: 1,
      }),
    );
    expect(distributeCoinsBatchSchema.safeParse({ items }).success).toBe(false);
  });

  it("rejects per-item amount above DISTRIBUTE_COINS_AMOUNT_MAX", () => {
    expect(
      distributeCoinsBatchSchema.safeParse({
        items: [
          { athlete_user_id: A1, amount: DISTRIBUTE_COINS_AMOUNT_MAX + 1 },
        ],
      }).success,
    ).toBe(false);
  });

  it("rejects negative or zero per-item amounts", () => {
    expect(
      distributeCoinsBatchSchema.safeParse({
        items: [{ athlete_user_id: A1, amount: 0 }],
      }).success,
    ).toBe(false);
    expect(
      distributeCoinsBatchSchema.safeParse({
        items: [{ athlete_user_id: A1, amount: -1 }],
      }).success,
    ).toBe(false);
  });

  it("rejects duplicate athlete_user_id within the same batch", () => {
    const result = distributeCoinsBatchSchema.safeParse({
      items: [
        { athlete_user_id: A1, amount: 10 },
        { athlete_user_id: A2, amount: 20 },
        { athlete_user_id: A1, amount: 5 },
      ],
    });
    expect(result.success).toBe(false);
    if (!result.success) {
      expect(result.error.issues[0].message).toContain("duplicado");
    }
  });

  it("rejects when total amount exceeds DISTRIBUTE_COINS_BATCH_MAX_TOTAL", () => {
    // 11 atletas × 100_000 = 1_100_000 > 1_000_000.
    const itemCount =
      Math.ceil(DISTRIBUTE_COINS_BATCH_MAX_TOTAL / DISTRIBUTE_COINS_AMOUNT_MAX) +
      1;
    const items = Array.from({ length: itemCount }, (_, i) => ({
      athlete_user_id: `550e8400-e29b-41d4-a716-44665544${(2000 + i)
        .toString()
        .padStart(4, "0")}`,
      amount: DISTRIBUTE_COINS_AMOUNT_MAX,
    }));
    const total = items.reduce((s, i) => s + i.amount, 0);
    if (total <= DISTRIBUTE_COINS_BATCH_MAX_TOTAL) {
      throw new Error("test fixture must exceed DISTRIBUTE_COINS_BATCH_MAX_TOTAL");
    }
    const result = distributeCoinsBatchSchema.safeParse({ items });
    expect(result.success).toBe(false);
    if (!result.success) {
      expect(result.error.issues[0].message).toMatch(/excede limite/);
    }
  });

  it("rejects fractional amounts inside items", () => {
    expect(
      distributeCoinsBatchSchema.safeParse({
        items: [{ athlete_user_id: A1, amount: 10.5 }],
      }).success,
    ).toBe(false);
  });

  it("rejects invalid UUID inside items", () => {
    expect(
      distributeCoinsBatchSchema.safeParse({
        items: [{ athlete_user_id: "not-a-uuid", amount: 10 }],
      }).success,
    ).toBe(false);
  });
});

describe("teamInviteSchema", () => {
  it("accepts valid input", () => {
    const result = teamInviteSchema.safeParse({
      email: "john@example.com",
      role: "coach",
    });
    expect(result.success).toBe(true);
  });

  it("rejects invalid email", () => {
    const result = teamInviteSchema.safeParse({
      email: "not-an-email",
      role: "coach",
    });
    expect(result.success).toBe(false);
  });

  it("rejects invalid role", () => {
    const result = teamInviteSchema.safeParse({
      email: "john@example.com",
      role: "admin_master",
    });
    expect(result.success).toBe(false);
  });
});

describe("teamRemoveSchema", () => {
  it("rejects empty member_id", () => {
    const result = teamRemoveSchema.safeParse({ member_id: "" });
    expect(result.success).toBe(false);
  });
});

describe("verificationEvaluateSchema", () => {
  it("accepts valid UUID", () => {
    const result = verificationEvaluateSchema.safeParse({
      user_id: "550e8400-e29b-41d4-a716-446655440000",
    });
    expect(result.success).toBe(true);
  });

  it("rejects non-UUID", () => {
    const result = verificationEvaluateSchema.safeParse({ user_id: "abc" });
    expect(result.success).toBe(false);
  });
});

describe("brandingSchema", () => {
  it("accepts valid colors", () => {
    const result = brandingSchema.safeParse({
      primary_color: "#ff0000",
      accent_color: "#00ff00",
    });
    expect(result.success).toBe(true);
  });

  it("rejects invalid hex", () => {
    const result = brandingSchema.safeParse({ primary_color: "red" });
    expect(result.success).toBe(false);
  });

  it("rejects unknown fields", () => {
    const result = brandingSchema.safeParse({ unknown_field: "value" });
    expect(result.success).toBe(false);
  });

  it("allows nullable logo_url", () => {
    const result = brandingSchema.safeParse({ logo_url: null });
    expect(result.success).toBe(true);
  });
});

describe("checkoutSchema", () => {
  const VALID_UUID = "550e8400-e29b-41d4-a716-446655440000";

  it("accepts with default gateway (mercadopago)", () => {
    const result = checkoutSchema.safeParse({ product_id: VALID_UUID });
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.gateway).toBe("mercadopago");
    }
  });

  it("accepts explicit gateway override", () => {
    const result = checkoutSchema.safeParse({
      product_id: VALID_UUID,
      gateway: "stripe",
    });
    expect(result.success).toBe(true);
    if (result.success) expect(result.data.gateway).toBe("stripe");
  });

  it("rejects non-UUID product_id (L01-09 hardening)", () => {
    expect(checkoutSchema.safeParse({ product_id: "prod-1" }).success).toBe(false);
    expect(checkoutSchema.safeParse({ product_id: "" }).success).toBe(false);
    expect(checkoutSchema.safeParse({ product_id: "../../etc/passwd" }).success).toBe(false);
  });

  it("rejects unknown extra fields (.strict)", () => {
    const result = checkoutSchema.safeParse({
      product_id: VALID_UUID,
      malicious: "<script>",
    });
    expect(result.success).toBe(false);
  });

  it("rejects unknown gateway", () => {
    const result = checkoutSchema.safeParse({
      product_id: VALID_UUID,
      gateway: "paypal",
    });
    expect(result.success).toBe(false);
  });
});

describe("gatewayPreferenceSchema", () => {
  it("accepts valid gateways", () => {
    expect(
      gatewayPreferenceSchema.safeParse({ preferred_gateway: "stripe" }).success,
    ).toBe(true);
    expect(
      gatewayPreferenceSchema.safeParse({ preferred_gateway: "mercadopago" })
        .success,
    ).toBe(true);
  });

  it("rejects invalid gateway", () => {
    expect(
      gatewayPreferenceSchema.safeParse({ preferred_gateway: "paypal" }).success,
    ).toBe(false);
  });
});

describe("autoTopupSchema", () => {
  it("accepts valid partial input", () => {
    const result = autoTopupSchema.safeParse({ enabled: true });
    expect(result.success).toBe(true);
  });

  it("rejects negative threshold", () => {
    const result = autoTopupSchema.safeParse({ threshold_tokens: -5 });
    expect(result.success).toBe(false);
  });
});
