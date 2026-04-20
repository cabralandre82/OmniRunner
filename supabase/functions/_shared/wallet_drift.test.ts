/**
 * Unit tests for wallet_drift.ts (L06-03).
 *
 * Run with:
 *   deno test --allow-net=hooks.slack.com supabase/functions/_shared/wallet_drift.test.ts
 *
 * No DB / network access (postSlackAlert tests inject a fake fetch).
 */

import {
  assertEquals,
  assertStrictEquals,
} from "https://deno.land/std@0.208.0/assert/mod.ts";

import {
  buildSlackDriftPayload,
  classifyWalletDrift,
  DEFAULT_DRIFT_WARN_THRESHOLD,
  postSlackAlert,
} from "./wallet_drift.ts";

const CTX = {
  totalWallets: 100,
  driftedCount: 5,
  runId: "11111111-2222-3333-4444-555555555555",
  runAt: "2026-04-20T10:00:00.000Z",
  environment: "production",
  runbookUrl: "https://runbook.example/wallet",
};

// ─── classifyWalletDrift ───────────────────────────────────────────────────

Deno.test("classifyWalletDrift — DEFAULT_DRIFT_WARN_THRESHOLD is 10", () => {
  assertEquals(DEFAULT_DRIFT_WARN_THRESHOLD, 10);
});

Deno.test("classifyWalletDrift — drift = 0 → ok / no alert / P4", () => {
  const c = classifyWalletDrift(0);
  assertEquals(c.severity, "ok");
  assertEquals(c.shouldAlert, false);
  assertEquals(c.pTier, "P4");
});

Deno.test("classifyWalletDrift — negative count is treated as ok", () => {
  const c = classifyWalletDrift(-7);
  assertEquals(c.severity, "ok");
  assertEquals(c.shouldAlert, false);
});

Deno.test("classifyWalletDrift — NaN treated as ok (defensive)", () => {
  const c = classifyWalletDrift(Number.NaN);
  assertEquals(c.severity, "ok");
});

Deno.test("classifyWalletDrift — Infinity treated as ok (defensive)", () => {
  const c = classifyWalletDrift(Number.POSITIVE_INFINITY);
  assertEquals(c.severity, "ok");
});

Deno.test("classifyWalletDrift — drift = 1 → warn / shouldAlert / P2", () => {
  const c = classifyWalletDrift(1);
  assertEquals(c.severity, "warn");
  assertEquals(c.shouldAlert, true);
  assertEquals(c.pTier, "P2");
});

Deno.test("classifyWalletDrift — drift = threshold → warn (boundary)", () => {
  const c = classifyWalletDrift(10);
  assertEquals(c.severity, "warn");
});

Deno.test("classifyWalletDrift — drift = threshold + 1 → critical", () => {
  const c = classifyWalletDrift(11);
  assertEquals(c.severity, "critical");
  assertEquals(c.shouldAlert, true);
  assertEquals(c.pTier, "P1");
});

Deno.test("classifyWalletDrift — large drift → critical", () => {
  const c = classifyWalletDrift(9_999);
  assertEquals(c.severity, "critical");
  assertEquals(c.pTier, "P1");
});

Deno.test("classifyWalletDrift — custom threshold lowers boundary", () => {
  assertEquals(classifyWalletDrift(3, 3).severity, "warn");
  assertEquals(classifyWalletDrift(4, 3).severity, "critical");
});

Deno.test("classifyWalletDrift — negative threshold clamps to 0 (everything > 0 is critical)", () => {
  assertEquals(classifyWalletDrift(1, -5).severity, "critical");
  assertEquals(classifyWalletDrift(0, -5).severity, "ok");
});

Deno.test("classifyWalletDrift — non-finite threshold falls back to default 10", () => {
  assertEquals(classifyWalletDrift(10, Number.NaN).severity, "warn");
  assertEquals(classifyWalletDrift(11, Number.NaN).severity, "critical");
});

Deno.test("classifyWalletDrift — fractional drift is floored", () => {
  // If reconcile_all_wallets ever returned a fractional count we must NOT
  // double-count near boundaries.
  assertEquals(classifyWalletDrift(10.7).severity, "warn");
  assertEquals(classifyWalletDrift(11.0).severity, "critical");
});

// ─── buildSlackDriftPayload ─────────────────────────────────────────────────

Deno.test("buildSlackDriftPayload — returns null when shouldAlert=false", () => {
  const c = classifyWalletDrift(0);
  assertStrictEquals(buildSlackDriftPayload(c, CTX), null);
});

Deno.test("buildSlackDriftPayload — warn payload contains P2 + driftedCount + runId", () => {
  const c = classifyWalletDrift(5);
  const p = buildSlackDriftPayload(c, CTX);
  if (!p) throw new Error("payload should not be null");
  if (!p.text.includes("P2")) throw new Error("missing P2 tag in text");
  if (!p.text.includes("Wallet drift detected")) throw new Error("missing headline");
  if (!p.text.includes(":warning:")) throw new Error("missing warn emoji");
  if (!p.text.includes("5")) throw new Error("missing drift count");
  if (!p.text.includes(CTX.runId)) throw new Error("missing run id");
  if (!p.text.includes(CTX.environment)) throw new Error("missing environment");
});

Deno.test("buildSlackDriftPayload — critical payload escalates wording + adds investigation prompt", () => {
  const c = classifyWalletDrift(50);
  const p = buildSlackDriftPayload(c, CTX);
  if (!p) throw new Error("payload should not be null");
  if (!p.text.includes("P1")) throw new Error("missing P1 tag in text");
  if (!p.text.includes("CRITICAL")) throw new Error("critical headline missing");
  if (!p.text.includes(":rotating_light:")) throw new Error("missing critical emoji");
  if (!p.text.toLowerCase().includes("investigate"))
    throw new Error("missing investigation prompt");
});

Deno.test("buildSlackDriftPayload — runbook URL is included when provided", () => {
  const c = classifyWalletDrift(5);
  const p = buildSlackDriftPayload(c, CTX);
  if (!p) throw new Error("payload should not be null");
  if (!p.text.includes(CTX.runbookUrl!)) throw new Error("missing runbook URL");
});

Deno.test("buildSlackDriftPayload — runbook URL is omitted when not provided", () => {
  const c = classifyWalletDrift(5);
  const p = buildSlackDriftPayload(c, { ...CTX, runbookUrl: undefined });
  if (!p) throw new Error("payload should not be null");
  if (p.text.includes("Runbook:")) throw new Error("runbook line should be absent");
});

Deno.test("buildSlackDriftPayload — emits Block Kit blocks alongside text fallback", () => {
  const c = classifyWalletDrift(5);
  const p = buildSlackDriftPayload(c, CTX);
  if (!p?.blocks) throw new Error("blocks missing");
  assertEquals(Array.isArray(p.blocks), true);
  if (p.blocks.length < 1) throw new Error("expected at least one block");
});

// ─── postSlackAlert ─────────────────────────────────────────────────────────

Deno.test("postSlackAlert — happy path returns { ok: true, status: 200 }", async () => {
  let captured: { url: string; body: string } | null = null;
  const fakeFetch: typeof fetch = (url, init) => {
    captured = { url: String(url), body: String(init?.body ?? "") };
    return Promise.resolve(new Response("ok", { status: 200 }));
  };
  const r = await postSlackAlert(
    "https://hooks.slack.com/services/X/Y/Z",
    { text: "hi" },
    fakeFetch,
  );
  assertEquals(r.ok, true);
  assertEquals(r.status, 200);
  assertEquals(r.error, undefined);
  if (!captured) throw new Error("fetch not called");
  const cap = captured as { url: string; body: string };
  assertEquals(cap.url, "https://hooks.slack.com/services/X/Y/Z");
  if (!cap.body.includes("hi")) throw new Error("payload not forwarded");
});

Deno.test("postSlackAlert — non-2xx returns { ok: false, status: 5xx, error: 'HTTP 5xx' }", async () => {
  const fakeFetch: typeof fetch = () =>
    Promise.resolve(new Response("oops", { status: 503 }));
  const r = await postSlackAlert(
    "https://hooks.slack.com/services/X/Y/Z",
    { text: "x" },
    fakeFetch,
  );
  assertEquals(r.ok, false);
  assertEquals(r.status, 503);
  assertEquals(r.error, "HTTP 503");
});

Deno.test("postSlackAlert — fetch throw is captured (no rethrow)", async () => {
  const fakeFetch: typeof fetch = () => {
    throw new Error("dns failure");
  };
  const r = await postSlackAlert(
    "https://hooks.slack.com/services/X/Y/Z",
    { text: "x" },
    fakeFetch,
  );
  assertEquals(r.ok, false);
  assertEquals(r.status, 0);
  assertEquals(r.error, "dns failure");
});

Deno.test("postSlackAlert — abort timeout returns ok=false (never throws)", async () => {
  // Fake fetch that respects AbortSignal and never resolves until aborted.
  const fakeFetch: typeof fetch = (_url, init) => {
    return new Promise((_resolve, reject) => {
      const sig = init?.signal;
      if (sig) {
        sig.addEventListener("abort", () => {
          reject(new DOMException("aborted", "AbortError"));
        });
      }
    });
  };
  const r = await postSlackAlert(
    "https://hooks.slack.com/services/X/Y/Z",
    { text: "x" },
    fakeFetch,
    10, // 10ms timeout
  );
  assertEquals(r.ok, false);
  assertEquals(r.status, 0);
  if (!r.error || !r.error.toLowerCase().includes("abort"))
    throw new Error(`expected abort error, got: ${r.error}`);
});
