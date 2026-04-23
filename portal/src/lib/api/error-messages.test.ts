/**
 * Unit tests for L07-01 API error message i18n registry.
 */
import { describe, expect, it } from "vitest";

import {
  ERROR_LOCALES,
  ERROR_MESSAGES,
  REGISTERED_ERROR_CODES,
  resolveClientLocale,
  resolveErrorMessage,
  type ErrorLocale,
  type LocalisedMessage,
} from "./error-messages";

import { COMMON_ERROR_CODES } from "./errors";

describe("ERROR_MESSAGES registry", () => {
  it("has English, pt-BR and Spanish entries for every code", () => {
    for (const code of REGISTERED_ERROR_CODES) {
      const entry = ERROR_MESSAGES[code];
      expect(entry).toBeDefined();
      expect(entry.en.length).toBeGreaterThan(0);
      expect(entry.ptBR.length).toBeGreaterThan(0);
      expect(entry.es.length).toBeGreaterThan(0);
    }
  });

  it("covers all COMMON_ERROR_CODES from errors.ts", () => {
    for (const code of COMMON_ERROR_CODES) {
      expect(ERROR_MESSAGES[code]).toBeDefined();
    }
  });

  it("English variants are ASCII-only (canonical server locale)", () => {
    const nonAscii = /[^\x20-\x7e]/;
    for (const code of REGISTERED_ERROR_CODES) {
      const en = ERROR_MESSAGES[code].en;
      expect(nonAscii.test(en), `en for ${code}: "${en}"`).toBe(false);
    }
  });

  it("codes are SCREAMING_SNAKE_CASE", () => {
    const re = /^[A-Z][A-Z0-9_]*$/;
    for (const code of REGISTERED_ERROR_CODES) {
      expect(re.test(code), code).toBe(true);
    }
  });

  it("ptBR entries contain non-ASCII chars (real translations, not copies of EN)", () => {
    const diacritic = /[áéíóúãõçÁÉÍÓÚÃÕÇ]/;
    const codesWithRealTranslation = REGISTERED_ERROR_CODES.filter(
      (code) => diacritic.test(ERROR_MESSAGES[code].ptBR),
    );
    expect(codesWithRealTranslation.length).toBeGreaterThan(
      Math.floor(REGISTERED_ERROR_CODES.length * 0.6),
    );
  });
});

describe("resolveErrorMessage", () => {
  it("returns English by default", () => {
    expect(resolveErrorMessage("UNAUTHORIZED")).toBe(
      ERROR_MESSAGES.UNAUTHORIZED.en,
    );
  });

  it("returns pt-BR when asked", () => {
    expect(resolveErrorMessage("UNAUTHORIZED", "ptBR")).toBe(
      ERROR_MESSAGES.UNAUTHORIZED.ptBR,
    );
  });

  it("returns es when asked", () => {
    expect(resolveErrorMessage("UNAUTHORIZED", "es")).toBe(
      ERROR_MESSAGES.UNAUTHORIZED.es,
    );
  });

  it("falls back to code when unregistered", () => {
    expect(resolveErrorMessage("TOTALLY_UNKNOWN_CODE_XYZ")).toBe(
      "TOTALLY_UNKNOWN_CODE_XYZ",
    );
  });

  it("falls back to English when locale is unknown (defensive)", () => {
    expect(
      resolveErrorMessage("UNAUTHORIZED", "fr" as unknown as ErrorLocale),
    ).toBe(ERROR_MESSAGES.UNAUTHORIZED.en);
  });
});

describe("resolveClientLocale", () => {
  it("returns en when header is missing or empty", () => {
    expect(resolveClientLocale(null)).toBe("en");
    expect(resolveClientLocale("")).toBe("en");
    expect(resolveClientLocale(undefined)).toBe("en");
  });

  it("recognises pt / pt-BR / pt_BR / pt;q=0.8", () => {
    expect(resolveClientLocale("pt")).toBe("ptBR");
    expect(resolveClientLocale("pt-BR")).toBe("ptBR");
    expect(resolveClientLocale("pt_BR")).toBe("ptBR");
    expect(resolveClientLocale("pt-BR,en;q=0.8")).toBe("ptBR");
    expect(resolveClientLocale("pt;q=0.8")).toBe("ptBR");
  });

  it("recognises es / es-MX / es-AR", () => {
    expect(resolveClientLocale("es")).toBe("es");
    expect(resolveClientLocale("es-MX")).toBe("es");
    expect(resolveClientLocale("es-AR,pt;q=0.7")).toBe("es");
  });

  it("recognises en variants", () => {
    expect(resolveClientLocale("en")).toBe("en");
    expect(resolveClientLocale("en-US")).toBe("en");
    expect(resolveClientLocale("en-GB,en;q=0.9")).toBe("en");
  });

  it("falls back to en for unknown locales", () => {
    expect(resolveClientLocale("fr-FR")).toBe("en");
    expect(resolveClientLocale("de")).toBe("en");
    expect(resolveClientLocale("zz-ZZ")).toBe("en");
  });
});

describe("ERROR_LOCALES", () => {
  it("has exactly 3 canonical locales", () => {
    expect(ERROR_LOCALES.length).toBe(3);
    expect([...ERROR_LOCALES].sort()).toEqual(["en", "es", "ptBR"].sort());
  });

  it("LocalisedMessage type covers all locales", () => {
    const sample: LocalisedMessage = {
      en: "x",
      ptBR: "x",
      es: "x",
    };
    expect(sample.en).toBeDefined();
    expect(sample.ptBR).toBeDefined();
    expect(sample.es).toBeDefined();
  });
});
