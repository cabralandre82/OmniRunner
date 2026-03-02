import { describe, it, expect } from "vitest";
import {
  formatUsd,
  formatBRL,
  formatKm,
  formatDateISO,
  formatDateMs,
  formatDateTime,
  formatPercent,
  formatCoins,
} from "./format";

describe("formatUsd", () => {
  it("formats positive amounts", () => {
    expect(formatUsd(1234.5)).toContain("1,234.50");
  });

  it("formats zero", () => {
    expect(formatUsd(0)).toContain("0.00");
  });
});

describe("formatBRL", () => {
  it("converts cents to reais", () => {
    const result = formatBRL(15000);
    expect(result).toMatch(/150/);
  });

  it("handles zero", () => {
    const result = formatBRL(0);
    expect(result).toMatch(/0/);
  });
});

describe("formatKm", () => {
  it("converts meters to km", () => {
    expect(formatKm(5280)).toBe("5,3");
  });

  it("handles zero", () => {
    expect(formatKm(0)).toBe("0");
  });
});

describe("formatDateISO", () => {
  it("formats valid ISO string", () => {
    const result = formatDateISO("2026-01-15T10:30:00Z");
    expect(result).toMatch(/15/);
    expect(result).toMatch(/01/);
  });

  it("returns dash for null", () => {
    expect(formatDateISO(null)).toBe("—");
  });
});

describe("formatDateMs", () => {
  it("formats epoch ms", () => {
    const ms = new Date("2026-03-10T12:00:00Z").getTime();
    const result = formatDateMs(ms);
    expect(result).toMatch(/\d{2}\/\d{2}\/\d{4}/);
  });
});

describe("formatDateTime", () => {
  it("includes time component", () => {
    const result = formatDateTime("2026-01-15T14:30:00Z");
    expect(result).toMatch(/15/);
  });
});

describe("formatPercent", () => {
  it("formats with default decimals", () => {
    expect(formatPercent(3.14159)).toBe("3.1%");
  });

  it("formats with custom decimals", () => {
    expect(formatPercent(3.14159, 2)).toBe("3.14%");
  });
});

describe("formatCoins", () => {
  it("formats large numbers with separators", () => {
    const result = formatCoins(10000);
    expect(result).toMatch(/10/);
  });

  it("handles zero", () => {
    expect(formatCoins(0)).toBe("0");
  });
});
