import { describe, it, expect } from "vitest";

const PUBLIC_ROUTES = new Set(["/login", "/no-access", "/api/auth/callback"]);
const PUBLIC_PREFIXES = ["/challenge/", "/invite/"];
const AUTH_ONLY_PREFIXES = ["/platform", "/api/platform/"];
const ADMIN_ONLY_ROUTES = [
  "/credits/history",
  "/credits/request",
  "/billing",
  "/settings",
];
const ADMIN_PROFESSOR_ROUTES = ["/engagement/export", "/settings/invite"];

function isPublic(pathname: string): boolean {
  return (
    PUBLIC_ROUTES.has(pathname) ||
    PUBLIC_PREFIXES.some((p) => pathname.startsWith(p))
  );
}

function isAuthOnly(pathname: string): boolean {
  return AUTH_ONLY_PREFIXES.some((p) => pathname.startsWith(p));
}

function isAdminOnly(pathname: string): boolean {
  return ADMIN_ONLY_ROUTES.some((r) => pathname.startsWith(r));
}

function isAdminOrProfessor(pathname: string): boolean {
  return ADMIN_PROFESSOR_ROUTES.some((r) => pathname.startsWith(r));
}

describe("middleware route classification", () => {
  describe("public routes", () => {
    it("login is public", () => expect(isPublic("/login")).toBe(true));
    it("no-access is public", () => expect(isPublic("/no-access")).toBe(true));
    it("auth callback is public", () =>
      expect(isPublic("/api/auth/callback")).toBe(true));
    it("challenge deep link is public", () =>
      expect(isPublic("/challenge/abc123")).toBe(true));
    it("invite deep link is public", () =>
      expect(isPublic("/invite/xyz")).toBe(true));
    it("dashboard is NOT public", () =>
      expect(isPublic("/dashboard")).toBe(false));
    it("athletes is NOT public", () =>
      expect(isPublic("/athletes")).toBe(false));
  });

  describe("auth-only routes", () => {
    it("platform pages require auth only", () =>
      expect(isAuthOnly("/platform/assessorias")).toBe(true));
    it("platform API requires auth only", () =>
      expect(isAuthOnly("/api/platform/support")).toBe(true));
    it("dashboard is NOT auth-only (needs group)", () =>
      expect(isAuthOnly("/dashboard")).toBe(false));
  });

  describe("admin-only routes", () => {
    it("billing is admin only", () =>
      expect(isAdminOnly("/billing")).toBe(true));
    it("settings is admin only", () =>
      expect(isAdminOnly("/settings")).toBe(true));
    it("credits/history is admin only", () =>
      expect(isAdminOnly("/credits/history")).toBe(true));
    it("dashboard is NOT admin only", () =>
      expect(isAdminOnly("/dashboard")).toBe(false));
    it("athletes is NOT admin only", () =>
      expect(isAdminOnly("/athletes")).toBe(false));
  });

  describe("admin or professor routes", () => {
    it("engagement/export requires admin or professor", () =>
      expect(isAdminOrProfessor("/engagement/export")).toBe(true));
    it("settings/invite requires admin or professor", () =>
      expect(isAdminOrProfessor("/settings/invite")).toBe(true));
    it("dashboard does NOT require admin or professor", () =>
      expect(isAdminOrProfessor("/dashboard")).toBe(false));
  });
});
