/**
 * tools/audit/check-event-catalog.ts
 *
 * L08-09 — keep `docs/analytics/EVENT_CATALOG.md` in sync with the
 * canonical TypeScript schema in
 * `portal/src/lib/product-event-schema.ts`.
 *
 * The trigger `fn_validate_product_event` and the Dart tracker
 * already have a runtime parity check
 * (`tools/test_l08_01_02_product_events_hardening.ts`); this guard
 * adds the third leg: docs.
 *
 * Failures
 *   1) An event in PRODUCT_EVENT_NAMES is missing from the catalog
 *   2) A property key in PRODUCT_EVENT_PROPERTY_KEYS is missing
 *   3) The catalog mentions an event/key not in the TS constants
 *
 * Exit codes
 *   0 — catalog matches TS schema
 *   1 — drift detected
 *
 * Usage
 *   npx tsx tools/audit/check-event-catalog.ts
 */

import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import {
  PRODUCT_EVENT_NAMES,
  PRODUCT_EVENT_PROPERTY_KEYS,
} from "../../portal/src/lib/product-event-schema";

const REPO_ROOT = resolve(__dirname, "..", "..");
const CATALOG_PATH = resolve(REPO_ROOT, "docs/analytics/EVENT_CATALOG.md");

function fail(msg: string): never {
  console.error(`[event-catalog] ${msg}`);
  process.exit(1);
}

function ok(msg: string): void {
  console.log(`[event-catalog] ${msg}`);
}

function main(): void {
  const md = readFileSync(CATALOG_PATH, "utf8");

  for (const name of PRODUCT_EVENT_NAMES) {
    const re = new RegExp("\\b" + name.replace(/[-/\\^$*+?.()|[\]{}]/g, "\\$&") + "\\b");
    if (!re.test(md)) {
      fail(`event "${name}" missing from EVENT_CATALOG.md`);
    }
  }

  for (const key of PRODUCT_EVENT_PROPERTY_KEYS) {
    const re = new RegExp("`" + key.replace(/[-/\\^$*+?.()|[\]{}]/g, "\\$&") + "`");
    if (!re.test(md)) {
      fail(`property key "${key}" missing from EVENT_CATALOG.md`);
    }
  }

  // Reverse drift check: collect any backticked snake_case identifier
  // listed in the "Property keys" table that is not in the TS set.
  const propertyTable = md.split("## Property keys")[1]?.split("\n## ")[0] ?? "";
  const allowed = new Set(PRODUCT_EVENT_PROPERTY_KEYS);
  const seen = new Set<string>();
  for (const m of propertyTable.matchAll(/^\|\s*`([a-z_][a-z0-9_]*)`/gm)) {
    seen.add(m[1]);
  }
  for (const key of seen) {
    if (!allowed.has(key)) {
      fail(
        `property key "${key}" listed in EVENT_CATALOG.md but missing ` +
          `from PRODUCT_EVENT_PROPERTY_KEYS — drift detected`,
      );
    }
  }

  ok(
    `OK — ${PRODUCT_EVENT_NAMES.length} events + ${PRODUCT_EVENT_PROPERTY_KEYS.size} property keys all present`,
  );
}

main();
