/**
 * Builder for the v1 OpenAPI document (L14-01).
 *
 * Imports each route-definition module for side effects (they
 * register paths against the shared `registry`), then asks the
 * generator to emit a final OpenAPI 3.1 document.
 *
 * Usage:
 *
 *     import { buildOpenApiDocument } from "@/lib/openapi/build";
 *     const doc = buildOpenApiDocument();
 *     fs.writeFileSync("public/openapi-v1.json",
 *                      JSON.stringify(doc, null, 2) + "\n");
 *
 * The output is **deterministic** for a given source: keys come out
 * in the order the registry was populated, and zod-to-openapi sorts
 * its component schemas alphabetically. This is critical for the
 * drift-detection CI gate to be useful — non-deterministic output
 * would create false positives on every PR.
 *
 * Versioning convention:
 *   - `info.version` mirrors `CURRENT_API_VERSION` from
 *     `lib/api/versioning.ts`. When we cut v2, both bump together.
 *   - The `servers` block lists production AND a localhost entry so
 *     Swagger UI's "Try it out" works during development.
 */

import { OpenApiGeneratorV31 } from "@asteasolutions/zod-to-openapi";
import { registry } from "./registry";
import { CURRENT_API_VERSION } from "@/lib/api/versioning";

import "./routes/v1-financial";

export function buildOpenApiDocument() {
  const generator = new OpenApiGeneratorV31(registry.definitions);
  return generator.generateDocument({
    openapi: "3.1.0",
    info: {
      title: "Omni Runner Portal API (v1)",
      version: `${CURRENT_API_VERSION}.0.0`,
      description:
        "Contract-first OpenAPI specification for the v1 portal API. " +
        "Generated from Zod schemas via @asteasolutions/zod-to-openapi. " +
        "DO NOT EDIT BY HAND — regenerate via `npm run openapi:build`.",
      contact: { name: "Omni Runner" },
    },
    servers: [
      { url: "https://portal.omnirunner.app", description: "Production" },
      { url: "http://localhost:3000", description: "Local development" },
    ],
    tags: [
      {
        name: "OmniCoins",
        description: "Custody, swap, distribution and clearing of coins.",
      },
    ],
  });
}
