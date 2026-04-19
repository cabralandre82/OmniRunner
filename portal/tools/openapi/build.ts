/**
 * CLI entry: regenerate `public/openapi-v1.json` from the Zod
 * registry (L14-01).
 *
 *   npx tsx tools/openapi/build.ts
 *
 * Wired into `npm run openapi:build`. Run it whenever you add or
 * change a route definition in `src/lib/openapi/routes/`. The
 * output is deterministic, so committing the file and gating drift
 * in CI catches accidental contract changes before they hit prod.
 */

import * as fs from "node:fs";
import * as path from "node:path";

import { buildOpenApiDocument } from "../../src/lib/openapi/build";

const OUT_PATH = path.resolve(__dirname, "../../public/openapi-v1.json");

const doc = buildOpenApiDocument();
const serialized = JSON.stringify(doc, null, 2) + "\n";

fs.writeFileSync(OUT_PATH, serialized, "utf-8");
const sizeKb = (serialized.length / 1024).toFixed(1);
const pathCount = Object.keys(doc.paths ?? {}).length;
const componentCount = Object.keys(
  (doc.components?.schemas ?? {}) as Record<string, unknown>,
).length;

console.log(
  `[openapi] wrote ${OUT_PATH} (${sizeKb} KiB, ${pathCount} paths, ` +
    `${componentCount} components)`,
);
