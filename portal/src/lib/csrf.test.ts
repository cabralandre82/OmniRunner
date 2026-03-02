import { describe, it, expect } from "vitest";
import { csrfCheck } from "./csrf";

function makeReq(method: string, headers: Record<string, string> = {}) {
  return {
    method,
    headers: new Headers({ host: "portal.omnirunner.com", ...headers }),
  } as unknown as import("next/server").NextRequest;
}

describe("csrfCheck", () => {
  it("skips safe methods", () => {
    expect(csrfCheck(makeReq("GET"))).toBeNull();
    expect(csrfCheck(makeReq("HEAD"))).toBeNull();
    expect(csrfCheck(makeReq("OPTIONS"))).toBeNull();
  });

  it("allows POST with matching origin", () => {
    const req = makeReq("POST", { origin: "https://portal.omnirunner.com" });
    expect(csrfCheck(req)).toBeNull();
  });

  it("allows POST with matching referer (no origin)", () => {
    const req = makeReq("POST", { referer: "https://portal.omnirunner.com/swap" });
    expect(csrfCheck(req)).toBeNull();
  });

  it("rejects POST with mismatched origin", () => {
    const req = makeReq("POST", { origin: "https://evil.com" });
    const res = csrfCheck(req);
    expect(res).not.toBeNull();
    expect(res!.status).toBe(403);
  });

  it("rejects POST with no origin or referer", () => {
    const req = makeReq("POST");
    const res = csrfCheck(req);
    expect(res).not.toBeNull();
    expect(res!.status).toBe(403);
  });

  it("rejects when host header is missing", () => {
    const req = {
      method: "POST",
      headers: new Headers({ origin: "https://example.com" }),
    } as unknown as import("next/server").NextRequest;
    const res = csrfCheck(req);
    expect(res).not.toBeNull();
    expect(res!.status).toBe(400);
  });
});
