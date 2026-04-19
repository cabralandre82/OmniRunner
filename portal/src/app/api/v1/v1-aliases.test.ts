/**
 * Smoke tests for the `/api/v1/*` route aliases (L14-02).
 *
 * Each alias file is intentionally trivial — it imports the legacy
 * handler and wraps it with `wrapV1Handler`. These tests assert
 * that:
 *
 *   1. each expected handler export exists on the alias,
 *   2. the alias re-exports a function (not the raw legacy handler),
 *      so `wrapV1Handler`'s tagging is in effect,
 *   3. the alias is structurally aligned with the legacy module
 *      (same set of HTTP verbs).
 *
 * We do NOT exercise the full handler logic here — that is covered
 * by the per-route test suites in `src/app/api/<path>/route.test.ts`.
 * The `wrapV1Handler` behaviour is covered by `versioning.test.ts`.
 */

import { describe, it, expect } from "vitest";

import * as legacySwap from "@/app/api/swap/route";
import * as v1Swap from "@/app/api/v1/swap/route";

import * as legacyCustody from "@/app/api/custody/route";
import * as v1Custody from "@/app/api/v1/custody/route";

import * as legacyWithdraw from "@/app/api/custody/withdraw/route";
import * as v1Withdraw from "@/app/api/v1/custody/withdraw/route";

import * as legacyDistribute from "@/app/api/distribute-coins/route";
import * as v1Distribute from "@/app/api/v1/distribute-coins/route";

import * as legacyClearing from "@/app/api/clearing/route";
import * as v1Clearing from "@/app/api/v1/clearing/route";

type RouteModule = Record<string, unknown>;

function handlerVerbs(mod: RouteModule): Set<string> {
  const verbs = new Set<string>();
  for (const v of ["GET", "POST", "PUT", "PATCH", "DELETE"] as const) {
    if (typeof mod[v] === "function") verbs.add(v);
  }
  return verbs;
}

const PAIRS: Array<{
  name: string;
  legacy: RouteModule;
  v1: RouteModule;
}> = [
  { name: "swap", legacy: legacySwap, v1: v1Swap },
  { name: "custody", legacy: legacyCustody, v1: v1Custody },
  { name: "custody/withdraw", legacy: legacyWithdraw, v1: v1Withdraw },
  { name: "distribute-coins", legacy: legacyDistribute, v1: v1Distribute },
  { name: "clearing", legacy: legacyClearing, v1: v1Clearing },
];

describe("/api/v1/* aliases — handler exports", () => {
  for (const { name, legacy, v1 } of PAIRS) {
    it(`${name}: v1 alias exports the same set of HTTP verbs as the legacy module`, () => {
      const legacyVerbs = handlerVerbs(legacy);
      const v1Verbs = handlerVerbs(v1);
      expect(v1Verbs).toEqual(legacyVerbs);
      expect(legacyVerbs.size).toBeGreaterThan(0);
    });

    it(`${name}: each v1 export is a function`, () => {
      const verbs = handlerVerbs(v1);
      for (const verb of verbs) {
        expect(typeof v1[verb]).toBe("function");
      }
    });

    it(`${name}: v1 wrapper is NOT the same function reference as legacy (proves wrap)`, () => {
      const verbs = handlerVerbs(v1);
      for (const verb of verbs) {
        // wrapV1Handler returns a NEW function — if v1[verb] === legacy[verb]
        // then the wrap was bypassed and X-Api-Version won't be applied.
        expect(v1[verb]).not.toBe(legacy[verb]);
      }
    });
  }
});
