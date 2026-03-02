import { describe, it, expect } from "vitest";
import crypto from "crypto";
import { verifyStripeSignature, verifyHmacSignature, WebhookError } from "./webhook";

const SECRET = "whsec_test_secret_key_12345";

function createStripeSignature(payload: string, secret: string, timestamp?: number): string {
  const t = timestamp ?? Math.floor(Date.now() / 1000);
  const sig = crypto.createHmac("sha256", secret).update(`${t}.${payload}`).digest("hex");
  return `t=${t},v1=${sig}`;
}

describe("verifyStripeSignature", () => {
  const payload = '{"type":"checkout.session.completed"}';

  it("accepts valid signature", () => {
    const sig = createStripeSignature(payload, SECRET);
    const result = verifyStripeSignature({ payload, signature: sig, secret: SECRET });
    expect(result.timestamp).toBeTypeOf("number");
  });

  it("rejects tampered payload", () => {
    const sig = createStripeSignature(payload, SECRET);
    expect(() =>
      verifyStripeSignature({ payload: payload + "x", signature: sig, secret: SECRET }),
    ).toThrow(WebhookError);
  });

  it("rejects wrong secret", () => {
    const sig = createStripeSignature(payload, "wrong_secret");
    expect(() =>
      verifyStripeSignature({ payload, signature: sig, secret: SECRET }),
    ).toThrow("Signature mismatch");
  });

  it("rejects stale timestamp", () => {
    const staleTs = Math.floor(Date.now() / 1000) - 600;
    const sig = createStripeSignature(payload, SECRET, staleTs);
    expect(() =>
      verifyStripeSignature({ payload, signature: sig, secret: SECRET, tolerance: 300 }),
    ).toThrow("too old");
  });

  it("rejects missing v1 component", () => {
    expect(() =>
      verifyStripeSignature({ payload, signature: "t=12345", secret: SECRET }),
    ).toThrow("missing t= or v1=");
  });

  it("rejects missing t component", () => {
    expect(() =>
      verifyStripeSignature({ payload, signature: "v1=abcdef", secret: SECRET }),
    ).toThrow("missing t= or v1=");
  });

  it("accepts custom tolerance", () => {
    const ts = Math.floor(Date.now() / 1000) - 400;
    const sig = createStripeSignature(payload, SECRET, ts);
    const result = verifyStripeSignature({
      payload,
      signature: sig,
      secret: SECRET,
      tolerance: 500,
    });
    expect(result.timestamp).toBe(ts);
  });
});

describe("verifyHmacSignature", () => {
  const payload = '{"event":"deposit.confirmed","amount":1000}';
  const secret = "hmac_secret_key";

  it("accepts valid signature", () => {
    const sig = crypto.createHmac("sha256", secret).update(payload).digest("hex");
    expect(() => verifyHmacSignature({ payload, signature: sig, secret })).not.toThrow();
  });

  it("rejects invalid signature", () => {
    expect(() =>
      verifyHmacSignature({ payload, signature: "bad_signature_hex_value_here_aaa", secret }),
    ).toThrow("Signature mismatch");
  });

  it("rejects tampered payload", () => {
    const sig = crypto.createHmac("sha256", secret).update(payload).digest("hex");
    expect(() =>
      verifyHmacSignature({ payload: payload + "x", signature: sig, secret }),
    ).toThrow("Signature mismatch");
  });
});
