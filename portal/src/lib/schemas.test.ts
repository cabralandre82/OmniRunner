import { describe, it, expect } from "vitest";
import {
  distributeCoinsSchema,
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

  it("rejects amount > 1000", () => {
    const result = distributeCoinsSchema.safeParse({
      athlete_user_id: "550e8400-e29b-41d4-a716-446655440000",
      amount: 1001,
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
