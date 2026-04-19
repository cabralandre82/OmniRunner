/**
 * @vitest-environment happy-dom
 *
 * Tests for the browser-side `csrfFetch` helper (L01-06). Lives in
 * happy-dom because the helper reads `document.cookie` and falls back
 * to native `fetch`; node default vitest env has neither. happy-dom
 * is preferred over jsdom here because the workspace's jsdom version
 * has a broken CJS/ESM dependency (html-encoding-sniffer).
 */

import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { CSRF_COOKIE_NAME, CSRF_HEADER_NAME } from "./csrf";
import { csrfFetch, readCookie } from "./csrf-fetch";

function installCookieShim(): () => void {
  const original = Object.getOwnPropertyDescriptor(
    Document.prototype,
    "cookie",
  );
  let store = "";
  Object.defineProperty(document, "cookie", {
    configurable: true,
    get: () => store,
    set: (v: string) => {
      const seg = v.split(";")[0]?.trim() ?? "";
      if (!seg) return;
      const eq = seg.indexOf("=");
      if (eq < 0) return;
      const name = seg.slice(0, eq);
      const val = seg.slice(eq + 1);
      const others = store
        .split("; ")
        .filter((c) => c && !c.startsWith(`${name}=`));
      others.push(`${name}=${val}`);
      store = others.join("; ");
    },
  });
  return () => {
    if (original) Object.defineProperty(document, "cookie", original);
  };
}

describe("readCookie", () => {
  let restore: () => void;
  beforeEach(() => {
    restore = installCookieShim();
  });
  afterEach(() => restore());

  it("returns null for unknown cookies", () => {
    expect(readCookie("never-set")).toBeNull();
  });

  it("reads a simple cookie value", () => {
    document.cookie = `${CSRF_COOKIE_NAME}=abc123`;
    expect(readCookie(CSRF_COOKIE_NAME)).toBe("abc123");
  });

  it("URL-decodes percent-encoded values", () => {
    document.cookie = `other=${encodeURIComponent("a b/c")}`;
    expect(readCookie("other")).toBe("a b/c");
  });

  it("returns the right value when multiple cookies are set", () => {
    document.cookie = "other=zzz";
    document.cookie = `${CSRF_COOKIE_NAME}=target-value`;
    expect(readCookie(CSRF_COOKIE_NAME)).toBe("target-value");
    expect(readCookie("other")).toBe("zzz");
  });
});

describe("csrfFetch", () => {
  let fetchSpy: ReturnType<typeof vi.fn>;
  let restore: () => void;

  beforeEach(() => {
    restore = installCookieShim();
    fetchSpy = vi.fn().mockResolvedValue(new Response("{}", { status: 200 }));
    vi.stubGlobal("fetch", fetchSpy);
  });

  afterEach(() => {
    vi.unstubAllGlobals();
    restore();
  });

  it("attaches the x-csrf-token header from the cookie on POST", async () => {
    document.cookie = `${CSRF_COOKIE_NAME}=tok-from-cookie`;
    await csrfFetch("/api/swap", { method: "POST", body: "{}" });
    const init = fetchSpy.mock.calls[0]?.[1] as RequestInit;
    const headers = new Headers(init.headers);
    expect(headers.get(CSRF_HEADER_NAME)).toBe("tok-from-cookie");
  });

  it("does NOT overwrite a header the caller already set", async () => {
    document.cookie = `${CSRF_COOKIE_NAME}=cookie-tok`;
    await csrfFetch("/api/swap", {
      method: "POST",
      headers: { [CSRF_HEADER_NAME]: "explicit-tok" },
    });
    const init = fetchSpy.mock.calls[0]?.[1] as RequestInit;
    const headers = new Headers(init.headers);
    expect(headers.get(CSRF_HEADER_NAME)).toBe("explicit-tok");
  });

  it("omits the header if no cookie is present (server returns 403 → UI surfaces)", async () => {
    // store starts empty by virtue of the per-test cookie shim.
    await csrfFetch("/api/swap", { method: "POST" });
    const init = fetchSpy.mock.calls[0]?.[1] as RequestInit;
    const headers = new Headers(init.headers);
    expect(headers.has(CSRF_HEADER_NAME)).toBe(false);
  });

  it("preserves other init fields (method, body, signal)", async () => {
    document.cookie = `${CSRF_COOKIE_NAME}=tok`;
    const ac = new AbortController();
    await csrfFetch("/api/clearing", {
      method: "POST",
      body: JSON.stringify({ x: 1 }),
      signal: ac.signal,
    });
    const init = fetchSpy.mock.calls[0]?.[1] as RequestInit;
    expect(init.method).toBe("POST");
    expect(init.body).toBe('{"x":1}');
    expect(init.signal).toBe(ac.signal);
  });

  it("forwards the URL/input unchanged", async () => {
    document.cookie = `${CSRF_COOKIE_NAME}=tok`;
    await csrfFetch("/api/distribute-coins", { method: "POST" });
    expect(fetchSpy.mock.calls[0]?.[0]).toBe("/api/distribute-coins");
  });
});
