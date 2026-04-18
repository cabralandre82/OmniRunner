import { describe, it, expect } from "vitest";
import {
  isPublicRoute,
  isAuthOnlyRoute,
  resolveRouteAccess,
  ADMIN_COACH_ROUTES,
  ADMIN_ONLY_ROUTES,
} from "./route-policy";

describe("middleware route classification", () => {
  describe("public routes", () => {
    it("login is public", () => expect(isPublicRoute("/login")).toBe(true));
    it("no-access is public", () => expect(isPublicRoute("/no-access")).toBe(true));
    it("auth callback is public", () =>
      expect(isPublicRoute("/api/auth/callback")).toBe(true));
    it("challenge deep link is public", () =>
      expect(isPublicRoute("/challenge/abc123")).toBe(true));
    it("invite deep link is public", () =>
      expect(isPublicRoute("/invite/xyz")).toBe(true));
    it("dashboard is NOT public", () =>
      expect(isPublicRoute("/dashboard")).toBe(false));
    it("athletes is NOT public", () =>
      expect(isPublicRoute("/athletes")).toBe(false));
  });

  describe("auth-only routes", () => {
    it("platform pages require auth only", () =>
      expect(isAuthOnlyRoute("/platform/assessorias")).toBe(true));
    it("platform API requires auth only", () =>
      expect(isAuthOnlyRoute("/api/platform/support")).toBe(true));
    it("dashboard is NOT auth-only (needs group)", () =>
      expect(isAuthOnlyRoute("/dashboard")).toBe(false));
  });

  describe("ADMIN_ONLY_ROUTES contents (smoke)", () => {
    it("includes /billing and /settings", () => {
      expect(ADMIN_ONLY_ROUTES).toContain("/billing");
      expect(ADMIN_ONLY_ROUTES).toContain("/settings");
    });
  });

  describe("ADMIN_COACH_ROUTES contents (smoke)", () => {
    it("includes /settings/invite and /engagement/export", () => {
      expect(ADMIN_COACH_ROUTES).toContain("/settings/invite");
      expect(ADMIN_COACH_ROUTES).toContain("/engagement/export");
    });
  });
});
