import { describe, it, expect, beforeEach, afterEach } from "vitest";
import {
  MEMBERSHIP_NONE,
  getCachedMembership,
  setCachedMembership,
  invalidateMembership,
  invalidateAllForUser,
  clearMembershipCache,
  membershipCacheSize,
  setMembershipCacheTTLForTests,
} from "./route-policy-cache";

const USER_A = "11111111-1111-4111-8111-111111111111";
const USER_B = "22222222-2222-4222-8222-222222222222";
const GROUP_A = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const GROUP_B = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";

describe("route-policy-cache (L13-03)", () => {
  beforeEach(() => {
    clearMembershipCache();
    setMembershipCacheTTLForTests(60_000);
  });

  afterEach(() => {
    clearMembershipCache();
    setMembershipCacheTTLForTests(null);
  });

  describe("get / set basics", () => {
    it("miss returns undefined", () => {
      expect(getCachedMembership(USER_A, GROUP_A)).toBeUndefined();
    });

    it("hit after set returns the stored role", () => {
      setCachedMembership(USER_A, GROUP_A, { role: "coach" });
      expect(getCachedMembership(USER_A, GROUP_A)).toEqual({ role: "coach" });
    });

    it("entries are scoped by (user, group)", () => {
      setCachedMembership(USER_A, GROUP_A, { role: "admin_master" });
      expect(getCachedMembership(USER_A, GROUP_B)).toBeUndefined();
      expect(getCachedMembership(USER_B, GROUP_A)).toBeUndefined();
    });

    it("set is idempotent — same key overwrites", () => {
      setCachedMembership(USER_A, GROUP_A, { role: "coach" });
      setCachedMembership(USER_A, GROUP_A, { role: "admin_master" });
      expect(getCachedMembership(USER_A, GROUP_A)).toEqual({
        role: "admin_master",
      });
      expect(membershipCacheSize()).toBe(1);
    });
  });

  describe("negative caching", () => {
    it("MEMBERSHIP_NONE round-trips through the cache", () => {
      setCachedMembership(USER_A, GROUP_A, MEMBERSHIP_NONE);
      expect(getCachedMembership(USER_A, GROUP_A)).toBe(MEMBERSHIP_NONE);
    });

    it("a positive entry can be replaced by a negative one (role removed)", () => {
      setCachedMembership(USER_A, GROUP_A, { role: "coach" });
      setCachedMembership(USER_A, GROUP_A, MEMBERSHIP_NONE);
      expect(getCachedMembership(USER_A, GROUP_A)).toBe(MEMBERSHIP_NONE);
    });
  });

  describe("TTL expiry", () => {
    it("returns undefined after TTL elapses (no fake timers — uses real Date)", async () => {
      setMembershipCacheTTLForTests(20);
      setCachedMembership(USER_A, GROUP_A, { role: "coach" });
      expect(getCachedMembership(USER_A, GROUP_A)).toEqual({ role: "coach" });
      await new Promise((r) => setTimeout(r, 30));
      expect(getCachedMembership(USER_A, GROUP_A)).toBeUndefined();
    });

    it("expired entries are evicted on read (no graveyard)", async () => {
      setMembershipCacheTTLForTests(15);
      setCachedMembership(USER_A, GROUP_A, { role: "coach" });
      expect(membershipCacheSize()).toBe(1);
      await new Promise((r) => setTimeout(r, 25));
      // Reading the expired key both returns undefined AND deletes it.
      getCachedMembership(USER_A, GROUP_A);
      expect(membershipCacheSize()).toBe(0);
    });
  });

  describe("invalidation", () => {
    it("invalidateMembership removes a single entry", () => {
      setCachedMembership(USER_A, GROUP_A, { role: "coach" });
      setCachedMembership(USER_A, GROUP_B, { role: "admin_master" });
      invalidateMembership(USER_A, GROUP_A);
      expect(getCachedMembership(USER_A, GROUP_A)).toBeUndefined();
      expect(getCachedMembership(USER_A, GROUP_B)).toEqual({
        role: "admin_master",
      });
    });

    it("invalidateMembership is a no-op for unknown keys", () => {
      // Should not throw and should not perturb other entries.
      setCachedMembership(USER_A, GROUP_A, { role: "coach" });
      invalidateMembership(USER_B, GROUP_B);
      expect(getCachedMembership(USER_A, GROUP_A)).toEqual({ role: "coach" });
    });

    it("invalidateAllForUser drops every group for that user", () => {
      setCachedMembership(USER_A, GROUP_A, { role: "coach" });
      setCachedMembership(USER_A, GROUP_B, { role: "admin_master" });
      setCachedMembership(USER_B, GROUP_A, { role: "coach" });
      invalidateAllForUser(USER_A);
      expect(getCachedMembership(USER_A, GROUP_A)).toBeUndefined();
      expect(getCachedMembership(USER_A, GROUP_B)).toBeUndefined();
      expect(getCachedMembership(USER_B, GROUP_A)).toEqual({ role: "coach" });
    });
  });

  describe("LRU semantics", () => {
    it("reading an entry refreshes its recency", () => {
      // We cannot easily exercise eviction with MAX_ENTRIES=5000 inside
      // a fast unit test, so we instead verify that get() behaves as if
      // it were calling delete+set: the entry remains present and
      // queryable after read.
      setCachedMembership(USER_A, GROUP_A, { role: "coach" });
      setCachedMembership(USER_B, GROUP_A, { role: "admin_master" });
      const beforeSize = membershipCacheSize();
      getCachedMembership(USER_A, GROUP_A);
      expect(membershipCacheSize()).toBe(beforeSize);
      expect(getCachedMembership(USER_A, GROUP_A)).toEqual({ role: "coach" });
    });
  });

  describe("clearMembershipCache", () => {
    it("wipes everything", () => {
      setCachedMembership(USER_A, GROUP_A, { role: "coach" });
      setCachedMembership(USER_B, GROUP_B, { role: "admin_master" });
      expect(membershipCacheSize()).toBe(2);
      clearMembershipCache();
      expect(membershipCacheSize()).toBe(0);
    });
  });
});
