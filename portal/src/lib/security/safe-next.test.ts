import { describe, expect, it } from "vitest";
import { safeNext } from "./safe-next";

describe("safeNext (L01-10)", () => {
  it("accepts canonical internal pathnames", () => {
    expect(safeNext("/dashboard")).toBe("/dashboard");
    expect(safeNext("/groups/a/dashboard")).toBe("/groups/a/dashboard");
    expect(safeNext("/groups?tab=overview")).toBe("/groups?tab=overview");
  });

  it("falls back on missing or empty input", () => {
    expect(safeNext(null)).toBe("/dashboard");
    expect(safeNext(undefined)).toBe("/dashboard");
    expect(safeNext("")).toBe("/dashboard");
  });

  it("rejects protocol-relative redirects", () => {
    expect(safeNext("//evil.example.com/x")).toBe("/dashboard");
    expect(safeNext("/\\evil.example.com/x")).toBe("/dashboard");
  });

  it("rejects schemes", () => {
    expect(safeNext("javascript:alert(1)")).toBe("/dashboard");
    expect(safeNext("https://evil.example.com")).toBe("/dashboard");
    expect(safeNext("data:text/html,foo")).toBe("/dashboard");
  });

  it("rejects values longer than 256 chars", () => {
    expect(safeNext("/" + "a".repeat(300))).toBe("/dashboard");
  });

  it("rejects bare characters outside the allowlist", () => {
    expect(safeNext("/path with space")).toBe("/dashboard");
    expect(safeNext("/path<script>")).toBe("/dashboard");
    expect(safeNext("/path#frag")).toBe("/dashboard");
  });

  it("respects a custom fallback", () => {
    expect(safeNext(null, "/login")).toBe("/login");
  });
});
