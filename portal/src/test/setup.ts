import "@testing-library/jest-dom/vitest";

// Node 18+ exposes fetch as a global — no polyfill needed.

// L01-38 — `globalThis.crypto` is a Node 19+ global. Under Node 18 in
// ESM mode (the default for Vitest 2) it is NOT auto-populated, so
// modules that rely on `globalThis.crypto.getRandomValues` (csp.ts,
// any other code path that wants Web Crypto in tests) would crash.
// Edge runtime + Node 19+ both expose it natively; here we just bridge
// the gap for the test environment using node:crypto.webcrypto, which
// has been stable since Node 16.
if (typeof globalThis.crypto === "undefined" || typeof globalThis.crypto.getRandomValues !== "function") {
  // Static import via top-level await is fine here — vitest supports
  // top-level await in setup files and this file is test-only (never
  // bundled into Edge / browser output).
  const { webcrypto } = await import("node:crypto");
  Object.defineProperty(globalThis, "crypto", {
    value: webcrypto,
    configurable: true,
    writable: true,
  });
}
