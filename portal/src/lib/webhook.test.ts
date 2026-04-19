import { describe, it, expect } from "vitest";
import crypto from "crypto";
import {
  verifyStripeSignature,
  verifyMercadoPagoSignature,
  verifyHmacSignature,
  WebhookError,
} from "./webhook";

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

// ────────────────────────────────────────────────────────────────────────
// MercadoPago v2 (L01-01)
// ────────────────────────────────────────────────────────────────────────

const MP_SECRET = "mp_test_secret_key_67890";
const MP_DEFAULT_DATA_ID = "1234567890";
const MP_DEFAULT_REQUEST_ID = "abcd1234-req-id";

function createMpV2Signature(args: {
  dataId: string;
  xRequestId: string;
  secret: string;
  ts?: number;
}): { signature: string; ts: number } {
  const ts = args.ts ?? Math.floor(Date.now() / 1000);
  const manifest = `id:${args.dataId};request-id:${args.xRequestId};ts:${ts};`;
  const sig = crypto.createHmac("sha256", args.secret).update(manifest).digest("hex");
  return { signature: `ts=${ts},v1=${sig}`, ts };
}

function createMpFallbackSignature(args: {
  payload: string;
  secret: string;
  ts?: number;
}): { signature: string; ts: number } {
  const ts = args.ts ?? Math.floor(Date.now() / 1000);
  const sig = crypto.createHmac("sha256", args.secret).update(`${ts}.${args.payload}`).digest("hex");
  return { signature: `ts=${ts},v1=${sig}`, ts };
}

describe("verifyMercadoPagoSignature (L01-01)", () => {
  const payload = '{"action":"payment.updated","data":{"id":"1234567890"}}';

  it("accepts valid v2 manifest signature", () => {
    const { signature, ts } = createMpV2Signature({
      dataId: MP_DEFAULT_DATA_ID,
      xRequestId: MP_DEFAULT_REQUEST_ID,
      secret: MP_SECRET,
    });
    const result = verifyMercadoPagoSignature({
      payload,
      signature,
      xRequestId: MP_DEFAULT_REQUEST_ID,
      dataId: MP_DEFAULT_DATA_ID,
      secret: MP_SECRET,
    });
    expect(result.timestamp).toBe(ts);
    expect(result.manifestUsed).toBe("v2");
  });

  it("falls back to ts.payload manifest when x-request-id missing", () => {
    const { signature, ts } = createMpFallbackSignature({ payload, secret: MP_SECRET });
    const result = verifyMercadoPagoSignature({
      payload,
      signature,
      xRequestId: null,
      dataId: MP_DEFAULT_DATA_ID,
      secret: MP_SECRET,
    });
    expect(result.timestamp).toBe(ts);
    expect(result.manifestUsed).toBe("fallback");
  });

  it("falls back to ts.payload manifest when data.id missing", () => {
    const { signature } = createMpFallbackSignature({ payload, secret: MP_SECRET });
    const result = verifyMercadoPagoSignature({
      payload,
      signature,
      xRequestId: MP_DEFAULT_REQUEST_ID,
      dataId: null,
      secret: MP_SECRET,
    });
    expect(result.manifestUsed).toBe("fallback");
  });

  it("rejects v2 signature when verifier passes wrong dataId", () => {
    const { signature } = createMpV2Signature({
      dataId: MP_DEFAULT_DATA_ID,
      xRequestId: MP_DEFAULT_REQUEST_ID,
      secret: MP_SECRET,
    });
    expect(() =>
      verifyMercadoPagoSignature({
        payload,
        signature,
        xRequestId: MP_DEFAULT_REQUEST_ID,
        dataId: "9999999999",
        secret: MP_SECRET,
      }),
    ).toThrow("Signature mismatch");
  });

  it("rejects v2 signature when verifier passes wrong xRequestId", () => {
    const { signature } = createMpV2Signature({
      dataId: MP_DEFAULT_DATA_ID,
      xRequestId: MP_DEFAULT_REQUEST_ID,
      secret: MP_SECRET,
    });
    expect(() =>
      verifyMercadoPagoSignature({
        payload,
        signature,
        xRequestId: "different-request-id",
        dataId: MP_DEFAULT_DATA_ID,
        secret: MP_SECRET,
      }),
    ).toThrow("Signature mismatch");
  });

  it("rejects stale timestamp (replay attack >300s old)", () => {
    const staleTs = Math.floor(Date.now() / 1000) - 600;
    const { signature } = createMpV2Signature({
      dataId: MP_DEFAULT_DATA_ID,
      xRequestId: MP_DEFAULT_REQUEST_ID,
      secret: MP_SECRET,
      ts: staleTs,
    });
    expect(() =>
      verifyMercadoPagoSignature({
        payload,
        signature,
        xRequestId: MP_DEFAULT_REQUEST_ID,
        dataId: MP_DEFAULT_DATA_ID,
        secret: MP_SECRET,
        tolerance: 300,
      }),
    ).toThrow("too old");
  });

  it("respects custom tolerance window", () => {
    const ts = Math.floor(Date.now() / 1000) - 400;
    const { signature } = createMpV2Signature({
      dataId: MP_DEFAULT_DATA_ID,
      xRequestId: MP_DEFAULT_REQUEST_ID,
      secret: MP_SECRET,
      ts,
    });
    const result = verifyMercadoPagoSignature({
      payload,
      signature,
      xRequestId: MP_DEFAULT_REQUEST_ID,
      dataId: MP_DEFAULT_DATA_ID,
      secret: MP_SECRET,
      tolerance: 500,
    });
    expect(result.timestamp).toBe(ts);
  });

  it("rejects wrong secret", () => {
    const { signature } = createMpV2Signature({
      dataId: MP_DEFAULT_DATA_ID,
      xRequestId: MP_DEFAULT_REQUEST_ID,
      secret: "wrong_secret",
    });
    expect(() =>
      verifyMercadoPagoSignature({
        payload,
        signature,
        xRequestId: MP_DEFAULT_REQUEST_ID,
        dataId: MP_DEFAULT_DATA_ID,
        secret: MP_SECRET,
      }),
    ).toThrow("Signature mismatch");
  });

  it("rejects missing ts component", () => {
    expect(() =>
      verifyMercadoPagoSignature({
        payload,
        signature: "v1=abcdef",
        xRequestId: MP_DEFAULT_REQUEST_ID,
        dataId: MP_DEFAULT_DATA_ID,
        secret: MP_SECRET,
      }),
    ).toThrow("missing ts= or v1=");
  });

  it("rejects missing v1 component", () => {
    const ts = Math.floor(Date.now() / 1000);
    expect(() =>
      verifyMercadoPagoSignature({
        payload,
        signature: `ts=${ts}`,
        xRequestId: MP_DEFAULT_REQUEST_ID,
        dataId: MP_DEFAULT_DATA_ID,
        secret: MP_SECRET,
      }),
    ).toThrow("missing ts= or v1=");
  });

  it("rejects empty v1 component", () => {
    const ts = Math.floor(Date.now() / 1000);
    expect(() =>
      verifyMercadoPagoSignature({
        payload,
        signature: `ts=${ts},v1=`,
        xRequestId: MP_DEFAULT_REQUEST_ID,
        dataId: MP_DEFAULT_DATA_ID,
        secret: MP_SECRET,
      }),
    ).toThrow("empty v1=");
  });

  it("rejects non-numeric timestamp", () => {
    expect(() =>
      verifyMercadoPagoSignature({
        payload,
        signature: "ts=notanumber,v1=abcdef",
        xRequestId: MP_DEFAULT_REQUEST_ID,
        dataId: MP_DEFAULT_DATA_ID,
        secret: MP_SECRET,
      }),
    ).toThrow("non-numeric timestamp");
  });

  it("auto-converts millisecond timestamps to seconds", () => {
    const tsMs = Date.now();
    const tsSec = Math.floor(tsMs / 1000);
    const manifest = `id:${MP_DEFAULT_DATA_ID};request-id:${MP_DEFAULT_REQUEST_ID};ts:${tsSec};`;
    const sig = crypto.createHmac("sha256", MP_SECRET).update(manifest).digest("hex");
    const result = verifyMercadoPagoSignature({
      payload,
      signature: `ts=${tsMs},v1=${sig}`,
      xRequestId: MP_DEFAULT_REQUEST_ID,
      dataId: MP_DEFAULT_DATA_ID,
      secret: MP_SECRET,
    });
    expect(result.timestamp).toBe(tsSec);
  });

  it("tolerates whitespace and order variations in signature header", () => {
    const ts = Math.floor(Date.now() / 1000);
    const manifest = `id:${MP_DEFAULT_DATA_ID};request-id:${MP_DEFAULT_REQUEST_ID};ts:${ts};`;
    const sig = crypto.createHmac("sha256", MP_SECRET).update(manifest).digest("hex");
    const result = verifyMercadoPagoSignature({
      payload,
      signature: `  v1=${sig}  ,  ts=${ts}  `,
      xRequestId: MP_DEFAULT_REQUEST_ID,
      dataId: MP_DEFAULT_DATA_ID,
      secret: MP_SECRET,
    });
    expect(result.timestamp).toBe(ts);
  });

  it("rejects fallback path with tampered payload", () => {
    const { signature } = createMpFallbackSignature({ payload, secret: MP_SECRET });
    expect(() =>
      verifyMercadoPagoSignature({
        payload: payload + "x",
        signature,
        xRequestId: null,
        dataId: null,
        secret: MP_SECRET,
      }),
    ).toThrow("Signature mismatch");
  });
});
