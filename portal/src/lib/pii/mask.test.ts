import { describe, expect, it } from "vitest";
import {
  maskCpf,
  maskCnpj,
  maskEmail,
  maskPhone,
  maskName,
  maskAccount,
  looksLikeCpf,
} from "./mask";

describe("maskCpf", () => {
  it("masks valid 11-digit CPF (no separators)", () => {
    expect(maskCpf("12345678945")).toBe("123.***.***-45");
  });
  it("masks valid CPF with separators", () => {
    expect(maskCpf("123.456.789-45")).toBe("123.***.***-45");
  });
  it("returns full mask for invalid lengths", () => {
    expect(maskCpf("123")).toBe("***.***.***-**");
  });
  it("returns empty string for null/undefined", () => {
    expect(maskCpf(null)).toBe("");
    expect(maskCpf(undefined)).toBe("");
  });
});

describe("maskCnpj", () => {
  it("masks valid 14-digit CNPJ", () => {
    expect(maskCnpj("12345678000134")).toBe("12.***.***/****-34");
  });
  it("masks CNPJ with separators", () => {
    expect(maskCnpj("12.345.678/0001-34")).toBe("12.***.***/****-34");
  });
});

describe("maskEmail", () => {
  it("masks local part keeping first char + full domain", () => {
    expect(maskEmail("alice@example.com")).toBe("a***@example.com");
  });
  it("masks 1-character local part", () => {
    expect(maskEmail("a@example.com")).toBe("*@example.com");
  });
  it("returns *** for malformed input", () => {
    expect(maskEmail("@nope")).toBe("***");
    expect(maskEmail("nope")).toBe("***");
  });
});

describe("maskPhone", () => {
  it("masks 11-digit cellphone", () => {
    expect(maskPhone("11987654321")).toBe("(11) ****-**21");
  });
  it("masks +55 prefixed phone", () => {
    expect(maskPhone("+5511987654321")).toBe("(11) ****-**21");
  });
  it("masks 10-digit landline", () => {
    expect(maskPhone("1133334444")).toBe("(11) ****-**44");
  });
});

describe("maskName", () => {
  it("keeps first name only, masks rest", () => {
    expect(maskName("Alice Beatriz Costa")).toBe("Alice **** ****");
  });
  it("returns single-token names verbatim (no PII to hide)", () => {
    expect(maskName("Alice")).toBe("Alice");
  });
});

describe("maskAccount", () => {
  it("keeps last 4 digits", () => {
    expect(maskAccount("0011223344")).toBe("******3344");
  });
  it("returns **** for short input", () => {
    expect(maskAccount("12")).toBe("****");
  });
});

describe("looksLikeCpf", () => {
  it("returns true for 11-digit strings", () => {
    expect(looksLikeCpf("12345678901")).toBe(true);
  });
  it("returns false for non-11-digit strings", () => {
    expect(looksLikeCpf("123")).toBe(false);
    expect(looksLikeCpf("abc")).toBe(false);
  });
});
