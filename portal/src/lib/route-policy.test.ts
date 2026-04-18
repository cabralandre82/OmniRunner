import { describe, it, expect } from "vitest";
import { resolveRouteAccess, isStaffRole } from "./route-policy";

describe("resolveRouteAccess — L13-01 ordering regression", () => {
  describe("/settings/invite (admin OR coach) vs /settings (admin only)", () => {
    it("admin_master can access /settings/invite", () => {
      expect(resolveRouteAccess("/settings/invite", "admin_master")).toBe(
        "allow",
      );
    });

    it("coach can access /settings/invite — the core L13-01 bug", () => {
      // BEFORE the fix: coach hitting /settings/invite was 403'd because
      // /settings (admin-only) prefix-matched first. After the fix:
      // ADMIN_COACH_ROUTES is checked before ADMIN_ONLY_ROUTES, so coach
      // is allowed through.
      expect(resolveRouteAccess("/settings/invite", "coach")).toBe("allow");
    });

    it("assistant cannot access /settings/invite (only admin/coach)", () => {
      expect(resolveRouteAccess("/settings/invite", "assistant")).toBe(
        "forbidden",
      );
    });

    it("coach is forbidden on /settings (general) — only admin", () => {
      expect(resolveRouteAccess("/settings", "coach")).toBe("forbidden");
    });

    it("admin_master is allowed on /settings (general)", () => {
      expect(resolveRouteAccess("/settings", "admin_master")).toBe("allow");
    });

    it("coach is forbidden on /settings/general (admin-only sub-path)", () => {
      // /settings/general is NOT in ADMIN_COACH_ROUTES, so the coach falls
      // through to ADMIN_ONLY_ROUTES and is forbidden.
      expect(resolveRouteAccess("/settings/general", "coach")).toBe(
        "forbidden",
      );
    });
  });

  describe("/engagement/export (admin OR coach)", () => {
    it("coach can access", () =>
      expect(resolveRouteAccess("/engagement/export", "coach")).toBe("allow"));
    it("admin_master can access", () =>
      expect(resolveRouteAccess("/engagement/export", "admin_master")).toBe(
        "allow",
      ));
    it("assistant cannot access", () =>
      expect(resolveRouteAccess("/engagement/export", "assistant")).toBe(
        "forbidden",
      ));
  });

  describe("/billing and /credits/* (admin only)", () => {
    it("admin_master allowed on /billing", () =>
      expect(resolveRouteAccess("/billing", "admin_master")).toBe("allow"));
    it("coach forbidden on /billing", () =>
      expect(resolveRouteAccess("/billing", "coach")).toBe("forbidden"));
    it("admin_master allowed on /credits/history", () =>
      expect(resolveRouteAccess("/credits/history", "admin_master")).toBe(
        "allow",
      ));
    it("coach forbidden on /credits/request", () =>
      expect(resolveRouteAccess("/credits/request", "coach")).toBe(
        "forbidden",
      ));
  });

  describe("unprotected routes", () => {
    it("/dashboard is unprotected by this policy", () =>
      expect(resolveRouteAccess("/dashboard", "coach")).toBe("unprotected"));
    it("/athletes is unprotected", () =>
      expect(resolveRouteAccess("/athletes", "admin_master")).toBe(
        "unprotected",
      ));
    it("/api/some-route is unprotected", () =>
      expect(resolveRouteAccess("/api/list", "assistant")).toBe(
        "unprotected",
      ));
  });

  describe("defensive role inputs", () => {
    it("null role on protected route → forbidden", () =>
      expect(resolveRouteAccess("/billing", null)).toBe("forbidden"));
    it("undefined role on protected route → forbidden", () =>
      expect(resolveRouteAccess("/settings/invite", undefined)).toBe(
        "forbidden",
      ));
    it("legacy 'professor' role is NOT silently honoured (L13-02)", () => {
      // We deliberately do NOT alias `professor → coach` in the resolver.
      // The DB migration renamed the role; if a row still has the old
      // value, it must surface as forbidden so the bug is fixed at the
      // root rather than papered over here.
      expect(resolveRouteAccess("/settings/invite", "professor")).toBe(
        "forbidden",
      );
    });
    it("nonsense role on unprotected route → still unprotected", () =>
      expect(resolveRouteAccess("/dashboard", "garbage")).toBe(
        "unprotected",
      ));
  });
});

describe("isStaffRole", () => {
  it("accepts admin_master / coach / assistant", () => {
    expect(isStaffRole("admin_master")).toBe(true);
    expect(isStaffRole("coach")).toBe(true);
    expect(isStaffRole("assistant")).toBe(true);
  });
  it("rejects athlete / professor / null / numbers", () => {
    expect(isStaffRole("athlete")).toBe(false);
    expect(isStaffRole("professor")).toBe(false);
    expect(isStaffRole(null)).toBe(false);
    expect(isStaffRole(undefined)).toBe(false);
    expect(isStaffRole(42)).toBe(false);
    expect(isStaffRole({ role: "coach" })).toBe(false);
  });
});
