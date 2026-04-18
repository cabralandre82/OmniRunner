import { describe, it, expect, afterEach } from "vitest";
import {
  resolveRouteAccess,
  isStaffRole,
  isAuthNoGroupRoute,
  portalCookieOptions,
  AUTH_NO_GROUP_ROUTES,
  PORTAL_COOKIE_MAX_AGE_SEC,
} from "./route-policy";

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

describe("isAuthNoGroupRoute (L13-04)", () => {
  it("matches /select-group exactly", () => {
    expect(isAuthNoGroupRoute("/select-group")).toBe(true);
  });

  it("does not match /select-group/ or sub-paths", () => {
    expect(isAuthNoGroupRoute("/select-group/")).toBe(false);
    expect(isAuthNoGroupRoute("/select-group/anything")).toBe(false);
  });

  it("does not match unrelated paths", () => {
    expect(isAuthNoGroupRoute("/")).toBe(false);
    expect(isAuthNoGroupRoute("/dashboard")).toBe(false);
    expect(isAuthNoGroupRoute("/select-groups")).toBe(false);
  });

  it("AUTH_NO_GROUP_ROUTES contains /select-group", () => {
    expect(AUTH_NO_GROUP_ROUTES.has("/select-group")).toBe(true);
  });
});

describe("portalCookieOptions (L13-05)", () => {
  const originalNodeEnv = process.env.NODE_ENV;
  afterEach(() => {
    if (originalNodeEnv === undefined) {
      delete process.env.NODE_ENV;
    } else {
      process.env.NODE_ENV = originalNodeEnv;
    }
  });

  it("returns httpOnly + sameSite=lax + path=/ defaults", () => {
    const opts = portalCookieOptions();
    expect(opts.httpOnly).toBe(true);
    expect(opts.sameSite).toBe("lax");
    expect(opts.path).toBe("/");
  });

  it("defaults maxAge to the 8h business-day constant", () => {
    expect(portalCookieOptions().maxAge).toBe(PORTAL_COOKIE_MAX_AGE_SEC);
    expect(PORTAL_COOKIE_MAX_AGE_SEC).toBe(60 * 60 * 8);
  });

  it("flips secure=true in production", () => {
    process.env.NODE_ENV = "production";
    expect(portalCookieOptions().secure).toBe(true);
  });

  it("keeps secure=false in development / test", () => {
    process.env.NODE_ENV = "development";
    expect(portalCookieOptions().secure).toBe(false);
    process.env.NODE_ENV = "test";
    expect(portalCookieOptions().secure).toBe(false);
  });

  it("respects explicit maxAge=0 for cookie clearing", () => {
    expect(portalCookieOptions({ maxAge: 0 }).maxAge).toBe(0);
  });

  it("honours overrideSecure for local-HTTPS dev parity", () => {
    process.env.NODE_ENV = "development";
    expect(portalCookieOptions({ overrideSecure: true }).secure).toBe(true);
    process.env.NODE_ENV = "production";
    expect(portalCookieOptions({ overrideSecure: false }).secure).toBe(false);
  });
});
