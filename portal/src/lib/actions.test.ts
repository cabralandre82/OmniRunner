import { describe, it, expect } from "vitest";

describe("portal actions", () => {
  it("module exports exist", async () => {
    const mod = await import("./actions");
    expect(mod).toBeDefined();
  });
});
