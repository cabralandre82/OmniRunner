import { describe, it, expect, vi, beforeEach } from "vitest";

const rpc = vi.fn();

vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: () => ({ rpc }),
}));

const {
  getAuthoritativeFxQuote,
  tryGetAuthoritativeFxQuote,
  FxQuoteMissingError,
  FxQuoteStaleError,
  FxQuoteUnsupportedError,
  FxQuoteError,
  SUPPORTED_CURRENCIES,
  MAX_QUOTE_AGE_SECONDS,
} = await import("./quote");

/**
 * L01-02 — Suite server-side authoritative FX quote.
 *
 * Garante que:
 *   - Moedas inválidas são rejeitadas antes de qualquer round-trip ao DB.
 *   - Cotações stale (> MAX_QUOTE_AGE_SECONDS) são rejeitadas fail-closed.
 *   - Cotações ausentes são sinalizadas com erro tipado, não retornam null mudo.
 *   - Rates inválidos (≤0, NaN) são rejeitados mesmo se DB retorna (defesa em profundidade).
 */
describe("getAuthoritativeFxQuote — L01-02", () => {
  beforeEach(() => {
    rpc.mockReset();
  });

  it("retorna cotação para moeda suportada (BRL)", async () => {
    rpc.mockResolvedValue({
      data: [
        {
          rate_per_usd: 5.2,
          source: "ptax",
          fetched_at: "2026-04-17T12:00:00Z",
          age_seconds: 600,
        },
      ],
      error: null,
    });

    const q = await getAuthoritativeFxQuote("BRL");
    expect(q.currency).toBe("BRL");
    expect(q.rate).toBe(5.2);
    expect(q.source).toBe("ptax");
    expect(q.ageSeconds).toBe(600);

    expect(rpc).toHaveBeenCalledWith("get_latest_fx_quote", { p_currency: "BRL" });
  });

  it("normaliza currency case-insensitive (brl → BRL)", async () => {
    rpc.mockResolvedValue({
      data: [{ rate_per_usd: 5.1, source: "seed", fetched_at: "t", age_seconds: 100 }],
      error: null,
    });
    const q = await getAuthoritativeFxQuote("brl");
    expect(q.currency).toBe("BRL");
    expect(rpc).toHaveBeenCalledWith("get_latest_fx_quote", { p_currency: "BRL" });
  });

  it("rejeita moeda não suportada com FxQuoteUnsupportedError", async () => {
    await expect(getAuthoritativeFxQuote("JPY")).rejects.toBeInstanceOf(
      FxQuoteUnsupportedError,
    );
    await expect(getAuthoritativeFxQuote("XYZ")).rejects.toMatchObject({
      code: "unsupported",
    });
    expect(rpc).not.toHaveBeenCalled();
  });

  it("rejeita cotação ausente com FxQuoteMissingError", async () => {
    rpc.mockResolvedValue({ data: [], error: null });
    await expect(getAuthoritativeFxQuote("BRL")).rejects.toBeInstanceOf(
      FxQuoteMissingError,
    );
  });

  it("rejeita cotação com rate_per_usd null", async () => {
    rpc.mockResolvedValue({
      data: [{ rate_per_usd: null, source: "seed", fetched_at: "t", age_seconds: 0 }],
      error: null,
    });
    await expect(getAuthoritativeFxQuote("BRL")).rejects.toBeInstanceOf(
      FxQuoteMissingError,
    );
  });

  it("rejeita cotação stale com FxQuoteStaleError (> maxAge)", async () => {
    rpc.mockResolvedValue({
      data: [
        {
          rate_per_usd: 5.2,
          source: "ptax",
          fetched_at: "2026-01-01T00:00:00Z",
          age_seconds: MAX_QUOTE_AGE_SECONDS + 100,
        },
      ],
      error: null,
    });
    await expect(getAuthoritativeFxQuote("BRL")).rejects.toBeInstanceOf(
      FxQuoteStaleError,
    );
  });

  it("aceita cotação dentro do maxAge custom passado via opts", async () => {
    rpc.mockResolvedValue({
      data: [{ rate_per_usd: 5.1, source: "seed", fetched_at: "t", age_seconds: 500 }],
      error: null,
    });
    const q = await getAuthoritativeFxQuote("BRL", { maxAgeSeconds: 1000 });
    expect(q.rate).toBe(5.1);
  });

  it("rejeita quando maxAge custom é menor que age", async () => {
    rpc.mockResolvedValue({
      data: [{ rate_per_usd: 5.1, source: "seed", fetched_at: "t", age_seconds: 500 }],
      error: null,
    });
    await expect(
      getAuthoritativeFxQuote("BRL", { maxAgeSeconds: 100 }),
    ).rejects.toBeInstanceOf(FxQuoteStaleError);
  });

  it("rejeita rate inválido (≤0) mesmo se DB retorna — defesa em profundidade", async () => {
    rpc.mockResolvedValue({
      data: [{ rate_per_usd: 0, source: "seed", fetched_at: "t", age_seconds: 10 }],
      error: null,
    });
    await expect(getAuthoritativeFxQuote("BRL")).rejects.toBeInstanceOf(FxQuoteError);
  });

  it("rejeita rate negativo mesmo se DB retorna", async () => {
    rpc.mockResolvedValue({
      data: [{ rate_per_usd: -5.2, source: "seed", fetched_at: "t", age_seconds: 10 }],
      error: null,
    });
    await expect(getAuthoritativeFxQuote("BRL")).rejects.toBeInstanceOf(FxQuoteError);
  });

  it("embrulha erros de DB em FxQuoteError code='db_error'", async () => {
    rpc.mockResolvedValue({ data: null, error: { message: "connection refused" } });
    await expect(getAuthoritativeFxQuote("BRL")).rejects.toMatchObject({
      code: "db_error",
    });
  });

  it("SUPPORTED_CURRENCIES contém as 3 moedas esperadas", () => {
    expect(SUPPORTED_CURRENCIES).toEqual(["BRL", "EUR", "GBP"]);
  });
});

describe("tryGetAuthoritativeFxQuote — L01-02", () => {
  beforeEach(() => {
    rpc.mockReset();
  });

  it("retorna null (não throw) quando cotação ausente", async () => {
    rpc.mockResolvedValue({ data: [], error: null });
    const q = await tryGetAuthoritativeFxQuote("BRL");
    expect(q).toBeNull();
  });

  it("retorna null quando cotação stale", async () => {
    rpc.mockResolvedValue({
      data: [
        {
          rate_per_usd: 5.2,
          source: "ptax",
          fetched_at: "2020-01-01",
          age_seconds: MAX_QUOTE_AGE_SECONDS + 1,
        },
      ],
      error: null,
    });
    const q = await tryGetAuthoritativeFxQuote("BRL");
    expect(q).toBeNull();
  });

  it("retorna quote válida quando disponível", async () => {
    rpc.mockResolvedValue({
      data: [{ rate_per_usd: 5.25, source: "seed", fetched_at: "t", age_seconds: 10 }],
      error: null,
    });
    const q = await tryGetAuthoritativeFxQuote("BRL");
    expect(q?.rate).toBe(5.25);
  });
});
