import "@testing-library/jest-dom/vitest";
import nodeFetch from "node-fetch";

// Polyfill fetch for API route tests that call external services (e.g. OpenAI).
// Node 18 exposes fetch as an experimental global but it is not reliably
// available in the vitest node environment.  node-fetch provides a stable
// WHATWG-compatible implementation that vi.stubGlobal / vi.spyOn can intercept.
if (typeof globalThis.fetch === "undefined") {
  (globalThis as any).fetch = nodeFetch;
  (globalThis as any).Response = nodeFetch.Response;
  (globalThis as any).Request = nodeFetch.Request;
  (globalThis as any).Headers = nodeFetch.Headers;
}
