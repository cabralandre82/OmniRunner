/**
 * L17-02 — unit tests for the bounded-context manifest invariants.
 */

import { describe, it, expect } from "vitest";
import {
  BOUNDED_CONTEXTS,
  CONTEXT_MANIFEST,
  LAYERING_RULES,
  allowsImport,
  contextOf,
  contextsWithMembers,
} from "./manifest";

describe("L17-02 BOUNDED_CONTEXTS", () => {
  it("includes every expected context", () => {
    expect(new Set(BOUNDED_CONTEXTS)).toEqual(
      new Set([
        "financial",
        "security",
        "platform",
        "infra",
        "domain",
        "integration",
        "shared",
        "qa",
        "boundaries",
      ]),
    );
  });
});

describe("L17-02 CONTEXT_MANIFEST", () => {
  it("has unique paths", () => {
    const seen = new Set<string>();
    for (const entry of CONTEXT_MANIFEST) {
      expect(seen.has(entry.path)).toBe(false);
      seen.add(entry.path);
    }
  });

  it("classifies every entry into a known context", () => {
    const known = new Set<string>(BOUNDED_CONTEXTS);
    for (const entry of CONTEXT_MANIFEST) {
      expect(known.has(entry.context)).toBe(true);
    }
  });

  it("has every entry resolvable via contextOf", () => {
    for (const entry of CONTEXT_MANIFEST) {
      expect(contextOf(entry.path)).toBe(entry.context);
    }
  });

  it("returns null for unknown paths", () => {
    expect(contextOf("definitely-not-a-real-file.ts")).toBeNull();
  });
});

describe("L17-02 LAYERING_RULES", () => {
  it("is an irreflexive relation (no [A,A] edges)", () => {
    for (const [s, t] of LAYERING_RULES) {
      expect(s).not.toBe(t);
    }
  });

  it("forbids domain → financial edges", () => {
    expect(allowsImport("domain", "financial")).toBe(false);
  });

  it("forbids domain → infra edges", () => {
    expect(allowsImport("domain", "infra")).toBe(false);
  });

  it("forbids domain → security edges", () => {
    expect(allowsImport("domain", "security")).toBe(false);
  });

  it("forbids financial → security edges only if rule absent", () => {
    // financial → security is explicitly allowed.  This guards against
    // regressions that would remove the rule accidentally.
    expect(allowsImport("financial", "security")).toBe(true);
  });

  it("forbids security → platform edges (isolated service layer)", () => {
    expect(allowsImport("security", "platform")).toBe(false);
  });

  it("allows qa → every other context", () => {
    for (const c of BOUNDED_CONTEXTS) {
      if (c === "qa") continue;
      expect(allowsImport("qa", c)).toBe(true);
    }
  });

  it("infra → shared is allowed; infra → financial is not", () => {
    expect(allowsImport("infra", "shared")).toBe(true);
    expect(allowsImport("infra", "financial")).toBe(false);
  });

  it("every source context always imports itself", () => {
    for (const c of BOUNDED_CONTEXTS) {
      expect(allowsImport(c, c)).toBe(true);
    }
  });
});

describe("L17-02 contextsWithMembers()", () => {
  it("covers every BOUNDED_CONTEXTS key", () => {
    const result = contextsWithMembers();
    const seen = new Set(result.map((r) => r.context));
    for (const c of BOUNDED_CONTEXTS) {
      expect(seen.has(c)).toBe(true);
    }
  });

  it("returns a non-empty array for every core context", () => {
    const core = ["financial", "security", "platform", "infra", "domain"];
    const result = contextsWithMembers();
    for (const c of core) {
      const row = result.find((r) => r.context === c);
      expect(row?.paths.length).toBeGreaterThan(0);
    }
  });
});
