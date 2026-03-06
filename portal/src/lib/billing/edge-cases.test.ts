import { describe, it, expect } from "vitest";
import {
  validateCpf,
  sanitizeCpf,
  canActivateBilling,
  shouldCreateAsaasSubscription,
  calculateSplitValue,
} from "./edge-cases";

describe("validateCpf", () => {
  it("accepts valid 11-digit CPF", () => {
    expect(validateCpf("52998224725")).toBe(true);
  });

  it("accepts CPF with dots and dashes", () => {
    expect(validateCpf("529.982.247-25")).toBe(true);
  });

  it("rejects too short CPF", () => {
    expect(validateCpf("1234567890")).toBe(false);
  });

  it("rejects too long CPF", () => {
    expect(validateCpf("123456789012")).toBe(false);
  });

  it("rejects CPF with letters", () => {
    expect(validateCpf("5299822472a")).toBe(false);
    expect(validateCpf("abc")).toBe(false);
  });
});

describe("sanitizeCpf", () => {
  it("strips dots", () => {
    expect(sanitizeCpf("529.982.247.25")).toBe("52998224725");
  });

  it("strips dashes", () => {
    expect(sanitizeCpf("529-982-247-25")).toBe("52998224725");
  });

  it("strips spaces", () => {
    expect(sanitizeCpf("529 982 247 25")).toBe("52998224725");
  });
});

describe("canActivateBilling", () => {
  it("returns false when api_key is missing", () => {
    const result = canActivateBilling({
      is_active: false,
      api_key: "",
      webhook_id: "wh_123",
    });
    expect(result.ok).toBe(false);
    expect(result.reason).toBe("api_key is required");
  });

  it("returns false when webhook_id is missing", () => {
    const result = canActivateBilling({
      is_active: false,
      api_key: "key_123",
      webhook_id: null,
    });
    expect(result.ok).toBe(false);
    expect(result.reason).toBe("webhook_id is required");
  });

  it("returns true when all present", () => {
    const result = canActivateBilling({
      is_active: false,
      api_key: "key_123",
      webhook_id: "wh_456",
    });
    expect(result.ok).toBe(true);
    expect(result.reason).toBeUndefined();
  });

  it("returns true when is_active is false (activation check)", () => {
    const result = canActivateBilling({
      is_active: false,
      api_key: "key_123",
      webhook_id: "wh_456",
    });
    expect(result.ok).toBe(true);
  });
});

describe("shouldCreateAsaasSubscription", () => {
  it("returns false when already mapped", () => {
    const result = shouldCreateAsaasSubscription(
      { status: "active" },
      { asaas_subscription_id: "sub_123" }
    );
    expect(result).toBe(false);
  });

  it("returns false when subscription is cancelled", () => {
    const result = shouldCreateAsaasSubscription(
      { status: "cancelled" },
      null
    );
    expect(result).toBe(false);
  });

  it("returns true on happy path", () => {
    const result = shouldCreateAsaasSubscription(
      { status: "active" },
      null
    );
    expect(result).toBe(true);
  });
});

describe("calculateSplitValue", () => {
  it("calculates R$150 with 2.5% split", () => {
    const result = calculateSplitValue(150, 2.5);
    expect(result.assessoriaValue).toBe(3.75);
    expect(result.platformValue).toBe(146.25);
  });

  it("handles R$0 edge case", () => {
    const result = calculateSplitValue(0, 2.5);
    expect(result.assessoriaValue).toBe(0);
    expect(result.platformValue).toBe(0);
  });

  it("rounds correctly with R$99.99", () => {
    const result = calculateSplitValue(99.99, 2.5);
    expect(result.assessoriaValue).toBe(2.5);
    expect(result.platformValue).toBe(97.49);
  });
});
